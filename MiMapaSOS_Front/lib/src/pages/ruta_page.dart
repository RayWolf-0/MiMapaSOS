import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RutaPage extends StatefulWidget {
  // Exigimos que esta pantalla reciba una lista de coordenadas para pintar
  final List<LatLng> puntosRuta;
  
  const RutaPage({super.key, required this.puntosRuta});

  @override
  State<RutaPage> createState() => _RutaPageState();
}

class _RutaPageState extends State<RutaPage> {
  final String _mainFont = 'Urbanist';
  bool checkNinos = false;
  bool checkComida = false;

  @override
  Widget build(BuildContext context) {
    // Si la ruta está vacía (error de cálculo), evitamos que la app colapse poniéndola en el puerto
    final LatLng centroMapa = widget.puntosRuta.isNotEmpty ? widget.puntosRuta.first : const LatLng(-33.045, -71.615);
    final LatLng destinoSeguro = widget.puntosRuta.isNotEmpty ? widget.puntosRuta.last : const LatLng(-33.035, -71.625);

    return Scaffold(
      appBar: AppBar(
        title: Text("Ruta de Evacuación", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), // Dark Blue Geocientífico
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. Área del Mapa Dinámico
          Expanded(
            flex: 5,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: centroMapa, 
                initialZoom: 16.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'cl.duoc.mimapasos.lylo',
                ),
                // Aquí se dibuja mágicamente la línea enviada desde la alerta
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: widget.puntosRuta,
                      color: const Color(0xFFF48FB1), // Rose Gold para la ruta
                      strokeWidth: 6.0,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Marcador de Destino Seguro
                    Marker(
                      point: destinoSeguro,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.flag_circle_rounded, color: Color(0xFFA5D6A7), size: 45), // Verde
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Checklist y Controles
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD), // Celeste pastel
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Se ha descargado la ruta correctamente. Revisa el checklist antes de salir.",
                            style: TextStyle(fontFamily: _mainFont, fontSize: 13, color: const Color(0xFF2E4D68), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  CheckboxListTile(
                    title: Text("Reuní al grupo familiar", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.w600)),
                    value: checkNinos,
                    activeColor: const Color(0xFFF48FB1), // Checkbox Rose Gold
                    onChanged: (val) => setState(() => checkNinos = val!),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    title: Text("Llevo kit de emergencia", style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.w600)),
                    value: checkComida,
                    activeColor: const Color(0xFFF48FB1),
                    onChanged: (val) => setState(() => checkComida = val!),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  
                  const Spacer(),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B), // Botón oscuro para contraste
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {}, 
                      icon: const Icon(Icons.phone_in_talk_rounded),
                      label: Text("Llamar a Emergencias", style: TextStyle(fontFamily: _mainFont, fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
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