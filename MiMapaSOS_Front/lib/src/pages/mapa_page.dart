import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  @override
  void initState() {
    super.initState();
    _cargarUsuario();
    _determinarUbicacion();
    _cargarPerimetrosVisuales();
  }

  // FIX 1: Con Google Sign-In el displayName viene en la cuenta de Google,
  // no siempre en currentUser inmediatamente. Se lee desde GoogleSignIn primero,
  // luego se refuerza con authStateChanges como respaldo.
Future<void> _cargarUsuario() async {
  try {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Buscar el perfil de Google dentro de los proveedores vinculados
      final googleData = user.providerData.firstWhere(
        (p) => p.providerId == 'google.com',
        orElse: () => user.providerData.first,
      );
      if (mounted) {
        setState(() {
          _nombreUsuario = googleData.displayName != null && googleData.displayName!.trim().isNotEmpty
              ? googleData.displayName!.trim().split(' ')[0].toLowerCase()
              : _extraerNombre(user);
        });
      }
    }

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
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user.displayName!.trim().split(' ')[0].toLowerCase();
    } else if (user.email != null && user.email!.isNotEmpty) {
      return user.email!.split('@')[0].toLowerCase();
    }
    return 'usuario';
  }

  Future<void> _cargarPerimetrosVisuales() async {
    try {
      final String yamlString = await rootBundle.loadString('assets/config/zonas.yml');
      final YamlMap yamlData = loadYaml(yamlString);
      final List<CircleMarker> listaTemporal = [];

      for (var zona in yamlData['zonas_seguras']) {
        final String idZona = (zona['id'] ?? zona['id_zona'] ?? '').toString().toUpperCase();
        final double lat = double.parse(zona['lat'].toString());
        final double lng = double.parse(zona['lng'].toString());

        bool esCota30 = idZona.contains('COTA30');

        if (!esCota30 && lat > -33.030 && lat < -33.000 && lng < -71.545) {
          continue;
        }

        listaTemporal.add(
          CircleMarker(
            point: LatLng(lat, lng),
            radius: esCota30 ? 120 : 400,
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

  // FIX 2: Reemplaza el ray-casting por zonas rectangulares del mar,
  // mucho más confiable para la costa recta de Valparaíso/Viña.
  // Cada zona define un rectángulo donde se sabe con certeza que hay mar.
  bool _esMar(LatLng punto) {
    final double lat = punto.latitude;
    final double lng = punto.longitude;

    // Zona mar abierto al oeste de toda la costa (límite seguro)
    if (lng < -71.660) return true;

    // Mar frente a Reñaca / Las Salinas (Viña del Mar norte)
    if (lat >= -33.000 && lat <= -32.960 && lng < -71.548) return true;

    // Mar frente a Viña del Mar centro (Av. Perú / Marina)
    if (lat >= -33.020 && lat < -33.000 && lng < -71.560) return true;

    // Mar frente a Viña del Mar sur / Caleta Abarca
    if (lat >= -33.035 && lat < -33.020 && lng < -71.572) return true;

    // Mar frente a Valparaíso norte (Av. España / Portales)
    if (lat >= -33.045 && lat < -33.035 && lng < -71.590) return true;

    // Mar frente a Valparaíso centro (Barón / Puerto)
    if (lat >= -33.055 && lat < -33.045 && lng < -71.615) return true;

    // Mar frente a Valparaíso sur (Torpederas / Laguna Verde)
    if (lat >= -33.080 && lat < -33.055 && lng < -71.640) return true;

    return false;
  }

  Future<void> _determinarUbicacion() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setUbicacionPorDefecto();
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _setUbicacionPorDefecto();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _setUbicacionPorDefecto();
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

  void _centrarMapaEnUsuario() {
    if (_ubicacionActual != null) {
      _mapController.move(_ubicacionActual!, 16.0);
    }
  }

  void _colocarPinSimulacion(LatLng punto) {
    // Primero: bloquear el mar con popup de diálogo (no solo snackbar)
    if (_esMar(punto)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.waves_rounded, color: Color(0xFF0288D1), size: 28),
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
            style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFFE57373),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      );
    }
  }

  Future<void> _ejecutarEvacuacion() async {
    Navigator.pop(context);

    try {
      LatLng puntoDePartida =
          _pinSimulacion ?? _ubicacionActual ?? const LatLng(-33.045, -71.615);

      final String yamlString =
          await rootBundle.loadString('assets/config/zonas.yml');
      final YamlMap yamlData = loadYaml(yamlString);

      LatLng puntoDestino = const LatLng(-33.0180, -71.5380);
      double distanciaMinimaCentroide = double.infinity;
      double distanciaMinimaAbsoluta = double.infinity;

      for (var zona in yamlData['zonas_seguras']) {
        final String idZona =
            (zona['id'] ?? zona['id_zona'] ?? '').toString().toUpperCase();
        final double lat = double.parse(zona['lat'].toString());
        final double lng = double.parse(zona['lng'].toString());
        final LatLng puntoZona = LatLng(lat, lng);

        bool esCota30 = idZona.contains('COTA30');

        if (!esCota30 && lat > -33.030 && lat < -33.000 && lng < -71.545) {
          continue;
        }

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

        if (!esCota30) {
          if (distancia < distanciaMinimaCentroide) {
            distanciaMinimaCentroide = distancia;
          }
        }
      }

      if (distanciaMinimaCentroide <= 400) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.verified_user_rounded,
                      color: Colors.green, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    "ya estás a salvo",
                    style: TextStyle(
                      fontFamily: _mainFont,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2E4D68),
                    ),
                  ),
                ],
              ),
              content: Text(
                "tu ubicación actual ya se encuentra dentro de una zona segura (sobre la cota 30). mantén la calma y quédate donde estás.",
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
              builder: (context) => AlertaPage(rutaSimulada: rutaCalculada)),
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
      List<LatLng> rutaOffline = (datosGuardados as List<dynamic>).map((nodo) {
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
                        child:
                            Icon(Icons.person, color: Colors.white, size: 30)),
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
                leading: const Icon(Icons.map_outlined, color: Colors.white70),
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
                    border:
                        Border.all(color: Colors.white.withOpacity(0.1)),
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
                          backgroundColor: Colors.white.withOpacity(0.05),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                  child: CircularProgressIndicator(color: Color(0xFFF48FB1)))
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
                                  borderRadius: BorderRadius.circular(15),
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
                                    borderRadius: BorderRadius.circular(10),
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
                                const Icon(Icons.person_pin_circle_rounded,
                                    color: Color(0xFF81D4FA), size: 52),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
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
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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