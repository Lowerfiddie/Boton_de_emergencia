import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DetalleEmergenciaPage extends StatelessWidget {
  final dynamic emergencia; // luego lo tipamos a SosItem

  const DetalleEmergenciaPage({
    super.key,
    required this.emergencia,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = emergencia.nombre;
    final desc = emergencia.grupo;

    final double? lat = emergencia.lat;
    final double? lng = emergencia.lng;

    final hasCoords = lat != null && lng != null && (lat != 0.0 || lng != 0.0);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de emergencia')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo.toString(), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(desc?.toString() ?? '—'),
            const SizedBox(height: 16),

            // MAPA (solo si hay coords)
            SizedBox(
              height: 260,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasCoords
                    ? GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(lat!, lng!),
                    zoom: 16,
                  ),
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: {
                    Marker(
                      markerId: const MarkerId('emergencia'),
                      position: LatLng(lat!, lng!),
                      infoWindow: InfoWindow(title: titulo.toString()),
                    ),
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
}