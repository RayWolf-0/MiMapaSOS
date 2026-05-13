from common.database import get_db_connection

class UsuarioDAO:
    def obtener_o_registrar(self, google_id, email, nombre):
        conn = get_db_connection()
        cur = conn.cursor()
        try:
            # Buscar si el google_id ya está en la tabla autenticacion
            cur.execute("SELECT usuarios_id_usuario FROM autenticacion WHERE google_id = %s", (google_id,))
            resultado = cur.fetchone()

            if resultado:
                # El usuario ya existe
                user_id = resultado['usuarios_id_usuario']
            else:
                # crear id si un usuario es nuevo
                cur.execute("SELECT COALESCE(MAX(id_usuario), 0) + 1 FROM usuarios")
                new_id = cur.fetchone()['f0']
                
                # insertar usuarios en la tabla
                cur.execute("INSERT INTO usuarios (id_usuario, nombre) VALUES (%s, %s)", (new_id, nombre))
                
                # autenticacion
                cur.execute("INSERT INTO autenticacion (google_id, email, usuarios_id_usuario) VALUES (%s, %s, %s)", 
                            (google_id, email, new_id))
                conn.commit()
                user_id = new_id

            return {"id": user_id, "nombre": nombre, "email": email}
        
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            cur.close()
            conn.close()