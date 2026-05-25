import uuid
from flask import Flask, jsonify, request
from flask_cors import CORS
import osmnx as ox
import networkx as nx
from pyproj import Transformer 

from ms_rutas.dao import RutaDAO
from ms_rutas.engine import EvacuacionEngine 

app = Flask(__name__)
CORS(app)

G = None
engine = None 

def cargar_mapa():
    global G, engine
    try:
        print("grafo Valparaiso cargando...")
        # Centro en Valparaíso (Plaza Sotomayor aprox)
        G = ox.graph_from_point((-33.045, -71.615), dist=5000, network_type="all")
        
        if not G.is_directed():
            G = G.to_directed()
        
        strongly_connected = max(nx.strongly_connected_components(G), key=len)
        G = G.subgraph(strongly_connected).copy()
        
        G = ox.projection.project_graph(G)
        engine = EvacuacionEngine(G)
        print("motor de evacuacion en funcionamiento-")
        
    except Exception as e:
        print(f"error al cargar el mapa: {e} ---")

cargar_mapa()

@app.route('/calcular-evacuacion', methods=['GET'])
async def calcular():
    if G is None or engine is None: 
        return jsonify({"error": "Servicio de mapas no operativo."}), 503

    try:
        # 1. PARÁMETROS DE ENTRADA 
        u_lat = request.args.get('lat')
        u_lon = request.args.get('lon')
        id_user = request.args.get('id_usuario')
        id_alerta = request.args.get('id_alerta') 
        id_zona = request.args.get('id_zona')     
        dest_lat = request.args.get('dest_lat')   
        dest_lon = request.args.get('dest_lon')   

        # emergencias
        if not all([u_lat, u_lon, id_user, id_alerta, id_zona, dest_lat, dest_lon]):
            return jsonify({
                "error": "Faltan parámetros críticos para la evacuación.",
                "detalles": "Se requiere ubicación actual, destino y vinculación a una alerta activa."
            }), 400

        u_lat, u_lon = float(u_lat), float(u_lon)
        dest_lat, dest_lon = float(dest_lat), float(dest_lon)

        # nodos
        transformer = Transformer.from_crs("epsg:4326", G.graph['crs'], always_xy=True)
        orig_x, orig_y = transformer.transform(u_lon, u_lat)
        dest_x, dest_y = transformer.transform(dest_lon, dest_lat)

        orig_node = ox.distance.nearest_nodes(G, X=orig_x, Y=orig_y)
        dest_node = ox.distance.nearest_nodes(G, X=dest_x, Y=dest_y)

        # calculo ACO + dijkstra
        ruta_nodos = engine.calcular_ruta(orig_node, dest_node)

        if not ruta_nodos:
            return jsonify({"error": "No se encontró una ruta segura al refugio."}), 404

        # metricas
        distancia = 0.0
        for u, v in zip(ruta_nodos[:-1], ruta_nodos[1:]):
            edge_data = G.get_edge_data(u, v)
            distancia += min(d['length'] for d in edge_data.values())
        
        # Velocidad de caminata en emergencia aprox 1.1 m/s
        tiempo_min = round((distancia / 1.1) / 60, 1) 

        # --- TRADUCCIÓN DE NODOS A COORDENADAS PARA FLUTTER ---
        # Extraemos la Lat/Lon real de cada nodo matemático
        trazado_coordenadas = []
        for nodo in ruta_nodos:
            lat = G.nodes[nodo]['lat']
            lng = G.nodes[nodo]['lon']
            trazado_coordenadas.append({"lat": lat, "lng": lng})
        # ------------------------------------------------------

        # persistencia de la ruta en base de datos
        dao = RutaDAO()
        id_ruta = f"RT-{str(uuid.uuid4())[:8].upper()}"
        
        # base de datos
        exito_db = await dao.guardar_ruta(
            id_ruta, 
            distancia, 
            tiempo_min, 
            ruta_nodos, # Guardamos los IDs enteros en la DB relacional por eficiencia
            int(id_user), 
            str(id_zona), 
            str(id_alerta)
        )

        return jsonify({
            "status": "RUTA DE EVACUACIÓN GENERADA" if exito_db else "RUTA GENERADA (ERROR DE PERSISTENCIA)",
            "id_ruta": id_ruta,
            "id_alerta_vinculada": id_alerta,
            "id_zona_destino": id_zona,
            "distancia_m": round(distancia, 2),
            "tiempo_estimado_min": tiempo_min,
            # Enviamos a Flutter el array de coordenadas GPS reales
            "trazado_nodos": trazado_coordenadas
        }), 200

    except Exception as e:
        print(f"Error en el proceso de rutas: {e}")
        return jsonify({"error": "Fallo interno en el motor de rutas."}), 500

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5003, debug=False)