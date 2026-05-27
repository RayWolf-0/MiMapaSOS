import networkx as nx

class EvacuacionEngine:
    def __init__(self, grafo):
        self.G = grafo
        # Inicializamos feromonas en todas las aristas de forma segura
        for u, v, data in self.G.edges(data=True):
            data['pheromone'] = 1.0

    def costo_hibrido_aco(self, u, v, d):
        # Accedemos a los datos de la arista correctamente
        distancia = d.get('length', 1.0)
        feromona = d.get('pheromone', 1.0)
        return distancia / feromona

    def calcular_ruta(self, origen_node, destino_node):
        try:
            # Usamos el peso como una lambda para asegurar que Dijkstra acceda bien a los datos
            ruta = nx.shortest_path(
                self.G, 
                source=origen_node, 
                target=destino_node, 
                weight=lambda u, v, d: self.costo_hibrido_aco(u, v, d)
            )
            self._actualizar_feromonas(ruta)
            return ruta
        except (nx.NetworkXNoPath, nx.NodeNotFound):
            return None

    def _actualizar_feromonas(self, ruta):
        # Evaporación en todas las aristas
        for u, v, data in self.G.edges(data=True):
            data['pheromone'] *= 0.95

        # Refuerzo en la ruta ganadora
        for i in range(len(ruta) - 1):
            u, v = ruta[i], ruta[i+1]
            # Acceso seguro a la arista en multigrafos de OSMnx
            edge_data = self.G.get_edge_data(u, v)
            if edge_data:
                # Actualizamos todas las aristas entre estos dos nodos
                for key in edge_data:
                    edge_data[key]['pheromone'] += 0.5