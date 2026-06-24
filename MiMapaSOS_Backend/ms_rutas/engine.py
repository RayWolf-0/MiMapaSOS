import networkx as nx
import unicodedata

class EvacuacionEngine:
    def __init__(self, grafo):
        self.G = grafo
        # arrancar feromonas en 1.0
        for u, v, data in self.G.edges(data=True):
            data['pheromone'] = 1.0

    def costo_hibrido_aco(self, u, v, d):
        distancia = d.get('length', 1.0)
        feromona = d.get('pheromone', 1.0)
        penalizacion = 1.0

        tipo_via_raw = d.get('highway', '')
        # Convertimos siempre a lista para buscar en todas las etiquetas sin perder datos
        tipos_via = tipo_via_raw if isinstance(tipo_via_raw, list) else [tipo_via_raw]

        # 1. prioridad maxima a escaleras, pasarelas y vias peatonales
        # retornamos al tiro para evitar que le afecten los castigos de abajo
        rutas_peatonales = ['steps', 'pedestrian', 'footway', 'path', 'bridge']
        if any(tipo in tipos_via for tipo in rutas_peatonales):
            # Descuento extremo: le decimos a Dijkstra que caminar por aquí "cuesta" un 10% de la distancia real
            return (distancia * 0.1) / feromona 

        # preparar nombre de la calle (minusculas, sin tildes)
        nombre_calle = d.get('name', '')
        if isinstance(nombre_calle, list): 
            nombre_calle = ' '.join(nombre_calle)
        else: 
            nombre_calle = str(nombre_calle)
        nombre_calle = unicodedata.normalize('NFKD', nombre_calle).encode('ASCII', 'ignore').decode('utf-8').lower()

        # 2. castigos por nombre de calle (gradiente de peligro)
        # nivel 1: calles pegadas al mar (castigo extremo)
        borde_costero = ['altamirano', 'espana', 'marina', 'san martin', 'peru', 'borgono', 'jorge montt']
        if any(calle in nombre_calle for calle in borde_costero):
            penalizacion *= 50000.0 

        # nivel 2: calles paralelas al plan o principales
        paralelas_mar = ['errazuriz', 'blanco', 'brasil', 'alberdi', 'carlos condell', 'victoria', 'independencia', 'libertad', '1 norte', '8 norte']
        if any(calle in nombre_calle for calle in paralelas_mar):
            penalizacion *= 10000.0

        # nivel 3: calles vehiculares anchas (privilegiamos las más chicas)
        if any(tipo in tipos_via for tipo in ['trunk', 'trunk_link', 'primary', 'primary_link']):
            penalizacion *= 5000.0
        elif any(tipo in tipos_via for tipo in ['secondary', 'secondary_link']):
            penalizacion *= 1000.0

        # 3. castigo espacial (caja contenedora del plan)
        # por si el nodo no tiene nombre en OSM
        try:
            lat = self.G.nodes[u].get('y', 0)
            lon = self.G.nodes[u].get('x', 0)
            en_zona_peligro = (-33.055 < lat < -33.000) and (-71.635 < lon < -71.540)
            
            # si esta en el plan y no le pegó el castigo de 50k, lo forzamos a salir del sector
            if en_zona_peligro and penalizacion < 50000.0:
                penalizacion *= 2000.0 
        except Exception:
            pass

        return (distancia * penalizacion) / feromona

    def calcular_ruta(self, origen_node, destino_node):
        try:
            ruta = nx.shortest_path(
                self.G, 
                source=origen_node, 
                target=destino_node, 
                weight=lambda u, v, d: self.costo_hibrido_aco(u, v, d)
            )
            self._actualizar_feromonas(ruta)
            return ruta
        except (nx.NetworkXNoPath, nx.NodeNotFound):
            return None

    def _actualizar_feromonas(self, ruta):
        # evaporar un 5%
        for u, v, data in self.G.edges(data=True):
            data['pheromone'] *= 0.95

        # dejar rastro en la ruta usada
        for i in range(len(ruta) - 1):
            u, v = ruta[i], ruta[i+1]
            edge_data = self.G.get_edge_data(u, v)
            if edge_data:
                for key in edge_data:
                    edge_data[key]['pheromone'] += 0.5