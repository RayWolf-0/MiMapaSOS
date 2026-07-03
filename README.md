# MiMapa SOS - Sistema de Evacuación ante Tsunamis
*(Valparaíso y Viña del Mar, Chile)*

## 1. Descripción del Proyecto

MiMapa SOS es una solución tecnológica diseñada para coordinar, optimizar y guiar evacuaciones peatonales preventivas y de emergencia ante alertas de tsunami en las comunas de Valparaíso y Viña del Mar. El objetivo principal de la plataforma es guiar a los usuarios en zona de riesgo de inundación hacia los puntos seguros más cercanos por encima de la Cota 30 (altura de seguridad de 30 metros definida por las autoridades locales), evitando que utilicen vías costeras de alto peligro.

El sistema combina:
*   Una arquitectura de **microservicios backend en Python (Flask)** que interactúa con una base de datos **PostgreSQL + PostGIS** (alojada en Supabase) usando **Prisma ORM**.
*   Un **motor de rutas inteligente** que descarga redes de calles reales de OpenStreetMap y calcula vías de evacuación aplicando penalizaciones espaciales de inundación, priorización de escaleras/pasarelas peatonales y un modelo de alineación de flujos basado en el comportamiento de colonias de hormigas (ACO - Ant Colony Optimization).
*   Una **aplicación móvil y web en Flutter** que interactúa con la geolocalización del dispositivo, visualiza mapas vectoriales dinámicos, consume los microservicios y alerta acústicamente a la población en caso de emergencia.

---

## 2. Arquitectura del Sistema

La solución está diseñada bajo un enfoque desacoplado de microservicios para garantizar escalabilidad, tolerancia a fallos y despliegues independientes.

```mermaid
graph TD
    subgraph Cliente_Movil [Cliente Móvil / Web]
        App[App Flutter]
        GPS[Geolocator GPS]
        Map[Flutter Map / Leaflet]
        Audio[Audioplayers - Alarma]
        App --> GPS
        App --> Map
        App --> Audio
    end

    subgraph Backend_Microservicios [Backend en Flask]
        MS_User[ms_usuarios - Port 5001]
        MS_Alert[ms_alertas - Port 5002]
        MS_Route[ms_rutas - Port 5003]
        MS_Geog[ms_geografia - Port 5004]
        
        MS_Route --> Engine[EvacuacionEngine - OSMnx & NetworkX]
    end

    subgraph Base_de_Datos [Persistencia]
        DB[(Supabase PostgreSQL + PostGIS)]
    end

    subgraph Externo [Servicios Externos]
        GoogleAuth[Google OAuth 2.0]
        USGS[USGS Earthquake API]
        OSM[OpenStreetMap Data]
    end

    %% Flujos de datos y comunicación
    App -->|1. Autenticación Google ID Token| MS_User
    MS_User -->|Validar Token| GoogleAuth
    
    App -->|2. Obtener Alertas Activas| MS_Alert
    MS_Alert -->|Consultar Sismos Reales| USGS
    
    App -->|3. Cargar Zonas de Riesgo / Seguridad| MS_Geog
    
    App -->|4. Solicitar Ruta de Evacuación| MS_Route
    Engine -->|Descargar Red de Caminos Peatonales| OSM

    %% Conexiones con la base de datos
    MS_User -->|Prisma Client Py| DB
    MS_Alert -->|Prisma Client Py| DB
    MS_Route -->|Prisma Client Py| DB
    MS_Geog -->|Prisma Client Py| DB
```

### 2.1 Microservicios del Backend

*   **ms_usuarios (Puerto 5001)**: Gestiona el inicio de sesión mediante autenticación federada con Google OAuth. Valida tokens de identidad enviados por la aplicación móvil y registra automáticamente nuevos usuarios en la base de datos si no existen previamente.
*   **ms_alertas (Puerto 5002)**: Monitorea sismos y posibles amenazas de tsunami. Consume feeds de datos en tiempo real de la USGS, filtra eventos ocurridos en Chile con magnitudes iguales o superiores a 5.0 y genera estados de precaución o alertas de tsunami en la base de datos. También expone rutas de prueba para simulacros controlados.
*   **ms_rutas (Puerto 5003)**: El núcleo lógico de la aplicación. Descarga la red de caminos peatonales de Valparaíso y Viña del Mar y calcula la ruta óptima de evacuación más rápida y segura desde las coordenadas del usuario hacia la zona segura más cercana. Persiste las rutas generadas para análisis posterior.
*   **ms_geografia (Puerto 5004)**: Expone las ubicaciones geográficas de las zonas seguras (puntos sobre la Cota 30) y los límites de las zonas inundables para que el cliente móvil las renderice como capas espaciales (Polígonos y Marcadores).

