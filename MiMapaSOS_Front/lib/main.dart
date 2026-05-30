import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'src/pages/login_page.dart';

// --- 1. VARIABLE GLOBAL PARA EL TEMA ---
// La creamos aquí afuera para que cualquier pantalla pueda cambiarla
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

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
    // 2. ENVOLVEMOS LA APP PARA ESCUCHAR EL MODO OSCURO
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Mi Mapa SOS',
          debugShowCheckedModeBanner: false,
          
          // 3. LE INDICAMOS A FLUTTER QUÉ MODO USAR
          themeMode: currentMode,
          
          // --- CONFIGURACIÓN TEMA CLARO ---
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.red,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF1F8E9), // El fondo claro de tu app
          ),
          
          // --- CONFIGURACIÓN TEMA OSCURO ---
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.red, // Mantendrá tus botones con acento rojo
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212), // Fondo gris muy oscuro
          ),
          
          home: const LoginPage(),
        );
      },
    );
  }
}