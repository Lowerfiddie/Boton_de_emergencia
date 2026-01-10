import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Regresa (lat,lng) o null si no se pudo (sin permisos, GPS apagado, etc.)
  static Future<({double lat, double lng})?> getLatLng() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    return (lat: pos.latitude, lng: pos.longitude);
  }
}