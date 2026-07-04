import logging
import unicodedata

import networkx as nx

logger = logging.getLogger("evacuacion_engine")


class EvacuacionEngine:
    """
    Motor híbrido Dijkstra + ACO para rutas de evacuación ante tsunami.

    Cambios respecto a la versión anterior:
    - El "riesgo" de cada arista (penalizaciones por tipo de calle, cercanía a la costa, etc.)
      se calcula UNA sola vez al cargar el grafo (_precalcular_riesgo_estatico), en vez de
      recalcularse en cada arista visitada por cada corrida de Dijkstra. Antes esto implicaba
      normalizar texto (unicodedata) por cada arista, por cada una de las ~19 zonas candidatas,
      en cada request -> era la causa principal de los timeouts ("no calcula ruta").
    - Dijkstra ahora usa weight='weight' (string), el camino nativo/optimizado de networkx,
      en vez de un `lambda` de Python. Es muchísimo más rápido.
    - calcular_mejor_ruta() corre Dijkstra UNA sola vez desde el origen hacia TODOS los nodos
      alcanzables (nx.single_source_dijkstra) y luego elige, entre las zonas candidatas, la de
      menor costo. Antes se ejecutaba un Dijkstra completo POR CADA zona (18-19 veces por request).
    - _distancia_real() ya no asume la key de arista "0" a la fuerza (G[u][v][0]), lo que antes
      podía lanzar un KeyError silencioso en grafos MultiDiGraph con aristas paralelas y descartar
      candidatos sin loguear nada.
    - El descuento por vía peatonal ya NO hace `return` inmediato saltándose el castigo costero:
      antes, un paseo peatonal justo sobre la costa (ej. borde de Av. San Martín) recibía un 90%
      de descuento en vez de la penalización de zona de riesgo, empujando la ruta HACIA la costa.
      Ahora el descuento peatonal se aplica como multiplicador adicional, después de los castigos.
    - La caja de "zona de peligro" se amplió para cubrir toda el área que realmente carga el grafo
      (antes cortaba en lat -33.000, dejando sin penalización zonas al norte, como Reñaca/Viña Norte).
    """

    ESCALERAS = {"steps"}
    RUTAS_PEATONALES = {"pedestrian", "footway", "path", "bridge"}
    BORDE_COSTERO = ["altamirano", "espana", "marina", "san martin", "peru", "borgono", "jorge montt", "wheelwright"]
    PARALELAS_MAR = [
        "errazuriz", "blanco", "brasil", "alberdi", "carlos condell",
        "victoria", "independencia", "libertad", "1 norte", "8 norte",
    ]
    VIAS_TRONCALES = ["trunk", "trunk_link", "primary", "primary_link"]
    VIAS_SECUNDARIAS = ["secondary", "secondary_link"]

    # Caja envolvente de la zona costera de riesgo, alineada con el polígono de tierra firme
    # y con `esCostaValpoVina` del cliente Flutter (mapa_page.dart), para no dejar sectores
    # del grafo sin penalización espacial.
    ZONA_PELIGRO_LAT = (-33.10, -32.95)
    ZONA_PELIGRO_LON = (-71.68, -71.50)

    def __init__(self, grafo):
        self.G = grafo
        self._precalcular_riesgo_estatico()

    # ------------------------------------------------------------------ #
    # Precálculo de riesgo (se ejecuta 1 sola vez, al cargar el grafo)
    # ------------------------------------------------------------------ #
    def _normalizar(self, texto):
        if isinstance(texto, list):
            texto = " ".join(texto)
        texto = str(texto)
        return unicodedata.normalize("NFKD", texto).encode("ASCII", "ignore").decode("utf-8").lower()

    def _riesgo_arista(self, u, v, d):
        """Multiplicador de riesgo de una arista, SIN feromona (esa parte es dinámica)."""
        distancia = d.get("length", 1.0)

        tipo_via_raw = d.get("highway", "")
        tipos_via = tipo_via_raw if isinstance(tipo_via_raw, list) else [tipo_via_raw]
        es_escalera = any(tipo in tipos_via for tipo in self.ESCALERAS)
        es_peatonal = any(tipo in tipos_via for tipo in self.RUTAS_PEATONALES)

        nombre_calle = self._normalizar(d.get("name", ""))

        penalizacion = 1.0

        # nivel 1: calles pegadas al mar (castigo extremo)
        if any(calle in nombre_calle for calle in self.BORDE_COSTERO):
            penalizacion *= 50000.0
        # nivel 2: calles paralelas al plan / principales
        elif any(calle in nombre_calle for calle in self.PARALELAS_MAR):
            penalizacion *= 10000.0

        # nivel 3: calles vehiculares anchas (privilegiamos las más chicas)
        if any(tipo in tipos_via for tipo in self.VIAS_TRONCALES):
            penalizacion *= 5000.0
        elif any(tipo in tipos_via for tipo in self.VIAS_SECUNDARIAS):
            penalizacion *= 1000.0

        # castigo espacial: nodo dentro de la caja de riesgo costero
        try:
            lat = self.G.nodes[u].get("y", 0)
            lon = self.G.nodes[u].get("x", 0)
            en_zona_peligro = (
                self.ZONA_PELIGRO_LAT[0] < lat < self.ZONA_PELIGRO_LAT[1]
                and self.ZONA_PELIGRO_LON[0] < lon < self.ZONA_PELIGRO_LON[1]
            )
            if en_zona_peligro and penalizacion < 50000.0:
                penalizacion *= 2000.0
        except Exception:
            pass

        # Descuento peatonal: SIEMPRE al final, como multiplicador adicional.
        # Las escaleras ('steps') son la mejor vía de escape hacia los cerros (90% descuento).
        # Los paseos peatonales planos ('footway', 'path') reciben solo un 40% de descuento
        # para evitar que la ruta prefiera bordear la costa en vez de subir.
        if es_escalera:
            penalizacion *= 0.1
        elif es_peatonal:
            penalizacion *= 0.6

        return distancia * penalizacion

    def _precalcular_riesgo_estatico(self):
        n_aristas = 0
        for u, v, k, data in self.G.edges(keys=True, data=True):
            data["pheromone"] = 1.0
            data["riesgo_estatico"] = self._riesgo_arista(u, v, data)
            data["weight"] = data["riesgo_estatico"] / data["pheromone"]
            n_aristas += 1
        logger.info(f"riesgo estatico precalculado para {n_aristas} aristas")

    def _sincronizar_pesos(self):
        """Recalcula weight = riesgo_estatico / pheromone para todas las aristas.
        Es O(E) pero aritmética simple (sin normalizar texto), y ahora se llama
        UNA sola vez por ruta calculada (no ~19 veces por request como antes)."""
        for _, _, data in self.G.edges(data=True):
            data["weight"] = data["riesgo_estatico"] / data["pheromone"]

    # ------------------------------------------------------------------ #
    # Cálculo de ruta
    # ------------------------------------------------------------------ #
    def calcular_mejor_ruta(self, origen_node, destinos_nodes):
        """
        Corre Dijkstra UNA sola vez desde `origen_node` (weight='weight', ruta nativa de
        networkx) y entre todos los nodos alcanzados busca cuál de `destinos_nodes`
        (nodos más cercanos a cada zona segura) tiene menor costo acumulado.

        Antes: un Dijkstra completo POR CADA zona candidata (18-19 corridas por request).
        Ahora: 1 sola corrida de Dijkstra por request.

        Retorna (ruta, nodo_destino_elegido, distancia_metros_reales) o
        (None, None, None) si no hay camino hacia ninguna zona segura.
        """
        try:
            distancias, rutas = nx.single_source_dijkstra(self.G, origen_node, weight="weight")
        except nx.NodeNotFound as e:
            logger.error(f"nodo origen no encontrado en el grafo: {e}")
            return None, None, None

        mejor_destino = None
        mejor_costo = float("inf")

        for destino in destinos_nodes:
            costo = distancias.get(destino)
            if costo is not None and costo < mejor_costo:
                mejor_costo = costo
                mejor_destino = destino

        if mejor_destino is None:
            return None, None, None

        ruta = rutas[mejor_destino]
        distancia_metros = self._distancia_real(ruta)
        self._actualizar_feromonas(ruta)
        return ruta, mejor_destino, distancia_metros

    def _distancia_real(self, ruta):
        """Suma la longitud real (metros) de la ruta. Antes se asumía la key de arista
        fija `0` (G[u][v][0]), lo que en un MultiDiGraph con aristas paralelas podía
        lanzar KeyError y descartar la zona candidata sin loguear nada. Ahora se toma
        siempre la arista de menor longitud entre cada par de nodos, igual que ya se
        hacía (correctamente) al construir el trazado de coordenadas."""
        total = 0.0
        for u, v in zip(ruta[:-1], ruta[1:]):
            edge_data = self.G.get_edge_data(u, v)
            if edge_data:
                mejor = min(edge_data.values(), key=lambda d: d.get("length", 1.0))
                total += mejor.get("length", 0.0)
        return total

    def _actualizar_feromonas(self, ruta):
        # evaporar un 5% en todo el grafo
        for _, _, data in self.G.edges(data=True):
            data["pheromone"] *= 0.95

        # reforzar la ruta usada
        for i in range(len(ruta) - 1):
            u, v = ruta[i], ruta[i + 1]
            edge_data = self.G.get_edge_data(u, v)
            if edge_data:
                for key in edge_data:
                    edge_data[key]["pheromone"] += 0.5

        # sincronizar pesos con la nueva feromona (1 sola vez por request, no ~19 veces)
        self._sincronizar_pesos()