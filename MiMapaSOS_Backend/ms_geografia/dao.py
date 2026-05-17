from common.database import get_db

class GeografiaDAO:
    async def obtener_zonas_seguras(self):
        """
        Recupera las zonas seguras desde Supabase usando Raw SQL para PostGIS.
        """
        try:
            db = await get_db()

            sql = """
                SELECT id_zona, nombre, descripcion, 
                       ST_X(geom::geometry) as lon, 
                       ST_Y(geom::geometry) as lat
                FROM zonas_seguras
                WHERE geom IS NOT NULL
            """
            resultados = await db.query_raw(sql)

            return resultados
            
        except Exception as e:
            print(f"Error en GeografiaDAO (Zonas Seguras): {e}")
            return []

    async def obtener_zonas_inundacion(self):
        """
        Recupera las áreas de riesgo de inundación.
        """
        try:
            db = await get_db()

            resultados = await db.zona_inundacion.find_many()

            return [zona.dict() for zona in resultados]
            
        except Exception as e:
            print(f"Error en GeografiaDAO (Inundación): {e}")
            return []