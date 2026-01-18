import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

class SosLiveService {
  SosLiveService._();
  static final SosLiveService I = SosLiveService._();

  final _db = FirebaseDatabase.instance;

  StreamSubscription<Position>? _sub;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  DatabaseReference _sosRef(String sosId) => _db.ref('sos/$sosId');

  /// Crea el nodo y empieza a enviar ubicación cada X segundos (throttle).
  Future<void> start({
    required String sosId,
    required String userId,
    required String nombre,
    required String rol,
    String? grupo,
    String? plantel,
    Duration minInterval = const Duration(seconds: 3),
  }) async {
    // Meta inicial (una vez)
    await _sosRef(sosId).child('meta').set({
      'sosId': sosId,
      'userId': userId,
      'nombre': nombre,
      'rol': rol,
      'grupo': grupo ?? '',
      'plantel': plantel ?? '',
      'status': 'active',
      'startedAt': ServerValue.timestamp,
    });

    // Última ubicación (inicial)
    final pos0 = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    await _sosRef(sosId).child('live').set({
      'lat': pos0.latitude,
      'lng': pos0.longitude,
      'accuracy': pos0.accuracy,
      'heading': pos0.heading,
      'speed': pos0.speed,
      'updatedAt': ServerValue.timestamp,
    });

    // Stream de GPS
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // solo si se mueve >= 5m (reduce costos)
      ),
    ).listen((pos) async {
      final now = DateTime.now();
      if (now.difference(_lastSent) < minInterval) return;
      _lastSent = now;

      await _sosRef(sosId).child('live').update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'heading': pos.heading,
        'speed': pos.speed,
        'updatedAt': ServerValue.timestamp,
      });
    });
  }

  Future<void> end(String sosId) async {
    await _sosRef(sosId).child('meta').update({
      'status': 'ended',
      'endedAt': ServerValue.timestamp,
    });
    await _sub?.cancel();
    _sub = null;
  }

  /// Para que monitores escuchen el live:
  Stream<DatabaseEvent> watchLive(String sosId) {
    return _sosRef(sosId).child('live').onValue;
  }
}