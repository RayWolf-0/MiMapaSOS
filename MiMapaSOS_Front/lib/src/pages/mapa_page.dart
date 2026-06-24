import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart' show rootBundle; 
import 'package:yaml/yaml.dart'; 
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

  @override
  void initState() {
    super.initState();
    _determinarUbicacion();
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
      desiredAccuracy: LocationAccuracy.high
    );

    setState(() {
      _ubicacionActual = LatLng(posicion.latitude, posicion.longitude);
      _buscandoGPS = false;
    });

    _mapController.move(_ubicacionActual!, 16.0);
  }

  void _setUbicacionPorDefecto() {
    setState(() {
      _ubicacionActual = const LatLng(-33.045, -71.615); // valparaiso
      _buscandoGPS = false;
    });
  }

  // centrar mapa en la ubicacion del usuario
  void _centrarMapaEnUsuario() {
    if (_ubicacionActual != null) {
      _mapController.move(_ubicacionActual!, 16.0);
    }
  }

  // logica para limitar el pin de simulacion a viña/valpo
  void _colocarPinSimulacion(LatLng punto) {
    bool esCostaValpoVina = punto.latitude >= -33.10 && punto.latitude <= -32.95 &&
                            punto.longitude >= -71.68 && punto.longitude <= -71.50;

    if (esCostaValpoVina) {
      setState(() {
        _pinSimulacion = punto;
      });
      _mapController.move(punto, 16.5);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('simulación limitada a la costa de valparaíso/viña.', style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFE57373),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        )
      );
    }
  }

  // logica de evacuacion y validacion cota 30
  Future<void> _ejecutarEvacuacion() async {
    Navigator.pop(context); // cierra el menu lateral antes de empezar

    try {
      LatLng puntoDePartida = _pinSimulacion ?? _ubicacionActual ?? const LatLng(-33.045, -71.615);
      
      // 1. lectura de yml
      final String yamlString = await rootBundle.loadString('assets/config/zonas.yml');
      final YamlMap yamlData = loadYaml(yamlString);
      
      final List<LatLng> zonasSeguras = [];
      for (var zona in yamlData['zonas_seguras']) {
        zonasSeguras.add(LatLng(zona['lat'], zona['lng']));
      }

      // 2. encontrar la zona segura mas cercana por distancia real
      LatLng puntoDestino = zonasSeguras.first;
      double distanciaMinima = double.infinity;

      for (var zona in zonasSeguras) {
        double distancia = Geolocator.distanceBetween(
          puntoDePartida.latitude, puntoDePartida.longitude,
          zona.latitude, zona.longitude
        );
        
        if (distancia < distanciaMinima) {
          distanciaMinima = distancia;
          puntoDestino = zona;
        }
      }
      
      // 3. validacion: esta sobre la cota 30?
      if (distanciaMinima <= 400) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Colors.green, size: 28),
                  const SizedBox(width: 10),
                  Text("ya estás a salvo", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, color: const Color(0xFF2E4D68))),
                ],
              ),
              content: Text(
                "tu ubicación actual ya se encuentra dentro de una zona segura (sobre la cota 30). mantén la calma y quédate donde estás.", 
                style: TextStyle(fontFamily: _mainFont, fontSize: 15)
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("entendido", style: TextStyle(fontFamily: _mainFont, color: const Color(0xFFE57373), fontWeight: FontWeight.bold, fontSize: 16)),
                )
              ],
            )
          );
        }
        return; // detenemos la funcion
      }

      // 4. mostramos feedback de carga
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('calculando ruta rápida con dijkstra...', style: TextStyle(fontFamily: _mainFont)), 
            backgroundColor: const Color(0xFF2E4D68), 
            duration: const Duration(seconds: 2)
          )
        );
      }

      // 5. conexion al motor backend
      final servicio = EvacuacionService();
      List<LatLng> rutaCalculada = await servicio.obtenerRuta(
        origen: puntoDePartida,
        destinoSeguro: puntoDestino
      );

      if (rutaCalculada.isEmpty) {
        if(context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('error al conectar con el motor de rutas. revisa el backend y la ip.', style: TextStyle(fontFamily: _mainFont)), 
              backgroundColor: Colors.red
            )
          );
        }
        return; 
      }

      // 6. guardado offline en hive
      var box = Hive.box('emergenciaBox');
      List<Map<String, double>> rutaParaGuardar = rutaCalculada.map((nodo) => {
        'lat': nodo.latitude,
        'lng': nodo.longitude
      }).toList();
      box.put('ultimaRuta', rutaParaGuardar);

      // 7. salto a pantalla de alerta
      if(context.mounted) {
        Navigator.push(
          context, 
          MaterialPageRoute(builder: (context) => AlertaPage(rutaSimulada: rutaCalculada))
        );
      }
    } catch (e) {
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error en el cálculo: $e', style: TextStyle(fontFamily: _mainFont)), 
            backgroundColor: Colors.red
          )
        );
      }
    }
  }

  // logica offline
  void _verRutaOffline() {
    Navigator.pop(context); // cierra el menu lateral

    var box = Hive.box('emergenciaBox');
    var datosGuardados = box.get('ultimaRuta');
    
    if (datosGuardados != null) {
      List<LatLng> rutaOffline = (datosGuardados as List<dynamic>).map((nodo) {
        final mapaNodo = Map<String, double>.from(nodo as Map);
        return LatLng(mapaNodo['lat']!, mapaNodo['lng']!);
      }).toList();
      
      Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => AlertaPage(rutaSimulada: rutaOffline))
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('no hay rutas guardadas en el dispositivo.', style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF2E4D68),
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  // helper para mostrar feedback de menus inactivos
  void _mostrarProximamente() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('función en desarrollo...', style: TextStyle(fontFamily: _mainFont)),
        backgroundColor: const Color(0xFF2E4D68),
        duration: const Duration(seconds: 1),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // menu lateral
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
                    const CircleAvatar(radius: 25, backgroundColor: Color(0xFFF48FB1), child: Icon(Icons.person, color: Colors.white, size: 30)),
                    const SizedBox(width: 15),
                    Text("menú sos", style: TextStyle(fontFamily: _mainFont, fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, thickness: 1),

              ListTile(
                leading: const Icon(Icons.account_circle, color: Colors.white70),
                title: Text("mi perfil", style: TextStyle(fontFamily: _mainFont, color: Colors.white, fontSize: 16)),
                onTap: () {
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const PerfilPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.map_outlined, color: Colors.white70),
                title: Text("regiones (próximamente)", style: TextStyle(fontFamily: _mainFont, color: Colors.white54, fontSize: 15)),
                onTap: _mostrarProximamente,
              ),
              ListTile(
                leading: const Icon(Icons.sensors, color: Colors.white70),
                title: Text("actividad sísmica (próximamente)", style: TextStyle(fontFamily: _mainFont, color: Colors.white54, fontSize: 15)),
                onTap: _mostrarProximamente,
              ),
              
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("estado shoa", style: TextStyle(fontFamily: _mainFont, fontSize: 12, color: Colors.blueGrey[300], letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFFA5D6A7), size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text("sin alertas de tsunami", style: TextStyle(fontFamily: _mainFont, color: Colors.white, fontWeight: FontWeight.w600))),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _colocarPinSimulacion(const LatLng(-33.0153, -71.5532)); 
                        },
                        icon: const Icon(Icons.touch_app_rounded, color: Color(0xFF81D4FA), size: 20),
                        label: Text("fijar pin de prueba (viña)", style: TextStyle(fontFamily: _mainFont, color: const Color(0xFF81D4FA), fontWeight: FontWeight.bold)),
                      ),
                    ),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE57373),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        onPressed: _ejecutarEvacuacion,
                        icon: const Icon(Icons.warning_rounded, size: 24),
                        label: Text("simular evacuación", style: TextStyle(fontFamily: _mainFont, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                      ),
                    ),
                    const SizedBox(height: 15),
                    
                    TextButton.icon(
                      onPressed: _verRutaOffline,
                      icon: const Icon(Icons.signal_wifi_off_rounded, color: Colors.blueGrey),
                      label: Text("ruta offline", style: TextStyle(fontFamily: _mainFont, color: Colors.blueGrey, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // contenido pantalla principal
      body: Stack(
        children: [
          // mapa
          _buscandoGPS 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF48FB1)))
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _ubicacionActual!,
                initialZoom: 16.0,
                onTap: (tapPosition, point) => _colocarPinSimulacion(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'cl.duoc.mimapasos.lylo',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _ubicacionActual!,
                      width: 120,
                      height: 80,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E4D68),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: const Color(0xFFF48FB1), width: 2),
                              boxShadow: [BoxShadow(color: const Color(0xFFF48FB1).withOpacity(0.4), blurRadius: 8)]
                            ),
                            child: Text("estás aquí", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                          ),
                          const Icon(Icons.location_on, color: Color(0xFFF48FB1), size: 42),
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
                              ),
                              child: Text("simulación", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, color: const Color(0xFF81D4FA), fontSize: 12)),
                            ),
                            const Icon(Icons.person_pin_circle_rounded, color: Color(0xFF81D4FA), size: 52),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

          // barra superior
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 14,
                              backgroundColor: Color(0xFFF48FB1),
                              child: Icon(Icons.person, size: 18, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            Text("bienvenid@ lylo", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF2E4D68))),
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
                          border: Border.all(color: Colors.white.withOpacity(0.4)),
                        ),
                        child: Builder( 
                          builder: (context) {
                            return IconButton(
                              icon: const Icon(Icons.menu, color: Color(0xFF2E4D68)),
                              onPressed: () {
                                Scaffold.of(context).openEndDrawer(); 
                              },
                            );
                          }
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // boton de ubicacion flotante
          Positioned(
            // sube dinamicamente si el recuadro del pin esta activo para no superponerse
            bottom: _pinSimulacion != null ? 100 : 30, 
            right: 20,
            child: FloatingActionButton(
              heroTag: "btnUbicacion", 
              backgroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              onPressed: _centrarMapaEnUsuario,
              child: const Icon(Icons.my_location_rounded, color: Color(0xFF2E4D68)),
            ),
          ),

          // pin flotante de simulacion
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
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF2E4D68)),
                    const SizedBox(width: 10),
                    Expanded(child: Text("punto de simulación listo. abre el menú para evacuar.", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, color: const Color(0xFF2E4D68)))),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() => _pinSimulacion = null),
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}