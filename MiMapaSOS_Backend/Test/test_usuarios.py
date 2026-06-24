import unittest
from unittest.mock import patch, AsyncMock

# Aquí usamos el alias 'flask_app' para romper la colisión de nombres
from ms_usuarios.app import app as flask_app 

class TestUsuariosAuth(unittest.TestCase):

    def setUp(self):
        """Configura el entorno de pruebas antes de cada test."""
        flask_app.config['TESTING'] = True
        self.client = flask_app.test_client()

    def test_login_sin_token(self):
        """Verifica el error 400 cuando el frontend no envía el token."""
        response = self.client.post('/auth/google', json={})
        
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()['message'], "Falta el token")

    # Interceptamos la llamada a Google apuntando al microservicio
    @patch('ms_usuarios.app.id_token.verify_oauth2_token')
    def test_login_token_invalido(self, mock_verify):
        """Verifica el error 401 si Google rechaza el token."""
        mock_verify.side_effect = ValueError("Token inválido")

        payload = {"token": "TOKEN_FALSO"}
        response = self.client.post('/auth/google', json=payload)
        
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.get_json()['message'], "Token de Google no válido")

    # Interceptamos el DAO asíncrono y la llamada a Google
    @patch('ms_usuarios.app.dao.obtener_o_registrar', new_callable=AsyncMock)
    @patch('ms_usuarios.app.id_token.verify_oauth2_token')
    def test_login_exitoso(self, mock_verify, mock_dao):
        """Simula un flujo perfecto retornando 200 y los datos del usuario."""
        
        mock_verify.return_value = {
            'sub': '111222333',
            'email': 'ciudadano@ejemplo.cl',
            'name': 'Ciudadano Prueba'
        }

        mock_dao.return_value = {
            "id": 105,
            "nombre": "Ciudadano Prueba",
            "email": "ciudadano@ejemplo.cl"
        }

        payload = {"token": "TOKEN_VALIDO_SIMULADO"}
        response = self.client.post('/auth/google', json=payload)

        self.assertEqual(response.status_code, 200)
        
        json_response = response.get_json()
        self.assertEqual(json_response['status'], "success")
        self.assertEqual(json_response['user']['id'], 105)
        
        mock_dao.assert_called_once_with('111222333', 'ciudadano@ejemplo.cl', 'Ciudadano Prueba')

    @patch('ms_usuarios.app.id_token.verify_oauth2_token')
    def test_login_error_servidor(self, mock_verify):
        """Verifica que atrape excepciones no controladas retornando 500."""
        mock_verify.side_effect = Exception("Fallo general de red")

        payload = {"token": "TOKEN_VALIDO"}
        response = self.client.post('/auth/google', json=payload)

        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.get_json()['status'], "error")

if __name__ == '__main__':
    unittest.main()