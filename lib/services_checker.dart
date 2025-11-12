import 'package:flutter/services.dart';

class ServicesChecker {
  static const _ch = MethodChannel('com.teckali.system/packages');

  static Future<bool> hasPackage(String packageName) async {
    final ok = await _ch.invokeMethod<bool>('hasPackage', {
      'packageName': packageName,
    });
    return ok ?? false;
  }

  static Future<({bool gms, bool hmsId, bool hmsCore})> checkServices() async {
    final map = await _ch.invokeMapMethod<String, dynamic>('checkServices') ?? {};
    return (
      gms: map['gms'] == true,
      hmsId: map['hmsId'] == true,
      hmsCore: map['hmsCore'] == true,
    );
  }
}
