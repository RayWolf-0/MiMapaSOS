from flask import Flask, jsonify, request
from flask_cors import CORS
from ms_alertas.dao import AlertaDAO 
import requests 

app = Flask(__name__)
CORS(app) 
dao = AlertaDAO()

# Monitoreo ajustado a Chile
@app.route('/verificar-sismos', methods=['GET'])
async def verificar_sismos():
    url_usgs = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson"
    
    try:
        respuesta = requests.get(url_usgs)
        datos = respuesta.json()
        alertas_detectadas = []
        
        for sismo in datos['features']:
            mag = sismo['properties']['mag']
            lugar = sismo['properties']['place'].lower()
            id_sismo = sismo['id']
            
            if mag and mag >= 5.0 and "chile" in lugar:
                estado = "ALERTA TSUNAMI" if mag >= 7.0 else "PRECAUCIÓN"
                
                # 1. AGREGAR AWAIT AQUÍ
                if await dao.insertar_alerta(id_sismo, mag, estado):
                    alertas_detectadas.append({
                        "id": id_sismo, 
                        "fuente": "CSN / SHOA",
                        "mag": mag, 
                        "estado": estado
                    })
        
        return jsonify({
            "mensaje": "Escaneo CSN completado",
            "alertas_chile": alertas_detectadas
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# Endpoint para generar un simulacro de alerta
@app.route('/activar-simulacro', methods=['POST'])
async def activar_simulacro(): # 2. AGREGAR ASYNC AQUÍ
    import uuid
    id_simulacro = f"BOLETIN-SHOA-SIM-{uuid.uuid4().hex[:4].upper()}"
    
    data_simulacro = {
        "id_alerta": id_simulacro,
        "institucion": "SHOA / CSN (SIMULACRO)",
        "epicentro": "Costa de Valparaíso",
        "magnitud": 8.5,
        "estado": "ALERTA ROJA",
        "instruccion": "Evacuación inmediata a zonas sobre la Cota 30 en Valparaíso."
    }
    
    if await dao.insertar_alerta(id_simulacro, 8.5, "ALERTA ROJA"):
        return jsonify(data_simulacro), 201
    return jsonify({"error": "Error al registrar simulacro"}), 500

if __name__ == "__main__":
    app.run(host='0.0.0.0',port=5002, debug=True)