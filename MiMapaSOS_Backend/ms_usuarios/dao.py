from common.database import get_db

class UsuarioDAO:
    async def obtener_o_registrar(self, google_id, email, nombre):
        try:
            db = await get_db()

            auth_record = await db.autenticacion.find_first(
                where={'google_id': str(google_id)}
            )

            if auth_record:
                user_id = auth_record.USUARIOS_id_usuario
            else:
                res = await db.query_raw('SELECT COALESCE(MAX(id_usuario), 0) + 1 as next_id FROM "USUARIOS"')
                new_id = res[0]['next_id']
                async with db.batch_() as batch:
                    batch.usuarios.create(
                        data={
                            'id_usuario': new_id,
                            'nombre': nombre
                        }
                    )
                    batch.autenticacion.create(
                        data={
                            'google_id': str(google_id),
                            'email': email,
                            'USUARIOS_id_usuario': new_id
                        }
                    )
                
                user_id = new_id

            return {"id": user_id, "nombre": nombre, "email": email}

        except Exception as e:
            print(f"Error en UsuarioDAO: {e}")
            raise e