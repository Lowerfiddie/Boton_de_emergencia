import 'package:flutter/material.dart';

import 'services_checker.dart';

class LoginOptions extends StatefulWidget {
  const LoginOptions({
    super.key,
    this.onGoogle,
    this.onHuawei,
    this.onEmail,
    this.showEmailOption = true,
  });

  final VoidCallback? onGoogle;
  final VoidCallback? onHuawei;
  final VoidCallback? onEmail;
  final bool showEmailOption;

  @override
  State<LoginOptions> createState() => _LoginOptionsState();
}

class _LoginOptionsState extends State<LoginOptions> {
  bool _gms = false;
  bool _hms = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ServicesChecker.checkServices();
    if (!mounted) return;
    setState(() {
      _gms = s.gms;
      _hms = s.hmsId || s.hmsCore;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final noGmsNoHms = !_gms && !_hms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _gms ? _loginWithGoogle : null,
          icon: const Icon(Icons.g_mobiledata),
          label: const Text('Iniciar con Google'),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _hms ? _loginWithHuawei : null,
          icon: const Icon(Icons.security),
          label: const Text('Iniciar con Huawei ID'),
        ),
        if (noGmsNoHms) ...[
          const SizedBox(height: 12),
          const Text(
            'Este dispositivo no cuenta con Google Mobile Services ni Huawei Mobile Services. '
            'Usa usuario/contraseña o teléfono.',
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.showEmailOption) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.onEmail != null ? _loginWithEmail : null,
            child: const Text('Iniciar con correo'),
          ),
        ],
      ],
    );
  }

  void _loginWithGoogle() {
    widget.onGoogle?.call();
    // tu flujo de Google sign-in
  }

  void _loginWithHuawei() {
    widget.onHuawei?.call();
    // tu flujo Huawei (HMS Account Kit)
  }

  void _loginWithEmail() {
    widget.onEmail?.call();
    // email/pass
  }
}
