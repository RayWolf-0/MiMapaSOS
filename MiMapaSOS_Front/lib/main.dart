import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'src/pages/login_page.dart';

void main() async {
  // Obligatorio: Le dice a Flutter que espere a que los motores nativos arranquen
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializamos Hive en la memoria del celular
  await Hive.initFlutter();
  
  // Abrimos una "Caja" (Box) llamada 'emergenciaBox'. Es como crear una tabla NoSQL.
  await Hive.openBox('emergenciaBox');

  runApp(const MiMapaApp());
}

class MiMapaApp extends StatelessWidget {
  const MiMapaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Mapa SOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
      ),
      home: const LoginPage(),
    );
  }
}