import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'session_manager.dart';
import 'email_registration_screen.dart';
import 'auth.dart';
import 'home_screen.dart';
import 'login_page.dart';
import 'Servicios/notificaciones.dart';
import 'firebase_options.dart';

import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final _passCtrl = TextEditingController();
final _pass2Ctrl = TextEditingController();
bool _showPass = false;
bool _showPass2 = false;

Future<void> ensureAnonAuth() async {
  final auth = FirebaseAuth.instance;

  // Ya hay sesión
  if (auth.currentUser != null) return;

  try {
    await auth.signInAnonymously();
    debugPrint('✅ Anonymous auth OK: ${auth.currentUser?.uid}');
  } on FirebaseAuthException catch (e) {
    debugPrint('❌ Anonymous auth failed: ${e.code} ${e.message}');
    // Importante: NO lanzar excepción para no dejar pantalla negra.
  } catch (e) {
    debugPrint('❌ Anonymous auth unknown error: $e');
  }
}

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔹 Inicializa Firebase + FCM + notificaciones locales
  try {
    await NotificationService.initialize(navigatorKey: rootNavigatorKey);
  } catch (e) {
    debugPrint('No se pudo inicializar NotificationService: $e');
  }

  final platform = GoogleMapsFlutterPlatform.instance;
  if (platform is GoogleMapsFlutterAndroid) {
    platform.useAndroidViewSurface = true; // Hybrid composition
  }

  await ensureAnonAuth();

  runApp(MyApp(navigatorKey: rootNavigatorKey));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Botón de Emergencia - Login',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        initialRoute: '/splash',
        routes: {
          '/splash': (_) => const SplashScreen(),
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
        }
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _splashDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _navigateToGate();
  }

  Future<void> _navigateToGate() async {
    await Future<void>.delayed(_splashDuration);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/Tuzita_sin_fondo.png',
                width: 400,
                height: 400,
                fit: BoxFit.cover,
              ),
              const SizedBox(height: 24),
              Text(
                'Botón de Emergencia',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Cargando…',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cliente HTTP que adjunta los headers de autenticación de Google
class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._baseClient, this._headers);
  final Map<String, String> _headers;
  final http.Client _baseClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _baseClient.send(request);
  }
}

String _shortBody(String body, [int max = 500]) {
  if (body.length <= max) return body;
  return '${body.substring(0, max)}...';
}

