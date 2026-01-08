import 'dart:async';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'Servicios/emergencia_service.dart';
import 'Servicios/emergency_socket_service.dart';
import 'auth.dart';

class EmergencyMapArgs {
  const EmergencyMapArgs({
    required this.item,
    required this.viewerRole,
    required this.viewerId,
  });

  final SosItem item;
  final String viewerRole;
  final String viewerId;
}

class EmergencyMapScreen extends StatefulWidget {
  const EmergencyMapScreen({super.key, required this.args});

  final EmergencyMapArgs args;

  @override
  State<EmergencyMapScreen> createState() => _EmergencyMapScreenState();
}

class _EmergencyMapScreenState extends State<EmergencyMapScreen> {
  static const MarkerId _markerId = MarkerId('emergency_location');

  GoogleMapController? _mapController;
  late SosItem _item;
  late LatLng _current;
  Marker? _marker;
  DateTime? _lastUpdate;
  DateTime? _expiresAt;
  String? _address;
  bool _canExit = false;
  bool _socketReady = false;
  EmergencySocketService? _socketService;
  StreamSubscription<EmergencyLocationUpdate>? _locationSub;
  StreamSubscription<void>? _expiredSub;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _item = widget.args.item;
    _expiresAt = _item.expiresAt;
    final lat = _item.lat ?? 0.0;
    final lng = _item.lng ?? 0.0;
    _current = LatLng(lat, lng);
    _marker = Marker(markerId: _markerId, position: _current);
    _lastUpdate = _item.lastUpdate;
    _configureExpiryGuard();
    _connectSocketIfAvailable();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _locationSub?.cancel();
    _expiredSub?.cancel();
    _socketService?.dispose();
    super.dispose();
  }

  void _configureExpiryGuard() {
    _updateCanExit();
    _expiryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _updateCanExit();
    });
  }

  void _updateCanExit() {
    final expiresAt = _expiresAt;
    if (expiresAt == null) {
      if (_canExit) {
        setState(() => _canExit = false);
      }
      return;
    }
    final expired = DateTime.now().isAfter(expiresAt);
    if (expired != _canExit) {
      setState(() => _canExit = expired);
    }
  }

  void _connectSocketIfAvailable() {
    if (kSocketUrl.isEmpty) return;
    _socketService = EmergencySocketService(
      emergencyId: _item.sosId,
      viewerId: widget.args.viewerId,
    );
    _socketService!.connect();
    _socketReady = true;
    _locationSub = _socketService!.locationUpdates.listen(_handleLocationUpdate);
    _expiredSub = _socketService!.expiredUpdates.listen((_) {
      if (!mounted) return;
      setState(() {
        _canExit = true;
        _expiresAt = DateTime.now();
      });
    });
  }

  void _handleLocationUpdate(EmergencyLocationUpdate update) {
    if (!mounted) return;
    if (update.emergencyId != _item.sosId) return;
    final previous = _current;
    setState(() {
      _current = LatLng(update.lat, update.lng);
      _marker = Marker(
        markerId: _markerId,
        position: _current,
      );
      _lastUpdate = update.updatedAt ?? DateTime.now();
      _address = update.address ?? _address;
    });
    final controller = _mapController;
    if (controller != null && _distanceInMeters(previous, _current) > 15) {
      controller.animateCamera(CameraUpdate.newLatLng(_current));
    }
  }

  Future<bool> _handleBack() async {
    return _canExit;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coordsText =
        '${_current.latitude.toStringAsFixed(5)}, ${_current.longitude.toStringAsFixed(5)}';
    final lastUpdateText = _formatDateTime(_lastUpdate);
    final expiresText = _expiresAt == null
        ? 'En seguimiento'
        : (_canExit
            ? 'Emergencia expirada'
            : 'Expira: ${_formatDateTime(_expiresAt)}');
    final viewerRole = widget.args.viewerRole;

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mapa de emergencia'),
          automaticallyImplyLeading: _canExit,
          leading: _canExit
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
        ),
        body: Column(
          children: [
            Expanded(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _current,
                  zoom: 16,
                ),
                markers: _marker == null ? {} : {_marker!},
                myLocationButtonEnabled: false,
                onMapCreated: (controller) {
                  _mapController = controller;
                },
              ),
            ),
            Material(
              color: theme.colorScheme.surface,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _item.nombre,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    if (viewerRole.isNotEmpty)
                      Text('Rol monitor: $viewerRole'),
                    Text('Coordenadas: $coordsText'),
                    if (_address != null && _address!.isNotEmpty)
                      Text('Dirección: $_address'),
                    Text('Última actualización: $lastUpdateText'),
                    Text('Estado: $expiresText'),
                    if (!_socketReady)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Socket no configurado. Define SOCKET_URL para recibir ubicación en tiempo real.',
                        ),
                      ),
                    if (!_canExit)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'La navegación está bloqueada hasta que la emergencia expire.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '—';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  double _distanceInMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final sinDLat = Math.sin(dLat / 2);
    final sinDLng = Math.sin(dLng / 2);
    final aVal = sinDLat * sinDLat +
        Math.cos(lat1) * Math.cos(lat2) * sinDLng * sinDLng;
    final cVal = 2 * Math.atan2(Math.sqrt(aVal), Math.sqrt(1 - aVal));
    return earthRadius * cVal;
  }

  double _toRadians(double deg) => deg * (Math.pi / 180);
}
