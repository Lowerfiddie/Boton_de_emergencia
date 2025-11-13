// lib/services/notification_service.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

final FlutterLocalNotificationsPlugin _flnp =
FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.handleRemoteMessage(message);
}

class NotificationService {
  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 👇 inicialización mínima, sin canales manuales
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _flnp.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    await _requestPermissions();

    FirebaseMessaging.onMessage.listen((message) async {
      await handleRemoteMessage(message);
    });

    await printFcmToken();
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
          'test_channel',   // canal simple sin config rara
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

  static Future<void> printFcmToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (kDebugMode) {
      print('🔥 FCM TOKEN: $token');
    }
  }
}