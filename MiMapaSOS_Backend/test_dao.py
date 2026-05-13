from ms_alertas.dao import AlertaDAO

def probar_insercion():
    print("Iniciando prueba de base de datos...")
    dao = AlertaDAO()
    
    # simulacion sismo en valparaiso
    id_falso = "us7000test"
    magnitud_falsa = 7.5
    estado_falso = "Roja"
    
    resultado = dao.insertar_alerta(id_falso, magnitud_falsa, estado_falso)
    
    if resultado:
        print("¡Éxito! Los datos se guardaron en PostgreSQL.")
    else:
        print("Error: No se pudo guardar la información. Revisa tu contraseña en database.py.")

if __name__ == "__main__":
    probar_insercion()