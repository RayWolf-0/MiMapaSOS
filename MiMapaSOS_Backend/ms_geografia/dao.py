from common.database import get_db_connection

class GeografiaDAO:
    def obtener_zonas_seguras(self):
        conn = get_db_connection()
        if not conn: return []
        try:
            cur = conn.cursor()
            # latitud y longitud de las zonas seguras
            sql = """
                SELECT id_zona, nombre, descripcion, 
                       ST_X(geom) as lon, ST_Y(geom) as lat,
                       detalle_zona_id_detalle
                FROM zonas_seguras
            """
            cur.execute(sql)
            return cur.fetchall()
        finally:
            cur.close()
            conn.close()

    def obtener_zonas_inundacion(self):
        conn = get_db_connection()
        if not conn: return []
        try:
            cur = conn.cursor()
            # datos de posible riesgo
            sql = "SELECT id_inundacion, cota, tipo_riesgo FROM zona_inundacion"
            cur.execute(sql)
            return cur.fetchall()
        finally:
            cur.close()
            conn.close()