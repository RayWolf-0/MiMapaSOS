import asyncio
from prisma import Prisma

async def test_prisma_connection():
    # 1. Instanciamos el cliente
    db = Prisma()
    
    print("--- 📡 Iniciando prueba de conexión con Prisma ---")
    
    try:
        # 2. Conectamos a Supabase
        await db.connect()
        print("✅ Conexión establecida exitosamente.")

        # 3. Intentamos leer algo simple (por ejemplo, contar los usuarios)
        # Nota: Prisma usa el nombre de la tabla en minúsculas
        count = await db.usuarios.count()
        print(f"📊 Prueba de lectura: Se encontraron {count} registros en la tabla USUARIOS.")

    except Exception as e:
        print(f"❌ Error durante la prueba: {e}")
    
    finally:
        # 4. Siempre desconectar al terminar
        if db.is_connected():
            await db.disconnect()
            print("--- 🔌 Conexión cerrada ---")

if __name__ == "__main__":
    # Ejecutamos la función asíncrona
    asyncio.run(test_prisma_connection())