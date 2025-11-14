// lib/services/notification_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:boton_de_emergencia/auth.dart';

import '../firebase_options.dart';
import '../roles.dart';

final FlutterLocalNotificationsPlugin _flnp =
    FlutterLocalNotificationsPlugin();

const String endpointRegisterToken =
    kAppsScriptUrl;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.handleRemoteMessage(message);
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  NotificationService.handleNotificationResponse(response);
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static RemoteMessage? _initialMessage;
  static bool _initialMessageHandled = false;
  static const AndroidNotificationChannel _emergencyChannel =
      AndroidNotificationChannel(
    'sos_emergencias',
    'Alertas de emergencia',
    description: 'Notificaciones críticas del botón de emergencia',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  static const String _payloadEmergency = 'sos_alert';

  static String? _tokenFcm;
  static String? _idUsuarioActual;
  static String? _rolActual;
  static String? _nombreUsuario;
  static String? _grupoActual;
  static String? _plantelActual;
  static String? _tipoDispositivo;
  static String? _emailActual;

  static final Set<String> _topicsSuscritos = <String>{};

  static Future<void> initialize({GlobalKey<NavigatorState>? navigatorKey}) async {
    _navigatorKey = navigatorKey;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Error inicializando Firebase: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    try {
      await _flnp.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
      await _createAndroidChannel();
    } catch (e) {
      debugPrint('Error inicializando notificaciones locales: $e');
    }

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    try {
      await _requestPermissions();
    } catch (e) {
      debugPrint('Error solicitando permisos de notificación: $e');
    }

    FirebaseMessaging.onMessage.listen((message) async {
      await handleRemoteMessage(message, fromForeground: true);
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && _esMensajeSos(initial)) {
      _initialMessage = initial;
      _initialMessageHandled = false;
    }

    await _obtenerTokenInicial();

    _messaging.onTokenRefresh.listen((token) async {
      _tokenFcm = token;
      if (kDebugMode) {
        print('🔥 Nuevo FCM TOKEN: $token');
      }
      await _enviarRegistroTokenSiDisponible();
    });
  }

  static Future<void> _requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _flnp
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> _createAndroidChannel() async {
    final androidPlugin =
        _flnp.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_emergencyChannel);
  }

  static Future<void> handleRemoteMessage(RemoteMessage msg,
      {bool fromForeground = false}) async {
    if (!_esMensajeSos(msg)) return;
    await _mostrarNotificacionEmergencia(msg);
    if (fromForeground) {
      _mostrarAvisoForeground(msg);
    }
  }

  static Future<void> _mostrarNotificacionEmergencia(RemoteMessage msg) async {
    final data = Map<String, dynamic>.from(msg.data);
    final title = msg.notification?.title ?? _tituloDesdeData(data);
    final body = msg.notification?.body ?? _mensajeDesdeData(data);
    final payload = jsonEncode({'type': _payloadEmergency, 'data': data});
    final id = data['sosId']?.hashCode ??
        data['sos_id']?.hashCode ??
        msg.sentTime?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _flnp.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _emergencyChannel.id,
          _emergencyChannel.name,
          channelDescription: _emergencyChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ticker: 'Emergencia',
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      payload: payload,
    );
  }

  static void _mostrarAvisoForeground(RemoteMessage msg) {
    if (!isMonitoringRole(_rolActual)) return;
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final body = _mensajeDesdeData(Map<String, dynamic>.from(msg.data));
    messenger.showSnackBar(
      SnackBar(
        content: Text(body),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () {
            unawaited(_navegarAMonitoreo());
          },
        ),
      ),
    );
  }

  static String _tituloDesdeData(Map<String, dynamic> data) {
    final alumno = data['nombre'] ?? data['student'] ?? data['alumno'];
    if (alumno != null && alumno.toString().trim().isNotEmpty) {
      return 'Emergencia de ${alumno.toString().trim()}';
    }
    return 'Botón de emergencia activado';
  }

  static String _mensajeDesdeData(Map<String, dynamic> data) {
    final alumno = (data['nombre'] ?? data['student'] ?? data['alumno'])
            ?.toString()
            .trim() ??
        'Un alumno';
    final grupo = (data['grupo'] ?? data['group'])?.toString().trim();
    if (grupo != null && grupo.isNotEmpty) {
      return '$alumno (${grupo}) necesita ayuda.';
    }
    return '$alumno necesita ayuda.';
  }

  static bool _esMensajeSos(RemoteMessage msg) {
    final data = msg.data;
    final tipo = (data['tipo'] ?? data['type'] ?? data['op'])?.toString().toLowerCase();
    if (_contieneSos(tipo)) return true;
    final categoria = (data['category'] ?? data['categoria'])?.toString().toLowerCase();
    if (_contieneSos(categoria)) return true;
    final tag = (data['tag'] ?? data['topic'])?.toString().toLowerCase();
    if (_contieneSos(tag)) return true;
    return false;
  }

  static bool _contieneSos(String? valor) {
    if (valor == null) return false;
    return valor.contains('sos');
  }

  static Future<void> _handleOpenedMessage(RemoteMessage message) async {
    if (!_esMensajeSos(message)) return;
    if (!isMonitoringRole(_rolActual)) return;
    _initialMessageHandled = true;
    await _navegarAMonitoreo();
  }

  static Future<void> _navegarAMonitoreo() async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    navigator.pushNamed('/home', arguments: const {'openEmergencyFeed': true});
  }

  static void handleNotificationResponse(NotificationResponse response) {
    unawaited(_procesarPayload(response.payload));
  }

  static Future<void> _procesarPayload(String? payload) async {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['type'] == _payloadEmergency && isMonitoringRole(_rolActual)) {
        await _navegarAMonitoreo();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error leyendo payload de notificación: $e');
      }
    }
  }

  static Future<void> maybeHandleInitialMessageAfterLogin() async {
    if (_initialMessage == null || _initialMessageHandled) return;
    if (!isMonitoringRole(_rolActual)) return;
    _initialMessageHandled = true;
    final message = _initialMessage!;
    _initialMessage = null;
    await _handleOpenedMessage(message);
  }

  static Future<void> _obtenerTokenInicial() async {
    try {
      _tokenFcm = await _messaging.getToken();
      if (kDebugMode) {
        print('🔥 FCM TOKEN: $_tokenFcm');
      }
      await _enviarRegistroTokenSiDisponible();
    } catch (e) {
      debugPrint('Error obteniendo token FCM: $e');
    }
  }

  static Future<void> actualizarDatosUsuarioNotificaciones({
    required String idUsuario,
    required String rol,
    required String nombre,
    required String email,
    String? grupo,
    String? plantel,
    required String tipoDispositivo,
  }) async {
    _idUsuarioActual = idUsuario.isEmpty ? null : idUsuario;
    _rolActual = rol;
    _nombreUsuario = nombre;
    _grupoActual = grupo;
    _plantelActual = plantel;
    _tipoDispositivo = tipoDispositivo;
    _emailActual = email;
    await _enviarRegistroTokenSiDisponible();
    await configurarSuscripcionesPorRol(rol: rol, plantel: plantel);
    await maybeHandleInitialMessageAfterLogin();
  }

  static Future<void> _enviarRegistroTokenSiDisponible() async {
    final token = _tokenFcm;
    final idUsuario = _idUsuarioActual;
    final rol = _rolActual;
    final nombre = _nombreUsuario;
    final tipoDispositivo = _tipoDispositivo;
    final email = _emailActual;
    if (token == null ||
        idUsuario == null ||
        rol == null ||
        nombre == null ||
        tipoDispositivo == null) {
      return;
    }

    await registerTokenEnBackend(
      idUsuario: idUsuario,
      rol: rol,
      nombre: nombre,
      email: email ?? '',
      grupo: _grupoActual,
      plantel: _plantelActual,
      fcmToken: token,
      tipoDispositivo: tipoDispositivo,
    );
  }

  // Registrar token FCM en backend (Google Sheets)
  static Future<void> registerTokenEnBackend({
    required String idUsuario,
    required String rol,
    required String nombre,
    required String email,
    String? grupo,
    String? plantel,
    required String fcmToken,
    required String tipoDispositivo,
  }) async {
    final uri = Uri.parse(endpointRegisterToken);
    final payload = jsonEncode({
      'op': 'register_token',      // 👈 IMPORTANTE
      'userId': idUsuario,         // 👈 Apps Script usa userId
      'nombre': nombre,
      'email': email,              // 👈 aunque sea el mismo que usaste para login
      'rol': rol,
      'grupo': grupo,
      // plantel lo puedes mandar aparte si luego lo quieres usar en el script:
      'plantel': plantel,
      'fcmToken': fcmToken,
      'dispositivo': tipoDispositivo,
    });

    try {
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: payload,
      );

      debugPrint(
          'register_token status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('No se pudo registrar token FCM.');
      }
    } catch (e) {
      debugPrint('Error registrando token en backend: $e');
    }
  }

  // Suscripción a topics de emergencia según rol
  static Future<void> configurarSuscripcionesPorRol({
    required String rol,
    String? plantel,
  }) async {
    final rolNormalizado = rol.trim().toLowerCase();
    final Set<String> topicsDeseados = <String>{};

    if (rolNormalizado == 'docente') {
      topicsDeseados.add('docentes_general');
      final topicPlantel = _topicPorPlantel('docentes', plantel);
      if (topicPlantel != null) topicsDeseados.add(topicPlantel);
    } else if (rolNormalizado == 'padre/madre/tutor' ||
        rolNormalizado == 'madre/padre/tutor' ||
        rolNormalizado == 'tutor') {
      topicsDeseados.add('tutores_general');
    } else if (rolNormalizado == 'vecino' || rolNormalizado == 'vecino/a') {
      topicsDeseados.add('vecinos_general');
    } else {
      // Alumnos y otros roles no se suscriben a topics de emergencia global
    }

    await _actualizarSuscripciones(topicsDeseados);
  }

  static Future<void> _actualizarSuscripciones(Set<String> deseados) async {
    final toUnsubscribe = _topicsSuscritos.difference(deseados);
    final toSubscribe = deseados.difference(_topicsSuscritos);

    for (final topic in toUnsubscribe) {
      try {
        await _messaging.unsubscribeFromTopic(topic);
      } catch (e) {
        debugPrint('Error al desuscribir topic $topic: $e');
      }
      _topicsSuscritos.remove(topic);
    }

    for (final topic in toSubscribe) {
      try {
        await _messaging.subscribeToTopic(topic);
        _topicsSuscritos.add(topic);
      } catch (e) {
        debugPrint('Error al suscribir topic $topic: $e');
      }
    }
  }

  static Future<void> limpiarSuscripciones() async {
    await _actualizarSuscripciones(<String>{});
    _idUsuarioActual = null;
    _rolActual = null;
    _nombreUsuario = null;
    _grupoActual = null;
    _plantelActual = null;
    _tipoDispositivo = null;
    _emailActual = null;
    _initialMessage = null;
    _initialMessageHandled = false;
  }

  static String? _topicPorPlantel(String prefijo, String? plantel) {
    if (plantel == null || plantel.trim().isEmpty) return null;
    final normalizado = plantel.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return '${prefijo}_$normalizado';
  }
}