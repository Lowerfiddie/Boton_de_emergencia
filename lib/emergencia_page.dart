import 'package:flutter/material.dart';

class DetalleEmergenciaPage extends StatelessWidget {
  final dynamic emergencia; // ideal: usa tu modelo (ver nota abajo)

  const DetalleEmergenciaPage({
    super.key,
    required this.emergencia,
  });

  @override
  Widget build(BuildContext context) {
    // Ajusta los campos según tu modelo real:
    final titulo = emergencia.nombre;
    final desc = emergencia.grupo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de emergencia'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo.toString(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(desc.toString()),
            const SizedBox(height: 16),

            // Placeholder del mapa (sin lógica todavía)
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