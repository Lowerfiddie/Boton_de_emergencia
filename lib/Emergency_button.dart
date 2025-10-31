import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth.dart';
import 'session_manager.dart';

class EmergencyButton extends StatefulWidget {
  const EmergencyButton({super.key, this.cooldown = const Duration(minutes: 5)});

  final Duration cooldown;

  @override
  State<EmergencyButton> createState() => _EmergencyButtonState();
}

class _EmergencyButtonState extends State<EmergencyButton> {
  static const _cooldownKey = 'emergency_button_cooldown_until';
  static const List<String> _targetRoles = ['Madre/Padre/Tutor', 'Docente'];

  Timer? _ticker;
  DateTime? _cooldownUntil;
  Duration? _remaining;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _restoreCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restoreCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_cooldownKey);
    if (millis == null) return;

    final until = DateTime.fromMillisecondsSinceEpoch(millis);
    if (until.isAfter(DateTime.now())) {
      _startTicker(until);
    } else {
      await prefs.remove(_cooldownKey);
    }
  }

  Future<void> _handlePressed() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final session = await SessionManager.loadSession();
      final userId = session['userId'] ?? '';
      final senderRole = session['role'] ?? '';
      final senderName = session['displayName'] ?? '';
      final senderEmail = session['email'] ?? '';

      final payload = jsonEncode({
        'op': 'broadcast_emergency',
        'userId': userId,
        'sender': {
          'name': senderName,
          'email': senderEmail,
          'role': senderRole,
        },
        'targetRoles': _targetRoles,
        'notification': {
          'title': 'Atención',
          'body': 'Se ha reportado una emergencia.',
        },
      });

      final response = await http.post(
        Uri.parse(kAppsScriptUrl),
        headers: const {'Content-Type': 'application/json'},
        body: payload,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Código ${response.statusCode}');
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Notificación de emergencia enviada.')),
      );

      await _activateCooldown();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo enviar la emergencia: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _activateCooldown() async {
    final until = DateTime.now().add(widget.cooldown);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cooldownKey, until.millisecondsSinceEpoch);
    _startTicker(until);
  }

  void _startTicker(DateTime until) {
    _ticker?.cancel();
    _cooldownUntil = until;
    _updateRemaining();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  Future<void> _clearCooldown() async {
    _ticker?.cancel();
    _ticker = null;
    _cooldownUntil = null;
    _remaining = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cooldownKey);
  }

  void _updateRemaining() {
    if (!mounted) return;

    final until = _cooldownUntil;
    if (until == null) {
      setState(() => _remaining = null);
      return;
    }

    final now = DateTime.now();
    final diff = until.difference(now);
    if (diff <= Duration.zero) {
      setState(() => _remaining = null);
      unawaited(_clearCooldown());
    } else {
      setState(() => _remaining = diff);
    }
  }

  bool get _isCoolingDown => _remaining != null && _remaining! > Duration.zero;

  String _labelText() {
    if (_sending) {
      return 'Enviando…';
    }
    if (_isCoolingDown) {
      final remaining = _remaining!;
      final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
      return 'Disponible en $minutes:$seconds';
    }
    return 'ENVIAR EMERGENCIA';
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.sos, size: 32),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          _labelText(),
          style: const TextStyle(fontSize: 18),
        ),
      ),
      onPressed: (_isCoolingDown || _sending) ? null : _handlePressed,
      style: FilledButton.styleFrom(minimumSize: const Size(280, 64)),
    );
  }
}
