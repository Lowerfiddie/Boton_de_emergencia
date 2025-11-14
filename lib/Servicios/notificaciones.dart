// lib/services/notification_service.dart
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:boton_de_emergencia/auth.dart';

import '../firebase_options.dart';

final FlutterLocalNotificationsPlugin _flnp =
    FlutterLocalNotificationsPlugin();

const String endpointRegisterToken =
    kAppsScriptUrl;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.handleRemoteMessage(message);
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static String? _tokenFcm;
  static String? _idUsuarioActual;
  static String? _rolActual;
  static String? _nombreUsuario;
  static String? _grupoActual;
  static String? _plantelActual;
  static String? _tipoDispositivo;

  static final Set<String> _topicsSuscritos = <String>{};

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Error inicializando Firebase: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 👇 inicialización mínima, sin canales manuales
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    try {
      await _flnp.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
    } catch (e) {
      debugPrint('Error inicializando notificaciones locales: $e');
    }

    try {
      await _requestPermissions();
    } catch (e) {
      debugPrint('Error solicitando permisos de notificación: $e');
    }

    FirebaseMessaging.onMessage.listen((message) async {
      await handleRemoteMessage(message);
    });

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

  static Future<void> handleRemoteMessage(RemoteMessage msg) async {
    await showTestAlarm(); // para probar, simplemente mostramos la misma alarma
  }

  static Future<void> showTestAlarm() async {
    await _flnp.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'ALERTA DE PRUEBA',
      'Disparo local desde el botón',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel', // canal simple sin config rara
          'Test',
          channelDescription: 'Canal de prueba',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
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
    await _enviarRegistroTokenSiDisponible();
    await configurarSuscripcionesPorRol(rol: rol, plantel: plantel);
  }

  static Future<void> _enviarRegistroTokenSiDisponible() async {
    final token = _tokenFcm;
    final idUsuario = _idUsuarioActual;
    final rol = _rolActual;
    final nombre = _nombreUsuario;
    final tipoDispositivo = _tipoDispositivo;
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
      grupo: _grupoActual,
      plantel: _plantelActual,
      fcmToken: token,
      tipoDispositivo: tipoDispositivo, email: '',
    );
  }

  // Registrar token FCM en backend (Google Sheets)
  static Future<void> registerTokenEnBackend({
    required String idUsuario,
    required String rol,
    required String nombre,
    required String email,       // 👈 NUEVO
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
  }

  static String? _topicPorPlantel(String prefijo, String? plantel) {
    if (plantel == null || plantel.trim().isEmpty) return null;
    final normalizado = plantel.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return '${prefijo}_$normalizado';
  }
}