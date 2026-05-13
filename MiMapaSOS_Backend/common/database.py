import psycopg2
from psycopg2.extras import RealDictCursor

def get_db_connection():
    try:
        conn = psycopg2.connect(
            host="localhost",
            database="mimapasos_db",
            user="postgres",
            password="12345",
            port="5432"
        )
        return conn
    except Exception as e:
        print(f"Error de conexión: {e}")
        return None