from common.database import get_db

class UsuarioDAO:
    async def obtener_o_registrar(self, google_id, email, nombre):
        try:
            db = await get_db()

            # 1. Buscamos si el usuario ya existe en la base de datos
            auth_record = await db.autenticacion.find_first(
                where={'google_id': str(google_id)}
            )

            if auth_record:
                # ¡Ya existe! Recuperamos su ID usando el atributo en minúsculas
                user_id = auth_record.usuarios_id_usuario
                print(f"Bienvenida de vuelta. ID recuperado: {user_id}")
            else:
                # 2. No existe. Calculamos el nuevo ID (sin comillas en el nombre de la tabla)
                res = await db.query_raw('SELECT COALESCE(MAX(id_usuario), 0) + 1 as next_id FROM usuarios')
                new_id = int(res[0]['next_id']) # Lo pasamos a int() por seguridad
                
                print(f"Registrando nuevo usuario con ID: {new_id}")

                # 3. Guardamos en ambas tablas usando una transacción segura
                async with db.tx() as transaction:
                    await transaction.usuarios.create(
                        data={
                            'id_usuario': new_id,
                            'nombre': nombre
                        }
                    )
                    await transaction.autenticacion.create(
                        data={
                            'google_id': str(google_id),
                            'email': email,
                            'usuarios_id_usuario': new_id
                        }
                    )
                
                user_id = new_id

            # 4. Devolvemos los datos limpios al controlador
            return {"id": user_id, "nombre": nombre, "email": email}

        except Exception as e:
            print(f"Error crítico en UsuarioDAO: {e}")
            raise e