import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'session_manager.dart';
import 'auth.dart'; // para googleSignIn
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'Servicios/notificaciones.dart';
import 'Servicios/emergencia_service.dart';
import 'roles.dart';

const String kRolPermitidoEmergencia = kRolAlumnoEstandar;
const Duration kBloqueoEmergencia = Duration(minutes: 1);
const int kHoraInicioEmergencia = 7;
const int kHoraFinEmergencia = 22;

enum HomeSection { perfil, emergencia, contactos }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, String?> _session = {};
  bool _loading = true;
  bool _silentTried = false;
  HomeSection _section = HomeSection.emergencia;
  bool _processedInitialArgs = false;

  @override
  void initState() {
    super.initState();
    _initHome();

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_processedInitialArgs) return;
    _processedInitialArgs = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['openEmergencyFeed'] == true) {
      setState(() => _section = HomeSection.emergencia);
    }
  }

  Future<void> _initHome() async {
    // 1) Cargar sesión guardada
    final s = await SessionManager.loadSession();
    if (!mounted) return;
    setState(() {
      _session = s;
      _loading = false;
    });

    await _configurarNotificacionesSesion(s);

    // Reintentar sesión Google de forma silenciosa (opcional)
    if (s['provider'] == 'google' && !_silentTried) {
      _silentTried = true;
      try {
        await googleSignIn.signInSilently(suppressErrors: true);
        // Si necesitas refrescar nombre/foto tras el silent sign-in:
        final acc = googleSignIn.currentUser;
        if (acc != null) {
          // No es obligatorio: solo si quieres actualizar datos guardados localmente
          await SessionManager.saveSession(
            userId: acc.id,
            provider: 'google',
            displayName: s['displayName'] ?? acc.displayName,
            email: s['email'] ?? acc.email,
            phone: s['phone'],
            role: s['role'],
            grupo: s['grupo'],
            plantel: s['plantel'],
          );
          final updated = await SessionManager.loadSession();
          if (!mounted) return;
          setState(() => _session = updated);
          await _configurarNotificacionesSesion(updated);
        }
      } catch (_) {
        // Silencio errores; si se requiere token se pedirá al usar Sheets
      }
    }
  }

  Future<void> _configurarNotificacionesSesion(
      Map<String, String?> datosSesion) async {
    final rol = datosSesion['role'];
    final idSesion = datosSesion['userId'];
    final idGoogle = googleSignIn.currentUser?.id;
    final idUsuario =
        (idSesion != null && idSesion.isNotEmpty) ? idSesion : (idGoogle ?? '');
    if (rol == null || rol.isEmpty || idUsuario.isEmpty) {
      return;
    }

    final nombre = datosSesion['displayName'] ??
        googleSignIn.currentUser?.displayName ??
        'Usuario';
    final email = datosSesion['email'] ??
        googleSignIn.currentUser?.email ??
        '';

    final dispositivo = defaultTargetPlatform.name;

    await NotificationService.actualizarDatosUsuarioNotificaciones(
      idUsuario: idUsuario,
      rol: rol,
      nombre: nombre,
      email: email,
      grupo: datosSesion['grupo'],
      plantel: datosSesion['plantel'],
      tipoDispositivo: dispositivo,
    );
  }

  void _onSelect(HomeSection s) {
    setState(() => _section = s);
    Navigator.of(context).maybePop(); // cierra el Drawer si está abierto
  }

  Future<void> _logout() async {
    // Si fue Google, cerrar sesión allí también
    if (_session['provider'] == 'google') {
      try {
        await googleSignIn.disconnect(); // Revoca el token
      } catch (_) {
        // ignorar errores de desconexión
      }
      try {
        await googleSignIn.signOut();
      } catch (_) {}
    }

    await NotificationService.limpiarSuscripciones();
    await SessionManager.clear();
    // Vuelve a la pantalla de login (o SplashGate que te mandará al login)
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
    // Nota: si tu MaterialApp no usa rutas, reemplaza por:
    // Navigator.of(context).pushAndRemoveUntil(
    //   MaterialPageRoute(builder: (_) => const SignInScreen()),
    //   (route) => false,
    // );
  }

  @override
  Widget build(BuildContext context) {
    final acc = googleSignIn.currentUser;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final displayName = _session['displayName']
        ?? acc?.displayName
        ?? (_session['email']?.split('@').first)
        ?? 'Usuario';
    final email    = _session['email'] ?? acc?.email ?? '—';
    final role     = _session['role'] ?? '—';
    final phone    = _session['phone'] ?? '—';
    final provider = _session['provider'] ?? (acc != null ? 'google' : '—');

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForSection(_section)),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              _DrawerHeader(displayName: displayName, email: email),
              Expanded(
                child: ListView(
                  children: [
                    _drawerTile(
                      icon: Icons.person,
                      text: 'Mis datos',
                      selected: _section == HomeSection.perfil,
                      onTap: () => _onSelect(HomeSection.perfil),
                    ),
                    _drawerTile(
                      icon: Icons.sos,
                      text: 'Botón de emergencia',
                      selected: _section == HomeSection.emergencia,
                      onTap: () => _onSelect(HomeSection.emergencia),
                    ),
                    _drawerTile(
                      icon: Icons.contacts,
                      text: 'Contactos de emergencia',
                      selected: _section == HomeSection.contactos,
                      onTap: () => _onSelect(HomeSection.contactos),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Cerrar sesión'),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _section.index,
        children: [
          PerfilPage(
            displayName: displayName,
            email: email,
            role: role,
            phone: phone,
            provider: provider,
          ),
          EmergenciaPage(
            userId: _session['userId'] ?? acc?.id ?? '',
            displayName: displayName,
            email: email,
            phone: phone,
            role: role,
            grupo: _session['grupo'],
            plantel: _session['plantel'],
          ),
          const ContactosPage(), // con persistencia local
        ],
      ),
    );
  }

  String _titleForSection(HomeSection s) {
    switch (s) {
      case HomeSection.perfil: return 'Mis datos';
      case HomeSection.emergencia:
        return isMonitoringRole(_session['role'])
            ? 'Monitoreo de emergencias'
            : 'Botón de emergencia';
      case HomeSection.contactos: return 'Contactos de emergencia';
    }
  }

  ListTile _drawerTile({
    required IconData icon,
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(text),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.displayName, required this.email});
  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    return DrawerHeader(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            child: Text(
              _initials(displayName),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('$displayName\n$email', style: const TextStyle(fontSize: 16)),
          )
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'U';
    final first  = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final ini = (first + second).toUpperCase();
    return ini.isEmpty ? 'U' : ini;
  }
}

