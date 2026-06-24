import unittest
from prisma import Prisma

class TestConexionSupabase(unittest.IsolatedAsyncioTestCase):

    async def asyncSetUp(self):
        """1 e 2. Instanciamos el cliente y conectamos antes de la prueba"""
        self.db = Prisma()
        await self.db.connect()

    async def asyncTearDown(self):
        """4. Siempre desconectar al terminar, pase lo que pase"""
        if self.db.is_connected():
            await self.db.disconnect()

    async def test_conexion_y_lectura_usuarios(self):
        """3. Verifica que Prisma se conecte a Supabase y lea la tabla usuarios"""
        
        # Intentamos contar los usuarios (operación de solo lectura, muy segura)
        count = await self.db.usuarios.count()
        
        # Aserciones formales en lugar de prints
        self.assertIsNotNone(count, "El conteo no debería ser nulo si la conexión fue exitosa")
        self.assertIsInstance(count, int, "El conteo devuelto debe ser un número entero")
        
        # Imprimimos el resultado solo como confirmación visual en la consola
        print(f"\n[Exito] Conexión OK. {count} registros en la tabla 'usuarios'.")

if __name__ == "__main__":
    unittest.main()