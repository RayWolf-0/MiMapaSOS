import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; // Librería de sonido
import 'package:latlong2/latlong.dart';
import 'ruta_page.dart';

class AlertaPage extends StatefulWidget {
  // Recibimos la ruta que el usuario simuló en el mapa
  final List<LatLng> rutaSimulada; 
  
  const AlertaPage({super.key, required this.rutaSimulada});

  @override
  State<AlertaPage> createState() => _AlertaPageState();
}

class _AlertaPageState extends State<AlertaPage> {
  final AudioPlayer _reproductorAudio = AudioPlayer();
  final String _mainFont = 'Urbanist';

  @override
  void initState() {
    super.initState();
    _activarAlarma();
  }

  // Función que hace sonar el ruido fuerte
  void _activarAlarma() async {
    // Configuramos para que el sonido se repita en bucle (loop) como una alarma real
    await _reproductorAudio.setReleaseMode(ReleaseMode.loop);
    // Reproducimos el archivo MP3
    await _reproductorAudio.play(AssetSource('audio/alarma.mp3'));
  }

  @override
  void dispose() {
    // Es VITAL apagar el reproductor si cerramos la pantalla, si no, sonará por siempre
    _reproductorAudio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E293B), // Fondo oscuro geocientífico
      body: SafeArea(
        child: Column(
          children: [
            // Contenedor Rojo Animado Superior
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F), // Rojo alerta clásico
                  boxShadow: [
                    BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 30, spreadRadius: 10),
                  ]
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.campaign_rounded, // Ícono de megáfono/sirena
                      size: 130,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "ALERTA DE\nTSUNAMI",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _mainFont,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 3.0,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Contenedor Inferior Dinámico
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  children: [
                    Text(
                      "El SHOA ha establecido estado de precaución. Debes evacuar lo más pronto posible hacia la cota 30.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _mainFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2E4D68),
                      ),
                    ),
                    const Spacer(),
                    
                    // Botón de escape hacia la ruta
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE57373), // Coral / Rose
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: const Color(0xFFE57373).withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                        ),
                        onPressed: () {
                          // 1. Apagamos la sirena
                          _reproductorAudio.stop();
                          
                          // 2. Navegamos al mapa final enviándole la ruta
                          Navigator.pushReplacement(
                            context, 
                            MaterialPageRoute(
                              builder: (context) => RutaPage(puntosRuta: widget.rutaSimulada)
                            )
                          );
                        },
                        icon: const Icon(Icons.map_rounded, size: 26),
                        label: Text(
                          "VER RUTA GENERADA",
                          style: TextStyle(fontFamily: _mainFont, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}