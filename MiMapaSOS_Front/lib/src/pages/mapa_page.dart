import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
      _ubicacionActual = const LatLng(-33.045, -71.615); // Valparaíso
      _buscandoGPS = false;
    });
  }

  // viña del mar
  void _colocarPinSimulacion(LatLng punto) {
    bool esCostaValpoVina = punto.latitude >= -33.10 && punto.latitude <= -32.95 &&
                            punto.longitude >= -71.68 && punto.longitude <= -71.50;

    if (esCostaValpoVina) {
      setState(() {
        _pinSimulacion = punto;
      });
      // camara
      _mapController.move(punto, 16.5);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Simulación limitada a la costa de Valparaíso/Viña.', style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFFE57373),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // --- 1. CAPA DEL MAPA ---
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
                            child: Text("Estás Aquí", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
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
                              child: Text("Simulación", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, color: const Color(0xFF81D4FA), fontSize: 12)),
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
                            Text("Bienvenid@ Lylo", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF2E4D68))),
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
                        
                        // menu
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.menu, color: Color(0xFF2E4D68)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          color: Colors.white,
                          onSelected: (String value) {
                            if (value == 'perfil') {
                              Navigator.push(
                                context, 
                                MaterialPageRoute(builder: (context) => const PerfilPage())
                              );
                            } else {
                              // Feedback para las opciones no terminadas
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Función en desarrollo...', style: TextStyle(fontFamily: _mainFont)),
                                  backgroundColor: const Color(0xFF2E4D68),
                                  duration: const Duration(seconds: 1),
                                )
                              );
                            }
                          },
                          itemBuilder: (BuildContext context) => [
                            PopupMenuItem(value: 'perfil', child: Text('Perfil', style: TextStyle(fontFamily: _mainFont))),
                            PopupMenuItem(value: 'regiones', child: Text('Regiones (próximamente)', style: TextStyle(fontFamily: _mainFont))),
                            PopupMenuItem(value: 'actividad', child: Text('Actividad Sísmica (próximamente)', style: TextStyle(fontFamily: _mainFont))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // panel dinamico
          DraggableScrollableSheet(
            initialChildSize: 0.42, 
            minChildSize: 0.30,
            maxChildSize: 0.70,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 85, 50, 99),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
                  boxShadow: [
                    BoxShadow(color: const Color.fromARGB(255, 82, 23, 160).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -5)),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(top: 15, bottom: 35, left: 24, right: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50, height: 5, margin: const EdgeInsets.only(bottom: 25),
                        decoration: BoxDecoration(color: Colors.blueGrey[600], borderRadius: BorderRadius.circular(10)),
                      ),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("MONITOREO SHOA", style: TextStyle(fontFamily: _mainFont, fontSize: 13, color: Colors.blueGrey[300], letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFA5D6A7).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFA5D6A7).withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFFA5D6A7), size: 14),
                                const SizedBox(width: 5),
                                Text("Litoral Seguro", style: TextStyle(fontFamily: _mainFont, fontSize: 12, color: const Color(0xFFA5D6A7), fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 15),

                      // shoa
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(255, 35, 8, 109),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.waves_rounded, color: Color(0xFF81D4FA), size: 28),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Sin alertas de tsunami", style: TextStyle(fontFamily: _mainFont, fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Text("Última actualización: Ahora", style: TextStyle(fontFamily: _mainFont, fontSize: 13, color: Colors.blueGrey[300])),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // TARJETA 2: Botón Interactivo de Simulación
                      GestureDetector(
                        onTap: () {
                          _colocarPinSimulacion(const LatLng(-33.0153, -71.5532));
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _pinSimulacion == null ? const Color(0xFF2E4D68) : const Color(0xFF4CAF50).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _pinSimulacion == null ? Colors.transparent : const Color(0xFF4CAF50).withOpacity(0.5), width: 2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _pinSimulacion == null ? Colors.white.withOpacity(0.1) : const Color(0xFF4CAF50),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(Icons.touch_app_rounded, color: _pinSimulacion == null ? const Color(0xFF81D4FA) : Colors.white, size: 28),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _pinSimulacion == null ? "Toca aquí para fijar punto de prueba" : "Punto de simulación listo",
                                      style: TextStyle(fontFamily: _mainFont, fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _pinSimulacion == null ? "Solo zona de Valparaíso y Viña" : "Coordenadas fijadas",
                                      style: TextStyle(fontFamily: _mainFont, fontSize: 13, color: Colors.blueGrey[200]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      
                      // hace el calculo y lo guarda en hive
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE57373),
                            foregroundColor: Colors.white,
                            elevation: 5,
                            shadowColor: const Color(0xFFE57373).withOpacity(0.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () async {
                            // cargando
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Calculando ruta segura con Dijkstra...', style: TextStyle(fontFamily: _mainFont)), 
                                backgroundColor: const Color(0xFF2E4D68), 
                                duration: const Duration(seconds: 2)
                              )
                            );

                            try {
                              LatLng puntoDePartida = _pinSimulacion ?? _ubicacionActual ?? const LatLng(-33.045, -71.615);
                              
                              // --- elige ruta mas cercana---
                              final List<LatLng> zonasSeguras = [
                                const LatLng(-33.0180, -71.5380), // Quinta Vergara
                                const LatLng(-33.0480, -71.6260), // Cerro Alegre
                                const LatLng(-33.0415, -71.6030), // Mirador Barón
                              ];

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
                              // --------------------separando-----------------------------------------
                              
                              // 2. CONEXIÓN AL BACKEND
                              final servicio = EvacuacionService();
                              List<LatLng> rutaCalculada = await servicio.obtenerRuta(
                                origen: puntoDePartida,
                                destinoSeguro: puntoDestino
                              );

                              // Validar si el backend falló o la IP está mal
                              if (rutaCalculada.isEmpty) {
                                if(context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error al conectar con el motor de rutas. Revisa tu backend y la IP.', style: TextStyle(fontFamily: _mainFont)), 
                                      backgroundColor: Colors.red
                                    )
                                  );
                                }
                                return; // Detenemos la función si no hay ruta
                              }

                              // 3. modo offline: Guardar la ruta en Hive para uso futuro sin conexión
                              var box = Hive.box('emergenciaBox');
                              
                              List<Map<String, double>> rutaParaGuardar = rutaCalculada.map((nodo) => {
                                'lat': nodo.latitude,
                                'lng': nodo.longitude
                              }).toList();
                              
                              box.put('ultimaRuta', rutaParaGuardar);

                              // 4. Continuar el flujo hacia la alerta roja
                              if(context.mounted) {
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(builder: (context) => AlertaPage(rutaSimulada: rutaCalculada))
                                );
                              }
                            } catch (e) {
                              // Manejo de errores
                              if(context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error en el cálculo: $e', style: TextStyle(fontFamily: _mainFont)), 
                                    backgroundColor: Colors.red
                                  )
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.warning_rounded, size: 28),
                          label: Text(
                            "SIMULAR EVACUACIÓN",
                            style: TextStyle(fontFamily: _mainFont, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 15),

                      // --- BOTÓN DE RESCATE OFFLINE ---
                      TextButton.icon(
                        onPressed: () {
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
                                content: Text('No hay rutas guardadas en el dispositivo.', style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold)),
                                backgroundColor: const Color(0xFF2E4D68),
                                behavior: SnackBarBehavior.floating,
                              )
                            );
                          }
                        },
                        icon: const Icon(Icons.signal_wifi_off_rounded, color: Colors.blueGrey),
                        label: Text(
                          "VER ÚLTIMA RUTA (MODO OFFLINE)", 
                          style: TextStyle(fontFamily: _mainFont, color: Colors.blueGrey, fontWeight: FontWeight.bold, letterSpacing: 1.0)
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}