import uuid
from flask import Flask, jsonify, request
from flask_cors import CORS
import osmnx as ox
import networkx as nx
from pyproj import Transformer # Necesario para convertir coordenadas

from ms_rutas.dao import RutaDAO
from ms_rutas.engine import EvacuacionEngine 

app = Flask(__name__)
CORS(app)

G = None
engine = None 

def cargar_mapa():
    global G, engine
    try:
        print("--- Iniciando Carga de Grafo: Valparaíso, Chile ---")
        # 1. Descarga (5km para asegurar cobertura)
        G = ox.graph_from_point((-33.045, -71.615), dist=5000, network_type="all")
        
        if not G.is_directed():
            G = G.to_directed()
        
        strongly_connected = max(nx.strongly_connected_components(G), key=len)
        G = G.subgraph(strongly_connected).copy()
        
        # 2. PROYECCIÓN: Guardamos el CRS para proyectar los puntos de búsqueda después
        G = ox.projection.project_graph(G)
        print(f"--- Grafo proyectado a: {G.graph['crs']} ---")
        
        engine = EvacuacionEngine(G)
        print("--- [ÉXITO] Motor de Evacuación ACO iniciado y Grafo cargado ---")
        
    except Exception as e:
        print(f"--- [ERROR CRÍTICO] Fallo al cargar mapa: {e} ---")

cargar_mapa()

@app.route('/calcular-evacuacion', methods=['GET'])
def calcular():
    if G is None or engine is None: 
        return jsonify({"error": "Servicio de mapas no inicializado."}), 500

    try:
        u_lat = float(request.args.get('lat', -33.037))
        u_lon = float(request.args.get('lon', -71.621))
        id_user = request.args.get('id_usuario', 1)
        dest_lat, dest_lon = -33.041, -71.627

        # --- AJUSTE CLAVE: Proyectar los puntos de búsqueda ---
        # Convertimos lat/lon (WGS84) al sistema de metros del grafo
        transformer = Transformer.from_crs("epsg:4326", G.graph['crs'], always_xy=True)
        orig_x, orig_y = transformer.transform(u_lon, u_lat)
        dest_x, dest_y = transformer.transform(dest_lon, dest_lat)

        # Ahora buscamos nodos usando las coordenadas proyectadas (en metros)
        orig_node = ox.distance.nearest_nodes(G, X=orig_x, Y=orig_y)
        dest_node = ox.distance.nearest_nodes(G, X=dest_x, Y=dest_y)

        print(f"DEBUG: Origen Nodo {orig_node} | Destino Nodo {dest_node}")

        # Cálculo de ruta
        ruta_nodos = engine.calcular_ruta(orig_node, dest_node)

        if not ruta_nodos or len(ruta_nodos) < 2:
            return jsonify({
                "error": "Puntos demasiado cercanos o sin conexión.",
                "status": "Cero distancia",
                "nodos": [orig_node, dest_node]
            }), 400

        # Cálculo de distancia manual sobre el grafo en metros
        distancia = 0.0
        for u, v in zip(ruta_nodos[:-1], ruta_nodos[1:]):
            edge_data = G.get_edge_data(u, v)
            distancia += min(d['length'] for d in edge_data.values())
        
        tiempo_min = round((distancia / 1.1) / 60, 1) 

        # Persistencia
        dao = RutaDAO()
        id_ruta = f"RT-{str(uuid.uuid4())[:8].upper()}"
        exito_db = False
        try:
            exito_db = dao.guardar_ruta(id_ruta, distancia, tiempo_min, ruta_nodos, id_user, "ZS-ALEGRE", "AL-TSU-01")
        except Exception as db_e:
            print(f"Error DB: {db_e}")

        return jsonify({
            "status": "Ruta optimizada con ACO" if exito_db else "Ruta calculada (Sin registro DB)",
            "id_ruta": id_ruta,
            "distancia_m": round(distancia, 2),
            "tiempo_estimado_min": tiempo_min,
            "trazado_nodos": ruta_nodos
        }), 200

    except Exception as e:
        return jsonify({"error": f"Fallo en el cálculo: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(port=5003, debug=False)