import logging
import uuid

import networkx as nx
import osmnx as ox
from flask import Flask, jsonify, request
from flask_cors import CORS
from pyproj import Transformer

from common.database import get_db
from dao import RutaDAO
from engine import EvacuacionEngine

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
logger = logging.getLogger("rutas")

app = Flask(__name__)
CORS(app)

G = None
engine = None

# Fallback en duro si Supabase no responde (sincronizado con Cota 30)
ZONAS_FALLBACK = [
    {"id_zona": "ZS-CERRO-ALEGRE", "lat": -33.0480, "lon": -71.6260, "nombre": "cancha cerro alegre"},
    {"id_zona": "ZS-CERRO-CONCE", "lat": -33.0465, "lon": -71.6245, "nombre": "plaza concepcion"},
    {"id_zona": "ZS-CERRO-PLAYA", "lat": -33.0290, "lon": -71.6350, "nombre": "polideportivo playa ancha"},
    {"id_zona": "ZS-CERRO-PANT", "lat": -33.0490, "lon": -71.6200, "nombre": "escuela alemania"},
    {"id_zona": "ZS-CERRO-BARON", "lat": -33.0415, "lon": -71.6030, "nombre": "mirador baron"},
    {"id_zona": "ZS-VINA-QUINTA", "lat": -33.0180, "lon": -71.5380, "nombre": "quinta vergara"},
    {"id_zona": "ZS-VAL-ALEJO", "lat": -33.0260, "lon": -71.6310, "nombre": "parque alejo barrios"},
    {"id_zona": "ZS-VAL-UTFSM", "lat": -33.0350, "lon": -71.5950, "nombre": "universidad santa maria"},
    {"id_zona": "ZS-VAL-POLANCO", "lat": -33.0460, "lon": -71.6050, "nombre": "ascensor polanco"},
    {"id_zona": "ZS-VAL-BDO_OHIGGINS", "lat": -33.0500, "lon": -71.6150, "nombre": "plaza washington"},
    {"id_zona": "ZS-VAL-ADUANA", "lat": -33.0330, "lon": -71.6280, "nombre": "cerro artilleria"},
    {"id_zona": "ZS-VINA-NORTE", "lat": -33.0040, "lon": -71.5430, "nombre": "santa ines"},
    {"id_zona": "ZS-COTA30-RECREO", "lat": -33.0280, "lon": -71.5670, "nombre": "límite cota 30 recreo"},
    {"id_zona": "ZS-COTA30-AGUASANTA", "lat": -33.0250, "lon": -71.5580, "nombre": "límite cota 30 agua santa"},
    {"id_zona": "ZS-COTA30-CHORRILLOS", "lat": -33.0210, "lon": -71.5420, "nombre": "límite cota 30 chorrillos"},
    {"id_zona": "ZS-COTA30-MIRAFLORES", "lat": -33.0120, "lon": -71.5350, "nombre": "límite cota 30 miraflores"},
    {"id_zona": "ZS-COTA30-BARON", "lat": -33.0400, "lon": -71.6020, "nombre": "límite cota 30 cerro baron"},
    {"id_zona": "ZS-COTA30-CARCEL", "lat": -33.0450, "lon": -71.6180, "nombre": "límite cota 30 cerro carcel"},
    {"id_zona": "ZS-COTA30-ARTILLERIA", "lat": -33.0360, "lon": -71.6300, "nombre": "límite cota 30 cerro artilleria"},
]


def cargar_mapa():
    global G, engine
    try:
        logger.info("cargando mega-grafo de valparaiso y viña del mar...")
        G = ox.graph_from_point((-33.030, -71.580), dist=8000, network_type="walk", simplify=True)

        if not G.is_directed():
            G = G.to_directed()

        strongly_connected = max(nx.strongly_connected_components(G), key=len)
        G = G.subgraph(strongly_connected).copy()

        G = ox.projection.project_graph(G)
        engine = EvacuacionEngine(G)
        logger.info("motor de evacuacion en funcionamiento.")

    except Exception as e:
        logger.exception(f"error al cargar el mapa: {e}")


