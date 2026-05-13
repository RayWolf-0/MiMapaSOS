from common.database import get_db_connection
import json

class RutaDAO:
    def guardar_ruta(self, id_ruta, distancia, tiempo, nodos, id_usuario, id_zona, id_alerta):
        conn = get_db_connection()
        if not conn:
            return False
            
        try:
            cur = conn.cursor()

            trazado_json = json.dumps(nodos)

            sql = """
                INSERT INTO rutas (
                    id_ruta, 
                    distancia_metros, 
                    tiempo_estimado, 
                    trazado, 
                    usuarios_id_usuario, 
                    zonas_seguras_id_zona, 
                    alertas_tsunami_id_alerta
                ) VALUES (%s, %s, %s, %s, %s, %s, %s);
            """
            valores = (
                str(id_ruta), 
                float(distancia), 
                int(tiempo), 
                trazado_json, 
                int(id_usuario), 
                str(id_zona), 
                str(id_alerta)
            )
            
            cur.execute(sql, valores)
            conn.commit()
            
            print(f"--- Ruta {id_ruta} persistida exitosamente en PostgreSQL ---")
            return True

        except Exception as e:
            print(f"Error crítico en RutaDAO: {e}")
            if conn:
                conn.rollback()
            return False
            
        finally:
            if cur:
                cur.close()
            if conn:
                conn.close()