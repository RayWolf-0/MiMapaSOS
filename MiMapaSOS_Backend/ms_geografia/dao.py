from common.database import get_db_connection

class GeografiaDAO:
    def obtener_zonas_seguras(self):
        conn = get_db_connection()
        if not conn: return []
        try:
            cur = conn.cursor()
            sql = """
                SELECT id_zona, nombre, descripcion, 
                       ST_X(geom) as lon, ST_Y(geom) as lat
                FROM zonas_seguras
            """
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, row)) for row in cur.fetchall()]
        finally:
            cur.close()
            conn.close()

    def obtener_zonas_inundacion(self):
        conn = get_db_connection()
        if not conn: return []
        try:
            cur = conn.cursor()
            sql = "SELECT id_inundacion, cota, tipo_riesgo FROM zona_inundacion"
            cur.execute(sql)
            columnas = [desc[0] for desc in cur.description]
            return [dict(zip(columnas, row)) for row in cur.fetchall()]
        finally:
            cur.close()
            conn.close()