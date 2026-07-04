from prisma import Prisma

# Creamos una única instancia global del cliente
db = Prisma()

async def get_db():
    """
    Función para obtener la conexión. 
    Se asegura de conectar si no está activo, y realiza una reconexión
    si la base de datos ha cerrado la conexión por inactividad.
    """
    if not db.is_connected():
        await db.connect()
    else:
        try:
            # Consulta de control para verificar si la conexión sigue viva
            await db.query_raw('SELECT 1')
        except Exception:
            # La conexión está caída: desconectar limpiamente y volver a conectar
            try:
                await db.disconnect()
            except Exception:
                pass
            await db.connect()
    return db

async def close_db():
    """Para cerrar la conexión limpiamente al apagar el servicio"""
    if db.is_connected():
        await db.disconnect()