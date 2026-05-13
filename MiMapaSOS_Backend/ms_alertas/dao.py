from common.database import get_db_connection

class AlertaDAO:
    def insertar_alerta(self, id_alerta, magnitud, estado):
        conn = get_db_connection()
        if conn:
            try:
                cur = conn.cursor()
                # ON CONFLICT evita que el script falle si el sismo ya existe
                sql = """INSERT INTO alertas_tsunami (id_alerta, magnitud, estado)
                         VALUES (%s, %s, %s)
                         ON CONFLICT (id_alerta) DO NOTHING"""
                cur.execute(sql, (id_alerta, magnitud, estado))
                conn.commit()
                return True
            except Exception as e:
                print(f"Error al insertar en DB: {e}")
                return False
            finally:
                cur.close()
                conn.close()
        return False