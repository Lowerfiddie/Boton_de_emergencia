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

import '../emergency_map_screen.dart';
import '../firebase_options.dart';
import '../roles.dart';
import 'emergencia_service.dart';

final FlutterLocalNotificationsPlugin _flnp = FlutterLocalNotificationsPlugin();

const String endpointRegisterToken = kAppsScriptUrl;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint(
      '📥 [background] RemoteMessage recibido: ${message.messageId}, data: ${message.data}');
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

  // Evita re-inicializaciones (hot restart/hot reload)
  static bool _initialized = false;

  static const AndroidNotificationChannel _emergencyChannel =
  AndroidNotificationChannel(
    'emergencias_channel',
    'Emergencias',
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
  static String? _tipoDispositivo;
  static String? _emailActual;
  static String? _grupoActual;
  static String? _plantelActual;


  // Evita duplicar registros de token (por hot restart o múltiples llamadas con mismos datos)
  static String? _lastRegisterSignature;
  static DateTime? _lastRegisterAt;
  static final Set<String> _topicsSuscritos = <String>{};
  static final StreamController<void> _feedRefreshController =
  StreamController<void>.broadcast();

  static Stream<void> get feedRefreshStream => _feedRefreshController.stream;

  // ===================================================================================

  static Future<void> initialize({GlobalKey<NavigatorState>? navigatorKey}) async {
    _navigatorKey = navigatorKey;

    // Evita duplicar listeners por hot restart / re-entradas
    if (_initialized) {
      debugPrint('NotificationService.initialize(): ya inicializado, se omite.');
      return;
    }
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        debugPrint('Firebase ya inicializado con ${Firebase.apps.length} apps.');
      }
    } catch (e) {
      debugPrint('Error inicializando Firebase: $e');
      return;
    }

    // Background handler (se registra una sola vez)
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
      debugPrint(
          '📩 [foreground] RemoteMessage: ${message.messageId}, data: ${message.data}');
      await handleRemoteMessage(message, fromForeground: true);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint(
          '🔔 onMessageOpenedApp -> ${message.messageId}, data: ${message.data}');
      unawaited(_handleOpenedMessage(message));
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && _esMensajeSos(initial)) {
      _initialMessage = initial;
      _initialMessageHandled = false;
    }

    await _obtenerTokenInicial();

    _messaging.onTokenRefresh.listen((token) async {
      _tokenFcm = token;
      debugPrint('🔥 onTokenRefresh → token: $token, rol: $_rolActual, user: $_idUsuarioActual');
      await _enviarRegistroTokenSiDisponible(
        grupo: _grupoActual,
        plantel: _plantelActual,
      );
    });
  }

  static Future<void> _requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _flnp
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> _createAndroidChannel() async {
    final androidPlugin = _flnp
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_emergencyChannel);
  }

  static Future<void> handleRemoteMessage(RemoteMessage msg,
      {bool fromForeground = false}) async {
    _logRemoteMessage(msg, source: fromForeground ? 'foreground' : 'background');
    if (!_esMensajeSos(msg)) {
      debugPrint('Mensaje recibido no corresponde a SOS, se ignora.');
      return;
    }
    if (!isMonitoringRole(_rolActual)) {
      debugPrint(
          'Rol actual ($_rolActual) no es de monitoreo. Ignorando notificación SOS.');
      return;
    }
    await _mostrarNotificacionEmergencia(msg);
    if (fromForeground) {
      _notificarActualizacionFeed();
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

    debugPrint('📣 Mostrando notificación local: $title - $body');
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
            unawaited(_navegarAEmergenciaSiAplica(Map<String, dynamic>.from(msg.data)));
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
      return '$alumno ($grupo) necesita ayuda.';
    }
    return '$alumno necesita ayuda.';
  }

  static bool _esMensajeSos(RemoteMessage msg) {
    final data = msg.data;
    final tipo = (data['tipo'] ?? data['type'] ?? data['op'])
        ?.toString()
        .toLowerCase();
    if (_contieneSos(tipo)) return true;
    final categoria =
    (data['category'] ?? data['categoria'])?.toString().toLowerCase();
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
    debugPrint('🧭 Abriendo feed de emergencias desde notificación.');
    await _navegarAEmergenciaSiAplica(Map<String, dynamic>.from(message.data));
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
        final payloadData =
            Map<String, dynamic>.from(data['data'] as Map? ?? {});
        await _navegarAEmergenciaSiAplica(payloadData);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error leyendo payload de notificación: $e');
      }
    }
  }

  static Future<void> _navegarAEmergenciaSiAplica(
      Map<String, dynamic> data) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    final item = _sosItemFromData(data);
    if (item?.lat == null ||
        item?.lng == null ||
        (item?.lat == 0.0 && item?.lng == 0.0)) {
      await _navegarAMonitoreo();
      return;
    }
    navigator.pushNamed(
      '/emergency-map',
      arguments: EmergencyMapArgs(
        item: item!,
        viewerRole: _rolActual ?? '',
        viewerId: _idUsuarioActual ?? '',
      ),
    );
  }

  static SosItem? _sosItemFromData(Map<String, dynamic> data) {
    try {
      final item = SosItem.fromJson(data);
      if (item.sosId.isEmpty) return null;
      return item;
    } catch (_) {
      return null;
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
      debugPrint(
          '🔥 Token inicial FCM: $_tokenFcm, rol: $_rolActual, user: $_idUsuarioActual');
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
    _tipoDispositivo = tipoDispositivo;
    _emailActual = email;
    _grupoActual = grupo;
    _plantelActual = plantel;

    debugPrint(
        'Configurando notificaciones -> user: $idUsuario, rol: $rol, grupo: $grupo, plantel: $plantel, dispositivo: $tipoDispositivo');

    await _enviarRegistroTokenSiDisponible(
      grupo: grupo,
      plantel: plantel,
    );
    await configurarSuscripcionesPorRol(rol: rol, plantel: plantel);
    await maybeHandleInitialMessageAfterLogin();
  }

  // Ajuste: pasar grupo/plantel realmente (antes estaban null siempre)
  static Future<void> _enviarRegistroTokenSiDisponible({
    String? grupo,
    String? plantel,
  }) async {
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
      debugPrint(
          'Registro de token pendiente. Datos incompletos (token: $token, user: $idUsuario, rol: $rol, nombre: $nombre, dispositivo: $tipoDispositivo)');
      return;
    }

    final sig = [
      idUsuario,
      rol,
      token,
      (grupo ?? ''),
      (plantel ?? ''),
      (tipoDispositivo),
      (email ?? ''),
    ].join('|');

    final nowTime = DateTime.now();
    if (_lastRegisterSignature == sig &&
        _lastRegisterAt != null &&
        nowTime.difference(_lastRegisterAt!).inSeconds < 30) {
      debugPrint('register_token: mismo payload reciente, se omite para evitar duplicado.');
      return;
    }
    _lastRegisterSignature = sig;
    _lastRegisterAt = nowTime;

    debugPrint('Listo para registrar token. user: $idUsuario, rol: $rol, token: $token');

    await registerTokenEnBackend(
      kAppsScriptUrl: kAppsScriptUrl,
      idUsuario: idUsuario,
      rol: rol,
      nombre: nombre,
      email: email ?? '',
      grupo: grupo,
      plantel: plantel,
      tipoDispositivo: tipoDispositivo,
      fcmToken: token,
    );
  }

  // ===================================================================================
  // ✅ FIX PRINCIPAL: Apps Script responde 302 -> location (script.googleusercontent.com)
  // y hay que seguirlo manteniendo POST para obtener JSON.
  // ===================================================================================

  static Future<Map<String, dynamic>?> registerTokenEnBackend({
    required String kAppsScriptUrl,
    required String idUsuario,
    required String nombre,
    required String email,
    required String rol,
    String? grupo,
    String? plantel,
    required String tipoDispositivo,
    required String fcmToken,
  }) async {
    final payload = {
      'op': 'register_token',
      'userId': idUsuario,
      'nombre': nombre,
      'email': email,
      'rol': rol,
      'grupo': grupo ?? '',
      'plantel': plantel ?? '',
      'dispositivo': tipoDispositivo,
      'fcmToken': fcmToken,
    };

    final uri = Uri.parse(kAppsScriptUrl);

    try {
      final result = await _postAppsScriptWithRedirect(
        uri: uri,
        payload: payload,
        tag: 'register_token',
      );

      if (kDebugMode) {
        debugPrint('✅ register_token OK: $result');
      }
      return result;
    } catch (e) {
      debugPrint('❌ register_token error: $e');
      // NO truena la app, solo registra el error
      return null;
    }
  }

  static Future<Map<String, dynamic>> _postAppsScriptWithRedirect({
    required Uri uri,
    required Map<String, dynamic> payload,
    required String tag,
  }) async {
    // 1) Primer POST (no seguir redirects automáticamente)
    final req1 = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..headers['Accept'] = 'application/json'
      ..body = jsonEncode(payload);

    final res1 = await req1.send();
    final body1 = await res1.stream.bytesToString();

    if (kDebugMode) {
      debugPrint('$tag status: ${res1.statusCode}');
      debugPrint('$tag headers: ${res1.headers}');
      debugPrint('$tag body (first 200): ${_short(body1, 200)}');
    }

    // 2) 200-299 OK -> JSON directo
    if (res1.statusCode >= 200 && res1.statusCode < 300) {
      return _parseJsonOrThrow(body1, res1.statusCode, tag);
    }

    // 3) Redirect -> Apps Script manda Location a script.googleusercontent.com
    if (res1.statusCode == 301 ||
        res1.statusCode == 302 ||
        res1.statusCode == 303 ||
        res1.statusCode == 307 ||
        res1.statusCode == 308) {
      final loc = res1.headers['location'];
      if (loc == null || loc.isEmpty) {
        throw Exception('$tag redirect sin header location. status=${res1.statusCode}');
      }

      if (kDebugMode) debugPrint('➡️ $tag redirect to: $loc');

      final locUri = Uri.parse(loc);

      // Conserva query del redirect (user_content_key, lib, etc.)
      final qp = <String, String>{}..addAll(locUri.queryParameters);

      String put(String k, dynamic v) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty) qp[k] = s;
        return s;
      }

      // Requeridos
      put('op', payload['op']);
      put('userId', payload['userId']);
      put('fcmToken', payload['fcmToken']);

      // Opcionales
      put('nombre', payload['nombre']);
      put('email', payload['email']);
      put('rol', payload['rol']);
      put('grupo', payload['grupo']);
      put('plantel', payload['plantel']);
      put('dispositivo', payload['dispositivo']);

      final getUri = locUri.replace(queryParameters: qp);

      if (kDebugMode) debugPrint('➡️ $tag GET redirect URL: $getUri');

      final res2 = await http.get(
        getUri,
        headers: const {'Accept': 'application/json'},
      );

      final body2 = res2.body;

      if (kDebugMode) {
        debugPrint('$tag final status: ${res2.statusCode}');
        debugPrint('$tag final headers: ${res2.headers}');
        debugPrint('$tag final body (first 400): ${_short(body2, 400)}');
      }

      if (res2.statusCode >= 200 && res2.statusCode < 300) {
        return _parseJsonOrThrow(body2, res2.statusCode, tag);
      }

      throw Exception('$tag falló tras redirect. status=${res2.statusCode}, body=${_short(body2, 400)}');
    }

    // 4) Cualquier otro status (4xx/5xx)
    throw Exception('$tag falló. status=${res1.statusCode}, body=${_short(body1, 400)}');
  }

  static Map<String, dynamic> _parseJsonOrThrow(
      String body, int status, String tag) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('$tag respuesta no es un JSON object. decoded=$decoded');
    } catch (e) {
      throw Exception('$tag respuesta no es JSON válido. status=$status body=${_short(body, 400)} err=$e');
    }
  }

  static String _short(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...';
  }

  // ===================================================================================

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
    _tipoDispositivo = null;
    _emailActual = null;
    _initialMessage = null;
    _initialMessageHandled = false;
  }

  static String? _topicPorPlantel(String prefijo, String? plantel) {
    if (plantel == null || plantel.trim().isEmpty) return null;
    final normalizado =
    plantel.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return '${prefijo}_$normalizado';
  }

  static void _notificarActualizacionFeed() {
    if (!_feedRefreshController.isClosed) {
      _feedRefreshController.add(null);
    }
  }

  static void _logRemoteMessage(RemoteMessage msg, {required String source}) {
    debugPrint(
        '📨 [$source] mensaje SOS potencial id=${msg.messageId}, data=${msg.data}');
    final notif = msg.notification;
    if (notif != null) {
      debugPrint('   título: ${notif.title} | cuerpo: ${notif.body}');
    }
  }
}
