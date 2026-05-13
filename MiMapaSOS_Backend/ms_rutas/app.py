import uuid
from flask import Flask, jsonify, request
from flask_cors import CORS
import osmnx as ox
import networkx as nx

from ms_rutas.dao import RutaDAO
from ms_rutas.engine import EvacuacionEngine # Importamos tu nuevo motor

app = Flask(__name__)
CORS(app)

G = None
engine = None 

def cargar_mapa():
    global G, engine
    try:
        print("--- Cargando Valparaíso con OSMnx ---")
        # Cargamos red peatonal para evacuación
        G = ox.graph_from_point((-33.045, -71.615), dist=3000, network_type="walk")
        G = ox.project_graph(G)
        
        # Inicializamos el motor de evacuación con el grafo
        engine = EvacuacionEngine(G)
        print("--- Motor de Evacuación ACO iniciado ---")
    except Exception as e:
        print(f"Error al inicializar mapa/motor: {e}")

cargar_mapa()

@app.route('/calcular-evacuacion', methods=['GET'])
def calcular():
    if G is None or engine is None: 
        return jsonify({"error": "Servicio de mapas no inicializado"}), 500

    try:
        # parametros de usuario (lat, lon, id_usuario)
        u_lat = float(request.args.get('lat', -33.037))
        u_lon = float(request.args.get('lon', -71.621))
        id_user = request.args.get('id_usuario', 1)
        
        # Coordenadas de Zona Segura (ejemplo)
        dest_lat, dest_lon = -33.041, -71.627

        # nodos
        orig_node = ox.distance.nearest_nodes(G, X=u_lon, Y=u_lat)
        dest_node = ox.distance.nearest_nodes(G, X=dest_lon, Y=dest_lat)

        # engine
        ruta_nodos = engine.calcular_ruta(orig_node, dest_node)

        if not ruta_nodos:
            return jsonify({"error": "No se encontró una ruta segura disponible"}), 404

        # 4. Cálculos de distancia y tiempo
        distancia = float(sum(ox.utils_graph.get_route_edge_attributes(G, ruta_nodos, 'length')))
        tiempo_min = round((distancia / 1.1) / 60, 1) 

        # 5. Persistencia en PostgreSQL
        dao = RutaDAO()
        id_ruta = f"RT-{str(uuid.uuid4())[:8].upper()}"
        
        exito_db = dao.guardar_ruta(
            id_ruta, 
            distancia, 
            tiempo_min, 
            ruta_nodos, 
            id_user, 
            "ZS-ALEGRE", 
            "AL-TSU-01"
        )

        # 6. Respuesta al Frontend
        return jsonify({
            "status": "Ruta optimizada con ACO" if exito_db else "Error en registro DB",
            "id_ruta": id_ruta,
            "distancia_m": round(distancia, 2),
            "tiempo_estimado_min": tiempo_min,
            "trazado_nodos": ruta_nodos
        }), 200

    except Exception as e:
        return jsonify({"error": f"Fallo en el cálculo: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(port=5003, debug=True)