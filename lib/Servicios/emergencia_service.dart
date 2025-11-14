import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:boton_de_emergencia/auth.dart';

class EmergenciaService {
  static const String endpointEmergencia =
      kAppsScriptUrl;

  // Envío de emergencia al backend
  static Future<bool> enviarEmergenciaAlBackend({
    required String idUsuario,
    required String nombreUsuario,
    required String email,          // 👈 NUEVO
    required String rol,
    String? grupo,
    String? plantel,
    required DateTime fechaHoraLocal,
    String? ubicacion,              // puedes usarla para construir lat/lng si luego lo haces
    required String dispositivo,
    double? lat,                    // 👈 NUEVO opcional
    double? lng,                    // 👈 NUEVO opcional
  }) async {
    final uri = Uri.parse(endpointEmergencia);

    // Por ahora, si no tienes geolocalización real, manda 0.0
    final payload = jsonEncode({
      'op': 'sos_start',                  // 👈 IMPORTANTE
      'userId': idUsuario,                // 👈 Apps Script usa userId
      'nombre': nombreUsuario,
      'email': email,
      'rol': rol,
      'grupo': grupo,
      'lat': lat ?? 0.0,
      'lng': lng ?? 0.0,
      'minutes': 10,                      // tiempo de vigencia del SOS
      // Datos extra que el script hoy ignora, pero puedes usar luego:
      'plantel': plantel,
      'fechaHoraLocal': fechaHoraLocal.toIso8601String(),
      'ubicacion': ubicacion,
      'dispositivo': dispositivo,
    });

      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: payload,
      );

      debugPrint(
          'sos_start status: ${response.statusCode}, body: ${response.body}');

      final status = response.statusCode;
      final ok = (status >= 200 && status < 300) || status == 302;

      debugPrint('sos_start status: $status, body: ${response.body}');

      if (!ok) {
        debugPrint('Error al registrar emergencia.');
      }
      return ok;
  }
}