class PerfilPage extends StatelessWidget {
  const PerfilPage({
    super.key,
    required this.displayName,
    required this.email,
    required this.role,
    required this.phone,
    required this.provider,
  });

  final String displayName;
  final String email;
  final String role;
  final String phone;
  final String provider;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Card(child: ListTile(leading: const Icon(Icons.person),  title: const Text('Nombre'),   subtitle: Text(displayName))),
          Card(child: ListTile(leading: const Icon(Icons.email),   title: const Text('Correo'),   subtitle: Text(email))),
          Card(child: ListTile(leading: const Icon(Icons.badge),   title: const Text('Rol'),      subtitle: Text(role))),
          Card(child: ListTile(leading: const Icon(Icons.phone),   title: const Text('Teléfono'), subtitle: Text(phone))),
          Card(child: ListTile(leading: const Icon(Icons.vpn_key), title: const Text('Proveedor'),subtitle: Text(provider.toUpperCase()))),
        ],
      ),
    );
  }
}

class EmergenciaPage extends StatefulWidget {
  const EmergenciaPage({
    super.key,
    required this.userId,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.role,
    this.grupo,
    this.plantel,
  });

  final String userId;
  final String displayName;
  final String email;
  final String phone;
  final String role;
  final String? grupo;
  final String? plantel;

  @override
  State<EmergenciaPage> createState() => _EmergenciaPageState();
}

class _EmergenciaPageState extends State<EmergenciaPage> {
  bool _enviando = false;
  Future<List<SosItem>>? _feedFuture;
  StreamSubscription<void>? _feedSubscription;

  bool get _esAlumno => isAlumnoRole(widget.role);

  @override
  void initState() {
    super.initState();
    if (!_esAlumno) {
      _feedFuture = _cargarFeed();
      _feedSubscription =
          NotificationService.feedRefreshStream.listen((_) async {
        if (!mounted) return;
        debugPrint(
            '🔄 Refrescando feed tras notificación en primer plano para ${widget.role}.');
        await refrescarFeed();
      });
    }
  }

