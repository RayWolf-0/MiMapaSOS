import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart' as g_auth;
import 'login_page.dart';
import '../../main.dart'; // 

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final String _mainFont = 'Urbanist';

// cerrar sesion
  Future<void> _cerrarSesion() async {
    try {
      await g_auth.GoogleSignIn.instance.signOut();
      
      await g_auth.GoogleSignIn.instance.disconnect(); 

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false, 
        );
      }
    } catch (e) {
      print("Error al cerrar sesión: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // El color de fondo se adapta si es oscuro o claro
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDarkMode ? Colors.white : const Color(0xFF2E4D68)),
        title: Text(
          "Mi Perfil",
          style: TextStyle(
            fontFamily: _mainFont,
            color: isDarkMode ? Colors.white : const Color(0xFF2E4D68),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 30),
            
            // --- Avatar ---
            CircleAvatar(
              radius: 50,
              backgroundColor: isDarkMode ? Colors.grey[800] : Colors.blue[100],
              child: Icon(
                FontAwesomeIcons.userAstronaut,
                size: 50,
                color: isDarkMode ? Colors.white : const Color(0xFF2E4D68),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Rescatista SOS", 
              style: TextStyle(
                fontFamily: _mainFont,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : const Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 40),

            // ajustes
            Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                children: [
                  // modo oscuro
                  ListTile(
                    leading: Icon(
                      isDarkMode ? FontAwesomeIcons.moon : FontAwesomeIcons.sun,
                      color: isDarkMode ? Colors.yellow[300] : Colors.orange,
                    ),
                    title: Text(
                      "Modo Oscuro",
                      style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87),
                    ),
                    trailing: Switch(
                      value: isDarkMode,
                      activeColor: const Color(0xFF2E4D68),
                      onChanged: (value) {
                        // Aquí llamamos a la variable global del main.dart
                        themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                      },
                    ),
                  ),
                  Divider(color: isDarkMode ? Colors.grey[800] : Colors.grey[200], height: 1),
                  
                  // Información extra de relleno
                  ListTile(
                    leading: Icon(FontAwesomeIcons.circleInfo, color: isDarkMode ? Colors.grey[400] : Colors.blueGrey),
                    title: Text(
                      "Versión de la App",
                      style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87),
                    ),
                    trailing: Text("1.0.0", style: TextStyle(color: isDarkMode ? Colors.grey[500] : Colors.grey)),
                  ),
                ],
              ),
            ),
            
            const Spacer(),

            // --- Botón de Cerrar Sesión ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red[700],
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _cerrarSesion,
                icon: const FaIcon(FontAwesomeIcons.arrowRightFromBracket, size: 20),
                label: Text(
                  "Cerrar Sesión",
                  style: TextStyle(fontFamily: _mainFont, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}