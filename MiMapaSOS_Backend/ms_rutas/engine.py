import networkx as nx
import random

class EvacuacionEngine:
    def __init__(self, grafo):
        """
        Iniciamos con el grafo de OSMnx cargado desde el app.py
        """
        self.G = grafo
        # Inicializamos las feromonas en 1.0 para todas las aristas (edges)
        for u, v, key, data in self.G.edges(keys=True, data=True):
            data['pheromone'] = 1.0

    def costo_hibrido_aco(self, u, v, data):
        """
        Función de peso que usará Dijkstra.
        Combina: Distancia real / Feromonas.
        """
        distancia = data.get('length', 0.1)
        # Si la distancia es 0, usamos un valor mínimo para no dividir por cero
        if distancia <= 0: distancia = 0.1
        
        feromona = data.get('pheromone', 1.0)
        
        # A mayor feromona, menor es el 'costo' percibido del camino
        return distancia / feromona

    def calcular_ruta(self, origen_node, destino_node):
        """
        Calcula la mejor ruta usando Dijkstra influenciado por el rastro de feromonas.
        """
        try:
            # Dijkstra
            ruta = nx.shortest_path(
                self.G, 
                source=origen_node, 
                target=destino_node, 
                weight=self.costo_hibrido_aco
            )
            
            # actualizacion de feromonas después de trazar la ruta
            self._actualizar_feromonas(ruta)
            
            return ruta
        except nx.NetworkXNoPath:
            return None

    def _actualizar_feromonas(self, ruta):
        """
        Refuerza el camino trazado y aplica evaporación al resto del mapa.
        """
        # disminucion de feromonas (evaporación)
        for u, v, key, data in self.G.edges(keys=True, data=True):
            data['pheromone'] *= 0.95

        #tramos reforzados
        for i in range(len(ruta) - 1):
            u, v = ruta[i], ruta[i+1]
            if self.G.has_edge(u, v):
                self.G[u][v][0]['pheromone'] += 0.5