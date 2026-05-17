from common.database import get_db
from prisma import errors

class AlertaDAO:
    async def insertar_alerta(self, id_alerta, magnitud, estado):
        """
        Inserta una nueva alerta de tsunami en Supabase.
        Si el id_alerta ya existe, se omite gracias al manejo de excepciones.
        """
        try:
            db = await get_db()

            nueva_alerta = await db.alertas_tsunami.create(
                data={
                    'id_alerta': str(id_alerta),
                    'magnitud': float(magnitud),
                    'estado': str(estado)
                }
            )
            
            print(f"--- Alerta {id_alerta} registrada exitosamente con Prisma ---")
            return True

        except errors.UniqueViolationError:
            print(f"--- Alerta {id_alerta} ya existía, se omitió el insert ---")
            return True
            
        except Exception as e:
            print(f"Error al insertar alerta en Supabase: {e}")
            return False