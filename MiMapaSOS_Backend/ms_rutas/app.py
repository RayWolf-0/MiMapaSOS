import uuid
from flask import Flask, jsonify, request
from flask_cors import CORS
import osmnx as ox
import networkx as nx
from pyproj import Transformer 

from dao import RutaDAO
from engine import EvacuacionEngine 
from common.database import get_db

app = Flask(__name__)
CORS(app)

G = None
engine = None 

def cargar_mapa():
    global G, engine
    try:
        print("cargando mega-grafo de valparaiso y viña del mar...", flush=True)
        G = ox.graph_from_point((-33.030, -71.580), dist=8000, network_type="walk", simplify=True)
        
        if not G.is_directed():
            G = G.to_directed()
        
        strongly_connected = max(nx.strongly_connected_components(G), key=len)
        G = G.subgraph(strongly_connected).copy()
        
        G = ox.projection.project_graph(G)
        engine = EvacuacionEngine(G)
        print("motor de evacuacion en funcionamiento.", flush=True)
        
    except Exception as e:
        print(f"error al cargar el mapa: {e}", flush=True)

cargar_mapa()

@app.route('/calcular-evacuacion', methods=['GET'])
async def calcular():
    if G is None or engine is None: 
        return jsonify({"error": "servicio de mapas no operativo."}), 503

    try:
        u_lat = request.args.get('lat')
        u_lon = request.args.get('lon')
        id_user = request.args.get('id_usuario')
        id_alerta = request.args.get('id_alerta') 
        
        if not all([u_lat, u_lon, id_user, id_alerta]):
            return jsonify({"error": "faltan parametros criticos."}), 400

        u_lat, u_lon = float(u_lat), float(u_lon)

        # cargar zonas usando funciones nativas de postgis (st_x y st_y)
        zonas_seguras_db = []
        try:
            db = await get_db()
            query = "SELECT id_zona, nombre, ST_X(geom) as lon, ST_Y(geom) as lat FROM zonas_seguras WHERE geom IS NOT NULL"
            zonas_raw = await db.query_raw(query)
            
            for z in zonas_raw:
                zonas_seguras_db.append({
                    "id_zona": z.get('id_zona'),
                    "lat": float(z.get('lat')),
                    "lon": float(z.get('lon')),
                    "nombre": z.get('nombre')
                })
            print(f"zonas cargadas desde bd: {len(zonas_seguras_db)}", flush=True)
        except Exception as e_db:
            print(f"error de db al cargar zonas: {e_db}. usando salvavidas.", flush=True)

        # salvavidas en duro si falla la base de datos (Sincronizado con Cota 30)
        if not zonas_seguras_db:
            zonas_seguras_db = [
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
                
                # Nuevos puntos fronterizos discretos de la Cota 30
                {"id_zona": "ZS-COTA30-RECREO", "lat": -33.0280, "lon": -71.5670, "nombre": "límite cota 30 recreo"},
                {"id_zona": "ZS-COTA30-AGUASANTA", "lat": -33.0250, "lon": -71.5580, "nombre": "límite cota 30 agua santa"},
                {"id_zona": "ZS-COTA30-CHORRILLOS", "lat": -33.0210, "lon": -71.5420, "nombre": "límite cota 30 chorrillos"},
                {"id_zona": "ZS-COTA30-MIRAFLORES", "lat": -33.0120, "lon": -71.5350, "nombre": "límite cota 30 miraflores"},
                {"id_zona": "ZS-COTA30-BARON", "lat": -33.0400, "lon": -71.6020, "nombre": "límite cota 30 cerro baron"},
                {"id_zona": "ZS-COTA30-CARCEL", "lat": -33.0450, "lon": -71.6180, "nombre": "límite cota 30 cerro carcel"},
                {"id_zona": "ZS-COTA30-ARTILLERIA", "lat": -33.0360, "lon": -71.6300, "nombre": "límite cota 30 cerro artilleria"}
            ]

        transformer = Transformer.from_crs("epsg:4326", G.graph['crs'], always_xy=True)
        orig_x, orig_y = transformer.transform(u_lon, u_lat)
        orig_node = ox.distance.nearest_nodes(G, X=orig_x, Y=orig_y)

        mejor_ruta = None
        mejor_id_zona = None
        menor_distancia_caminando = float('inf')

        for zona in zonas_seguras_db:
            try:
                dest_x, dest_y = transformer.transform(zona["lon"], zona["lat"])
                dest_node = ox.distance.nearest_nodes(G, X=dest_x, Y=dest_y)

                ruta_prueba = engine.calcular_ruta(orig_node, dest_node)

                if ruta_prueba:
                    distancia = sum(G[u][v][0].get('length', 0) for u, v in zip(ruta_prueba[:-1], ruta_prueba[1:]))
                    
                    if distancia < menor_distancia_caminando:
                        menor_distancia_caminando = distancia
                        mejor_ruta = ruta_prueba
                        mejor_id_zona = zona["id_zona"]
            except Exception:
                pass

        if not mejor_ruta:
            return jsonify({"error": "no se encontro ruta segura hacia los cerros."}), 404

        tiempo_min = round((menor_distancia_caminando / 1.1) / 60, 1) 

        trazado_coordenadas = []
        inv_transformer = Transformer.from_crs(G.graph['crs'], "epsg:4326", always_xy=True)
        
        for u, v in zip(mejor_ruta[:-1], mejor_ruta[1:]):
            edge_data = G.get_edge_data(u, v)
            if edge_data:
                data = min(edge_data.values(), key=lambda d: d.get('length', 1))
                if 'geometry' in data:
                    for x, y in data['geometry'].coords:
                        lng, lat = inv_transformer.transform(x, y)
                        trazado_coordenadas.append({"lat": float(lat), "lng": float(lng)})
                else:
                    x, y = G.nodes[u]['x'], G.nodes[u]['y']
                    lng, lat = inv_transformer.transform(x, y)
                    trazado_coordenadas.append({"lat": float(lat), "lng": float(lng)})

        ultimo_nodo = mejor_ruta[-1]
        x_ult, y_ult = G.nodes[ultimo_nodo]['x'], G.nodes[ultimo_nodo]['y']
        lng_ult, lat_ult = inv_transformer.transform(x_ult, y_ult)
        trazado_coordenadas.append({"lat": float(lat_ult), "lng": float(lng_ult)})

        dao = RutaDAO()
        id_ruta = f"RT-{str(uuid.uuid4())[:8].upper()}"
        
        try:
            exito_db = await dao.guardar_ruta(
                id_ruta, menor_distancia_caminando, tiempo_min, mejor_ruta, 
                int(id_user), str(mejor_id_zona), str(id_alerta)
            )
        except Exception as e_dao:
            print(f"ignorando error de llaves foraneas: {e_dao}", flush=True)
            exito_db = False

        return jsonify({
            "status": "RUTA GENERADA" if exito_db else "ERROR DE PERSISTENCIA",
            "id_ruta": id_ruta,
            "distancia_m": round(menor_distancia_caminando, 2),
            "tiempo_estimado_min": tiempo_min,
            "trazado_nodos": trazado_coordenadas
        }), 200

    except Exception as e:
        print(f"error critico en controlador: {e}", flush=True)
        return jsonify({"error": "fallo interno en el motor de rutas."}), 500

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5003, debug=False)