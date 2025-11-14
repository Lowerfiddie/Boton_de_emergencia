import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmergenciaService {
  static const String endpointEmergencia =
      'https://MI_ENDPOINT/emergencia'; // TODO: reemplazar

  // Envío de emergencia al backend
  static Future<bool> enviarEmergenciaAlBackend({
    required String idUsuario,
    required String nombreUsuario,
    required String rol,
    String? grupo,
    String? plantel,
    required DateTime fechaHoraLocal,
    String? ubicacion,
    required String dispositivo,
  }) async {
    final uri = Uri.parse(endpointEmergencia);
    final payload = jsonEncode({
      'idUsuario': idUsuario,
      'nombreUsuario': nombreUsuario,
      'rol': rol,
      'grupo': grupo,
      'plantel': plantel,
      'fechaHoraLocal': fechaHoraLocal.toIso8601String(),
      'ubicacion': ubicacion,
      'dispositivo': dispositivo,
    });

    try {
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: payload,
      );

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if (!ok) {
        debugPrint(
            'Error al registrar emergencia. Status: ${response.statusCode}');
      }
      return ok;
    } catch (e) {
      debugPrint('Error enviando emergencia al backend: $e');
      return false;
    }
  }
}
