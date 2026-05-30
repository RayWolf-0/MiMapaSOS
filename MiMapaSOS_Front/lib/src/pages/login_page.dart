import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart' as g_auth; 
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'mapa_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final String _mainFont = 'Urbanist';
  bool _isGoogleSignInInitialized = false;

  @override
  void initState() {
    super.initState();
    _iniciarYComprobarSesion();
  }

  // inicio de sesion
  Future<void> _iniciarYComprobarSesion() async {
    try {
      await g_auth.GoogleSignIn.instance.initialize(
        serverClientId: '1033944391120-6jp2pjgh0uricvohg8rth2vpj5dud27a.apps.googleusercontent.com',
      );
      _isGoogleSignInInitialized = true;
      
      final result = g_auth.GoogleSignIn.instance.attemptLightweightAuthentication();
      
      // Manejamos el resultado para evitar errores de asincronía de la nueva versión
      final g_auth.GoogleSignInAccount? account = result is Future ? await result : result as g_auth.GoogleSignInAccount?;
      
      if (account != null && mounted) {
        // El usuario ya estaba logueado. Lo mandamos directo al mapa.
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const MapaPage())
        );
      }
    } catch (e) {
      // Si falla o no hay sesión, simplemente se queda en la pantalla de login.
      print("No hay sesión activa guardada: $e");
    }
  }

  // login
  Future<void> _iniciarSesionConGoogle(BuildContext context) async {
    // se forza inicio de sesion
    if (!_isGoogleSignInInitialized) {
      await g_auth.GoogleSignIn.instance.initialize(
        serverClientId: '1033944391120-6jp2pjgh0uricvohg8rth2vpj5dud27a.apps.googleusercontent.com',
      );
      _isGoogleSignInInitialized = true;
    }

    try {
      final g_auth.GoogleSignInAccount? googleUser = await g_auth.GoogleSignIn.instance.authenticate();
      if (googleUser == null) return; // El usuario canceló el login

      // autenticacion
      final g_auth.GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken != null) {
        //token
        final response = await http.post(
          Uri.parse('http://10.55.139.163:5001/auth/google'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': idToken}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print("Login exitoso: ${data['user']}");
          
          // validador
          if (context.mounted) {
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => const MapaPage())
            );
          }
        } else {
          print("Error del backend: ${response.body}");
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error al validar con el servidor.')),
            );
          }
        }
      }
    } catch (e) {
      print("Error en Google Sign-In: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexión: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE3F2FD), 
              Colors.white,      
              Color(0xFFF1F8E9), 
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              //decoraciones
              Positioned(
                top: -50, left: -60,
                child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFBBDEFB).withOpacity(0.5))),
              ),
              Positioned(
                top: 250, right: -80,
                child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFCDD2).withOpacity(0.4))),
              ),
              Positioned(
                bottom: -100, left: -20,
                child: Container(width: 250, height: 250, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2E4D68).withOpacity(0.05))),
              ),

              // contenido
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(flex: 2),
                      
                      Text(
                        "Mi Mapa SOS",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _mainFont, fontSize: 38, fontWeight: FontWeight.w800, color: const Color(0xFF2E4D68), letterSpacing: 1.2,
                          shadows: [Shadow(color: Colors.black.withOpacity(0.1), offset: const Offset(0, 3), blurRadius: 5)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      Text("Inicia Sesión con Google", style: TextStyle(fontFamily: _mainFont, fontSize: 16, color: Colors.blueGrey[400], fontWeight: FontWeight.w500)),
                      const SizedBox(height: 45),
                      
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, color: Colors.white.withOpacity(0.6),
                          boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 30, spreadRadius: 10)],
                        ),
                        child: Image.asset('assets/images/imagen_onboarding.png', height: 220, width: 220, fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 60),
                      
                      // boton de login con google
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white, foregroundColor: const Color(0xFF333333), elevation: 4, shadowColor: Colors.blue[100],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () => _iniciarSesionConGoogle(context),
                          icon: const FaIcon(FontAwesomeIcons.google, color: Color(0xFFEA4335), size: 24),
                          label: Text("Sign up with Google", style: TextStyle(fontFamily: _mainFont, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ),
                      ),
                      
                      const Spacer(flex: 3),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}