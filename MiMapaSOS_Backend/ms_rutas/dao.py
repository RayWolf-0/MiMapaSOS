from common.database import get_db
import json

class RutaDAO:
    async def guardar_ruta(self, id_ruta, distancia, tiempo, nodos, id_usuario, id_zona, id_alerta, id_inundacion="ZI-PLAN-VAP-01"):
        """
        Guarda la ruta calculada en Supabase usando Prisma.
        """
        try:
            db = await get_db()
            
            # Convertimos la lista de nodos a lista de enteros estándar para evitar errores de serialización
            nodos_limpios = [int(n) for n in nodos]

            await db.rutas.create(
                data={
                    'id_ruta': str(id_ruta),
                    'distancia_metros': float(distancia),
                    'tiempo_estimado': int(tiempo),
                    'trazado': json.dumps(nodos_limpios), 
                    'usuarios_id_usuario': int(id_usuario),
                    'zonas_seguras_id_zona': str(id_zona),
                    'alertas_tsunami_id_alerta': str(id_alerta),
                    'zona_inundacion_id_inundacion': str(id_inundacion)
                }
            )

            print(f"--- Ruta {id_ruta} persistida exitosamente con Prisma ---")
            return True

        except Exception as e:
            print(f"Error crítico en RutaDAO: {e}")
            return False