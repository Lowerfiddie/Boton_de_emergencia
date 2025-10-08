import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'email_registration_screen.dart';
import 'home_screen.dart';
import 'session_manager.dart';

class SplashGate extends StatelessWidget {
  const SplashGate({super.key});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: SessionManager.isRegistered(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final registered = snap.data ?? false;
        return registered ? const HomeScreen() : const SignInScreen();
      },
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Botón de Emergencia - Login',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      initialRoute: '/', // arranca en el gate
      routes: {
        '/': (_) => const SplashGate(), // decide /home o /login
        '/home': (_) => const HomeScreen(),
        '/login': (_) => const SignInScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/register-google') {
          final acc = settings.arguments as GoogleSignInAccount;
          return MaterialPageRoute(
            builder: (_) => RegistrationScreen(googleAccount: acc),
          );
        }
        return null; // usa el handler por defecto si no coincide
      },
    );
  }
}