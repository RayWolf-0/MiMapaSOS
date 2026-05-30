from flask import Flask, request, jsonify
from google.oauth2 import id_token
from google.auth.transport import requests
from ms_usuarios.dao import UsuarioDAO

app = Flask(__name__)
dao = UsuarioDAO()

# google id
GOOGLE_CLIENT_ID = "1033944391120-6jp2pjgh0uricvohg8rth2vpj5dud27a.apps.googleusercontent.com"

@app.route('/auth/google', methods=['POST'])
async def login_google(): # <--- AGREGAR ASYNC
    token = request.json.get('token')
    
    if not token:
        return jsonify({"status": "error", "message": "Falta el token"}), 400
    
    try:
        # Verificación del token de google (esto es síncrono, no necesita await)
        idinfo = id_token.verify_oauth2_token(token, requests.Request(), GOOGLE_CLIENT_ID)
        
        # Datos del usuario obtenidos de Google
        google_id = idinfo['sub']
        email = idinfo['email']
        nombre = idinfo.get('name', 'Usuario de Google')

        # 3. Verificar en DB o registrar (AQUÍ AGREGAMOS EL AWAIT)
        usuario = await dao.obtener_o_registrar(google_id, email, nombre)
        
        return jsonify({"status": "success", "user": usuario}), 200

    except ValueError:
        # Token inválido
        return jsonify({"status": "error", "message": "Token de Google no válido"}), 401
    except Exception as e:
        print(f"Error en login_google: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0',port=5001)