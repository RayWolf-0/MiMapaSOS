import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/evacuacion_service.dart';
import 'dart:ui';
import 'alerta_page.dart';
import 'perfil_page.dart';

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  final String _mainFont = 'Urbanist';
  final MapController _mapController = MapController();

  LatLng? _ubicacionActual;
  LatLng? _pinSimulacion;
  bool _buscandoGPS = true;
  List<CircleMarker> _circulosZonasSeguras = [];

  String _nombreUsuario = 'usuario';

  // Polígono de tierra firme — SOLO costa Pacífico + Punta Ángeles + caja continental.
  //
  // ⚠ POR QUÉ no trazamos la costa de la bahía (Puerto → Barón → Viña):
  //   El rayo se proyecta al ESTE. Los vértices de la bahía corren de NW a SE,
  //   cruzando el rayo de cualquier punto urbano de Valparaíso → doble cruce
  //   (costa + caja continental) → paridad par → clasificado "mar". Bug crítico.
  //   Al eliminar esos vértices, la bahía queda clasificada como "tierra" (aceptable
  //   para esta app) y todo el casco urbano queda correctamente clasificado como tierra.
  static const List<LatLng> _poligonoLand = [
    // === Costa sur (Laguna Verde → Torpederas) ===
    LatLng(-33.100, -71.665),
    LatLng(-33.065, -71.650), // Laguna Verde
    LatLng(-33.055, -71.636), // Torpederas
    // === Costa Pacífico de Playa Ancha (oeste) ===
    LatLng(-33.050, -71.640),
    LatLng(-33.044, -71.648),
    LatLng(-33.037, -71.654),
    LatLng(-33.028, -71.659),
    LatLng(-33.019, -71.659),
    LatLng(-33.012, -71.654), // Punta Ángeles
    // === Cierre norte: NO se traza la bahía (evita doble cruce en zona urbana) ===
    LatLng(-32.945, -71.645), // Punto norte de cierre (sobre el agua)
    LatLng(-32.945, -71.400), // Esquina NE
    // === Caja continental ===
    LatLng(-33.120, -71.400),
    LatLng(-33.120, -71.665),
  ];


  // Algoritmo Ray-Casting (Even-Odd) proyectando el rayo al ESTE
  bool _puntoEnPoligono(LatLng punto, List<LatLng> vertices) {
    int intersectCount = 0;
    for (int i = 0; i < vertices.length; i++) {
      LatLng p1 = vertices[i];
      LatLng p2 = vertices[(i + 1) % vertices.length];
      if (p1.latitude > punto.latitude != p2.latitude > punto.latitude) {
        double intersectLng = (p2.longitude - p1.longitude) *
                (punto.latitude - p1.latitude) /
                (p2.latitude - p1.latitude) +
            p1.longitude;
        if (punto.longitude < intersectLng) {
          intersectCount++;
        }
      }
    }
    return intersectCount % 2 != 0;
  }

  @override
  void initState() {
    super.initState();
    _cargarUsuario();
    _determinarUbicacion();
    _cargarPerimetrosVisuales();
  }

  // Ahora Firebase Auth sí tiene sesión activa (login_page la registra).
  // providerData de google.com siempre contiene el displayName completo.
  void _cargarUsuario() {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        setState(() {
          _nombreUsuario = _extraerNombre(user);
        });
      }

      // Listener para mantener el nombre actualizado si cambia la sesión
      FirebaseAuth.instance.authStateChanges().listen((User? user) {
        if (mounted) {
          setState(() {
            _nombreUsuario = user != null ? _extraerNombre(user) : 'usuario';
          });
        }
      });
    } catch (e) {
      debugPrint("No se pudo cargar la sesión de Auth: $e");
    }
  }

  String _extraerNombre(User user) {
    // providerData de Google siempre tiene displayName correcto
    try {
      final googleProvider = user.providerData.firstWhere(
        (p) => p.providerId == 'google.com',
      );
      if (googleProvider.displayName != null &&
          googleProvider.displayName!.trim().isNotEmpty) {
        return googleProvider.displayName!.trim().split(' ')[0].toLowerCase();
      }
    } catch (_) {}

    // Fallback: displayName directo del usuario de Firebase
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim().split(' ')[0].toLowerCase();
    }

    // Último recurso: parte del email
    if (user.email != null && user.email!.isNotEmpty) {
      return user.email!.split('@')[0].toLowerCase();
    }

    return 'usuario';
  }

  Future<void> _cargarPerimetrosVisuales() async {
    try {
      final String yamlString =
          await rootBundle.loadString('assets/config/zonas.yml');
      final YamlMap yamlData = loadYaml(yamlString);
      final List<CircleMarker> listaTemporal = [];

      for (var zona in yamlData['zonas_seguras']) {
        final String idZona =
            (zona['id'] ?? zona['id_zona'] ?? '').toString().toUpperCase();
        final double lat = double.parse(zona['lat'].toString());
        final double lng = double.parse(zona['lng'].toString());

        bool esCota30 = idZona.contains('COTA30');

        if (!esCota30 && lat > -33.030 && lat < -33.000 && lng < -71.545) {
          continue;
        }

        listaTemporal.add(
          CircleMarker(
            point: LatLng(lat, lng),
            radius: esCota30 ? 120 : 200,
            useRadiusInMeter: true,
            color: esCota30
                ? const Color(0xFF0288D1).withOpacity(0.06)
                : const Color(0xFF4CAF50).withOpacity(0.12),
            borderColor: esCota30
                ? const Color(0xFF29B6F6).withOpacity(0.25)
                : const Color(0xFF81C784).withOpacity(0.35),
            borderStrokeWidth: 2.0,
          ),
        );
      }
      setState(() {
        _circulosZonasSeguras = listaTemporal;
      });
    } catch (e) {
      debugPrint("Error al inicializar perímetros visuales: $e");
    }
  }

  bool _esMar(LatLng punto) {
    // Si NO está dentro de la masa de tierra firme, entonces está en el mar
    return !_puntoEnPoligono(punto, _poligonoLand);
  }


  Future<void> _determinarUbicacion() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setUbicacionPorDefecto();
      _mostrarWarningGPS(disabled: true);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _setUbicacionPorDefecto();
        _mostrarWarningGPS(disabled: false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _setUbicacionPorDefecto();
      _mostrarWarningGPS(disabled: false);
      return;
    }

    Position posicion = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _ubicacionActual = LatLng(posicion.latitude, posicion.longitude);
      _buscandoGPS = false;
    });

    _mapController.move(_ubicacionActual!, 16.0);
  }

  void _setUbicacionPorDefecto() {
    setState(() {
      _ubicacionActual = const LatLng(-33.045, -71.615);
      _buscandoGPS = false;
    });
  }

  void _mostrarWarningGPS({required bool disabled}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          content: Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AnimatedGPSIcon(),
                const SizedBox(height: 30),
                Text(
                  disabled ? "GPS Desactivado" : "Ubicación Denegada",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: _mainFont,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF2E4D68),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  disabled
                      ? "Para calcular tu ruta de evacuación rápida ante un tsunami, es obligatorio activar la localización GPS del dispositivo."
                      : "Para ubicarte en el mapa y trazar tu ruta de escape, la aplicación necesita permisos de localización permanente.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: _mainFont,
                    fontSize: 14,
                    color: Colors.blueGrey[400],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE57373),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(context);
                      if (disabled) {
                        await Geolocator.openLocationSettings();
                      } else {
                        await Geolocator.openAppSettings();
                      }
                    },
                    child: Text(
                      disabled ? "activar gps" : "otorgar permisos",
                      style: TextStyle(
                        fontFamily: _mainFont,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "continuar sin gps",
                    style: TextStyle(
                      fontFamily: _mainFont,
                      color: Colors.blueGrey[400],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _centrarMapaEnUsuario() async {
    setState(() {
      _buscandoGPS = true;
    });
    await _determinarUbicacion();
    if (_ubicacionActual != null) {
      _mapController.move(_ubicacionActual!, 16.0);
    }
  }

  void _colocarPinSimulacion(LatLng punto) {
    // Primero: bloquear el mar con diálogo modal
    if (_esMar(punto)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.waves_rounded,
                  color: Color(0xFF0288D1), size: 28),
              const SizedBox(width: 10),
              Text(
                "zona inválida",
                style: TextStyle(
                  fontFamily: _mainFont,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2E4D68),
                ),
              ),
            ],
          ),
          content: Text(
            "no es posible iniciar una simulación de evacuación desde el mar.\n\nla amenaza proviene del océano, fija el pin en tierra firme.",
            style: TextStyle(fontFamily: _mainFont, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "entendido",
                style: TextStyle(
                  fontFamily: _mainFont,
                  color: const Color(0xFFE57373),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Segundo: verificar zona costera soportada
    bool esCostaValpoVina = punto.latitude >= -33.10 &&
        punto.latitude <= -32.95 &&
        punto.longitude >= -71.68 &&
        punto.longitude <= -71.50;

    if (esCostaValpoVina) {
      setState(() {
        _pinSimulacion = punto;
      });
      _mapController.move(punto, 16.5);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Simulación limitada a la costa de valparaíso/viña.',
            style: TextStyle(
                fontFamily: _mainFont, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFFE57373),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      );
    }
  }

  Future<void> _ejecutarEvacuacion() async {
    Navigator.pop(context);

    try {
      LatLng puntoDePartida = _pinSimulacion ??
          _ubicacionActual ??
          const LatLng(-33.045, -71.615);

      if (_esMar(puntoDePartida)) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.waves_rounded,
                      color: Color(0xFF0288D1), size: 28),
                  const SizedBox(width: 10),
                  Text(
                    "zona inválida",
                    style: TextStyle(
                      fontFamily: _mainFont,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2E4D68),
                    ),
                  ),
                ],
              ),
              content: Text(
                "no es posible calcular una ruta de evacuación desde el mar.\n\nla amenaza de tsunami proviene del océano, por favor colócate en tierra firme para evacuar.",
                style: TextStyle(fontFamily: _mainFont, fontSize: 15),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "entendido",
                    style: TextStyle(
                      fontFamily: _mainFont,
                      color: const Color(0xFFE57373),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      final String yamlString =
          await rootBundle.loadString('assets/config/zonas.yml');
      final YamlMap yamlData = loadYaml(yamlString);

      LatLng puntoDestino = const LatLng(-33.0180, -71.5380);
      double distanciaMinimaAbsoluta = double.infinity;

      for (var zona in yamlData['zonas_seguras']) {
        final double lat = double.parse(zona['lat'].toString());
        final double lng = double.parse(zona['lng'].toString());
        final LatLng puntoZona = LatLng(lat, lng);

        double distancia = Geolocator.distanceBetween(
          puntoDePartida.latitude,
          puntoDePartida.longitude,
          puntoZona.latitude,
          puntoZona.longitude,
        );

        if (distancia < distanciaMinimaAbsoluta) {
          distanciaMinimaAbsoluta = distancia;
          puntoDestino = puntoZona;
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('calculando ruta rápida con dijkstra...',
                style: TextStyle(fontFamily: _mainFont)),
            backgroundColor: const Color(0xFF2E4D68),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      final servicio = EvacuacionService();
      List<LatLng> rutaCalculada = await servicio.obtenerRuta(
        origen: puntoDePartida,
        destinoSeguro: puntoDestino,
      );

      if (rutaCalculada.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'error al conectar con el motor de rutas. revisa el backend y la ip.',
                style: TextStyle(fontFamily: _mainFont),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      var box = Hive.box('emergenciaBox');
      List<Map<String, double>> rutaParaGuardar = rutaCalculada
          .map((nodo) => {'lat': nodo.latitude, 'lng': nodo.longitude})
          .toList();
      box.put('ultimaRuta', rutaParaGuardar);

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  AlertaPage(rutaSimulada: rutaCalculada)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error en el cálculo: $e',
                style: TextStyle(fontFamily: _mainFont)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _verRutaOffline() {
    Navigator.pop(context);

    var box = Hive.box('emergenciaBox');
    var datosGuardados = box.get('ultimaRuta');

    if (datosGuardados != null) {
      List<LatLng> rutaOffline =
          (datosGuardados as List<dynamic>).map((nodo) {
        final mapaNodo = Map<String, double>.from(nodo as Map);
        return LatLng(mapaNodo['lat']!, mapaNodo['lng']!);
      }).toList();

      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => AlertaPage(rutaSimulada: rutaOffline)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'no hay rutas guardadas en el dispositivo.',
            style: TextStyle(
                fontFamily: _mainFont, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF2E4D68),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _mostrarProximamente() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('función en desarrollo...',
            style: TextStyle(fontFamily: _mainFont)),
        backgroundColor: const Color(0xFF2E4D68),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _abrirPlanesSenapred() async {
    Navigator.pop(context);
    final Uri url = Uri.parse("https://www.senapred.cl/plan-de-evacuacion-valparaiso/");
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No se pudo abrir el sitio web de SENAPRED."),
              backgroundColor: Color(0xFFE57373),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al abrir el enlace: $e"),
            backgroundColor: Color(0xFFE57373),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: Drawer(
        backgroundColor: const Color.fromARGB(255, 45, 25, 55),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    const CircleAvatar(
                        radius: 25,
                        backgroundColor: Color(0xFFF48FB1),
                        child: Icon(Icons.person,
                            color: Colors.white, size: 30)),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        "bienvenid@ $_nombreUsuario",
                        style: TextStyle(
                          fontFamily: _mainFont,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, thickness: 1),

              ListTile(
                leading:
                    const Icon(Icons.account_circle, color: Colors.white70),
                title: Text("mi perfil",
                    style: TextStyle(
                        fontFamily: _mainFont,
                        color: Colors.white,
                        fontSize: 16)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PerfilPage()));
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.menu_book_rounded, color: Colors.white70),
                title: Text("planes oficiales senapred",
                    style: TextStyle(
                        fontFamily: _mainFont,
                        color: Colors.white,
                        fontSize: 16)),
                onTap: _abrirPlanesSenapred,
              ),
              ListTile(
                leading:
                    const Icon(Icons.map_outlined, color: Colors.white70),
                title: Text("regiones (próximamente)",
                    style: TextStyle(
                        fontFamily: _mainFont,
                        color: Colors.white54,
                        fontSize: 15)),
                onTap: _mostrarProximamente,
              ),
              ListTile(
                leading: const Icon(Icons.sensors, color: Colors.white70),
                title: Text("actividad sísmica (próximamente)",
                    style: TextStyle(
                        fontFamily: _mainFont,
                        color: Colors.white54,
                        fontSize: 15)),
                onTap: _mostrarProximamente,
              ),

              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "estado shoa",
                        style: TextStyle(
                          fontFamily: _mainFont,
                          fontSize: 12,
                          color: Colors.blueGrey[300],
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Color(0xFFA5D6A7), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "sin alertas de tsunami",
                              style: TextStyle(
                                  fontFamily: _mainFont,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 15),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor:
                              Colors.white.withOpacity(0.05),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _colocarPinSimulacion(
                              const LatLng(-33.0153, -71.5532));
                        },
                        icon: const Icon(Icons.touch_app_rounded,
                            color: Color(0xFF81D4FA), size: 20),
                        label: Text(
                          "fijar pin de prueba (viña)",
                          style: TextStyle(
                            fontFamily: _mainFont,
                            color: const Color(0xFF81D4FA),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE57373),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                        ),
                        onPressed: _ejecutarEvacuacion,
                        icon: const Icon(Icons.warning_rounded, size: 24),
                        label: Text(
                          "simular evacuación",
                          style: TextStyle(
                            fontFamily: _mainFont,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    TextButton.icon(
                      onPressed: _verRutaOffline,
                      icon: const Icon(Icons.signal_wifi_off_rounded,
                          color: Colors.blueGrey),
                      label: Text(
                        "ruta offline",
                        style: TextStyle(
                          fontFamily: _mainFont,
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      body: Stack(
        children: [
          _buscandoGPS
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFFF48FB1)))
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _ubicacionActual!,
                    initialZoom: 16.0,
                    onTap: (tapPosition, point) =>
                        _colocarPinSimulacion(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'cl.duoc.mimapasos.lylo',
                    ),
                    CircleLayer(circles: _circulosZonasSeguras),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _ubicacionActual!,
                          width: 120,
                          height: 80,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E4D68),
                                  borderRadius:
                                      BorderRadius.circular(15),
                                  border: Border.all(
                                      color: const Color(0xFFF48FB1),
                                      width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF48FB1)
                                          .withOpacity(0.4),
                                      blurRadius: 8,
                                    )
                                  ],
                                ),
                                child: Text(
                                  "estás aquí",
                                  style: TextStyle(
                                    fontFamily: _mainFont,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const Icon(Icons.location_on,
                                  color: Color(0xFFF48FB1), size: 42),
                            ],
                          ),
                        ),
                        if (_pinSimulacion != null)
                          Marker(
                            point: _pinSimulacion!,
                            width: 100,
                            height: 80,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 5)
                                    ],
                                  ),
                                  child: Text(
                                    "simulación",
                                    style: TextStyle(
                                      fontFamily: _mainFont,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF81D4FA),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const Icon(
                                    Icons.person_pin_circle_rounded,
                                    color: Color(0xFF81D4FA),
                                    size: 52),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

          // Leyenda oficial de mapas de inundación (SENAPRED / SHOA)
          Positioned(
            bottom: _pinSimulacion != null ? 180 : 100,
            left: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withOpacity(0.25),
                              border: Border.all(color: const Color(0xFF81C784), width: 1.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Zona Segura (Cota 30+)",
                            style: TextStyle(
                              fontFamily: _mainFont,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2E4D68),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: BackdropFilter(
                      filter:
                          ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 14,
                              backgroundColor: Color(0xFFF48FB1),
                              child: Icon(Icons.person,
                                  size: 18, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "bienvenid@ $_nombreUsuario",
                              style: TextStyle(
                                fontFamily: _mainFont,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: const Color(0xFF2E4D68),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter:
                          ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.4)),
                        ),
                        child: Builder(
                          builder: (context) {
                            return IconButton(
                              icon: const Icon(Icons.menu,
                                  color: Color(0xFF2E4D68)),
                              onPressed: () {
                                Scaffold.of(context).openEndDrawer();
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: _pinSimulacion != null ? 100 : 30,
            right: 20,
            child: FloatingActionButton(
              heroTag: "btnUbicacion",
              backgroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              onPressed: _centrarMapaEnUsuario,
              child: const Icon(Icons.my_location_rounded,
                  color: Color(0xFF2E4D68)),
            ),
          ),

          if (_pinSimulacion != null)
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10)
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Color(0xFF2E4D68)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "punto de simulación listo. abre el menú para evacuar.",
                        style: TextStyle(
                          fontFamily: _mainFont,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2E4D68),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () =>
                          setState(() => _pinSimulacion = null),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AnimatedGPSIcon extends StatefulWidget {
  const AnimatedGPSIcon({super.key});

  @override
  State<AnimatedGPSIcon> createState() => _AnimatedGPSIconState();
}

class _AnimatedGPSIconState extends State<AnimatedGPSIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Efecto de onda de radar
            Container(
              width: 100 * _scaleAnimation.value,
              height: 100 * _scaleAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE57373).withOpacity(1.0 - _controller.value),
              ),
            ),
            // Contenedor central con icono
            Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE57373),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  )
                ],
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ],
        );
      },
    );
  }
}