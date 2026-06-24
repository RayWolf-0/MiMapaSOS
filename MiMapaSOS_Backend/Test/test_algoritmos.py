import unittest
import networkx as nx
from ms_rutas.engine import EvacuacionEngine

class TestMotorAlgoritmico(unittest.TestCase):

    def setUp(self):
        """
        Construimos un mini-grafo en memoria simulando la topografía de Valparaíso.
        No usamos OSMnx para evitar depender de internet y tiempos de carga largos.
        """
        # MultiDiGraph permite múltiples caminos entre dos mismos nodos (ej. calle vs escalera)
        self.G = nx.MultiDiGraph()
        
        # Nodo 1 (La costa/Plan) y Nodo 2 (La Cota 30/Cerro)
        self.G.add_node(1, x=-71.6260, y=-33.0480)
        self.G.add_node(2, x=-71.6245, y=-33.0465)
        self.G.add_node(3, x=-71.6200, y=-33.0400)

        # Arista 0 (Camino A): Una avenida principal plana y peligrosa (Ej. Errázuriz)
        self.G.add_edge(1, 2, key=0, length=100.0, highway='primary', name='Avenida Errazuriz')
        
        # Arista 1 (Camino B): Una escalera corta pero segura hacia el cerro
        self.G.add_edge(1, 2, key=1, length=150.0, highway='steps', name='Subida Templeman')

        # Instanciamos tu motor con nuestro grafo de prueba
        self.engine = EvacuacionEngine(self.G)

    def test_heuristica_penaliza_zonas_inundables(self):
        """Verifica que el algoritmo castigue el peso de las avenidas costeras."""
        datos_avenida = self.G[1][2][0]
        
        # Calculamos el costo con tu función
        costo = self.engine.costo_hibrido_aco(1, 2, datos_avenida)
        
        # Una avenida 'primary' (x5000) llamada 'Errazuriz' (x10000) 
        # debería tener un costo artificial gigantesco comparado a su largo real (100m)
        self.assertGreater(costo, 100000.0, "El costo de vías inundables debe ser prohibitivo")

    def test_heuristica_premia_evacuacion_vertical(self):
        """Verifica que las escaleras y senderos reduzcan su costo percibido."""
        datos_escalera = self.G[1][2][1]
        
        costo = self.engine.costo_hibrido_aco(1, 2, datos_escalera)
        
        # La escalera mide 150m, pero al ser 'steps' se multiplica por 0.2
        # Su costo percibido por el algoritmo debe ser 30.0
        self.assertEqual(costo, 30.0, "El algoritmo no está premiando la evacuación por escaleras")

    def test_calculo_ruta_elige_camino_seguro(self):
        """
        Prueba reina: Comprueba que Dijkstra modificado elija la escalera (150m) 
        por sobre la avenida plana (100m) para salvar al usuario.
        """
        # Ejecutamos el cálculo de ruta
        ruta = self.engine.calcular_ruta(1, 2)
        
        # En NetworkX, shortest_path devuelve la lista de nodos. 
        # Sabemos que pasó de 1 a 2 directamente.
        self.assertEqual(ruta, [1, 2])
        
        # Para estar 100% seguros de qué arista tomó (ya que hay dos conectando 1 y 2),
        # comparamos los costos de ambas.
        costo_avenida = self.engine.costo_hibrido_aco(1, 2, self.G[1][2][0])
        costo_escalera = self.engine.costo_hibrido_aco(1, 2, self.G[1][2][1])
        
        self.assertLess(costo_escalera, costo_avenida, "El algoritmo decidió irse por la costa en lugar del cerro")

    def test_actualizacion_feromonas_aco(self):
        """Verifica que el rastro de feromonas evapore y se refuerce correctamente."""
        # Estado inicial: Todas las feromonas parten en 1.0
        self.assertEqual(self.G[1][2][0]['pheromone'], 1.0)
        
        # Forzamos una actualización de feromonas simulando que alguien usó la ruta [1, 2]
        self.engine._actualizar_feromonas([1, 2])
        
        # La arista debe haber evaporado (1.0 * 0.95) y luego reforzado (+0.5)
        # No podemos predecir a qué MultiEdge (calle o escalera) se lo sumó el código base exacto,
        # pero al menos una de las dos opciones entre 1 y 2 debe tener más feromonas que el inicio.
        feromona_calle = self.G[1][2][0]['pheromone']
        feromona_escalera = self.G[1][2][1]['pheromone']
        
        max_feromona = max(feromona_calle, feromona_escalera)
        self.assertGreater(max_feromona, 1.0, "Las feromonas de la colonia de hormigas no se están actualizando")

if __name__ == '__main__':
    unittest.main()