Future<http.Response> postAppsScriptJson({
  required Uri uri,
  required Map<String, dynamic> payload,
  required String tag,
}) async {
  final encodedBody = jsonEncode(payload);
  final headers = <String, String>{
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json',
  };

  final request = http.Request('POST', uri)
    ..headers.addAll(headers)
    ..body = encodedBody
    ..followRedirects = false
    ..persistentConnection = false;

  final first = await http.Response.fromStream(await request.send());
  debugPrint('$tag STATUS=${first.statusCode}');
  debugPrint('$tag HEADERS=${first.headers}');
  debugPrint('$tag BODY=${_shortBody(first.body)}');

  final status = first.statusCode;
  if (status >= 300 && status < 400) {
    final location = first.headers['location'];
    if (location == null || location.isEmpty) return first;

    final redirectedUri = Uri.parse(location);
    debugPrint('$tag REDIRECT TO=$redirectedUri');

    late final http.Response second;
    if (status == 307 || status == 308) {
      second = await http.post(
        redirectedUri,
        headers: headers,
        body: encodedBody,
      );
    } else {
      second = await http.get(
        redirectedUri,
        headers: const {'Accept': 'application/json'},
      );
    }

    debugPrint('$tag REDIRECT STATUS=${second.statusCode}');
    debugPrint('$tag REDIRECT HEADERS=${second.headers}');
    debugPrint('$tag REDIRECT BODY=${_shortBody(second.body)}');
    return second;
  }

  return first;
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _handleSignIn() async {
    setState(() {_loading = true;_error = null;});
    try {
      final account = await googleSignIn.signIn();
      if (account == null) {
        // Usuario canceló
        setState(() => _loading = false);
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RegistrationScreen(googleAccount: account),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Error al iniciar con Google: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/Tuzita_sin_fondo.png',
          width: 300,
          height: 300,
          fit: BoxFit.cover,
        ),
        const SizedBox(height: 16),
        const Text(
          'Botón de Emergencia\nEMSAD #26\nIgnacio Zaragoza',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Seguridad para los alumnos',
          textAlign: TextAlign.center,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.vpn_key),
          label: const Text('Iniciar sesión'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()),
            );
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.mail),
          label: const Text('Registrase con Google'),
            onPressed: _loading ? null : _handleSignIn,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.mail),
          label: const Text('Registrarme con correo'),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmailRegistrationScreen()));
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _loading ? const CircularProgressIndicator() : child,
        ),
      ),
    );
  }
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, required this.googleAccount});
  final GoogleSignInAccount googleAccount;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _role = 'Alumno/a';
  bool _sending = false;
  String? _feedback;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _sending = true;
      _feedback = null;
    });

    try {
      final user = widget.googleAccount;

      final body = {
        'op'      : 'register_once',
        'userId'  : user.id,
        'nombre'  : user.displayName ?? '',
        'email': user.email.toLowerCase(),
        'telefono': _phoneCtrl.text.trim(),
        'rol'     : _role,
        'provider': 'Google Sign-In',
        'photoUrl': user.photoUrl ?? '',
        'password': _passCtrl.text,
      };

      assert(kAppsScriptUrl.startsWith('https://script.google.com/macros/s/') && kAppsScriptUrl.endsWith('/exec'));
      debugPrint('POST to $kAppsScriptUrl');

      final res = await postAppsScriptJson(
        uri: Uri.parse(kAppsScriptUrl),
        payload: body,
        tag: 'REGISTER',
      );

      bool ok = false;
      int updated = 0;
      String? err;
      Map<String, dynamic>? j;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic>) {
            j = decoded;
            ok = j['ok'] == true;
            err = j['error']?.toString();
            updated = int.tryParse('${j['updated'] ?? j['updatedRows'] ?? 0}') ?? 0;
          } else {
            err = 'server_response_not_map';
            debugPrint('REGISTER decoded no es Map: $decoded');
          }
        } catch (e) {
          err = 'json_parse_error';
          debugPrint('REGISTER JSON parse error: $e');
          debugPrint('REGISTER RAW BODY: ${res.body}');
        }
      } else {
        err = 'http_${res.statusCode}';
      }

      if (ok) {
        await SessionManager.saveSession(
          userId: user.id,
          provider: 'google',
          displayName: user.displayName ?? '',
          email: user.email,
          phone: _phoneCtrl.text.trim(),
          role: _role,
        );

        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
        messenger.showSnackBar(
          SnackBar(content: Text(updated > 0 ? 'Registro actualizado' : 'Registro creado')),
        );
        return;
      }

      if (err == 'already_exists') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este correo ya está registrado. Por favor inicia sesión.'),
        ));
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _feedback = 'Error al registrar: ${err ?? 'respuesta inválida del servidor'}';
      });
    } catch (e) {
      if (mounted) setState(() => _feedback = 'Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.googleAccount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completar registro'),
      ),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage:
                  (user.photoUrl != null) ? NetworkImage(user.photoUrl!) : null,
                  child: (user.photoUrl == null)
                      ? const Icon(Icons.person, size: 28)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${user.displayName ?? 'Usuario'}\n${user.email}',
                    style: const TextStyle(fontSize: 16),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),
            const Text('Completa tus datos para el registro inicial.'),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Rol dentro de la comunidad',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _role,
                    items: const [
                      DropdownMenuItem(value: 'Alumno/a', child: Text('Alumno/a')),
                      DropdownMenuItem(value: 'Madre/Padre/Tutor', child: Text('Madre/Padre/Tutor')),
                      DropdownMenuItem(value: 'Docente', child: Text('Docente')),
                      DropdownMenuItem(value: 'Vecino/a', child: Text('Vecino/a')),
                      DropdownMenuItem(value: 'Personal Administrativo', child: Text('Personal Administrativo')),
                    ],
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (para contacto en emergencias)',
                      border: OutlineInputBorder(),
                      hintText: 'Ej. 246-123-4567',
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Ingresa un teléfono.';
                      if (s.length < 7) return 'Teléfono no válido.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: !_showPass,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Crea una contraseña (mín. 6)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass2Ctrl,
                    obscureText: !_showPass2,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Confirmar contraseña',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_showPass2 ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPass2 = !_showPass2),
                      ),
                    ),
                    validator: (v) => (v != _passCtrl.text) ? 'No coincide' : null,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: _sending
                          ? const Text('Enviando…')
                          : const Text('Guardar registro'),
                      onPressed: _sending ? null : _submit,
                    ),
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _feedback!,
                      style: TextStyle(
                        color: _feedback!.startsWith('Error') ? Colors.red : Colors.green,
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
