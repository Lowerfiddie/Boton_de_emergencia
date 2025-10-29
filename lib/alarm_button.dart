import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

/// Posibles estados del flujo del botón de emergencia.
enum AlarmButtonStatus { idle, sending }

/// Resultado de un intento de disparar la alarma.
class AlarmTriggerResult {
  const AlarmTriggerResult.success(this.message)
      : success = true,
        error = null;

  const AlarmTriggerResult.failure(this.error)
      : success = false,
        message = null;

  final bool success;
  final String? message;
  final String? error;
}

/// Excepción controlada para comunicar errores al usuario final.
class AlarmButtonException implements Exception {
  AlarmButtonException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Controlador encargado de orquestar el flujo de "ENVIAR EMERGENCIA".
///
/// - Valida el horario permitido (lunes a viernes de 06:00 a 16:00).
/// - Solicita permisos de ubicación y transmite los cambios de posición
///   en tiempo real durante 15 minutos mediante un socket WebSocket.
/// - Genera una URL de Google Maps que pueden consumir los receptores
///   para visualizar la ubicación dinámica del alumno.
/// - Bloquea el botón durante el mismo lapso de 15 minutos.
class AlarmButtonController extends ChangeNotifier {
  AlarmButtonController({
    Uri? socketUrl,
    Duration? streamingDuration,
    LocationSettings? locationSettings,
  })  : socketUrl = socketUrl ?? _defaultSocketUrl,
        streamingDuration = streamingDuration ?? const Duration(minutes: 15),
        locationSettings = locationSettings ??
            const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 5,
            );

  /// URL del backend encargado de distribuir la alerta.
  final Uri socketUrl;

  /// Duración total de la sesión de ubicación/tiempo de bloqueo del botón.
  final Duration streamingDuration;

  /// Configuración usada para escuchar cambios de ubicación.
  final LocationSettings locationSettings;

  AlarmButtonStatus _status = AlarmButtonStatus.idle;
  String? _lastError;
  DateTime? _cooldownUntil;
  Timer? _cooldownTicker;
  Timer? _sessionTimer;
  WebSocketChannel? _channel;
  StreamSubscription<Position>? _positionSub;
  String? _activeSessionId;

  static final Uri _defaultSocketUrl = Uri.parse('wss://example.com/emergency');

  /// Último mensaje de error presentado por el controlador.
  String? get lastError => _lastError;

  /// Estatus actual del flujo.
  AlarmButtonStatus get status => _status;

  /// Indica si ya existe una sesión activa.
  bool get isSending => _status == AlarmButtonStatus.sending;

  /// Indica si el botón se encuentra temporalmente bloqueado.
  bool get isOnCooldown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  /// Tiempo restante del bloqueo.
  Duration? get cooldownRemaining {
    if (!isOnCooldown || _cooldownUntil == null) {
      return null;
    }
    final remaining = _cooldownUntil!.difference(DateTime.now());
    if (remaining.isNegative) {
      return null;
    }
    return remaining;
  }

  /// Determina si el flujo puede ejecutarse en este momento.
  bool get canTrigger =>
      !isSending && !isOnCooldown && _isWithinAllowedSchedule(DateTime.now());

  /// Indica si el horario actual se encuentra dentro de la ventana permitida.
  bool get isWithinScheduleNow => _isWithinAllowedSchedule(DateTime.now());

