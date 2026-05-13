from flask import Flask, jsonify
from flask_cors import CORS
from ms_geografia.dao import GeografiaDAO

app = Flask(__name__)
CORS(app)
dao = GeografiaDAO()

@app.route('/mapa/zonas-seguras', methods=['GET'])
def get_zonas_seguras():
    try:
        zonas = dao.obtener_zonas_seguras()
        return jsonify({
            "status": "success",
            "total": len(zonas),
            "data": zonas
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/mapa/zonas-inundacion', methods=['GET'])
def get_zonas_inundacion():
    try:
        zonas = dao.obtener_zonas_inundacion()
        return jsonify({"status": "success", "data": zonas}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(port=5004, debug=True)