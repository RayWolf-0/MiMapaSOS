import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart' as g_auth;
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _comprobarSesionActiva();
  }

  Future<void> _comprobarSesionActiva() async {
    try {
      await g_auth.GoogleSignIn.instance.initialize(
        serverClientId: '1033944391120-6jp2pjgh0uricvohg8rth2vpj5dud27a.apps.googleusercontent.com',
      );
      _isGoogleSignInInitialized = true;

      // Si Firebase ya tiene sesión activa, ir directo al mapa
      final User? firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MapaPage()),
        );
        return;
      }

      // Intentar sesión ligera de Google como respaldo
      final result = g_auth.GoogleSignIn.instance.attemptLightweightAuthentication();
      final g_auth.GoogleSignInAccount? account =
          result is Future ? await result : result as g_auth.GoogleSignInAccount?;

      if (account != null && mounted) {
        // Hay sesión de Google guardada: completar sign-in en Firebase también
        await _completarSignInFirebase(account);
      }
    } catch (e) {
      debugPrint("No hay sesión activa guardada: $e");
    }
  }

  // Centraliza el sign-in en Firebase con la cuenta de Google obtenida
  Future<void> _completarSignInFirebase(g_auth.GoogleSignInAccount googleUser) async {
    try {
      final g_auth.GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) return;

      // 1. Registrar en Firebase Auth (esto puebla currentUser.displayName)
      // En google_sign_in v7+, el idToken es suficiente para autenticar con Firebase.
      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);

      // 2. Validar con tu backend (se mantiene el flujo original)
      final response = await http.post(
        Uri.parse('http://10.223.8.163:5001/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': idToken}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MapaPage()),
          );
        }
      } else {
        debugPrint("Error del backend: ${response.body}");
        // Si el backend falla, cerrar sesión de Firebase para no dejar estado inconsistente
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          _mostrarError('Error al validar con el servidor. Intenta nuevamente.');
        }
      }
    } catch (e) {
      debugPrint("Error completando sign-in Firebase: $e");
      rethrow;
    }
  }

  Future<void> _iniciarSesionConGoogle(BuildContext context) async {
    if (_cargando) return;
    setState(() => _cargando = true);

    try {
      if (!_isGoogleSignInInitialized) {
        await g_auth.GoogleSignIn.instance.initialize(
          serverClientId: '1033944391120-6jp2pjgh0uricvohg8rth2vpj5dud27a.apps.googleusercontent.com',
        );
        _isGoogleSignInInitialized = true;
      }

      final g_auth.GoogleSignInAccount? googleUser =
          await g_auth.GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        // Usuario canceló el flujo
        setState(() => _cargando = false);
        return;
      }

      await _completarSignInFirebase(googleUser);
    } catch (e) {
      debugPrint("Error en Google Sign-In: $e");
      if (mounted) {
        _mostrarError('No se pudo iniciar sesión. Verifica tu conexión e intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(mensaje,
                  style: TextStyle(fontFamily: _mainFont, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
              // Decoraciones de fondo
              Positioned(
                top: -50, left: -60,
                child: Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBBDEFB).withOpacity(0.5),
                  ),
                ),
              ),
              Positioned(
                top: 250, right: -80,
                child: Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFCDD2).withOpacity(0.4),
                  ),
                ),
              ),
              Positioned(
                bottom: -100, left: -20,
                child: Container(
                  width: 250, height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2E4D68).withOpacity(0.05),
                  ),
                ),
              ),

              // Contenido principal
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
                          fontFamily: _mainFont,
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF2E4D68),
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.1),
                              offset: const Offset(0, 3),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      Text(
                        "Rutas de evacuación ante tsunami",
                        style: TextStyle(
                          fontFamily: _mainFont,
                          fontSize: 15,
                          color: Colors.blueGrey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 45),

                      Container(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          'assets/images/imagen_onboarding.png',
                          height: 220,
                          width: 220,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 60),

                      // Botón de login con Google
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF333333),
                            elevation: 4,
                            shadowColor: Colors.blue[100],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _cargando ? null : () => _iniciarSesionConGoogle(context),
                          icon: _cargando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFF2E4D68),
                                  ),
                                )
                              : const FaIcon(FontAwesomeIcons.google,
                                  color: Color(0xFFEA4335), size: 24),
                          label: Text(
                            _cargando ? "Iniciando sesión..." : "Continuar con Google",
                            style: TextStyle(
                              fontFamily: _mainFont,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        "Al continuar, aceptas el uso de tus datos\npara gestionar rutas de emergencia.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _mainFont,
                          fontSize: 11,
                          color: Colors.blueGrey[300],
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