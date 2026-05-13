import requests

url = "http://127.0.0.1:5001/auth/google"

payload = {
    "token": "TOKEN_DE_PRUEBA_GENERADO_POR_FLUTTER"
}

try:
    response = requests.post(url, json=payload)
    # Si el token es falso, el backend debería responder 401 Unauthorized
    print(f"Status Code: {response.status_code}")
    print("Respuesta del servidor:")
    print(response.json())
except Exception as e:
    print(f"Error al conectar con el microservicio: {e}")