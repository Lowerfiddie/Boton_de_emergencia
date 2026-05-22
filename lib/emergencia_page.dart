import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';

import 'Servicios/sos_live_service.dart'; // <- el servicio RTDB

class DetalleEmergenciaPage extends StatefulWidget {
  final dynamic emergencia; // luego lo tipamos a SosItem

  const DetalleEmergenciaPage({
    super.key,
    required this.emergencia,
  });

  @override
  State<DetalleEmergenciaPage> createState() => _DetalleEmergenciaPageState();
}

class _DetalleEmergenciaPageState extends State<DetalleEmergenciaPage> {
  GoogleMapController? _map;
  StreamSubscription<DatabaseEvent>? _sub;

  LatLng? _pos;              // posición actual del alumno (stream)
  double? _accuracy;         // opcional
  DateTime? _lastUpdate;     // opcional
  bool _autoFollow = true;   // si quieres que la cámara lo siga

  String get _titulo => widget.emergencia.nombre?.toString() ?? '—';
  String get _desc => widget.emergencia.grupo?.toString() ?? '—';

  String? get _sosId {
    // depende de tu modelo SosItem; en tu Apps Script el campo se llama "sosId"
    final v = widget.emergencia.sosId;
    return v?.toString();
  }

  @override
  void initState() {
    super.initState();

    final double? lat = widget.emergencia.lat;
    final double? lng = widget.emergencia.lng;
    final hasCoords = lat != null && lng != null && (lat != 0.0 || lng != 0.0);
    if (hasCoords) _pos = LatLng(lat, lng);

    // 🔴 Arranca streaming si hay sosId
    final sosId = _sosId;
    if (sosId != null && sosId.isNotEmpty) {
      _sub = SosLiveService.I.watchLive(sosId).listen((event) {
        final v = event.snapshot.value;
        if (v is! Map) return;

        final lat2 = (v['lat'] as num?)?.toDouble();
        final lng2 = (v['lng'] as num?)?.toDouble();
        if (lat2 == null || lng2 == null) return;

        final acc = (v['accuracy'] as num?)?.toDouble();
        final updatedAt = v['updatedAt'];

        DateTime? dt;
        // updatedAt normalmente viene como timestamp ms en RTDB (ServerValue.timestamp)
        if (updatedAt is int) {
          dt = DateTime.fromMillisecondsSinceEpoch(updatedAt);
        }

        if (!mounted) return;
        setState(() {
          _pos = LatLng(lat2, lng2);
          _accuracy = acc;
          _lastUpdate = dt;
        });

        // mueve cámara si auto-follow activo y ya hay mapa
        if (_autoFollow && _map != null && _pos != null) {
          _map!.animateCamera(CameraUpdate.newLatLng(_pos!));
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _pos;
    final hasPos = pos != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de emergencia')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titulo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_desc),
            const SizedBox(height: 8),

            // Info extra del streaming
            if (_sosId == null || _sosId!.isEmpty)
              const Text('⚠️ Esta emergencia no tiene sosId, no se puede hacer streaming.')
            else ...[
              Row(
                children: [
                  FilterChip(
                    label: Text(_autoFollow ? 'Siguiendo' : 'Libre'),
                    selected: _autoFollow,
                    onSelected: (v) => setState(() => _autoFollow = v),
                  ),
                  const SizedBox(width: 8),
                  if (_accuracy != null)
                    Text('Precisión: ${_accuracy!.toStringAsFixed(0)} m'),
                ],
              ),
              if (_lastUpdate != null)
                Text('Última actualización: ${_fmt(_lastUpdate!)}'),
            ],

            const SizedBox(height: 16),

            SizedBox(
              height: 260,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasPos
                    ? GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: pos,
                    zoom: 16,
                  ),
                  onMapCreated: (c) => _map = c,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: {
                    Marker(
                      markerId: const MarkerId('emergencia'),
                      position: pos,
                      infoWindow: InfoWindow(title: _titulo),
                    ),
                  },
                  // Tip: si quieres que al tocar el mapa se quite el follow:
                  onCameraMoveStarted: () {
                    // solo si el usuario tocó/arrastró
                    // setState(() => _autoFollow = false);
                  },
                )
                    : Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Sin ubicación disponible'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    final sec = d.second.toString().padLeft(2, '0');
    return '$day/$month $hour:$min:$sec';
  }
}