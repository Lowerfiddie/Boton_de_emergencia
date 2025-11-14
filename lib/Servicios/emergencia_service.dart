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

  static Future<List<SosItem>> obtenerFeedEmergencias({
    String? grupo,
    String? plantel,
  }) async {
    final uri = Uri.parse(endpointEmergencia);
    final payload = <String, dynamic>{'op': 'sos_feed'};
    if (grupo != null && grupo.trim().isNotEmpty) {
      payload['grupo'] = grupo.trim();
    }
    if (plantel != null && plantel.trim().isNotEmpty) {
      payload['plantel'] = plantel.trim();
    }

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (kDebugMode) {
      debugPrint('sos_feed status: ${response.statusCode}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('No se pudo obtener el feed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    final items = _extraerLista(decoded);
    return items.map(SosItem.fromJson).toList();
  }

  static List<Map<String, dynamic>> _extraerLista(dynamic decoded) {
    List<dynamic>? raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic>) {
      for (final key in ['items', 'sos', 'data', 'result']) {
        final value = decoded[key];
        if (value is List) {
          raw = value;
          break;
        }
      }
    }
    final base = raw ?? <dynamic>[];
    return base
        .whereType<Map>()
        .map((entry) =>
            entry.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }
}

class SosItem {
  const SosItem({
    required this.sosId,
    required this.userId,
    required this.nombre,
    this.rol,
    this.grupo,
    this.lat,
    this.lng,
    this.lastUpdate,
    this.expiresAt,
  });

  final String sosId;
  final String userId;
  final String nombre;
  final String? rol;
  final String? grupo;
  final double? lat;
  final double? lng;
  final DateTime? lastUpdate;
  final DateTime? expiresAt;

  factory SosItem.fromJson(Map<String, dynamic> json) {
    return SosItem(
      sosId: _asString(json['sosId'] ?? json['sos_id'] ?? json['id']) ?? '',
      userId: _asString(json['userId'] ?? json['uid']) ?? '',
      nombre: _asString(json['nombre'] ?? json['name']) ?? 'Alumno',
      rol: _asString(json['rol']),
      grupo: _asString(json['grupo'] ?? json['group']),
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
      lastUpdate: _asDate(json['lastUpdate'] ?? json['last_update']),
      expiresAt: _asDate(json['expiresAt'] ?? json['expires_at']),
    );
  }
}

String? _asString(dynamic value) {
  if (value == null) return null;
  final str = value.toString();
  return str.isEmpty ? null : str;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
