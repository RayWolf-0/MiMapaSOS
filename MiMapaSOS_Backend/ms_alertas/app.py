from flask import Flask, jsonify
from flask_cors import CORS
from ms_alertas.dao import AlertaDAO 
import requests 

app = Flask(__name__)
CORS(app) 

@app.route('/verificar-sismos', methods=['GET'])
def verificar_sismos():
    url_usgs = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson"
    
    try:
        respuesta = requests.get(url_usgs)
        datos = respuesta.json()
        alertas_detectadas = []
        dao = AlertaDAO()
        
        for sismo in datos['features']:
            mag = sismo['properties']['mag']
            id_sismo = sismo['id']
            
            # magnitud definida
            if mag and mag >= 5.0:
                estado = "Amarilla" if mag < 7.0 else "Roja"
                # Intentamos insertar
                if dao.insertar_alerta(id_sismo, mag, estado):
                    alertas_detectadas.append({"id": id_sismo, "mag": mag, "estado": estado})
        
        return jsonify({
            "mensaje": "Escaneo completado",
            "alertas_nuevas_encontradas": len(alertas_detectadas),
            "detalles": alertas_detectadas
        }), 200
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(port=5002, debug=True)