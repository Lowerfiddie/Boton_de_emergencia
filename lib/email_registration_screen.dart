import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'login_page.dart';
import 'session_manager.dart';
import 'auth.dart';

final _passCtrl = TextEditingController();
final _pass2Ctrl = TextEditingController();
bool _showPass = false;
bool _showPass2 = false;

class EmailRegistrationScreen extends StatefulWidget {
  const EmailRegistrationScreen({super.key});
  @override
  State<EmailRegistrationScreen> createState() => _EmailRegistrationScreenState();
}

class _EmailRegistrationScreenState extends State<EmailRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _role = 'Alumno/a';
  bool _sending = false;
  String? _msg;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() { _sending = true; _msg = null; });

    final userId = const Uuid().v4();

    try {
      final body = {
        'op'      : 'register_once',
        'userId'  : userId,
        'nombre'  : _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'telefono': _phoneCtrl.text.trim(),
        'rol'     : _role,
        'provider': 'Email',
        'photoUrl': '',
        'password': _passCtrl.text,
      };

      assert(kAppsScriptUrl.startsWith('https://script.google.com/macros/s/') && kAppsScriptUrl.endsWith('/exec'));
      debugPrint('POST to $kAppsScriptUrl');

      final res = await http.post(
        Uri.parse(kAppsScriptUrl), // tu URL /exec
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      int updated = 0;
      (res.headers['content-type'] ?? '').toLowerCase();
      bool ok = false;
      String? err;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          ok = j['ok'] == true;
          err = j['error'] as String?;
        } catch (_) {}
      }

      if (ok) {
        // continúa tu flujo: guardar sesión y navegar
        await SessionManager.saveSession(
          userId: userId,
          provider: 'email',
          displayName: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          role: _role,
        );
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
        messenger.showSnackBar(
          SnackBar(content: Text(updated > 0 ? 'Registro actualizado' : 'Registro creado')),
        );
      } else if (err == 'already_exists') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este correo ya está registrado. Por favor inicia sesión.'),
        ));
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      } else {
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'Error de red: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro con correo')),
      body: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre completo', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Correo electrónico', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final s = (v ?? '').trim();
                  final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(s);
                  return ok ? null : 'Correo no válido';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().length < 7) ? 'Teléfono no válido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rol', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Alumno/a', child: Text('Alumno/a')),
                  DropdownMenuItem(value: 'Madre/Padre/Tutor', child: Text('Madre/Padre/Tutor')),
                  DropdownMenuItem(value: 'Docente', child: Text('Docente')),
                  DropdownMenuItem(value: 'Vecino/a', child: Text('Vecino/a')),
                  DropdownMenuItem(value: 'Personal Administrativo', child: Text('Personal Administrativo')),
                ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passCtrl,
                obscureText: !_showPass,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Contraseña (mín. 6)',
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
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(_sending ? 'Enviando...' : 'Registrar'),
                  onPressed: _sending ? null : _submit,
                ),
              ),
              if (_msg != null) ...[
                const SizedBox(height: 12),
                Text(_msg!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}