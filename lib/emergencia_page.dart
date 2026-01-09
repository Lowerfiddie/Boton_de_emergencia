import 'package:flutter/material.dart';
// Ajusta este import al archivo real donde esté SosItem
import 'Servicios/emergencia_service.dart'; // o models/sos_item.dart

class DetalleEmergenciaPage extends StatelessWidget {
  final SosItem emergencia;

  const DetalleEmergenciaPage({
    super.key,
    required this.emergencia,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = emergencia.nombre;
    final desc = emergencia.grupo ?? 'Sin grupo';

    // Para el paso del mapa más adelante:
    final hasCoords = emergencia.lat != null && emergencia.lng != null;
    final coordsTxt = hasCoords
        ? '${emergencia.lat!.toStringAsFixed(5)}, ${emergencia.lng!.toStringAsFixed(5)}'
        : 'Sin ubicación';

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de emergencia')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(desc),
            const SizedBox(height: 8),
            Text('Coordenadas: $coordsTxt'),
            const SizedBox(height: 16),

            // Placeholder del mapa (Paso 1)
            Container(
              height: 220,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Aquí irá el mapa'),
            ),
          ],
        ),
      ),
    );
  }
}