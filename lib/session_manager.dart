import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const _kIsRegistered = 'is_registered';
  static const _kUserId = 'user_id';
  static const _kProvider = 'provider'; // 'google' | 'email'
  static const _kDisplayName = 'display_name';
  static const _kEmail = 'email';
  static const _kPhone = 'phone';
  static const _kRole = 'role';
  static const _kGrupo = 'grupo';
  static const _kPlantel = 'plantel';

  static Future<bool> isRegistered() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kIsRegistered) ?? false;
    // Si quieres condicionar a que "completó registro", puedes usar otra bandera.
  }

  static Future<void> saveSession({
    required String userId,
    required String provider,
    String? displayName,
    String? email,
    String? phone,
    String? role,
    String? grupo,
    String? plantel,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kIsRegistered, true);
    await sp.setString(_kUserId, userId);
    await sp.setString(_kProvider, provider);
    if (displayName != null) {
      await sp.setString(_kDisplayName, displayName);
    } else {
      await sp.remove(_kDisplayName);
    }
    if (email != null) {
      await sp.setString(_kEmail, email);
    } else {
      await sp.remove(_kEmail);
    }
    if (phone != null) {
      await sp.setString(_kPhone, phone);
    } else {
      await sp.remove(_kPhone);
    }
    if (role != null) {
      await sp.setString(_kRole, role);
    } else {
      await sp.remove(_kRole);
    }
    if (grupo != null) {
      await sp.setString(_kGrupo, grupo);
    } else {
      await sp.remove(_kGrupo);
    }
    if (plantel != null) {
      await sp.setString(_kPlantel, plantel);
    } else {
      await sp.remove(_kPlantel);
    }
  }

  static Future<Map<String, String?>> loadSession() async {
    final sp = await SharedPreferences.getInstance();
    return {
      'userId': sp.getString(_kUserId),
      'provider': sp.getString(_kProvider),
      'displayName': sp.getString(_kDisplayName),
      'email': sp.getString(_kEmail),
      'phone': sp.getString(_kPhone),
      'role': sp.getString(_kRole),
      'grupo': sp.getString(_kGrupo),
      'plantel': sp.getString(_kPlantel),
    };
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.clear();
  }
}