cargar_mapa()


async def _obtener_zonas_seguras():
    """Devuelve las zonas seguras desde Supabase, o el fallback si la consulta falla."""
    zonas = []
    try:
        db = await get_db()
        query = "SELECT id_zona, nombre, ST_X(geom) as lon, ST_Y(geom) as lat FROM zonas_seguras WHERE geom IS NOT NULL"
        zonas_raw = await db.query_raw(query)
        for z in zonas_raw:
            zonas.append(
                {
                    "id_zona": z.get("id_zona"),
                    "lat": float(z.get("lat")),
                    "lon": float(z.get("lon")),
                    "nombre": z.get("nombre"),
                }
            )
        logger.info(f"zonas cargadas desde bd: {len(zonas)}")
    except Exception as e_db:
        logger.warning(f"error de db al cargar zonas: {e_db}. usando fallback en duro.")

    return zonas if zonas else ZONAS_FALLBACK


async def _asegurar_referencias_fk(db, id_alerta, id_inundacion):
    """
    ANTES: si `id_alerta` (ej. "BOLETIN-SHOA-SIM-001", hardcodeado en el cliente Flutter)
    no existía como fila real en `alertas_tsunami`, el INSERT de la ruta fallaba con:
        Foreign key constraint failed on the field: `rutas_alertas_tsunami_fk (index)`
    y la ruta jamás se guardaba en Supabase (el error se tragaba en dao.py sin que el
    usuario ni el resto del sistema se enteraran).

    AHORA: nos aseguramos de que la alerta y la zona de inundación existan (creándolas si
    hace falta) ANTES de intentar guardar la ruta, para que el insert nunca falle por FK.
    """
    try:
        existe_alerta = await db.alertas_tsunami.find_unique(where={"id_alerta": id_alerta})
        if not existe_alerta:
            await db.alertas_tsunami.create(data={"id_alerta": id_alerta, "estado": "SIMULACION"})
    except Exception as e:
        logger.warning(f"no se pudo asegurar la alerta '{id_alerta}': {e}")

    try:
        existe_zona = await db.zona_inundacion.find_unique(where={"id_inundacion": id_inundacion})
        if not existe_zona:
            await db.zona_inundacion.create(data={"id_inundacion": id_inundacion, "tipo_riesgo": "TSUNAMI"})
    except Exception as e:
        logger.warning(f"no se pudo asegurar zona_inundacion '{id_inundacion}': {e}")