  /// Inicia el flujo completo de alerta.
  Future<AlarmTriggerResult> trigger(Map<String, String?> session) async {
    final now = DateTime.now();
    if (!_isWithinAllowedSchedule(now)) {
      const message =
          'El botón solo está disponible de lunes a viernes de 06:00 a 16:00.';
      _registerError(message);
      return const AlarmTriggerResult.failure(message);
    }

    if (isOnCooldown) {
      final remaining = cooldownRemaining;
      final message = remaining == null
          ? 'Debes esperar antes de volver a enviar una emergencia.'
          : 'Debes esperar ${_formatDuration(remaining)} para volver a usar el botón.';
      _registerError(message);
      return AlarmTriggerResult.failure(message);
    }

    if (isSending) {
      const message = 'Ya existe una sesión de emergencia en curso.';
      _registerError(message);
      return const AlarmTriggerResult.failure(message);
    }

    try {
      await _ensureLocationPermission();
    } on AlarmButtonException catch (e) {
      _registerError(e.message);
      return AlarmTriggerResult.failure(e.message);
    } catch (e) {
      final message = 'No fue posible obtener la ubicación: $e';
      _registerError(message);
      return AlarmTriggerResult.failure(message);
    }

    _status = AlarmButtonStatus.sending;
    _lastError = null;
    notifyListeners();

    try {
      final channel = WebSocketChannel.connect(socketUrl);
      _channel = channel;
      final sessionId = const Uuid().v4();
      _activeSessionId = sessionId;

      final expiresAt = DateTime.now().add(streamingDuration);
      _cooldownUntil = expiresAt;
      _startCooldownTicker();

      channel.sink.add(jsonEncode({
        'type': 'alarm:init',
        'sessionId': sessionId,
        'userId': session['userId'],
        'displayName': session['displayName'],
        'email': session['email'],
        'phone': session['phone'],
        'role': session['role'],
        'recipients': const ['docente', 'padre_tutor'],
        'expiresAt': expiresAt.toIso8601String(),
      }));

      _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen(
        (position) {
          _sendLocationUpdate(position);
        },
        onError: (Object error, StackTrace stackTrace) {
          _registerError('Error obteniendo la ubicación: $error');
          _finishSession();
        },
      );

      _sessionTimer = Timer(streamingDuration, () {
        _finishSession(releaseCooldown: true);
      });

      return const AlarmTriggerResult.success(
        'Se notificó la emergencia y se compartirá tu ubicación por 15 minutos.',
      );
    } catch (e) {
      _registerError('No fue posible conectarse con el servidor de emergencias: $e');
      _tearDownActiveSession(resetCooldown: true);
      return AlarmTriggerResult.failure(lastError ?? e.toString());
    }
  }

  /// Cancela todos los recursos activos y cierra la sesión en curso.
  void _finishSession({bool releaseCooldown = false}) {
    _sendSessionEnded();
    _tearDownActiveSession(resetCooldown: releaseCooldown);
    if (!releaseCooldown && _cooldownUntil != null) {
      _startCooldownTicker();
    }
    notifyListeners();
  }

  void _sendLocationUpdate(Position position) {
    final sessionId = _activeSessionId;
    final channel = _channel;
    if (sessionId == null || channel == null) {
      return;
    }

    final mapUrl = _buildGoogleMapsUrl(position.latitude, position.longitude);

    channel.sink.add(jsonEncode({
      'type': 'alarm:location',
      'sessionId': sessionId,
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'timestamp': DateTime.now().toIso8601String(),
      'mapUrl': mapUrl,
    }));
  }

  void _sendSessionEnded() {
    final sessionId = _activeSessionId;
    final channel = _channel;
    if (sessionId == null || channel == null) {
      return;
    }
    try {
      channel.sink.add(jsonEncode({
        'type': 'alarm:ended',
        'sessionId': sessionId,
        'timestamp': DateTime.now().toIso8601String(),
      }));
    } catch (_) {
      // Ignorar errores al cerrar la sesión.
    }
  }

  void _tearDownActiveSession({required bool resetCooldown}) {
    _positionSub?.cancel();
    _positionSub = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;

    try {
      _channel?.sink.close();
    } catch (_) {
      // Ignorar errores de cierre.
    }
    _channel = null;
    _activeSessionId = null;

    if (resetCooldown) {
      _cooldownUntil = null;
    }
    _stopCooldownTicker();
    _status = AlarmButtonStatus.idle;
  }

  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw AlarmButtonException(
        'Activa los servicios de ubicación para enviar una emergencia.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw AlarmButtonException(
        'La aplicación necesita permiso de ubicación para continuar.',
      );
    }
  }

  bool _isWithinAllowedSchedule(DateTime now) {
    const allowedWeekdays = <int>{
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    };

    if (!allowedWeekdays.contains(now.weekday)) {
      return false;
    }

    final start = DateTime(now.year, now.month, now.day, 6);
    final end = DateTime(now.year, now.month, now.day, 16);

    if (now.isBefore(start)) {
      return false;
    }

    if (!now.isBefore(end)) {
      return false;
    }

    return true;
  }

  void _startCooldownTicker() {
    _cooldownTicker?.cancel();
    if (_cooldownUntil == null) {
      return;
    }
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isOnCooldown) {
        _stopCooldownTicker();
      }
      notifyListeners();
    });
  }

  void _stopCooldownTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = null;
  }

  void _registerError(String message) {
    _lastError = message;
    notifyListeners();
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  static String _buildGoogleMapsUrl(double lat, double lng) {
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  @override
  void dispose() {
    _tearDownActiveSession(resetCooldown: true);
    super.dispose();
  }
}