  @override
  void dispose() {
    _feedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_esAlumno) {
      return _buildAlumnoContent();
    }
    return _buildMonitoreoContent();
  }

  Widget _buildAlumnoContent() {
    final boton = FilledButton.icon(
      icon: const Icon(Icons.sos, size: 32),
      label: const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text('ENVIAR EMERGENCIA', style: TextStyle(fontSize: 18)),
      ),
      onPressed: _enviando ? null : _manejarBoton,
      style: FilledButton.styleFrom(minimumSize: const Size(280, 64)),
    );

    return SafeArea(
      minimum: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          boton,
          const SizedBox(height: 12),
          const Text(
            'Presiona solo si necesitas ayuda inmediata.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoreoContent() {
    final future = _feedFuture;
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Monitoreo de emergencias',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('Desliza hacia abajo para actualizar el listado.'),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refrescarFeed,
              child: FutureBuilder<List<SosItem>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting ||
                      future == null) {
                    return _buildLoadingList();
                  }
                  if (snapshot.hasError) {
                    return _buildMessageList(
                      Text(
                        'No se pudo cargar el feed: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      action: FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        onPressed: () {
                          refrescarFeed();
                        },
                      ),
                    );
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return _buildMessageList(
                      const Text(
                        'No hay emergencias activas en este momento.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.redAccent,
                            child: Icon(Icons.warning, color: Colors.white),
                          ),
                          title: Text(item.nombre),
                          subtitle: Text(_detalleItem(item)),
                          trailing: _buildEstadoChip(item),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<SosItem>> _cargarFeed() {
    return EmergenciaService.obtenerFeedEmergencias(
      grupo: widget.grupo,
      plantel: widget.plantel,
    );
  }

  Future<void> refrescarFeed() async {
    try {
      final future = _cargarFeed();
      final items = await future;
      if (!mounted) return;
      setState(() {
        _feedFuture = Future.value(items);
      });
    } catch (e) {
      debugPrint('Error refrescando feed: $e');
      if (!mounted) return;
      setState(() {
        _feedFuture = Future.error(e);
      });
    }
  }

  Widget _buildLoadingList() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 80),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildMessageList(Widget child, {Widget? action}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      children: [
        Center(child: child),
        if (action != null) ...[
          const SizedBox(height: 16),
          Center(child: action),
        ],
      ],
    );
  }

  String _detalleItem(SosItem item) {
    final grupo = (item.grupo?.isNotEmpty ?? false) ? item.grupo : 'Sin grupo';
    final rol = (item.rol?.isNotEmpty ?? false) ? item.rol : '—';
    final lastUpdate = _formatDateTime(item.lastUpdate);
    final coords = (item.lat != null && item.lng != null)
        ? '\nUbicación aprox.: ${item.lat!.toStringAsFixed(4)}, ${item.lng!.toStringAsFixed(4)}'
        : '';
    return 'Grupo: $grupo\nRol: $rol\nÚltima actualización: $lastUpdate$coords';
  }

  Widget _buildEstadoChip(SosItem item) {
    final expires = item.expiresAt;
    late final String texto;
    late final Color fondo;
    late final Color textoColor;
    if (expires == null) {
      texto = 'En seguimiento';
      fondo = Colors.orange.shade100;
      textoColor = Colors.orange.shade700;
    } else {
      final diff = expires.difference(DateTime.now());
      if (diff.isNegative) {
        texto = 'Expirada';
        fondo = Colors.grey.shade200;
        textoColor = Colors.grey.shade700;
      } else {
        final mins = diff.inMinutes;
        final secs = diff.inSeconds % 60;
        texto = 'Expira en ${mins}m ${secs.toString().padLeft(2, '0')}s';
        fondo = Colors.redAccent.shade100;
        textoColor = Colors.redAccent.shade700;
      }
    }
    return Chip(
      backgroundColor: fondo,
      label: Text(
        texto,
        style: TextStyle(color: textoColor),
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

  Future<void> _manejarBoton() async {
    final messenger = ScaffoldMessenger.of(context);
    final ahora = DateTime.now();

    // Restricción de horario
    if (!_estaDentroHorario(ahora)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('El botón solo funciona de 7:00 a 16:00.')),
      );
      return;
    }

    final userKey = widget.userId.isNotEmpty ? widget.userId : widget.email;
    final ultima = await EmergencyUsageStore.obtenerUltimaActivacion(userKey);
    if (ultima != null) {
      final diff = ahora.difference(ultima);
      if (diff < kBloqueoEmergencia) {
        final restante = kBloqueoEmergencia - diff;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Botón bloqueado. Intenta de nuevo en ${_formatDuration(restante)}.'),
          ),
        );
        return;
      }
    }

    setState(() => _enviando = true);
    try {
      final enviado = await _enviarEmergencia(ahora);
      if (!mounted) return;

      if (enviado) {
        await EmergencyUsageStore.guardarActivacion(userKey, ahora);
        messenger.showSnackBar(
          const SnackBar(content: Text('Emergencia enviada.')), // Bloqueo de 15 minutos
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo registrar la emergencia en el backend. Intenta nuevamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<bool> _enviarEmergencia(DateTime fecha) async {
    final dispositivo = defaultTargetPlatform.name;
    return EmergenciaService.enviarEmergenciaAlBackend(
      idUsuario: widget.userId,
      nombreUsuario: widget.displayName,
      email: widget.email,
      rol: widget.role,
      grupo: widget.grupo,
      plantel: widget.plantel,
      fechaHoraLocal: fecha,
      ubicacion: null,
      dispositivo: dispositivo,
    );
  }

  bool _estaDentroHorario(DateTime ahora) {
    final inicio = DateTime(ahora.year, ahora.month, ahora.day, kHoraInicioEmergencia);
    final fin = DateTime(ahora.year, ahora.month, ahora.day, kHoraFinEmergencia);
    return !ahora.isBefore(inicio) && !ahora.isAfter(fin);
  }

  String _formatDuration(Duration d) {
    final minutos = d.inMinutes;
    final segundos = d.inSeconds % 60;
    if (minutos > 0) {
      return '${minutos}m ${segundos.toString().padLeft(2, '0')}s';
    }
    return '${segundos}s';
  }

}

class ContactosPage extends StatefulWidget {
  const ContactosPage({super.key});
  @override
  State<ContactosPage> createState() => _ContactosPageState();
}

///net.dart
/// Hace POST a /exec. Si hay redirect:
/// - 302/303 → GET a Location (Apps Script sirve el JSON cacheado)
/// - 307/308 → re-POST a Location (preservar metodo)
Future<http.Response> postAppsScript(Uri url, Map<String, String> headers, String body) async {
  final req = http.Request('POST', url)
    ..headers.addAll(headers)
    ..body = body
    ..followRedirects = false
    ..persistentConnection = false;

  final first = await http.Response.fromStream(await req.send());

  final status = first.statusCode;
  if (status >= 300 && status < 400) {
    final loc = first.headers['location'];
    if (loc == null) return first;

    final hdrs = {...headers};
    final setCookie = first.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      hdrs['cookie'] = setCookie;
    }

    final uri = Uri.parse(loc);
    if (status == 307 || status == 308) {
      // (raro en Apps Script) preservar POST
      return await http.post(uri, headers: hdrs, body: body);
    } else {
      // 302/303: usar GET para leer el contenido JSON generado por doPost
      return await http.get(uri, headers: hdrs);
    }
  }

  return first;
}

class _ContactosPageState extends State<ContactosPage> {
  List<EmergencyContact> _items = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> deleteContactOnServer({
    required String appsScriptUrl,
    required String userId,
    required String emailLower,
    required String phoneRaw,
  }) async {
    final payload = jsonEncode({
      'op': 'contacts_delete',
      'userId': userId,              // puede ir vacío, server usa fallback por email
      'email': emailLower,           // fallback si no hay userId
      'phones': [phoneRaw],          // tal como se muestra al usuario; server normaliza
    });

    final res = await postAppsScript(
      Uri.parse(appsScriptUrl),
      {'Content-Type': 'application/json'},
      payload,
    );

    if (res.statusCode >= 200 && res.statusCode < 400) {
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return j['ok'] == true;
      } catch (_) {
        // Apps Script a veces regresa text/plain; considéralo OK si 2xx/3xx
        return true;
      }
    }
    return false;
  }

  void _orderUserOverDefaults({bool alsoPersist = true}) {
    final users = _items.where((c) => c.origin != 'default').toList();
    final defaults = _items.where((c) => c.origin == 'default').toList();
    setState(() {
      _items = [...users, ...defaults]; // usuarios primero, luego predeterminados
    });
    if (alsoPersist) {
      ContactsStore.save(_items);
    }
  }

  Future<void> _syncContacts() async {
    setState(() => _syncing = true);
    try {
      final session = await SessionManager.loadSession();
      final userId = session['userId'] ?? '';
      const municipio = 'Huamantla, Tlaxcala';

      // 🔒 Enviar SOLO contactos del usuario que aún no se han subido
      final toUpload = _items.where((c) => c.origin == 'user' && c.synced == false).toList();

      if (toUpload.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No hay contactos nuevos para sincronizar')));
        return;
      }

      final body = jsonEncode({
        'op': 'contacts_batch',
        'userId': userId,
        'municipio': municipio,
        'items': toUpload.map((c) => {
          'name': c.name,
          'phone': c.phone,
          'relationship': c.relationship,
          'origin': c.origin,
        }).toList(),
      });

      final res = await http.post(
        Uri.parse(kAppsScriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      bool ok = false;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (ct.contains('application/json')) {
          try {
            final j = jsonDecode(res.body);
            ok = j is Map && (j['ok'] == true);
          } catch (_) { ok = true; }
        } else { ok = true; }
      } else if (res.statusCode >= 300 && res.statusCode < 400) {
        ok = true; // Apps Script puede redirigir pero ya procesó el POST
      }

      if (!mounted) return;

      if (ok) {
        // Marcar los subidos como sincronizados
        final updated = _items.map((c) {
          if (c.origin == 'user' && c.synced == false) {
            // Si quieres marcar solo los realmente insertados, necesitaríamos que el server
            // regrese las llaves aceptadas; para simplificar, marcamos todos los enviados.
            return c.copyWith(synced: true);
          }
          return c;
        }).toList();
        setState(() => _items = updated);
        await ContactsStore.save(updated);
        _orderUserOverDefaults(alsoPersist: false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contactos sincronizados ✅')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al sincronizar (${res.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de red: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _load() async {
    _items = await ContactsStore.load();
    if (!mounted) return;
    _orderUserOverDefaults(); // <- aplica el orden
    setState(() => _loading = false);
  }

  Future<void> _addContact() async {
    final res = await showDialog<EmergencyContact>(
      context: context,
      builder: (_) => const _ContactDialog(),
    );
    if (res != null) {
      setState(() => _items.add(res));
      await ContactsStore.save(_items);
      _orderUserOverDefaults(alsoPersist: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SafeArea(
      minimum: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Agregar contacto'),
                onPressed: _addContact,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: _syncing ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.cloud_upload),
                label: const Text('Guardar'),
                onPressed: _syncing ? null : _syncContacts,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final c = _items[i]; // captura la referencia, NO dependas del índice luego
                final isDefault = c.origin == 'default';

                if (isDefault) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.contact_phone),
                      title: Text(c.name),
                      subtitle: Text('${c.relationship} · ${c.phone}'),
                      trailing: const Icon(Icons.lock, color: Colors.grey),
                    ),
                  );
                }

                return Dismissible(
                  key: ValueKey('contact_${c.name}_${c.phone}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  // Opcional: pedir confirmación antes de borrar
                  confirmDismiss: (direction) async {
                    // (opcional) pides confirmación
                    return await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Eliminar contacto'),
                        content: Text('¿Eliminar a ${c.name}?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
                        ],
                      ),
                    ) ?? false;
                  },

                  // ¡Aquí debes eliminarlo INMEDIATAMENTE!
                  onDismissed: (_) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final idx = _items.indexOf(c);      // guarda posición para posible rollback

                    // 1) quita de UI de inmediato
                    setState(() => _items.removeAt(idx));
                    await ContactsStore.save(_items);
                    _orderUserOverDefaults(alsoPersist: false);

                    final session = await SessionManager.loadSession();
                    final ok = await deleteContactOnServer(
                      appsScriptUrl: kAppsScriptUrl,
                      userId: (session['userId'] ?? '').toString(),
                      emailLower: (session['email'] ?? '').toString().trim().toLowerCase(),
                      phoneRaw: c.phone,
                    );

                    if (ok) {
                      messenger.showSnackBar(SnackBar(content: Text('Eliminado: ${c.name}')));
                    } else {
                      // 3) rollback si falló en server
                      if (!mounted) return;
                      setState(() => _items.insert(idx, c));
                      await ContactsStore.save(_items);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('No se pudo eliminar en la hoja. Se revirtió.')),
                      );
                    }
                  },
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.contact_phone),
                      title: Text(c.name),
                      subtitle: Text('${c.relationship} · ${c.phone}'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ======= Modelo + Persistencia local ======= */

class EmergencyContact {
  final String name;
  final String phone;
  final String relationship;
  final String origin; // 'default' | 'user'
  final bool synced;

  EmergencyContact({
    required this.name,
    required this.phone,
    required this.relationship,
    this.origin = 'user',
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'phone': phone,
    'relationship': relationship,
    'origin': origin,
    'synced': synced,
  };

  factory EmergencyContact.fromMap(Map<String, dynamic> m) =>
      EmergencyContact(
        name: m['name'],
        phone: m['phone'],
        relationship: m['relationship'],
        origin: (m['origin'] ?? 'user'),
        synced: (m['synced'] ?? false) == true,
      );

  EmergencyContact copyWith({
    String? name,
    String? phone,
    String? relationship,
    String? origin,
    bool? synced,
  }) => EmergencyContact(
    name: name ?? this.name,
    phone: phone ?? this.phone,
    relationship: relationship ?? this.relationship,
    origin: origin ?? this.origin,
    synced: synced ?? this.synced,
  );
}

class ContactsStore {
  static const _kKey = 'emergency_contacts';
  static List<EmergencyContact> defaultsHuamantla() => [
    EmergencyContact(name: '911 Emergencias', phone: '911', relationship: 'Nacional', origin: 'default'),
    EmergencyContact(name: 'Policía Municipal Huamantla', phone: '247 472 00 47', relationship: 'Municipal', origin: 'default'),
    EmergencyContact(name: 'Policía Municipal Huamantla (línea alternativa)', phone: '247 472 20 76', relationship: 'Municipal', origin: 'default'),
    EmergencyContact(name: 'Cruz Roja Huamantla', phone: '247 472 01 04', relationship: 'Cruz Roja', origin: 'default'),
    EmergencyContact(name: 'Bomberos Huamantla', phone: '247 472 32 72', relationship: 'Bomberos', origin: 'default'),
    EmergencyContact(name: 'Protección Civil Tlaxcala', phone: '246 462 17 25', relationship: 'Estatal', origin: 'default'),
  ];

  static Future<List<EmergencyContact>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null || raw.isEmpty){
      // Primera vez: si no hay nada, sembramos predeterminados
      final seed = defaultsHuamantla();
      await save(seed);
      return seed;
    }
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(EmergencyContact.fromMap).toList();
  }

  static Future<void> save(List<EmergencyContact> items) async {
    final sp = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((e) => e.toMap()).toList());
    await sp.setString(_kKey, raw);
  }
}