@app.route("/calcular-evacuacion", methods=["GET"])
async def calcular():
    if G is None or engine is None:
        return jsonify({"error": "servicio de mapas no operativo."}), 503

    try:
        u_lat = request.args.get("lat")
        u_lon = request.args.get("lon")
        id_user = request.args.get("id_usuario")
        id_alerta = request.args.get("id_alerta")

        if not all([u_lat, u_lon, id_user, id_alerta]):
            return jsonify({"error": "faltan parametros criticos."}), 400

        u_lat, u_lon = float(u_lat), float(u_lon)

        zonas_seguras_db = await _obtener_zonas_seguras()

        transformer = Transformer.from_crs("epsg:4326", G.graph["crs"], always_xy=True)
        inv_transformer = Transformer.from_crs(G.graph["crs"], "epsg:4326", always_xy=True)

        orig_x, orig_y = transformer.transform(u_lon, u_lat)
        try:
            orig_node = ox.distance.nearest_nodes(G, X=orig_x, Y=orig_y)
        except Exception as e:
            logger.error(f"no se pudo ubicar el nodo de origen ({u_lat}, {u_lon}): {e}")
            return jsonify({"error": "no se pudo ubicar tu posicion sobre la red peatonal."}), 422

        # Mapeamos cada zona segura a su nodo más cercano UNA sola vez (antes se recalculaba
        # dentro del mismo loop que ejecutaba Dijkstra completo por zona).
        nodo_a_zona = {}
        for zona in zonas_seguras_db:
            try:
                dest_x, dest_y = transformer.transform(zona["lon"], zona["lat"])
                dest_node = ox.distance.nearest_nodes(G, X=dest_x, Y=dest_y)
                nodo_a_zona[dest_node] = zona
            except Exception as e:
                # antes: `except Exception: pass` silencioso. Ahora se loguea con el id de zona
                # para poder diagnosticar por qué una zona específica queda fuera del cálculo.
                logger.warning(f"zona '{zona.get('id_zona')}' descartada, no se pudo proyectar: {e}")

        if not nodo_a_zona:
            logger.error("ninguna zona segura pudo proyectarse sobre el grafo.")
            return jsonify({"error": "no hay zonas seguras disponibles para calcular ruta."}), 500

        # 1 SOLO Dijkstra desde el origen hacia todas las zonas candidatas
        # (antes: un Dijkstra completo POR CADA zona, ~18-19 veces por request)
        ruta, nodo_destino, distancia_metros = engine.calcular_mejor_ruta(orig_node, list(nodo_a_zona.keys()))

        if not ruta:
            return jsonify({"error": "no se encontro ruta segura hacia los cerros."}), 404

        zona_elegida = nodo_a_zona[nodo_destino]
        tiempo_min = round((distancia_metros / 1.1) / 60, 1)

        trazado_coordenadas = []
        for u, v in zip(ruta[:-1], ruta[1:]):
            edge_data = G.get_edge_data(u, v)
            if edge_data:
                data = min(edge_data.values(), key=lambda d: d.get("length", 1))
                if "geometry" in data:
                    for x, y in data["geometry"].coords:
                        lng, lat = inv_transformer.transform(x, y)
                        trazado_coordenadas.append({"lat": float(lat), "lng": float(lng)})
                else:
                    x, y = G.nodes[u]["x"], G.nodes[u]["y"]
                    lng, lat = inv_transformer.transform(x, y)
                    trazado_coordenadas.append({"lat": float(lat), "lng": float(lng)})

        x_ult, y_ult = G.nodes[ruta[-1]]["x"], G.nodes[ruta[-1]]["y"]
        lng_ult, lat_ult = inv_transformer.transform(x_ult, y_ult)
        trazado_coordenadas.append({"lat": float(lat_ult), "lng": float(lng_ult)})

        id_ruta = f"RT-{str(uuid.uuid4())[:8].upper()}"
        id_inundacion = "ZI-PLAN-VAP-01"

        exito_db = False
        try:
            db = await get_db()
            await _asegurar_referencias_fk(db, str(id_alerta), id_inundacion)

            dao = RutaDAO()
            exito_db = await dao.guardar_ruta(
                id_ruta,
                distancia_metros,
                tiempo_min,
                ruta,
                int(id_user),
                str(zona_elegida["id_zona"]),
                str(id_alerta),
                id_inundacion,
            )
        except Exception as e_dao:
            logger.exception(f"no se pudo persistir la ruta {id_ruta}: {e_dao}")

        return (
            jsonify(
                {
                    "status": "RUTA GENERADA" if exito_db else "ERROR DE PERSISTENCIA",
                    "id_ruta": id_ruta,
                    "id_zona_destino": zona_elegida["id_zona"],
                    "nombre_zona_destino": zona_elegida.get("nombre"),
                    "distancia_m": round(distancia_metros, 2),
                    "tiempo_estimado_min": tiempo_min,
                    "trazado_nodos": trazado_coordenadas,
                }
            ),
            200,
        )

    except Exception as e:
        logger.exception(f"error critico en controlador: {e}")
        return jsonify({"error": "fallo interno en el motor de rutas."}), 500


if __name__ == "__main__":
    # threaded=True: el servidor de desarrollo de Werkzeug por defecto atiende UNA sola
    # request a la vez. Con el cálculo ya optimizado esto importa menos, pero conviene
    # habilitarlo para no serializar requests mientras no migres a gunicorn/hypercorn
    # con varios workers para producción.
    app.run(host="0.0.0.0", port=5003, debug=False, threaded=True)