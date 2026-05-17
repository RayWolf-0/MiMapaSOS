from prisma import Prisma

# Creamos una única instancia global del cliente
db = Prisma()

async def get_db():
    """
    Función para obtener la conexión. 
    Se asegura de conectar si no está activo.
    """
    if not db.is_connected():
        await db.connect()
    return db

async def close_db():
    """Para cerrar la conexión limpiamente al apagar el servicio"""
    if db.is_connected():
        await db.disconnect()