import unittest
from unittest.mock import patch, AsyncMock
from ms_alertas.app import app as flask_app

class TestAlertasMicroservicio(unittest.TestCase):

    def setUp(self):
        """Configuramos el cliente de pruebas de Flask antes de cada test."""
        flask_app.config['TESTING'] = True
        self.client = flask_app.test_client()

    # 1. PRUEBA DEL ENDPOINT DE MONITOREO (SIMULANDO LA API DEL USGS)
    @patch('ms_alertas.app.dao.insertar_alerta', new_callable=AsyncMock)
    @patch('ms_alertas.app.requests.get')
    def test_verificar_sismos_detecta_chile(self, mock_get, mock_dao_insert):
        """Simula un sismo fuerte en Chile y verifica que se intente guardar."""
        
        # Simulamos la estructura JSON exacta que devuelve el USGS
        mock_respuesta_usgs = {
            "features": [
                {
                    "id": "us_sismo_prueba_1",
                    "properties": {
                        "mag": 7.5,
                        "place": "10km of Valparaíso, Chile"
                    }
                },
                {
                    "id": "us_sismo_prueba_2", # Este no debería procesarse (mag baja y no es Chile)
                    "properties": {
                        "mag": 4.0,
                        "place": "California"
                    }
                }
            ]
        }
        
        # Configuramos el mock de requests para que devuelva nuestro JSON falso
        mock_get.return_value.json.return_value = mock_respuesta_usgs
        
        # Configuramos el DAO para que simule una inserción exitosa
        mock_dao_insert.return_value = True

        # Ejecutamos la petición a tu ruta
        response = self.client.get('/verificar-sismos')
        
        # Aserciones
        self.assertEqual(response.status_code, 200)
        json_response = response.get_json()
        
        # Verificamos que el sistema haya detectado exactamente 1 sismo (el de Chile)
        self.assertEqual(len(json_response['alertas_chile']), 1)
        self.assertEqual(json_response['alertas_chile'][0]['estado'], "ALERTA TSUNAMI")
        self.assertEqual(json_response['alertas_chile'][0]['id'], "us_sismo_prueba_1")
        
        # Verificamos que el código intentó guardar el sismo correcto en la BD
        mock_dao_insert.assert_called_once_with("us_sismo_prueba_1", 7.5, "ALERTA TSUNAMI")

    # 2. PRUEBA DEL ENDPOINT DE SIMULACRO (ÉXITO)
    @patch('ms_alertas.app.dao.insertar_alerta', new_callable=AsyncMock)
    def test_activar_simulacro_exitoso(self, mock_dao_insert):
        """Prueba que la ruta de simulacro genere correctamente la alerta roja."""
        
        # Simulamos que la base de datos guardó el simulacro sin problemas
        mock_dao_insert.return_value = True

        response = self.client.post('/activar-simulacro')
        
        self.assertEqual(response.status_code, 201)
        json_response = response.get_json()
        
        self.assertIn("BOLETIN-SHOA-SIM", json_response['id_alerta'])
        self.assertEqual(json_response['estado'], "ALERTA ROJA")
        
        # Verificamos que el DAO fue llamado correctamente
        mock_dao_insert.assert_called_once()

    # 3. PRUEBA DEL ENDPOINT DE SIMULACRO (FALLO DE BD)
    @patch('ms_alertas.app.dao.insertar_alerta', new_callable=AsyncMock)
    def test_activar_simulacro_error_bd(self, mock_dao_insert):
        """Verifica que el sistema retorne 500 si falla la escritura en Supabase."""
        
        # Simulamos que Prisma o la base de datos falló
        mock_dao_insert.return_value = False

        response = self.client.post('/activar-simulacro')
        
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.get_json()['error'], "Error al registrar simulacro")

if __name__ == '__main__':
    unittest.main()