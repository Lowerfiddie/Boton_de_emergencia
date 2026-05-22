import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth.dart';

class EmergencyLocationUpdate {
  const EmergencyLocationUpdate({
    required this.emergencyId,
    required this.lat,
    required this.lng,
    this.updatedAt,
    this.address,
  });

  final String emergencyId;
  final double lat;
  final double lng;
  final DateTime? updatedAt;
  final String? address;
}

class EmergencySocketService {
  EmergencySocketService({required this.emergencyId, required this.viewerId});

  final String emergencyId;
  final String viewerId;

  io.Socket? _socket;
  final StreamController<EmergencyLocationUpdate> _locationController =
      StreamController<EmergencyLocationUpdate>.broadcast();
  final StreamController<void> _expiredController =
      StreamController<void>.broadcast();

  Stream<EmergencyLocationUpdate> get locationUpdates =>
      _locationController.stream;
  Stream<void> get expiredUpdates => _expiredController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect() {
    if (_socket != null) return;

    final socket = io.io(
      kSocketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .build(),
    );

    socket.onConnect((_) {
      debugPrint('✅ Socket conectado para emergencia $emergencyId');
      socket.emit('emergency:join', {
        'sosId': emergencyId,
        'viewerId': viewerId,
      });
    });

    socket.onDisconnect((_) {
      debugPrint('🔌 Socket desconectado para emergencia $emergencyId');
    });

    socket.on('emergency:location', (data) {
      final update = _parseLocationUpdate(data);
      if (update != null) {
        _locationController.add(update);
      }
    });

    socket.on('emergency:expired', (_) {
      _expiredController.add(null);
    });

    socket.onError((error) {
      debugPrint('Socket error: $error');
    });

    socket.connect();
    _socket = socket;
  }

  void sendLocationUpdate({
    required double lat,
    required double lng,
    DateTime? updatedAt,
  }) {
    final socket = _socket;
    if (socket == null) return;
    socket.emit('emergency:location_update', {
      'sosId': emergencyId,
      'lat': lat,
      'lng': lng,
      'updatedAt': updatedAt?.toIso8601String(),
    });
  }

  void disconnect() {
    final socket = _socket;
    if (socket == null) return;
    socket.emit('emergency:leave', {
      'sosId': emergencyId,
      'viewerId': viewerId,
    });
    socket.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    if (!_locationController.isClosed) {
      _locationController.close();
    }
    if (!_expiredController.isClosed) {
      _expiredController.close();
    }
  }

  EmergencyLocationUpdate? _parseLocationUpdate(dynamic data) {
    if (data is! Map) return null;
    final lat = _asDouble(data['lat']);
    final lng = _asDouble(data['lng']);
    if (lat == null || lng == null) return null;
    final emergencyId =
        (data['sosId'] ?? data['sos_id'] ?? data['id'])?.toString();
    if (emergencyId == null || emergencyId.isEmpty) return null;
    return EmergencyLocationUpdate(
      emergencyId: emergencyId,
      lat: lat,
      lng: lng,
      updatedAt: _asDate(data['updatedAt'] ?? data['lastUpdate']),
      address: data['address']?.toString(),
    );
  }
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

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
