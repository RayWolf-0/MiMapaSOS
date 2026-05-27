import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class EvacuacionService {
  // 🔴 ¡CRÍTICO! Cambia esta IP por la Dirección IPv4 de tu adaptador Wi-Fi/Móvil 
  // que te dio el comando 'ipconfig' en la consola de tu PC (ej: 192.168.43.x).
  final String _baseUrl = "http://10.247.146.163:5003";

  Future<List<LatLng>> obtenerRuta({
    required LatLng origen,
    required LatLng destinoSeguro,
  }) async {
    // Armamos la URL con los parámetros que exige tu backend
    final url = Uri.parse(
        '$_baseUrl/calcular-evacuacion'
        '?lat=${origen.latitude}'
        '&lon=${origen.longitude}'
        '&dest_lat=${destinoSeguro.latitude}'
        '&dest_lon=${destinoSeguro.longitude}'
        '&id_usuario=1' // Hardcodeado por ahora hasta conectar el login
        '&id_alerta=BOLETIN-SHOA-SIM-001'
        '&id_zona=ZS-VALPO-01'
    );

try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      
      // DEBUGEA AQUÍ: Esto imprimirá en la consola de VS Code qué respondió exactamente Python
      print("Respuesta del servidor: ${response.body}");

      if (response.statusCode == 200) {
        final decodedData = json.decode(response.body);
        final List<dynamic> nodos = decodedData['trazado_nodos'];
        
        return nodos.map((nodo) {
          return LatLng(nodo['lat'].toDouble(), nodo['lng'].toDouble());
        }).toList();
      } else {
        print("Backend falló con código ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("ERROR TOTAL: $e"); // ESTO ES LO QUE QUIERO QUE ME COPIES Y PEGUEN AQUÍ
      return [];
    }
  }
}