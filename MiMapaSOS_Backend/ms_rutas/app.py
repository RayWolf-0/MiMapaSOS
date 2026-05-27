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
        print("Cargando mega-grafo de Valparaíso y Viña del Mar...")
        # Radio de 8km centrado entre ambas ciudades
        G = ox.graph_from_point((-33.030, -71.580), dist=8000, network_type="all")
        
        if not G.is_directed():
            G = G.to_directed()
        
        strongly_connected = max(nx.strongly_connected_components(G), key=len)
        G = G.subgraph(strongly_connected).copy()
        
        G = ox.projection.project_graph(G)
        engine = EvacuacionEngine(G)
        print("Motor de evacuación en funcionamiento.")
        
    except Exception as e:
        print(f"Error al cargar el mapa: {e} ---")

cargar_mapa()

@app.route('/calcular-evacuacion', methods=['GET'])
async def calcular():
    if G is None or engine is None: 
        return jsonify({"error": "Servicio de mapas no operativo."}), 503

    try:
        # 1. PARÁMETROS
        u_lat = request.args.get('lat')
        u_lon = request.args.get('lon')
        id_user = request.args.get('id_usuario')
        id_alerta = request.args.get('id_alerta') 
        id_zona = request.args.get('id_zona')     
        dest_lat = request.args.get('dest_lat')   
        dest_lon = request.args.get('dest_lon')   

        if not all([u_lat, u_lon, id_user, id_alerta, id_zona, dest_lat, dest_lon]):
            return jsonify({"error": "Faltan parámetros críticos."}), 400

        u_lat, u_lon = float(u_lat), float(u_lon)
        dest_lat, dest_lon = float(dest_lat), float(dest_lon)

        # 2. NODOS (Proyección correcta)
        transformer = Transformer.from_crs("epsg:4326", G.graph['crs'], always_xy=True)
        orig_x, orig_y = transformer.transform(u_lon, u_lat)
        dest_x, dest_y = transformer.transform(dest_lon, dest_lat)

        orig_node = ox.distance.nearest_nodes(G, X=orig_x, Y=orig_y)
        dest_node = ox.distance.nearest_nodes(G, X=dest_x, Y=dest_y)

        ruta_nodos = engine.calcular_ruta(orig_node, dest_node)

        if not ruta_nodos:
            return jsonify({"error": "No se encontró una ruta segura."}), 404

        # 3. MÉTRICAS
        distancia = sum(G[u][v][0].get('length', 0) for u, v in zip(ruta_nodos[:-1], ruta_nodos[1:]))
        tiempo_min = round((distancia / 1.1) / 60, 1) 

        # 4. TRANSFORMACIÓN INVERSA (Extracción de geometría de calles)
        trazado_coordenadas = []
        inv_transformer = Transformer.from_crs(G.graph['crs'], "epsg:4326", always_xy=True)
        
        for u, v in zip(ruta_nodos[:-1], ruta_nodos[1:]):
            edge_data = G.get_edge_data(u, v)
            if edge_data:
                # Tomamos la arista más corta en caso de haber múltiples caminos (multigrafo)
                data = min(edge_data.values(), key=lambda d: d.get('length', 1))
                
                if 'geometry' in data:
                    # Extraemos los puntos intermedios para dibujar curvas correctamente
                    for x, y in data['geometry'].coords:
                        lng, lat = inv_transformer.transform(x, y)
                        trazado_coordenadas.append({"lat": float(lat), "lng": float(lng)})
                else:
                    # Línea recta sin geometría extra
                    x, y = G.nodes[u]['x'], G.nodes[u]['y']
                    lng, lat = inv_transformer.transform(x, y)
                    trazado_coordenadas.append({"lat": float(lat), "lng": float(lng)})

        # Añadir el destino final explícitamente para cerrar la línea
        ultimo_nodo = ruta_nodos[-1]
        x_ult, y_ult = G.nodes[ultimo_nodo]['x'], G.nodes[ultimo_nodo]['y']
        lng_ult, lat_ult = inv_transformer.transform(x_ult, y_ult)
        trazado_coordenadas.append({"lat": float(lat_ult), "lng": float(lng_ult)})

        # 5. PERSISTENCIA
        dao = RutaDAO()
        id_ruta = f"RT-{str(uuid.uuid4())[:8].upper()}"
        
        try:
            exito_db = await dao.guardar_ruta(
                id_ruta, distancia, tiempo_min, ruta_nodos, 
                int(id_user), str(id_zona), str(id_alerta)
            )
        except Exception:
            exito_db = False

        return jsonify({
            "status": "RUTA GENERADA" if exito_db else "ERROR DE PERSISTENCIA",
            "id_ruta": id_ruta,
            "distancia_m": round(distancia, 2),
            "tiempo_estimado_min": tiempo_min,
            "trazado_nodos": trazado_coordenadas
        }), 200

    except Exception as e:
        print(f"Error interno: {e}")
        return jsonify({"error": "Fallo interno en el motor de rutas."}), 500

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5003, debug=False)