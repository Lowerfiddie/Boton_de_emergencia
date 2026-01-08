# boton_de_emergencia

Aplicacion para emsad de boton que mande señal de emergencia

## Mapa de emergencia (Google Maps + Socket)

### Configuración de API key de Google Maps
- **Android:** define `MAPS_API_KEY` en `android/local.properties` o `~/.gradle/gradle.properties`.
- **iOS:** define `MAPS_API_KEY` en `ios/Flutter/Debug.xcconfig` y `ios/Flutter/Release.xcconfig`.

### Socket en tiempo real
Configura la URL del servidor de sockets con un `dart-define`:

```bash
flutter run --dart-define=SOCKET_URL=wss://tu-servidor-socket
```

El cliente se suscribe cuando se abre el mapa y se desconecta al salir. Se usan estos eventos:
- `emergency:join` / `emergency:leave` con `{ sosId, viewerId }`.
- `emergency:location` con `{ sosId, lat, lng, updatedAt?, address? }`.
- `emergency:expired` para liberar el bloqueo de navegación.

### Geocoding y consumo
El cliente **no** ejecuta reverse geocoding en cada actualización. Si el backend proporciona `address` en los eventos de socket, se muestra en el mapa. Se recomienda centralizar el reverse geocoding en backend con cache y throttling para compartir resultados entre clientes.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
