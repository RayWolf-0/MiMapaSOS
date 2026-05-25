import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'mapa_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  final String _mainFont = 'Urbanist';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Quitamos el color de fondo estático del Scaffold para usar un Container
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // 1. Degradado (Gradient) suave de fondo
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE3F2FD), // Celeste pastel muy suave arriba
              Colors.white,      // Blanco al medio
              Color(0xFFF1F8E9), // Verde agua pastel muy suave abajo
            ],
          ),
        ),
        child: SafeArea(
          // 2. Usamos Stack para poder poner figuras flotantes detrás del texto
          child: Stack(
            children: [
              // --- Decoraciones Flotantes (Blobs) ---
              // Burbuja superior izquierda (Celeste)
              Positioned(
                top: -50,
                left: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBBDEFB).withOpacity(0.5),
                  ),
                ),
              ),
              // Burbuja media derecha (Rosada/Roja suave para combinar con los corazones)
              Positioned(
                top: 250,
                right: -80,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFCDD2).withOpacity(0.4),
                  ),
                ),
              ),
              // Burbuja inferior izquierda (Azul oscuro difuminado)
              Positioned(
                bottom: -100,
                left: -20,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2E4D68).withOpacity(0.05),
                  ),
                ),
              ),

              // --- Contenido Principal de la Pantalla ---
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(flex: 2),
                      
                      // Título con una leve sombra para resaltar sobre el fondo
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
                        "Inicia Sesión con Google",
                        style: TextStyle(
                          fontFamily: _mainFont,
                          fontSize: 16,
                          color: Colors.blueGrey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 45),
                      
                      // Contenedor para darle un efecto más premium a tu imagen
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.1),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/imagen_onboarding.png',
                          height: 220,
                          width: 220,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 60),
                      
                      // Botón de Google perfeccionado
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
                              borderRadius: BorderRadius.circular(16), // Bordes más suaves
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const MapaPage()));
                          },
                          icon: const FaIcon(FontAwesomeIcons.google, color: Color(0xFFEA4335), size: 24),
                          label: Text(
                            "Sign up with Google",
                            style: TextStyle(
                              fontFamily: _mainFont, 
                              fontSize: 17, 
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
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