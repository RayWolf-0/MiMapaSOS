from flask import Flask, request, jsonify
from google.oauth2 import id_token
from google.auth.transport import requests
from ms_usuarios.dao import UsuarioDAO

app = Flask(__name__)
dao = UsuarioDAO()

# google id
GOOGLE_CLIENT_ID = "TU_CLIENT_ID_AQUI.apps.googleusercontent.com"

@app.route('/auth/google', methods=['POST'])
def login_google():
    token = request.json.get('token')
    
    try:
        # token de google
        idinfo = id_token.verify_oauth2_token(token, requests.Request(), GOOGLE_CLIENT_ID)
        
        # usuario
        google_id = idinfo['sub'] # ID de Google
        email = idinfo['email']
        nombre = idinfo.get('name', 'Usuario de Google')

        # 3. Verificar en DB o registrar si es nuevo
        usuario = dao.obtener_o_registrar(google_id, email, nombre)
        
        return jsonify({"status": "success", "user": usuario}), 200

    except ValueError:
        # Token inválido
        return jsonify({"status": "error", "message": "Token de Google no válido"}), 401

if __name__ == '__main__':
    app.run(port=5001)