/// Bloqueo de 15 minutos: persistimos la última activación por usuario.
class EmergencyUsageStore {
  static const _kPrefix = 'last_emergency_activation_';

  static Future<DateTime?> obtenerUltimaActivacion(String userKey) async {
    if (userKey.isEmpty) return null;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('$_kPrefix$userKey');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> guardarActivacion(String userKey, DateTime fecha) async {
    if (userKey.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('$_kPrefix$userKey', fecha.toIso8601String());
  }
}

/* ======= Diálogo para capturar contacto ======= */

class _ContactDialog extends StatefulWidget {
  const _ContactDialog();
  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _rel = 'Familiar';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo contacto'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              validator: (v) => (v == null || v.trim().length < 7) ? 'No válido' : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _rel,
              decoration: const InputDecoration(labelText: 'Relación'),
              items: const [
                DropdownMenuItem(value: 'Familiar', child: Text('Familiar')),
                DropdownMenuItem(value: 'Amigo', child: Text('Amigo')),
                DropdownMenuItem(value: 'Docente', child: Text('Docente')),
                DropdownMenuItem(value: 'Vecino', child: Text('Vecino')),
                DropdownMenuItem(value: 'Otro', child: Text('Otro')),
              ],
              onChanged: (v) => setState(() => _rel = v ?? _rel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(
                context,
                EmergencyContact(name: _name.text.trim(), phone: _phone.text.trim(), relationship: _rel),
              );
            }
          },
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}