---

## 3. Modelo de Datos (Prisma Schema)

El esquema de base de datos aprovecha las capacidades relacionales y espaciales de PostgreSQL con la extensión PostGIS. A continuación se detallan las tablas principales administradas mediante el archivo [schema.prisma](file:///c:/TallerAplicado/MapaSOS/MiMapaSOS_Backend/prisma/schema.prisma):

| Tabla | Descripción | Campos Clave |
| :--- | :--- | :--- |
| **usuarios** | Información de los ciudadanos o turistas registrados. | `id_usuario` (PK), `nombre` |
| **autenticacion** | Credenciales vinculadas al login social de Google. | `google_id` (PK), `email`, `token`, `usuarios_id_usuario` (FK) |
| **alertas_tsunami** | Registro de alertas sísmicas activas y de tsunami generadas por USGS o simulacros. | `id_alerta` (PK), `magnitud`, `estado`, `fecha_hora` |
| **zonas_seguras** | Puntos geográficos de refugio sobre la Cota 30. Posee columna geométrica. | `id_zona` (PK), `geom` (PostGIS Geometry), `nombre`, `descripcion`, `detalle_zona_id_detalle` (FK) |
| **detalle_zona** | Especificaciones físicas de las zonas seguras. | `id_detalle` (PK), `cota` (elevación), `capacidad` |
| **zona_inundacion** | Delimitación de sectores bajo riesgo de anegamiento. | `id_inundacion` (PK), `cota`, `tipo_riesgo` |
| **rutas** | Trazados de evacuación calculados e indicados a los usuarios. | `id_ruta` (PK), `distancia_metros`, `tiempo_estimado`, `trazado` (JSON de nodos del grafo), `usuarios_id_usuario` (FK), `zonas_seguras_id_zona` (FK) |
| **ubicaciones_tiempo_real** | Historial de localización geográfica de los usuarios durante el proceso de evacuación. | `id_posicion` (PK), `geom` (PostGIS Geometry), `fecha_hora`, `usuarios_id_usuario` (FK) |

---

## 4. El Motor de Evacuación (EvacuacionEngine)

El cálculo de rutas de evacuación ante catástrofes no puede depender de un algoritmo de distancia más corta tradicional (como Dijkstra simple sobre longitud de calles), ya que este podría dirigir a los usuarios a lo largo del borde costero plano, incrementando el riesgo de ser alcanzados por la ola.

Para solucionar esto, [ms_rutas/engine.py](file:///c:/TallerAplicado/MapaSOS/MiMapaSOS_Backend/ms_rutas/engine.py) implementa un modelo de costo adaptativo:

### 4.1 Costo Híbrido de Aristas
El costo ficticio de transitar por cada calle (arista) se calcula mediante la fórmula:

$$\text{Costo} = \frac{\text{Distancia Real} \times \text{Penalización}}{\text{Concentración de Feromonas}}$$

Las penalizaciones se aplican dinámicamente según la clasificación y ubicación de las vías:
1.  **Priorización Peatonal Extrema**: Vías etiquetadas en OpenStreetMap como `steps` (escaleras), `pedestrian` (paseos peatonales), `footway` o `path` reciben un **descuento del 90%** en su costo aparente (multiplicador de $0.1$). Esto empuja al algoritmo a elegir escaleras y pasajes que suben directamente a los cerros, en lugar de avenidas vehiculares.
2.  **Castigo por Borde Costero**: Calles expuestas al mar como *Av. Altamirano, Av. España, Av. Marina, San Martín, Perú, Borgoño* y *Jorge Montt* reciben una **penalización extrema de 50,000x** en su peso, impidiendo que el motor trace rutas de escape que transcurran por la costa.
3.  **Castigo por Plan de la Ciudad**: Calles en la planicie interior paralelas al mar (*Errázuriz, Blanco, Brasil, Condell, Victoria, Independencia, Libertad, 1 Norte*) reciben un **castigo de 10,000x**, incentivando a las personas a abandonarlas inmediatamente y tomar calles perpendiculares de subida hacia los cerros.
4.  **Penalización Espacial de Zona Baja**: Cualquier nodo situado dentro del polígono delimitador de la inundación potencial del plan de Valparaíso/Viña del Mar (latitud entre $-33.055$ y $-33.000$, longitud entre $-71.635$ y $-71.540$) recibe un factor de **2,000x** para acelerar el escape hacia cotas elevadas.

### 4.2 Optimización por Colonia de Hormigas (ACO)
Para evitar que toda la población colapse una sola vía de escape, el motor implementa un mecanismo de feromonas:
*   Cada vez que una ruta es calculada y asignada a un usuario, los enlaces pertenecientes a esa ruta reciben un depósito de feromona (`+0.5`), disminuyendo su costo relativo para futuros cálculos y creando un canal preferencial de evacuación coordinada.
*   En cada nueva consulta de ruta, el sistema aplica una evaporación global del 5% (`*0.95`) en todo el grafo para disipar rutas obsoletas y mantener el sistema dinámico.

---

## 5. Guía de Instalación y Despliegue

Siga estos pasos detallados para configurar y levantar la arquitectura completa en su entorno local de desarrollo.

### 5.1 Requisitos Previos

Asegúrese de contar con los siguientes componentes en su sistema operativo:
*   **Python 3.10 o superior** (para ejecutar los microservicios backend).
*   **Flutter SDK 3.0.0 o superior** (para compilar y ejecutar la app móvil).
*   **Node.js y npm** (necesarios para ejecutar herramientas de desarrollo de Prisma CLI).
*   **Base de datos PostgreSQL** activa, preferiblemente con la extensión **PostGIS** habilitada. Puede crear una instancia gratuita en [Supabase](https://supabase.com/).

---

### 5.2 Configuración del Backend

#### Paso 1: Configurar las variables de entorno
Cree un archivo llamado `.env` en la raíz del directorio `MiMapaSOS_Backend/` basándose en el siguiente ejemplo:

```bash
# Dirección de conexión de pool de Supabase/PostgreSQL (para uso de la app)
DATABASE_URL="postgresql://usuario:contraseña@servidor:puerto/base_de_datos?schema=public"

# Conexión directa a la base de datos (requerida por Prisma para aplicar esquemas y migraciones)
DIRECT_URL="postgresql://usuario:contraseña@servidor:puerto/base_de_datos?schema=public"
```

#### Paso 2: Crear el entorno virtual e instalar dependencias
Abra un terminal en `MiMapaSOS_Backend/` y ejecute:

```powershell
# Crear entorno virtual de Python
python -m venv venv

# Activar el entorno virtual (Windows)
.\venv\Scripts\activate

# Instalar dependencias de Flask, base de datos y utilidades
pip install -r requirements.txt

# Instalar el cliente de Prisma para Python de forma explícita
pip install prisma
```

#### Paso 3: Generar el cliente de base de datos con Prisma
El backend utiliza `prisma-client-py`. Genere los archivos de binding de Python ejecutando:

```powershell
# Generar cliente Python
prisma generate
```

#### Paso 4: Levantar los microservicios
Puede iniciar cada microservicio de forma manual abriendo múltiples consolas y activando el entorno virtual en cada una de ellas, o bien utilizar herramientas de procesos si dispone de ellos.

Los comandos manuales para cada microservicio son:

```powershell
# En consola 1: Levantar microservicio de Usuarios (Port 5001)
set PYTHONPATH=.
python ms_usuarios/app.py

# En consola 2: Levantar microservicio de Alertas (Port 5002)
set PYTHONPATH=.
python ms_alertas/app.py

# En consola 3: Levantar microservicio de Rutas (Port 5003)
# NOTA: Al iniciar este servicio por primera vez, descargará el mapa peatonal OSM (aprox. 8km a la redonda de Valparaíso). Esto puede demorar un par de minutos según la velocidad de conexión.
set PYTHONPATH=.
python ms_rutas/app.py

# En consola 4: Levantar microservicio de Geografía (Port 5004)
set PYTHONPATH=.
python ms_geografia/app.py
```

---

### 5.3 Configuración del Frontend (Flutter)

#### Paso 1: Instalar dependencias del proyecto Flutter
Abra un terminal en la carpeta `MiMapaSOS_Front/` y ejecute:

```bash
flutter pub get
```

#### Paso 2: Configurar la dirección IP del servidor Backend
Dado que la aplicación móvil se ejecutará en un emulador o un dispositivo físico, debe apuntar las solicitudes HTTP a la dirección IP de la máquina donde se están ejecutando los microservicios backend.

Abra el archivo [evacuacion_service.dart](file:///c:/TallerAplicado/MapaSOS/MiMapaSOS_Front/lib/src/services/evacuacion_service.dart) y modifique la línea de la dirección IP base:

```dart
// Reemplace 10.223.8.163 con la IP local de su computadora en la red Wi-Fi
final String _baseUrl = "http://SU_DIRECCION_IP:5003";
```

#### Paso 3: Ejecutar la aplicación
Conecte su teléfono móvil con depuración USB activa o inicie un emulador, y luego ejecute en el terminal:

```bash
flutter run
```

---

## 6. Guía de Pruebas y Validación (Paso a Paso)

Siga las siguientes instrucciones estructuradas para validar el correcto funcionamiento de cada componente del ecosistema.

### 6.1 Validación del Registro e Inicio de Sesión
1.  Abra la aplicación en su dispositivo móvil. Visualizará la pantalla de inicio de sesión (`LoginPage`).
2.  Presione el botón "Iniciar Sesión con Google".
3.  El cliente de Flutter solicitará autorización a Firebase Auth, el cual retornará un Google ID Token.
4.  La aplicación enviará dicho token mediante un método `POST` al endpoint `/auth/google` del microservicio `ms_usuarios` (Puerto 5001).
5.  **Resultado esperado**: En la terminal de `ms_usuarios`, se debe imprimir el mensaje de confirmación:
    `Registrando nuevo usuario con ID: X` (si es la primera vez) o `Bienvenida de vuelta. ID recuperado: X`. La aplicación del móvil pasará automáticamente a la pantalla del mapa interactivo (`MapaPage`).

### 6.2 Consulta de Zonas Seguras y de Inundación en el Mapa
1.  Una vez cargado el mapa principal, la aplicación móvil realiza dos llamadas HTTP tipo `GET` en segundo plano:
    *   Al microservicio de geografía: `GET http://SU_DIRECCION_IP:5004/mapa/zonas-seguras`
    *   Al microservicio de geografía: `GET http://SU_DIRECCION_IP:5004/mapa/zonas-inundacion`
2.  **Resultado esperado**:
    *   El mapa debe dibujar marcadores verdes en las ubicaciones correspondientes a las zonas de resguardo (como Cancha Cerro Alegre, Quinta Vergara, Universidad Santa María, etc.).
    *   El mapa debe dibujar sombreados o zonas delimitadas (según el set de datos geográficos) correspondientes a las cotas bajo peligro de inundación.

### 6.3 Monitoreo Sísmico y Simulación de Emergencia
Para probar la reacción acústica y visual del sistema ante un desastre, se puede activar un simulacro de alerta:
1.  Utilice un cliente REST (como Postman o curl) para realizar una petición HTTP en su computadora al microservicio de alertas:
    ```bash
    curl -X POST http://localhost:5002/activar-simulacro
    ```
2.  El servicio insertará en base de datos una alerta con estado `ALERTA ROJA` y retornará el JSON del simulacro.
3.  **Resultado esperado en el móvil**: La aplicación, al sincronizarse, detectará la alerta activa. El mapa cambiará a modo de evacuación de emergencia, se desplegará una pantalla roja con instrucciones ("Evacuación inmediata a zonas sobre la Cota 30") y se reproducirá una sirena de evacuación a través del altavoz del dispositivo.

### 6.4 Cálculo de la Ruta de Evacuación Segura
1.  Con la simulación de emergencia activa en la aplicación móvil, presione en el botón de calcular evacuación o marque una ubicación de origen en el plano dentro del plan inundable de Valparaíso (por ejemplo, cerca de la costa o de la Av. Errázuriz).
2.  El dispositivo enviará sus coordenadas al microservicio de rutas:
    `GET http://SU_DIRECCION_IP:5003/calcular-evacuacion?lat=-33.042&lon=-71.615&id_usuario=1&id_alerta=ID_ALERTA_ACTIVA`
3.  El motor `EvacuacionEngine` procesará el algoritmo de costo híbrido. Evitará las avenidas costeras que tienen 50k de penalización y trazará una ruta que busque escaleras y calles empinadas hacia los cerros de Valparaíso.
4.  **Resultado esperado**: La respuesta HTTP retornará código `200 OK` con un JSON estructurado que incluye:
    *   `distancia_m`: La longitud física a caminar.
    *   `tiempo_estimado_min`: El tiempo calculado a paso moderado (1.1 m/s).
    *   `trazado_nodos`: La lista ordenada de coordenadas latitud/longitud que forman el camino de escape.
    En la pantalla del móvil se dibujará una línea roja continua que conecta la ubicación del usuario con la zona segura de destino asignada por encima del límite de riesgo. En la terminal de base de datos se confirmará la escritura de la ruta: `--- ruta RT-XXXX persistida exitosamente con prisma ---`.
