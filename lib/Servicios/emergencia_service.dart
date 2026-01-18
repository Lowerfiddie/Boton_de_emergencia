import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:boton_de_emergencia/auth.dart';
import 'package:http/io_client.dart';


class SosStartResponse {
  final bool ok;
  final String? sosId;
  final DateTime? expiresAt;
  final String? error;

  const SosStartResponse({
    required this.ok,
    this.sosId,
    this.expiresAt,
    this.error,
  });

  factory SosStartResponse.fromJson(Map<String, dynamic> j) {
    return SosStartResponse(
      ok: j['ok'] == true,
      sosId: _asString(j['sosId']),
      expiresAt: _asDate(j['expiresAt']),
      error: _asString(j['error']),
    );
  }
}

class EmergenciaService {
  static const String endpointEmergencia = kAppsScriptUrl;

  // Envío de emergencia al backend
  static Future<SosStartResponse> enviarEmergenciaAlBackend({
    required String idUsuario,
    required String nombreUsuario,
    required String email,
    required String rol,
    String? grupo,
    String? plantel,
    required DateTime fechaHoraLocal,
    String? ubicacion,
    required String dispositivo,
    double? lat,
    double? lng,
    int minutes = 10, // <-- YA EXISTE minutes
  }) async {
    final uri = Uri.parse(endpointEmergencia);

    final payload = jsonEncode({
      'op': 'sos_start',
      'userId': idUsuario,
      'nombre': nombreUsuario,
      'email': email,
      'rol': rol,
      'grupo': grupo,
      'lat': lat ?? 0.0,
      'lng': lng ?? 0.0,
      'minutes': minutes,
      'plantel': plantel,
      'fechaHoraLocal': fechaHoraLocal.toIso8601String(),
      'ubicacion': ubicacion,
      'dispositivo': dispositivo,
    });

    debugPrint('sos_start payload: $payload');

    final response = await _postAppsScript(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: payload,
    );

    if (response.statusCode < 200 || response.statusCode >= 400) {
      return SosStartResponse(
        ok: false,
        error: 'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return SosStartResponse.fromJson(decoded);
      }
      return const SosStartResponse(ok: false, error: 'Respuesta no es JSON Map');
    } catch (e) {
      return SosStartResponse(ok: false, error: 'JSON parse error: $e');
    }
  }

  static Future<List<SosItem>> obtenerFeedEmergencias({
    String? grupo,
    String? plantel,
  }) async {
    final uri = Uri.parse(endpointEmergencia);

    final payload = jsonEncode({
      'op': 'sos_feed',
      'grupo': grupo,
      'plantel': plantel,
    });

    debugPrint('sos_feed payload: $payload');

    final client = IOClient();

    try {
      // 1) Primera petición POST normal
      final req = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = payload
        ..followRedirects = false; // 👈 IMPORTANTE: nosotros manejamos el 302

      final streamed = await client.send(req);
      var response = await http.Response.fromStream(streamed);

      debugPrint('sos_feed response: ${response.statusCode} ${response.body}');

      // 2) Si Apps Script responde 302/303 con HTML -> seguir el Location
      if ((response.statusCode == 302 || response.statusCode == 303) &&
          response.headers['location'] != null) {
        final location = response.headers['location']!;
        debugPrint('sos_feed redirect -> $location');

        // En 302/303 normalmente se resuelve con GET al Location
        final resp2 = await client.get(Uri.parse(location));
        response = resp2;

        debugPrint('sos_feed response(redirect): ${response.statusCode} ${response.body}');
      }

      if (response.statusCode != 200) {
        throw Exception('Error al obtener feed: HTTP ${response.statusCode}');
      }

      final bodyTrim = response.body.trimLeft();
      if (bodyTrim.startsWith('<!DOCTYPE') || bodyTrim.startsWith('<HTML')) {
        throw Exception('Respuesta HTML inesperada. Revisa endpointEmergencia (/exec) o permisos.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        throw Exception('Feed inválido: $decoded');
      }

      final items = (decoded['items'] as List?) ?? [];
      return items.map((e) => SosItem.fromJson(e)).toList();
    } finally {
      client.close();
    }
  }

  /// Maneja redirects típicos de Apps Script (302/303/307/308)
  static Future<http.Response> _postAppsScript(
      Uri url, {
        required Map<String, String> headers,
        required String body,
      }) async {
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
        return await http.post(uri, headers: hdrs, body: body);
      } else {
        return await http.get(uri, headers: hdrs);
      }
    }

    return first;
  }
}

class SosItem {
  final String sosId;
  final String userId;
  final String nombre;
  final String rol;
  final String grupo;
  final double? lat;
  final double? lng;
  final DateTime? lastUpdate;
  final DateTime? expiresAt;

  SosItem({
    required this.sosId,
    required this.userId,
    required this.nombre,
    required this.rol,
    required this.grupo,
    this.lat,
    this.lng,
    this.lastUpdate,
    this.expiresAt,
  });

  factory SosItem.fromJson(Map<String, dynamic> json) {
    return SosItem(
      sosId: json['sosId'] ?? '',
      userId: json['userId'] ?? '',
      nombre: json['nombre'] ?? '',
      rol: json['rol'] ?? '',
      grupo: json['grupo'] ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      lastUpdate: _asDate(json['lastUpdate']),
      expiresAt: _asDate(json['expiresAt']),
    );
  }
}

String? _asString(dynamic v) => v?.toString();

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString();
  return DateTime.tryParse(s);
}