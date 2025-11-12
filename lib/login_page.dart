import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'session_manager.dart';
import 'auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass  = TextEditingController();
  bool _showPass = false;
  bool _loading = false;
  bool _hasGms = false;
  bool _hasHms = false;
  bool _servicesLoading = true;

  @override
  void initState() {
    super.initState();
    _detectServices();
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }


  Future<void> _login() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final url = Uri.parse(kAppsScriptUrl);
      final payload = jsonEncode({
        'op': 'login',
        'email': _email.text.trim().toLowerCase(),
        'password': _pass.text, // sin trim
      });

      final res = await postAppsScript(url, {'Content-Type': 'application/json'}, payload);

      // Debug opcional
      debugPrint('LOGIN STATUS=${res.statusCode} CT=${res.headers['content-type']}');
      debugPrint('LOGIN BODY=${res.body.substring(0, res.body.length.clamp(0,300))}');

      bool ok = false;
      Map<String, dynamic>? user;
      String? serverError;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          ok = j['ok'] == true;
          user = (j['user'] as Map?)?.cast<String, dynamic>();
          serverError = j['error'] as String?;
        } catch (_) { ok = false; }
      }

      if (!mounted) return;

      if (ok && user != null) {
        await SessionManager.saveSession(
          userId: user['uid'] ?? '',
          provider: 'password',
          displayName: (user['nombre']?.toString().isNotEmpty ?? false)
              ? user['nombre']
              : _email.text.split('@').first,
          email: user['email'] ?? _email.text.trim().toLowerCase(),
          phone: user['telefono'] ?? '—',
          role: user['rol'] ?? '—',
        );
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
      } else {
        switch (serverError) {
          case 'not_found':
            messenger.showSnackBar(const SnackBar(content: Text('No existe una cuenta con ese correo.')));
            break;
          case 'no_password_set':
            messenger.showSnackBar(const SnackBar(content: Text('Tu cuenta no tiene contraseña. Define una primero.')));
            break;
          case 'invalid_credentials':
          default:
            messenger.showSnackBar(const SnackBar(content: Text('Contraseña incorrecta')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error de red: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _detectServices() async {
    try {
      final gms = await DeviceApps.isAppInstalled('com.google.android.gms');
      final hms = await DeviceApps.isAppInstalled('com.huawei.hwid');

      if (!mounted) return;

      setState(() {
        _hasGms = gms;
        _hasHms = hms;
        _servicesLoading = false;
      });

      if (!gms && !hms) {
        Fluttertoast.showToast(
          msg: 'Este dispositivo no tiene GMS ni HMS. Algunas opciones se deshabilitarán.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasGms = false;
        _hasHms = false;
        _servicesLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    // tu flujo de Google Sign-In aquí
  }

  Future<void> _signInWithHuawei() async {
    // tu flujo de Huawei ID aquí
  }

  @override
  Widget build(BuildContext context) {
    if (_servicesLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final noGmsNoHms = !_hasGms && !_hasHms;

    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: ListView(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _hasGms ? _signInWithGoogle : null,
                  icon: const Icon(Icons.login),
                  label: const Text('Iniciar con Google'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _hasHms ? _signInWithHuawei : null,
                  icon: const Icon(Icons.login),
                  label: const Text('Iniciar con Huawei ID'),
                ),
              ),
              const SizedBox(height: 16),
              if (noGmsNoHms)
                const Text(
                  'Este dispositivo no cuenta con Google Mobile Services ni Huawei Mobile Services. '
                  'Usa usuario/contraseña o teléfono.',
                  textAlign: TextAlign.center,
                ),
              if (noGmsNoHms) const SizedBox(height: 24) else const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'O inicia sesión con correo y contraseña',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s);
                  return ok ? null : 'Correo no válido';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: !_showPass,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
                validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_open),
                  label: Text(_loading ? 'Entrando…' : 'Iniciar con correo/contraseña'),
                  onPressed: _loading ? null : _login,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Consejo: activa el autocompletado/gestor de contraseñas de Google en tu dispositivo para autocompletar email y contraseña.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
  ///net.dart
  /// Hace POST a /exec. Si hay redirect:
  /// - 302/303 → GET a Location (Apps Script sirve el JSON cacheado)
  /// - 307/308 → re-POST a Location (preservar mtodo)
  Future<http.Response> postAppsScript(Uri url, Map<String, String> headers, String body) async {
    final req = http.Request('POST', url)
      ..headers.addAll(headers)
      ..body = body
      ..followRedirects = false
      ..persistentConnection = false;

    final first = await http.Response.fromStream(await req.send());

    final status = first.statusCode;
    if (status >= 300 && status < 400) {
      final loc = first.headers['location'];
      if (loc == null) return first;

      final hdrs = {...headers};
      final setCookie = first.headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        hdrs['cookie'] = setCookie;
      }

      final uri = Uri.parse(loc);
      if (status == 307 || status == 308) {
        // (raro en Apps Script) preservar POST
        return await http.post(uri, headers: hdrs, body: body);
      } else {
        // 302/303: usar GET para leer el contenido JSON generado por doPost
        return await http.get(uri, headers: hdrs);
      }
    }

    return first;
  }
}

