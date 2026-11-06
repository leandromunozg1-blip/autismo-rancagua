import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'tesoreria.dart';
import 'permisos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'public_home.dart';
import 'pages/eventos/eventos_apoderado_page.dart';
import 'pages/inicio_page.dart';
import 'pages/role_router_page.dart';
import 'app_roles.dart';
import 'pages/configuracion_credencial_page.dart';
import 'pages/admin/admin_home_page.dart';
import 'pages/tesoreria/tesorero_home_page.dart';
import 'pages/materiales/materiales_apoderado_page.dart';
import 'pages/apoderados/profesionales_asignados_apoderado_page.dart';
import 'pages/ayudante_autismo_page.dart';
import 'services/tesoreria_finanzas_service.dart';
import 'services/tesoreria_v58_service.dart';
import 'services/tesoreria_v58_gateway.dart';
import 'pages/tesoreria/comprobante_pago_v58_page.dart';
import 'pages/tesoreria/revision_comprobantes_v58_page.dart';
import 'pages/tesoreria/comprobante_widgets_v58.dart';

bool esUsuarioAdmin() {
  final correo = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ?? '';
  return correo.isNotEmpty && adminGeneralEmails.contains(correo);
}

/// El panel de padres queda separado de los módulos administrativos.
/// Los roles de tesorería, aseo, reciclaje, eventos, coordinación y profesionales
/// entran por RoleRouterPage después del login.
bool esUsuarioTesorero() {
  return false;
}

Future<void> main() => iniciarAplicacion();

Future<void> iniciarAplicacion({bool firebaseYaInicializado = false, bool modoPruebas = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CL', null);
  await initializeDateFormatting('es', null);
  Intl.defaultLocale = 'es_CL';
  try {
    if (!firebaseYaInicializado) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    await FirebaseAuth.instance.authStateChanges().first;
  } catch (e) {
    debugPrint("Error Firebase: $e");
  }
  runApp(AutismoRancaguaApp(modoPruebas: modoPruebas));
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}


String _arLimpiar(dynamic v) => (v ?? '').toString().trim();

String _arRutNormalizado(dynamic value) {
  final limpio = (value ?? '').toString().toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
  if (limpio.length < 2) return '';
  return '${limpio.substring(0, limpio.length - 1)}-${limpio.substring(limpio.length - 1)}';
}

bool _arPareceRut(String value) => RegExp(r'^\d{7,8}-[0-9K]$').hasMatch(_arRutNormalizado(value));

/// Avisos manuales de Tesorería contrastados contra el saldo vencido real.
/// Los avisos automáticos/resultados se reciben en avisos_apoderados.
Future<List<Map<String, dynamic>>> _avisosVigentesTesoreria(String uid) async {
  if (uid.isEmpty) return [];
  final cuentas = await TesoreriaV58Service.cuentas();
  final avisos = <Map<String, dynamic>>[];
  for (final cuenta in cuentas) {
    final id = (cuenta['id'] ?? '').toString();
    final respuesta = await TesoreriaV58Service.consultar(id);
    final ficha = TesoreriaV58Service.mapa(respuesta['cuenta']);
    final resumen = TesoreriaFinanzasService.desdeRespuesta(respuesta);
    if (ficha['aviso_activo'] != true || resumen.saldoVencido <= 0 || resumen.advertencias.isNotEmpty) continue;
    avisos.add({...ficha, 'id': id, 'monto_deuda': resumen.saldoVencido});
  }
  return avisos;
}

bool _arListaContiene(dynamic value, String uid) {
  if (uid.isEmpty || value is! List) return false;
  return value.map((e) => e.toString().trim()).contains(uid);
}

bool _arApoyoAutorizado(dynamic value, String uid) {
  if (uid.isEmpty || value is! List) return false;
  for (final item in value) {
    if (item is Map) {
      final apoyoUid = _arLimpiar(item['uid'] ?? item['apoyo_uid']);
      if (apoyoUid == uid) return true;
    }
  }
  return false;
}

/// Devuelve todos los identificadores de beneficiarios que puede ver el usuario actual.
/// No reemplaza la lógica anterior: la amplía para apoyos autorizados.
Future<Set<String>> _beneficiariosVisiblesParaUid(String uid) async {
  final ids = <String>{};
  if (uid.isEmpty) return ids;
  ids.add(uid);
  final emailActual = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ?? '';
  if (emailActual.isNotEmpty) ids.add(emailActual);

  final snap = await FirebaseFirestore.instance.collection('ar_beneficiarios').get();
  for (final doc in snap.docs) {
    final data = doc.data();
    final apoderadoUid = _arLimpiar(data['apoderado_uid'] ?? data['uid_apoderado']);
    final visible = apoderadoUid == uid ||
        _arListaContiene(data['apoderados_uids_autorizados'], uid) ||
        _arApoyoAutorizado(data['apoyos_autorizados'], uid);

    if (!visible) continue;

    ids.add(doc.id);
    for (final key in [
      'beneficiario_id',
      'rut',
      'rut_beneficiario',
      'rut_usuario',
      'nombre',
      'nombre_beneficiario',
      'beneficiario_nombre',
      'apoderado_uid',
      'uid_apoderado',
      'email_apoderado',
      'correo_apoderado',
      'email',
      'correo',
    ]) {
      final v = _arLimpiar(data[key]);
      if (v.isNotEmpty) ids.add(v);
    }
  }

  return ids;
}

bool _docVisibleParaApoderadoOApoyo(Map<String, dynamic> data, String uid, Set<String> idsBeneficiarios) {
  if (uid.isEmpty) return false;

  final apoderadoUid = _arLimpiar(data['apoderado_uid'] ?? data['uid_apoderado']);
  if (apoderadoUid == uid) return true;
  // Compatibilidad para apoyos autorizados: si el documento fue creado antes
  // de agregar el UID del apoyo, se valida también contra el UID del apoderado principal
  // resuelto desde el beneficiario. Así no se pierden reportes antiguos ni recientes.
  if (apoderadoUid.isNotEmpty && idsBeneficiarios.contains(apoderadoUid)) return true;
  if (_arListaContiene(data['apoderados_uids_autorizados'], uid)) return true;
  if (_arApoyoAutorizado(data['apoyos_autorizados'], uid)) return true;

  for (final key in [
    'beneficiario_id',
    'rut_beneficiario',
    'rut_usuario',
    'beneficiario_rut',
    'rut',
    'beneficiario_nombre',
    'nombre_beneficiario',
    'nombre',
    'apoderado_uid',
    'uid_apoderado',
    'email_apoderado',
    'correo_apoderado',
  ]) {
    final v = _arLimpiar(data[key]);
    if (v.isNotEmpty && idsBeneficiarios.contains(v)) return true;
  }

  return false;
}



class _RoleBasedSelection extends StatelessWidget {
  final Widget child;
  const _RoleBasedSelection({required this.child});

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) return child;

    return FutureBuilder<String>(
      future: obtenerRolActual(),
      builder: (context, snapshot) {
        final rol = snapshot.data;
        final puedeCopiar = rol == AppRoles.profesional ||
            (rol != null && esAdminGlobalPorRol(rol));
        return puedeCopiar ? SelectionArea(child: child) : child;
      },
    );
  }
}

class AutismoRancaguaApp extends StatelessWidget {
  final bool modoPruebas;
  const AutismoRancaguaApp({super.key, this.modoPruebas = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // V57: la selección/copia de textos queda habilitada únicamente
      // para profesionales y administradores. Los apoderados y demás roles
      // reciben la interfaz normal, sin SelectionArea global.
      builder: (context, child) => Column(children: [
        if (modoPruebas) const Material(color: Color(0xFFFFE082), child: SafeArea(bottom: false, child: Padding(padding: EdgeInsets.all(8), child: Text('V58 DE PRUEBAS · SOLO EMULADORES · COBROS AUTOMÁTICOS DESACTIVADOS', textAlign: TextAlign.center)))),
        Expanded(child: _RoleBasedSelection(child: child ?? const SizedBox.shrink())),
      ]),
      debugShowCheckedModeBanner: false,
      title: 'Autismo Rancagua',
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F9FD),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B69B7),
          primary: const Color(0xFF0B69B7),
          secondary: const Color(0xFF12A89D),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B69B7),
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
          titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: const Color(0xFF0B4778).withOpacity(.12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFD7E7F2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF0B69B7), width: 2)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0B69B7),
            foregroundColor: Colors.white,
            elevation: 2,
            minimumSize: const Size(0, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
      home: const PublicHomePage(),

      routes: {
        '/panel': (context) => const RoleRouterPage(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}

// LOGIN
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _cargando = false;
  bool _ocultarClave = true;
  bool _recordar = true;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _cargarAccesoGuardado();
  }

  Future<void> _cargarAccesoGuardado() async {
    try {
      final correo = await _storage.read(key: 'login_correo');
      final clave = await _storage.read(key: 'login_clave');
      if (!mounted) return;
      setState(() {
        if (correo != null) _email.text = correo;
        if (clave != null) _pass.text = clave;
        _recordar = correo != null && clave != null;
      });
    } catch (_) {}
  }

  Future<void> _guardarAcceso(String correo, String clave) async {
    try {
      if (_recordar) {
        await _storage.write(key: 'login_correo', value: correo);
        await _storage.write(key: 'login_clave', value: clave);
      } else {
        await _storage.delete(key: 'login_correo');
        await _storage.delete(key: 'login_clave');
      }
    } catch (_) {}
  }

  void _entrar() async {
    final email = _email.text.trim().toLowerCase();
    final password = _pass.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ingrese correo y contraseña"),
        ),
      );
      return;
    }

    setState(() => _cargando = true);

    bool loginCorrecto = false;

    try {
      await FirebaseAuth.instance.signOut();

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      loginCorrecto = true;
    } catch (e) {
      // En algunas compilaciones Firebase inicia sesión correctamente,
      // pero lanza error interno tipo PigeonUserDetails al devolver el UserCredential.
      // Por eso verificamos si igual quedó un usuario autenticado.
      await Future.delayed(const Duration(milliseconds: 600));

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        loginCorrecto = true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error de acceso: $e"),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }

    if (loginCorrecto && mounted) {
      await _guardarAcceso(email, password);
      final correoActual =
          FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? email;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const RoleRouterPage(),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final web = ancho >= 800;

    Widget formulario = Container(
      constraints: const BoxConstraints(maxWidth: 470),
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 28),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.97),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: const Color(0xff07538d).withOpacity(.14), blurRadius: 28, offset: const Offset(0, 10))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Bienvenido/a ♡', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff0876bd), fontSize: 31, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        const Text('Ingresa a tu cuenta para acceder\na la comunidad de Autismo Rancagua.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff66727d), fontSize: 15, height: 1.35)),
        const SizedBox(height: 22),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(hintText: 'Correo Electrónico', prefixIcon: Icon(Icons.mail_outline_rounded, color: Color(0xff147fd0)))),
        const SizedBox(height: 14),
        TextField(controller: _pass, obscureText: _ocultarClave, onSubmitted: (_) => _cargando ? null : _entrar(), decoration: InputDecoration(hintText: 'Contraseña', prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xff147fd0)), suffixIcon: IconButton(onPressed: () => setState(() => _ocultarClave = !_ocultarClave), icon: Icon(_ocultarClave ? Icons.visibility_off_rounded : Icons.visibility_rounded)))),
        const SizedBox(height: 8),
        CheckboxListTile(value: _recordar, onChanged: (v) => setState(() => _recordar = v ?? false), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, dense: true, title: const Text('Recordar usuario y contraseña', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xff526775)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: _cargando ? const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Center(child: CircularProgressIndicator())) : ElevatedButton.icon(onPressed: _entrar, icon: const Icon(Icons.arrow_forward_rounded), label: const Text('INGRESAR'))),
      ]),
    );

    return Scaffold(
      backgroundColor: const Color(0xffeef9ff),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xffe8f8ff), Color(0xfffffbf3), Color(0xffe9f7ff)])),
        child: SafeArea(
          child: Stack(children: [
            if (web)
              Positioned.fill(child: Opacity(opacity: .11, child: Image.asset('assets/images/fondo_comunidad.png', fit: BoxFit.cover))),
            Positioned(left: 12, top: 12, child: Material(color: Colors.white.withOpacity(.92), borderRadius: BorderRadius.circular(16), child: InkWell(onTap: () => Navigator.maybePop(context), borderRadius: BorderRadius.circular(16), child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.arrow_back_rounded, color: Color(0xff07538d)))))),
            if (web)
              Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080), child: Padding(padding: const EdgeInsets.all(32), child: Row(children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(34), child: Image.asset('assets/images/acceso_casa_autismo.png', height: 540, fit: BoxFit.contain))),
                const SizedBox(width: 34),
                Expanded(child: formulario),
              ]))))
            else
              SingleChildScrollView(child: Column(children: [
                ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)), child: AspectRatio(aspectRatio: 709 / 875, child: Image.asset('assets/images/acceso_casa_autismo.png', width: double.infinity, fit: BoxFit.cover, alignment: Alignment.topCenter))),
                Transform.translate(offset: const Offset(0, -24), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: formulario)),
              ])),
          ]),
        ),
      ),
    );
  }

}

// HOME
class HomePage extends StatelessWidget {
  static bool avisoTesoreriaMostrado = false;

  const HomePage({super.key});

  void _mostrarCredencial(BuildContext context, String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();

    if (doc.exists && doc.data()!['credencial_digital'] != null) {
      String credBase64 = doc.data()!['credencial_digital'];

      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Cerrar",
        pageBuilder: (ctx, anim1, anim2) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    child: Image.memory(
                      base64Decode(credBase64),
                      width: MediaQuery.of(context).size.width,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  top: 50,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 40,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay credencial cargada en el perfil.")),
      );
    }
  }

  void _revisarAvisoTesoreria(BuildContext context, String uid) {
    if (HomePage.avisoTesoreriaMostrado) return;
    HomePage.avisoTesoreriaMostrado = true;

    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
    }

    String money(int v) {
      final s = v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
      return '\$$s';
    }

    Future.microtask(() async {
      try {
        final deudas = await _avisosVigentesTesoreria(uid);

        if (deudas.isEmpty) return;

        final total = deudas.fold<int>(0, (sum, data) => sum + toInt(data['monto_deuda']));
        final detalles = deudas.map((data) {
          final mensaje = (data['mensaje_aviso'] ?? '').toString().trim();
          final concepto = mensaje.isNotEmpty
              ? mensaje
              : (data['concepto'] ?? data['tipo_cobro'] ?? data['servicio'] ?? 'Cobro pendiente').toString();
          return '• $concepto: ${money(toInt(data['monto_deuda']))}';
        }).join('\n');
        final mensaje = 'Mantienes una deuda total de ${money(total)}.\n\nDetalle:\n$detalles';
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: const Text('Deuda Tesorería'),
              content: Text(mensaje),
              actions: [
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar')),
              ],
            ),
          );
        }
      } catch (e) {
        debugPrint('Error al revisar aviso de Tesorería por RUT: $e');
        HomePage.avisoTesoreriaMostrado = false;
      }
    });
  }

  Future<Map<String, String>> _contadoresApoderado() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    int tareas = 0;
    int avisos = 0;
    try {
      final idsBeneficiarios = await _beneficiariosVisiblesParaUid(uid);
      final tareasSnap = await FirebaseFirestore.instance
          .collection('ar_bitacora_casa')
          .get();
      for (final d in tareasSnap.docs) {
        final data = d.data();
        if (!_docVisibleParaApoderadoOApoyo(data, uid, idsBeneficiarios)) continue;
        if (data['tipo_doc'] != 'plan_trabajo_casa') continue;
        if (data['activa'] != true) continue;
        final estado = (data['estado'] ?? 'activo').toString().toLowerCase();
        final fechaFin = data['fecha_fin'];
        final vigente = fechaFin is Timestamp ? fechaFin.toDate().isAfter(DateTime.now()) : true;
        if (estado == 'activo' && vigente) tareas++;
      }
    } catch (_) {}
    try {
      final avisosSnap = await FirebaseFirestore.instance
          .collection('avisos_apoderados')
          .where('apoderado_id', isEqualTo: uid)
          .get();
      for (final d in avisosSnap.docs) {
        final data = d.data();
        if (data['leido'] != true && data['aceptado'] != true) avisos++;
      }
    } catch (_) {}
    try {
      final tesAvisos = await _avisosVigentesTesoreria(uid);
      avisos += tesAvisos.where((d) => d['aviso_visto_por_apoderado'] != true).length;
    } catch (_) {}
    return {'tareas': tareas.toString(), 'avisos': avisos.toString()};
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _revisarAvisoTesoreria(context, uid);

    return FutureBuilder<Map<String, String>>(
      future: _contadoresApoderado(),
      builder: (context, contadorSnap) {
        final contadores = contadorSnap.data ?? const {'tareas': '0', 'avisos': '0'};
        return InicioPage(
      tareasPendientes: contadores['tareas'] ?? '0',
      avisosPendientes: contadores['avisos'] ?? '0',
      onInicio: () => Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const PublicHomePage()),
        (route) => false,
      ),
      onAgenda: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AgendaPage()),
      ),
      onCredencial: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ConfiguracionCredencialPage()),
      ),
      onTareas: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GestionPage()),
      ),
      onComprobante: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ComprobantePagoPage()),
      ),
      onDocumentos: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DocumentosPage()),
      ),
      onReciclaje: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReciclajePage()),
      ),
      onEventos: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EventosApoderadoPage()),
      ),
      onAvisos: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AvisosApoderadoPage()),
      ),
      onSettings: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ConfiguracionCredencialPage(),
        ),
      ),
      mostrarMateriales: false,
      onMateriales: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MaterialesApoderadoPage(),
        ),
      ),
      mostrarPanelTesoreria: false,
      onTesoreria: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const TesoreroHomePage(),
        ),
      ),
      onLogout: () async {
        await FirebaseAuth.instance.signOut();
        if (context.mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const PublicHomePage()),
            (route) => false,
          );
        }
      },
    );
      },
    );
  }
}
// MENÚ GESTIÓN FAMILIAR APODERADO
class _ApoyoImageBanner extends StatelessWidget {
  final String asset;
  final double height;
  const _ApoyoImageBanner(this.asset, {this.height = 145});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    child: Container(
      height: height, clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: const Color(0xFF0B4778).withOpacity(.12), blurRadius: 18, offset: const Offset(0, 8))]),
      child: Image.asset(asset, width: double.infinity, fit: BoxFit.cover),
    ),
  );
}

class GestionPage extends StatelessWidget {
  const GestionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <({String title, String subtitle, IconData icon, Color color, Widget page})>[
      (title: 'Trabajo en casa', subtitle: 'Plan semanal y actividades sugeridas', icon: Icons.task_alt_rounded, color: const Color(0xFF2587D8), page: const TareasProfesionalesPage()),
      (title: 'Profesionales asignados', subtitle: 'Conoce al equipo que acompaña el proceso', icon: Icons.groups_2_rounded, color: const Color(0xFF6657C8), page: const ProfesionalesAsignadosApoderadoPage()),
      (title: 'Reporte terapia del día', subtitle: 'Revisa el registro de la jornada', icon: Icons.fact_check_rounded, color: const Color(0xFF10A294), page: const ReporteTerapiaDiaPage()),
      (title: 'Mi ayudante', subtitle: 'Pregunta, organiza y prepara el trabajo en casa', icon: Icons.auto_awesome_rounded, color: const Color(0xFFF2A11F), page: const AyudanteAutismoPage(contexto: AyudanteContexto.apoderado)),
      (title: 'Historial de avances', subtitle: 'Consulta avances y registros familiares', icon: Icons.insights_rounded, color: const Color(0xFF54788C), page: const HistorialFamiliarPage()),
    ];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEAF7FF), Color(0xFFF8FBFF), Color(0xFFFFFAF1)])),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0B5795))),
                const Expanded(child: Text('Apoyo terapéutico', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF083F72)))),
                Image.asset('assets/images/inicio.jpg', width: 48, height: 48, fit: BoxFit.contain),
              ]),
            ),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 30), children: [
              Container(
                height: 175, clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: const Color(0xFF0B69B7).withOpacity(.18), blurRadius: 20, offset: const Offset(0, 10))]),
                child: Image.asset('assets/images/apoyo_01_portada.png', fit: BoxFit.cover, width: double.infinity),
              ),
              const SizedBox(height: 18),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(color: Colors.white, borderRadius: BorderRadius.circular(22), elevation: 1.5, shadowColor: const Color(0xFF0B4778).withOpacity(.12), child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.page)),
                  child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                    Container(width: 54, height: 54, decoration: BoxDecoration(color: item.color.withOpacity(.12), borderRadius: BorderRadius.circular(17)), child: Icon(item.icon, color: item.color, size: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF083F72))), const SizedBox(height: 3), Text(item.subtitle, style: const TextStyle(color: Color(0xFF60798E), fontSize: 13))])),
                    Icon(Icons.chevron_right_rounded, color: item.color),
                  ])),
                )),
              )),
            ])),
          ]),
        ),
      ),
    );
  }
}

class ProximamentePage extends StatelessWidget {
  const ProximamentePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAF2),
      appBar: AppBar(
        title: const Text('Próximamente', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF8B5A00))),
        backgroundColor: const Color(0xFFFFFAF2), foregroundColor: const Color(0xFFE99500), elevation: 0, surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 28),
        children: [
          const _ApoyoImageBanner('assets/images/apoyo_06_herramientas.png', height: 205),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: const Color(0xFFE99500).withOpacity(.08), blurRadius: 18, offset: const Offset(0, 8))]),
            child: const Text('Este espacio crecerá junto al acompañamiento terapéutico. Aquí incorporaremos nuevas herramientas cuando estén listas para usarse.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF7D725F), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}


class TareasProfesionalesPage extends StatefulWidget {
  const TareasProfesionalesPage({super.key});

  @override
  State<TareasProfesionalesPage> createState() => _TareasProfesionalesPageState();
}

class _TareasProfesionalesPageState extends State<TareasProfesionalesPage> {
  bool guardando = false;
  late Future<Set<String>> _idsBeneficiariosFuture;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _idsBeneficiariosFuture = _beneficiariosVisiblesParaUid(uid);
  }

  String _fecha(dynamic fecha) {
    if (fecha is! Timestamp) return '';
    return DateFormat('dd-MM-yyyy').format(fecha.toDate());
  }

  List<String> _ideasAyudante(Map<String, dynamic> data) {
    final objetivo = (data['objetivo'] ?? '').toString().trim();
    final indicaciones = (data['indicaciones'] ?? '').toString().trim();
    final base = objetivo.isNotEmpty ? objetivo : indicaciones;
    return [
      'Comienza con una actividad corta y simple relacionada con ${base.isEmpty ? 'la indicación del profesional' : base.toLowerCase()}.',
      'Da una instrucción a la vez, espera la respuesta y refuerza cada pequeño avance.',
      'Si aparece frustración, haz una pausa breve y retoma con una versión más sencilla de la actividad.',
    ];
  }

  Future<void> _verAyuda(DocumentSnapshot plan) async {
    final data = plan.data() as Map<String, dynamic>;
    final ideas = _ideasAyudante(data);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 78, height: 78, fit: BoxFit.contain),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('¿Trabajamos juntos?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF0B69B7))),
              SizedBox(height: 3),
              Text('Te ayudo a llevar a casa las indicaciones del profesional.', style: TextStyle(color: Colors.black54)),
            ])),
          ]),
          const SizedBox(height: 14),
          ...ideas.map((idea) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lightbulb_rounded, color: Color(0xFFFFB300), size: 22), const SizedBox(width: 9), Expanded(child: Text(idea, style: const TextStyle(fontSize: 15.5, height: 1.35))),
          ]))),
          const SizedBox(height: 4),
          const Text('Estas ideas complementan las indicaciones del profesional y no las reemplazan.', style: TextStyle(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w600)),
        ]),
      )),
    );
  }

  Future<void> _verEnvios(DocumentSnapshot plan) async {
    final snap = await FirebaseFirestore.instance.collection('ar_bitacora_casa').where('trabajo_id', isEqualTo: plan.id).get();
    final docs = snap.docs.toList()..sort((a,b) {
      final fa=a.data()['fecha']; final fb=b.data()['fecha'];
      if (fa is Timestamp && fb is Timestamp) return fb.compareTo(fa); return 0;
    });
    if (!mounted) return;
    await showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), builder: (_) => DraggableScrollableSheet(expand:false, initialChildSize:.72, maxChildSize:.92, builder:(context,scroll)=>Padding(
      padding: const EdgeInsets.fromLTRB(18,18,18,10),
      child: Column(children:[
        const Row(children:[Icon(Icons.history_rounded,color:Color(0xFFE99500)),SizedBox(width:8),Text('Enviado al profesional',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))]),
        const SizedBox(height:12),
        Expanded(child: docs.isEmpty ? const Center(child:Text('Aún no hay registros enviados.')) : ListView.builder(controller:scroll,itemCount:docs.length,itemBuilder:(_,i){
          final m=docs[i].data(); final f=m['fecha']; final fecha=f is Timestamp?DateFormat('dd-MM-yyyy HH:mm').format(f.toDate()):'Sin fecha';
          final preguntas=(m['respuestas_guiadas'] is Map)?Map<String,dynamic>.from(m['respuestas_guiadas']):<String,dynamic>{};
          return Card(margin:const EdgeInsets.only(bottom:10),child:ExpansionTile(title:Text(fecha,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${m['tiempo_minutos'] ?? 0} min · ${m['estado_emocional'] ?? ''}'),children:[Padding(padding:const EdgeInsets.fromLTRB(16,0,16,16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            if ((m['observacion']??'').toString().isNotEmpty) Text('Resumen: ${m['observacion']}'),
            ...preguntas.entries.where((e)=>e.value.toString().trim().isNotEmpty).map((e)=>Padding(padding:const EdgeInsets.only(top:7),child:Text('${e.key}: ${e.value}'))),
            if (m['evidencias'] is List && (m['evidencias'] as List).isNotEmpty) Padding(padding:const EdgeInsets.only(top:8),child:Text('Adjuntos: ${(m['evidencias'] as List).length}',style:const TextStyle(fontWeight:FontWeight.w700))),
          ]))]));
        })),
      ]),
    )));
  }

  Future<void> _registrarBitacora(DocumentSnapshot plan) async {
    final obsCtrl = TextEditingController();
    final actividadCtrl = TextEditingController();
    final ayudaCtrl = TextEditingController();
    final funcionoCtrl = TextEditingController();
    final dificultadCtrl = TextEditingController();
    String estado = 'Participó bien';
    int minutos = 30;
    bool realizado = true;
    final List<XFile> evidencias = [];
    final List<String> evidenciaTipos = [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Bitácora familiar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: realizado,
                  onChanged: (v) => setDialog(() => realizado = v),
                  title: const Text('¿Se trabajó hoy?'),
                ),
                DropdownButtonFormField<int>(
                  value: minutos,
                  decoration: const InputDecoration(labelText: 'Tiempo trabajado'),
                  items: const [15, 30, 45, 60, 90]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m minutos')))
                      .toList(),
                  onChanged: (v) => setDialog(() => minutos = v ?? 30),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: estado,
                  decoration: const InputDecoration(labelText: 'Respuesta del beneficiario'),
                  items: const [
                    'Participó bien',
                    'Le costó al inicio',
                    'Se frustró',
                    'No quiso participar',
                    'Se adaptó mejor que antes',
                    'Otro',
                  ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialog(() => estado = v ?? 'Participó bien'),
                ),
                const SizedBox(height: 10),
                const SizedBox(height: 14),
                Row(children: [
                  Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 52, height: 52, fit: BoxFit.contain),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Cuéntame cómo les fue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0B69B7)))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: actividadCtrl, decoration: const InputDecoration(labelText: '¿Qué actividad realizaron?')),
                const SizedBox(height: 8),
                TextField(controller: ayudaCtrl, decoration: const InputDecoration(labelText: '¿Necesitó ayuda para comenzar?')),
                const SizedBox(height: 8),
                TextField(controller: funcionoCtrl, decoration: const InputDecoration(labelText: '¿Qué fue lo que mejor resultó?')),
                const SizedBox(height: 8),
                TextField(controller: dificultadCtrl, decoration: const InputDecoration(labelText: '¿Hubo alguna dificultad o frustración?')),
                const SizedBox(height: 8),
                TextField(
                  controller: obsCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '¿Quieres contarle algo más al profesional?'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: evidenciaTipos.where((t) => t == 'foto').length >= 5 ? null : () async {
                        final picker = ImagePicker();
                        final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 65);
                        if (img != null) setDialog(() { evidencias.add(img); evidenciaTipos.add('foto'); });
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text("Adjuntar foto (${evidenciaTipos.where((t) => t == 'foto').length}/5)"),
                    ),
                    OutlinedButton.icon(
                      onPressed: evidenciaTipos.where((t) => t == 'video').length >= 1 ? null : () async {
                        final picker = ImagePicker();
                        final vid = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
                        if (vid != null) setDialog(() { evidencias.add(vid); evidenciaTipos.add('video'); });
                      },
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text("Adjuntar video (${evidenciaTipos.where((t) => t == 'video').length}/1)"),
                    ),
                  ],
                ),
                if (evidencias.isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(evidencias.length, (i) => Text(
                      '${i + 1}. ${evidenciaTipos[i] == 'video' ? 'Video' : 'Foto'}: ${evidencias[i].name}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => guardando = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final data = plan.data() as Map<String, dynamic>;
      final evidenciasSubidas = <Map<String, dynamic>>[];
      for (var i = 0; i < evidencias.length; i++) {
        final archivo = evidencias[i];
        final tipo = evidenciaTipos[i];
        final esVideo = tipo == 'video';
        final extension = esVideo ? 'mp4' : 'jpg';
        final contentType = esVideo ? 'video/mp4' : 'image/jpeg';
        final path = 'bitacora_casa/${user.uid}-${plan.id}-${DateTime.now().millisecondsSinceEpoch}-$i.$extension';
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putData(await archivo.readAsBytes(), SettableMetadata(contentType: contentType));
        final url = await ref.getDownloadURL();
        evidenciasSubidas.add({
          'url': url,
          'path': path,
          'tipo': tipo,
          'content_type': contentType,
          'nombre': archivo.name,
        });
      }
      final primeraEvidencia = evidenciasSubidas.isNotEmpty ? evidenciasSubidas.first : <String, dynamic>{};

      final bitacoraRef = await FirebaseFirestore.instance.collection('ar_bitacora_casa').add({
        'trabajo_id': plan.id,
        'realizado': realizado,
        'tiempo_minutos': realizado ? minutos : 0,
        'estado_emocional': estado,
        'observacion': obsCtrl.text.trim(),
        'respuestas_guiadas': {
          'Actividad realizada': actividadCtrl.text.trim(),
          'Ayuda para comenzar': ayudaCtrl.text.trim(),
          'Lo que mejor resultó': funcionoCtrl.text.trim(),
          'Dificultad o frustración': dificultadCtrl.text.trim(),
          'Comentario adicional': obsCtrl.text.trim(),
        },
        'fecha': FieldValue.serverTimestamp(),
        'email_apoderado': user.email?.toLowerCase().trim() ?? '',
        'email_apoderado_normalizado': user.email?.toLowerCase().trim() ?? '',
        'apoderado_uid': user.uid,
        'apoderados_uids_autorizados': (data['apoderados_uids_autorizados'] is List) ? data['apoderados_uids_autorizados'] : [user.uid],
        'profesional_uid': data['profesional_uid'] ?? '',
        'profesional_email': data['profesional_email'] ?? '',
        'beneficiario_id': data['beneficiario_id'] ?? '',
        'beneficiario_nombre': data['beneficiario_nombre'] ?? '',
        'objetivo': data['objetivo'] ?? '',
        'evidencias': evidenciasSubidas,
        'evidencia_url': primeraEvidencia['url'] ?? '',
        'evidencia_path': primeraEvidencia['path'] ?? '',
        'evidencia_tipo': primeraEvidencia['tipo'] ?? '',
        'evidencia_content_type': primeraEvidencia['content_type'] ?? '',
        'vence_el': Timestamp.fromDate(DateTime.now().add(const Duration(days: 8))),
      });

      final profesionalUid = (data['profesional_uid'] ?? '').toString().trim();
      if (profesionalUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notificaciones_profesionales').add({
          'profesional_uid': profesionalUid,
          'tipo': 'apoderado_trabajo_casa',
          'titulo': 'Trabajo en casa registrado',
          'mensaje': 'El apoderado envió un nuevo registro de trabajo en casa.',
          'beneficiario_id': data['beneficiario_id'] ?? '',
          'beneficiario_nombre': data['beneficiario_nombre'] ?? '',
          'apoderado_uid': user.uid,
          'bitacora_id': bitacoraRef.id,
          'trabajo_id': plan.id,
          'resuelta': false,
          'fecha': FieldValue.serverTimestamp(),
        });
      }

      await plan.reference.update({
        'ultima_bitacora': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitácora guardada correctamente.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar bitácora: $e')));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;
    final email = user.email?.toLowerCase().trim() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      appBar: AppBar(
        title: const Text('Trabajo en casa', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF083F72))),
        backgroundColor: const Color(0xFFF4FAFF),
        foregroundColor: const Color(0xFF0B5795),
        elevation: 0, surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Align(alignment: Alignment.topCenter, child: _ApoyoImageBanner('assets/images/apoyo_02_trabajo_casa.png', height: 145)),
          Padding(
            padding: const EdgeInsets.only(top: 167),
            child: FutureBuilder<Set<String>>(
            future: _idsBeneficiariosFuture,
            builder: (context, idsSnap) {
              if (idsSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final idsBeneficiarios = idsSnap.data ?? <String>{};
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('ar_bitacora_casa')
                    .snapshots(),
                builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo cargar el trabajo en casa. Revisa permisos de Firestore.\n\n${snap.error}', textAlign: TextAlign.center),
                  ),
                );
              }

                  final docs = (snap.data?.docs ?? []).where((d) {
                    final m = d.data() as Map<String, dynamic>;
                    if (!_docVisibleParaApoderadoOApoyo(m, uid, idsBeneficiarios)) return false;
                    if (m['tipo_doc'] != 'plan_trabajo_casa') return false;
                    // Periodo de pruebas: no se ocultan planes por fecha_fin ni por estado activo,
                    // para que todo lo ya enviado en Firebase siga visible después de cada actualización.
                    return true;
              }).toList();
              docs.sort((a, b) {
                final da = (a.data() as Map<String, dynamic>)['fecha_creacion'];
                final db = (b.data() as Map<String, dynamic>)['fecha_creacion'];
                if (da is Timestamp && db is Timestamp) return db.compareTo(da);
                return 0;
              });

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aún no tienes planes de trabajo en casa asignados por profesionales.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
                  ),
                );
              }

              final grupos = _agruparPorProfesional(docs);
              final profesionales = grupos.keys.toList()..sort();
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: profesionales.length,
                itemBuilder: (_, i) {
                  final profesional = profesionales[i];
                  final items = grupos[profesional] ?? <QueryDocumentSnapshot>[];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: ExpansionTile(
                      initiallyExpanded: profesionales.length == 1,
                      title: _encabezadoProfesional(profesional, items.length, Colors.blueAccent),
                      children: [
                        _calendarioFisicoPorDia(
                          items: items,
                          color: Colors.blueAccent,
                          abrirDetalleAlTocar: true,
                          itemBuilder: (doc, data) {
                            final objetivo = (data['objetivo'] ?? 'Plan semanal').toString();
                            final indicaciones = (data['indicaciones'] ?? '').toString();
                            final beneficiario = _nombreBeneficiarioDoc(data);
                            final terapia = (data['terapia'] ?? '').toString();
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.blueAccent.withOpacity(0.20)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    _distintivo('TAREA PROFESIONAL', Colors.blueAccent, Icons.home_work),
                                    _distintivo('DISPONIBLE: ${_fecha(data['fecha_inicio'])} al ${_fecha(data['fecha_fin'])}', Colors.blueGrey, Icons.event),
                                  ]),
                                  const SizedBox(height: 10),
                                  Text(objetivo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 8),
                                  Text('Beneficiario: $beneficiario', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  if (terapia.isNotEmpty) Text('Terapia: $terapia'),
                                  const SizedBox(height: 10),
                                  const Text('Indicaciones del profesional', style: TextStyle(fontWeight: FontWeight.w900)),
                                  Text(indicaciones),
                                  if ((data['material_url'] ?? '').toString().isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () => _abrirArchivoEvidencia(context, (data['material_url'] ?? '').toString(), (data['material_tipo'] ?? '').toString()),
                                      icon: Icon((data['material_tipo'] ?? '').toString() == 'video' ? Icons.play_circle_outline : Icons.photo_library_outlined),
                                      label: Text((data['material_tipo'] ?? '').toString() == 'video' ? 'Ver video del profesional' : 'Ver foto del profesional'),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: const Color(0xFFEFF8FF), borderRadius: BorderRadius.circular(16)),
                                    child: Row(children: [
                                      Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 58, height: 58, fit: BoxFit.contain),
                                      const SizedBox(width: 9),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        const Text('¿Trabajamos juntos?', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0B69B7), fontSize: 16)),
                                        const SizedBox(height: 3),
                                        const Text('Tengo ideas para ayudarte con esta actividad.', style: TextStyle(color: Colors.black54)),
                                        TextButton(onPressed: () => _verAyuda(doc), child: const Text('Ver ideas')),
                                      ])),
                                    ]),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _registrarBitacora(doc),
                                    icon: const Icon(Icons.edit_note),
                                    label: const Text('Registrar bitácora de hoy'),
                                  ),
                                  const SizedBox(height: 8),
                                  StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance.collection('ar_bitacora_casa').where('trabajo_id', isEqualTo: doc.id).snapshots(),
                                    builder: (context, bitSnap) {
                                      final total = bitSnap.data?.docs.length ?? 0;
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: total == 0 ? null : () => _verEnvios(doc),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          _distintivo('ENVIADO POR APODERADO: $total', Colors.orange, Icons.family_restroom),
                                          if (total > 0) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right, color: Colors.orange)),
                                        ]),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
                },
              );
            },
          ),
          ),
          if (guardando) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}


void _abrirArchivoEvidencia(BuildContext context, String url, String tipo) {
  if (url.trim().isEmpty) return;
  final esVideo = tipo.toLowerCase().contains('video');
  if (esVideo) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }
  showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Text('Foto de evidencia', style: TextStyle(fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Flexible(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                url,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No se pudo cargar la foto.'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}



String _nombreProfesionalDoc(Map<String, dynamic> m) {
  final nombre = (m['profesional_nombre'] ?? m['nombre_profesional'] ?? '').toString().trim();
  if (nombre.isNotEmpty) return nombre;
  final email = (m['profesional_email'] ?? '').toString().trim();
  if (email.isNotEmpty) return email;
  return 'Profesional no informado';
}

String _nombreBeneficiarioDoc(Map<String, dynamic> m) {
  final nombre = (m['beneficiario_nombre'] ?? '').toString().trim();
  return nombre.isNotEmpty ? nombre : 'Beneficiario no informado';
}

Timestamp? _timestampDoc(Map<String, dynamic> m) {
  final f = m['fecha'] ?? m['fecha_creacion'] ?? m['fecha_inicio'] ?? m['ultima_bitacora'];
  return f is Timestamp ? f : null;
}

String _fechaCortaDoc(dynamic fecha) {
  if (fecha is! Timestamp) return 'Sin fecha';
  return DateFormat('dd-MM-yyyy').format(fecha.toDate());
}

String _fechaHoraDoc(dynamic fecha) {
  if (fecha is! Timestamp) return 'Sin fecha';
  return DateFormat('dd-MM-yyyy HH:mm').format(fecha.toDate());
}

String _emailProfesionalDoc(Map<String, dynamic> m) {
  final email = (m['profesional_email'] ?? m['email_profesional'] ?? m['correo_profesional'] ?? '').toString().trim().toLowerCase();
  return email;
}

String _tokenProfesional(String value) {
  var v = value.toLowerCase().trim();
  if (v.contains('@')) v = v.split('@').first;
  v = v.replaceAll(RegExp(r'[^a-záéíóúñ0-9]+'), ' ');
  final partes = v.split(' ').where((x) => x.length >= 4 && x != 'prof' && x != 'to').toList();
  return partes.isNotEmpty ? partes.first : v.replaceAll(' ', '');
}

Map<String, List<QueryDocumentSnapshot>> _agruparPorProfesional(List<QueryDocumentSnapshot> docs) {
  final profesionalPorTrabajo = <String, String>{};
  final profesionalPorEmail = <String, String>{};
  final profesionalPorToken = <String, String>{};

  for (final d in docs) {
    final m = d.data() as Map<String, dynamic>;
    if (m['tipo_doc'] == 'plan_trabajo_casa') {
      final nombre = _nombreProfesionalDoc(m);
      final email = _emailProfesionalDoc(m);
      if (nombre != 'Profesional no informado') {
        profesionalPorTrabajo[d.id] = nombre;
        if (email.isNotEmpty) profesionalPorEmail[email] = nombre;
        final tokenNombre = _tokenProfesional(nombre);
        if (tokenNombre.isNotEmpty) profesionalPorToken[tokenNombre] = nombre;
        final tokenEmail = _tokenProfesional(email);
        if (tokenEmail.isNotEmpty) profesionalPorToken[tokenEmail] = nombre;
      }
    }
  }

  final grupos = <String, List<QueryDocumentSnapshot>>{};
  for (final d in docs) {
    final m = d.data() as Map<String, dynamic>;
    var profesional = _nombreProfesionalDoc(m);
    final trabajoId = (m['trabajo_id'] ?? '').toString();
    final email = _emailProfesionalDoc(m);
    final token = _tokenProfesional(email.isNotEmpty ? email : profesional);

    if (trabajoId.isNotEmpty && profesionalPorTrabajo.containsKey(trabajoId)) {
      profesional = profesionalPorTrabajo[trabajoId]!;
    } else if (email.isNotEmpty && profesionalPorEmail.containsKey(email)) {
      profesional = profesionalPorEmail[email]!;
    } else if (token.isNotEmpty && profesionalPorToken.containsKey(token)) {
      profesional = profesionalPorToken[token]!;
    }

    grupos.putIfAbsent(profesional, () => <QueryDocumentSnapshot>[]).add(d);
  }
  for (final lista in grupos.values) {
    lista.sort((a, b) {
      final ma = a.data() as Map<String, dynamic>;
      final mb = b.data() as Map<String, dynamic>;
      final da = _timestampDoc(ma);
      final db = _timestampDoc(mb);
      if (da != null && db != null) return db.compareTo(da);
      return 0;
    });
  }
  return grupos;
}

Widget _distintivo(String texto, Color color, IconData icono) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      border: Border.all(color: color.withOpacity(0.45)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 5),
        Text(texto, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 12)),
      ],
    ),
  );
}

Widget _encabezadoProfesional(String profesional, int total, Color color) {
  return Row(
    children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.person_rounded, color: color)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profesional, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text('$total registro${total == 1 ? '' : 's'} disponible${total == 1 ? '' : 's'}', style: const TextStyle(color: Color(0xFF718394), fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ],
  );
}


DateTime? _fechaBaseDoc(Map<String, dynamic> m) {
  final ts = _timestampDoc(m);
  if (ts == null) return null;
  final d = ts.toDate();
  return DateTime(d.year, d.month, d.day);
}

String _nombreMes(int mes) {
  const meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];
  if (mes < 1 || mes > 12) return '';
  return meses[mes - 1];
}

String _nombreDiaCorto(int dia) {
  const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  return dias[(dia - 1).clamp(0, 6).toInt()];
}

Widget _calendarioFisicoPorDia({
  required List<QueryDocumentSnapshot> items,
  required Color color,
  required Widget Function(QueryDocumentSnapshot doc, Map<String, dynamic> data) itemBuilder,
  bool abrirDetalleAlTocar = false,
}) {
  final porDia = <DateTime, List<QueryDocumentSnapshot>>{};
  for (final doc in items) {
    final data = doc.data() as Map<String, dynamic>;
    final fecha = _fechaBaseDoc(data);
    if (fecha == null) continue;
    porDia.putIfAbsent(fecha, () => <QueryDocumentSnapshot>[]).add(doc);
  }
  final fechas = porDia.keys.toList()..sort((a, b) => b.compareTo(a));
  final sinFecha = items.where((doc) => _fechaBaseDoc(doc.data() as Map<String, dynamic>) == null).toList();
  DateTime mesVisible = fechas.isNotEmpty
      ? DateTime(fechas.first.year, fechas.first.month, 1)
      : DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime diaSeleccionado = fechas.isNotEmpty
      ? fechas.first
      : DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  const diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  return StatefulBuilder(
    builder: (context, setState) {
      final primerDia = DateTime(mesVisible.year, mesVisible.month, 1);
      final ultimoDia = DateTime(mesVisible.year, mesVisible.month + 1, 0);
      final celdasVaciasInicio = primerDia.weekday - 1;
      final totalCeldas = celdasVaciasInicio + ultimoDia.day;
      final filas = (totalCeldas / 7).ceil();
      final registrosDelDia = porDia[diaSeleccionado] ?? <QueryDocumentSnapshot>[];

      Widget celdaDia(DateTime? fecha) {
        if (fecha == null) return const SizedBox(height: 54);
        final cantidad = porDia[fecha]?.length ?? 0;
        final seleccionado = fecha.year == diaSeleccionado.year && fecha.month == diaSeleccionado.month && fecha.day == diaSeleccionado.day;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            setState(() => diaSeleccionado = fecha);
            final registros = porDia[fecha] ?? <QueryDocumentSnapshot>[];
            if (abrirDetalleAlTocar && registros.isNotEmpty) {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
                builder: (_) => DraggableScrollableSheet(
                  expand: false, initialChildSize: .78, maxChildSize: .94,
                  builder: (context, scroll) => ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    children: registros.map((doc) => itemBuilder(doc, doc.data() as Map<String, dynamic>)).toList(),
                  ),
                ),
              );
            }
          },
          child: Container(
            height: 54,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: cantidad > 0 ? color.withOpacity(seleccionado ? 0.20 : 0.10) : Colors.white,
              border: Border.all(color: seleccionado ? color : (cantidad > 0 ? color.withOpacity(.30) : Colors.black12), width: seleccionado ? 2 : 1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text('${fecha.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: seleccionado || cantidad > 0 ? color : Colors.black87)),
                if (cantidad > 0)
                  Positioned(left: 5, bottom: 4, child: Icon(Icons.home_work_rounded, size: 13, color: color)),
                if (cantidad > 0)
                  Positioned(
                    right: 5,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                      child: Text('$cantidad', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      return Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              border: Border.all(color: color.withOpacity(0.22)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() => mesVisible = DateTime(mesVisible.year, mesVisible.month - 1, 1)),
                    ),
                    Expanded(
                      child: Center(
                        child: Text('${_nombreMes(mesVisible.month)[0].toUpperCase()}${_nombreMes(mesVisible.month).substring(1)} ${mesVisible.year}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(() => mesVisible = DateTime(mesVisible.year, mesVisible.month + 1, 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: diasSemana.map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black54))))).toList(),
                ),
                const SizedBox(height: 6),
                ...List.generate(filas, (fila) {
                  return Row(
                    children: List.generate(7, (col) {
                      final index = fila * 7 + col;
                      final diaNumero = index - celdasVaciasInicio + 1;
                      final fecha = (diaNumero < 1 || diaNumero > ultimoDia.day) ? null : DateTime(mesVisible.year, mesVisible.month, diaNumero);
                      return Expanded(child: celdaDia(fecha));
                    }),
                  );
                }),
              ],
            ),
          ),
          if (!abrirDetalleAlTocar)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: color.withOpacity(0.22)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_nombreDiaCorto(diaSeleccionado.weekday)} ${diaSeleccionado.day} de ${_nombreMes(diaSeleccionado.month)} de ${diaSeleccionado.year}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 4),
                Text('${registrosDelDia.length} registro${registrosDelDia.length == 1 ? '' : 's'} dentro del día', style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 12),
                if (registrosDelDia.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: Text('No hay información registrada para este día.')),
                  )
                else
                  ...registrosDelDia.map((doc) => itemBuilder(doc, doc.data() as Map<String, dynamic>)),
              ],
            ),
          ),
          if (!abrirDetalleAlTocar && sinFecha.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sin fecha registrada', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  ...sinFecha.map((doc) => itemBuilder(doc, doc.data() as Map<String, dynamic>)),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class ReporteTerapiaDiaPage extends StatelessWidget {
  const ReporteTerapiaDiaPage({super.key});

  String _fecha(dynamic fecha) {
    if (fecha is! Timestamp) return '';
    return DateFormat('dd-MM-yyyy HH:mm').format(fecha.toDate());
  }

  List<Map<String, dynamic>> _evidencias(Map<String, dynamic> m) {
    final raw = m['evidencias'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    final url = (m['evidencia_url'] ?? '').toString();
    if (url.isEmpty) return [];
    return [{
      'url': url,
      'tipo': (m['evidencia_tipo'] ?? '').toString(),
      'nombre': 'Evidencia',
    }];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF3FBFA),
      appBar: AppBar(
        title: const Text('Reporte terapia del día', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF075F58))),
        backgroundColor: const Color(0xFFF3FBFA),
        foregroundColor: const Color(0xFF0A9489),
        elevation: 0, surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Align(alignment: Alignment.topCenter, child: _ApoyoImageBanner('assets/images/apoyo_04_reporte_terapia.png', height: 145)),
          Padding(
            padding: const EdgeInsets.only(top: 167),
            child: FutureBuilder<Set<String>>(
        future: _beneficiariosVisiblesParaUid(uid),
        builder: (context, idsSnap) {
          if (idsSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final idsBeneficiarios = idsSnap.data ?? <String>{};
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('atenciones_profesionales')
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final docs = (snap.data?.docs ?? []).where((d) {
                final m = d.data() as Map<String, dynamic>;
                if (!_docVisibleParaApoderadoOApoyo(m, uid, idsBeneficiarios)) return false;
                return m['visible_apoderado'] != false;
              }).toList();
          docs.sort((a, b) {
            final da = (a.data() as Map<String, dynamic>)['fecha'];
            final db = (b.data() as Map<String, dynamic>)['fecha'];
            if (da is Timestamp && db is Timestamp) return db.compareTo(da);
            return 0;
          });
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aún no hay reportes de terapia registrados por profesionales.', textAlign: TextAlign.center),
              ),
            );
          }
          final grupos = _agruparPorProfesional(docs);
          final profesionales = grupos.keys.toList()..sort();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: profesionales.length,
            itemBuilder: (_, i) {
              final profesional = profesionales[i];
              final items = grupos[profesional] ?? <QueryDocumentSnapshot>[];
              return Card(
                margin: const EdgeInsets.only(bottom: 14), elevation: 0, color: Colors.white, surfaceTintColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.black.withOpacity(.035))),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: profesionales.length == 1,
                  title: _encabezadoProfesional(profesional, items.length, Colors.teal),
                  children: [
                    _calendarioFisicoPorDia(
                      items: items,
                      color: Colors.teal,
                      itemBuilder: (doc, m) {
                        final evs = _evidencias(m);
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.teal.withOpacity(0.20)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                _distintivo('REPORTE PROFESIONAL', Colors.teal, Icons.assignment_turned_in),
                              ]),
                              const SizedBox(height: 10),
                              Text(_nombreBeneficiarioDoc(m), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text('${m['terapia'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                              const Divider(),
                              Text('Asistencia: ${m['asistencia'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text('Objetivos trabajados: ${m['objetivos_trabajados'] ?? ''}'),
                              const SizedBox(height: 8),
                              Text('Observaciones: ${m['observaciones'] ?? ''}'),
                              const SizedBox(height: 8),
                              Text('Recomendaciones para casa: ${m['recomendaciones_casa'] ?? ''}'),
                              if (evs.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                const Text('Evidencias del profesional', style: TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: List.generate(evs.length, (idx) {
                                    final ev = evs[idx];
                                    final tipo = (ev['tipo'] ?? '').toString();
                                    final url = (ev['url'] ?? '').toString();
                                    final esVideo = tipo.toLowerCase().contains('video');
                                    return OutlinedButton.icon(
                                      onPressed: url.isEmpty ? null : () => _abrirArchivoEvidencia(context, url, tipo),
                                      icon: Icon(esVideo ? Icons.play_circle_outline : Icons.image_outlined),
                                      label: Text('${esVideo ? 'Video' : 'Foto'} profesional ${idx + 1}'),
                                    );
                                  }),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
            },
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}

class ActividadesCasaPage extends StatelessWidget {
  const ActividadesCasaPage({super.key});

  String _fecha(dynamic fecha) {
    if (fecha is! Timestamp) return '';
    return DateFormat('dd-MM-yyyy HH:mm').format(fecha.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;
    final email = user.email?.toLowerCase().trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Bitácora diaria'), backgroundColor: Colors.orange, foregroundColor: Colors.white),
      body: FutureBuilder<Set<String>>(
        future: _beneficiariosVisiblesParaUid(uid),
        builder: (context, idsSnap) {
          if (idsSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final idsBeneficiarios = idsSnap.data ?? <String>{};
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('ar_bitacora_casa').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final docs = (snap.data?.docs ?? []).where((d) {
                final m = d.data() as Map<String, dynamic>;
                if (!_docVisibleParaApoderadoOApoyo(m, uid, idsBeneficiarios)) return false;
                return m['tipo_doc'] == 'plan_trabajo_casa';
              }).toList();
          docs.sort((a, b) {
            final da = (a.data() as Map<String, dynamic>)['fecha'];
            final db = (b.data() as Map<String, dynamic>)['fecha'];
            if (da is Timestamp && db is Timestamp) return db.compareTo(da);
            return 0;
          });
          if (docs.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aún no has registrado bitácoras. Ingresa a Trabajo en casa y registra el avance diario.', textAlign: TextAlign.center),
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final m = docs[i].data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(m['realizado'] == true ? Icons.check_circle : Icons.cancel, color: m['realizado'] == true ? Colors.green : Colors.red),
                  title: Text((m['objetivo'] ?? 'Trabajo en casa').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${_fecha(m['fecha'])}\nTiempo: ${m['tiempo_minutos'] ?? 0} minutos\n${m['estado_emocional'] ?? ''}\n${m['observacion'] ?? ''}'),
                  isThreeLine: true,
                ),
              );
            },
          );
            },
          );
        },
      ),
    );
  }
}

class HistorialFamiliarPage extends StatelessWidget {
  const HistorialFamiliarPage({super.key});

  String _fecha(dynamic fecha) {
    if (fecha is! Timestamp) return '';
    return DateFormat('dd-MM-yyyy').format(fecha.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final email = user?.email?.toLowerCase().trim() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FB),
      appBar: AppBar(
        title: const Text('Historial de avances', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF31576B))),
        backgroundColor: const Color(0xFFF6F9FB), foregroundColor: const Color(0xFF54788C),
        elevation: 0, surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Align(alignment: Alignment.topCenter, child: _ApoyoImageBanner('assets/images/apoyo_05_avances.png', height: 145)),
          Padding(
            padding: const EdgeInsets.only(top: 167),
            child: FutureBuilder<Set<String>>(
        future: _beneficiariosVisiblesParaUid(uid),
        builder: (context, idsSnap) {
          if (idsSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final idsBeneficiarios = idsSnap.data ?? <String>{};
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('ar_bitacora_casa').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final docs = (snap.data?.docs ?? []).where((d) {
                final m = d.data() as Map<String, dynamic>;
                return _docVisibleParaApoderadoOApoyo(m, uid, idsBeneficiarios);
              }).toList();
          docs.sort((a, b) {
            final da = (a.data() as Map<String, dynamic>)['fecha_creacion'];
            final db = (b.data() as Map<String, dynamic>)['fecha_creacion'];
            if (da is Timestamp && db is Timestamp) return db.compareTo(da);
            return 0;
          });
          if (docs.isEmpty) return const Center(child: Text('Aún no existe historial familiar.'));
          final grupos = _agruparPorProfesional(docs);
          final profesionales = grupos.keys.toList()..sort();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: profesionales.length,
            itemBuilder: (_, i) {
              final profesional = profesionales[i];
              final items = grupos[profesional] ?? <QueryDocumentSnapshot>[];
              return Card(
                margin: const EdgeInsets.only(bottom: 14), elevation: 0, color: Colors.white, surfaceTintColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.black.withOpacity(.035))),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: profesionales.length == 1,
                  title: _encabezadoProfesional(profesional, items.length, Colors.blueGrey),
                  children: [
                    _calendarioFisicoPorDia(
                      items: items,
                      color: Colors.blueGrey,
                      itemBuilder: (doc, m) {
                        final esPlan = m['tipo_doc'] == 'plan_trabajo_casa';
                        final esRespuesta = (m['trabajo_id'] ?? '').toString().isNotEmpty && !esPlan;
                        final color = esRespuesta ? Colors.orange : Colors.blueAccent;
                        final texto = esRespuesta ? 'ENVIADO POR APODERADO' : 'TAREA PROFESIONAL';
                        final icono = esRespuesta ? Icons.family_restroom : Icons.home_work;
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: color.withOpacity(0.22)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                _distintivo(texto, color, icono),
                              ]),
                              const SizedBox(height: 10),
                              Text((m['objetivo'] ?? 'Trabajo en casa').toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                              Text(_nombreBeneficiarioDoc(m), style: const TextStyle(fontWeight: FontWeight.w700)),
                              if ((m['terapia'] ?? '').toString().isNotEmpty) Text('Terapia: ${m['terapia']}'),
                              const Divider(),
                              if (esPlan) ...[
                                const Text('Indicaciones del profesional', style: TextStyle(fontWeight: FontWeight.w900)),
                                Text((m['indicaciones'] ?? '').toString()),
                                if ((m['fecha_inicio'] is Timestamp) || (m['fecha_fin'] is Timestamp))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('Periodo: ${_fecha(m['fecha_inicio'])} al ${_fecha(m['fecha_fin'])}', style: const TextStyle(color: Colors.black54)),
                                  ),
                              ] else ...[
                                Text('Realizado: ${m['realizado'] == true ? 'Sí' : 'No'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('Tiempo: ${m['tiempo_minutos'] ?? 0} minutos'),
                                if ((m['estado_emocional'] ?? '').toString().isNotEmpty) Text('Respuesta: ${m['estado_emocional']}'),
                                const SizedBox(height: 8),
                                const Text('Observación del apoderado', style: TextStyle(fontWeight: FontWeight.w900)),
                                Text((m['observacion'] ?? '').toString()),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
            },
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}

class AvisosApoderadoPage extends StatefulWidget {
  const AvisosApoderadoPage({super.key});

  @override
  State<AvisosApoderadoPage> createState() => _AvisosApoderadoPageState();
}

class _AvisosApoderadoPageState extends State<AvisosApoderadoPage> {
  late Future<List<_AvisoItem>> future;

  @override
  void initState() {
    super.initState();
    future = _cargarAvisos();
  }

  Future<List<_AvisoItem>> _cargarAvisos() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final items = <_AvisoItem>[];
    final consultas = <String, Future<Map<String, dynamic>>>{};

    try {
      final snap = await FirebaseFirestore.instance
          .collection('avisos_apoderados')
          .where('apoderado_id', isEqualTo: uid)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        var titulo = (data['titulo'] ?? 'Aviso').toString();
        var detalleAviso = (data['detalle'] ?? data['mensaje'] ?? '').toString();
        var resuelto = data['resuelta'] == true;
        if (data['version'] == 58 && ['recordatorio_pago', 'aviso_cobranza'].contains(data['tipo'])) {
          final emitido = (data['fecha_efectiva'] ?? '').toString();
          detalleAviso = 'Aviso emitido el $emitido. Saldo informado a esa fecha:\n$detalleAviso';
          final cuentaId = (data['cuenta_id'] ?? '').toString();
          if (cuentaId.isNotEmpty) {
            try {
              final actual = await consultas.putIfAbsent(cuentaId, () => TesoreriaV58Service.consultar(cuentaId));
              final resumen = TesoreriaFinanzasService.desdeRespuesta(actual);
              final cargosAvisados = TesoreriaV58Service.mapas(data['cargos']).map((c) => c['cargo_id']).toSet();
              final saldoActual = TesoreriaV58Service.mapas(actual['cargos'])
                  .where((c) => cargosAvisados.contains(c['id']))
                  .fold<int>(0, (total, c) => total + TesoreriaFinanzasService.toInt(c['saldo']));
              if (resumen.advertencias.isEmpty && cargosAvisados.isNotEmpty) {
                resuelto = saldoActual == 0;
                if (resuelto) titulo = '$titulo · regularizado';
                detalleAviso += '\nSaldo pendiente actual de esos cargos: \$${saldoActual}.';
              } else {
                detalleAviso += '\nLa cuenta requiere conciliación; este aviso no acredita el saldo actual.';
              }
            } catch (_) {
              detalleAviso += '\nNo se pudo consultar el saldo actual. Este mensaje conserva el saldo de emisión.';
            }
          }
        }
        items.add(_AvisoItem(
          id: doc.id,
          origen: 'avisos_apoderados',
          titulo: titulo,
          detalle: detalleAviso,
          leido: resuelto || data['leido'] == true || data['aceptado'] == true,
          fecha: data['fecha'] ?? data['creado'] ?? data['fecha_creacion'],
        ));
      }
    } catch (_) {}

    try {
      for (final data in await _avisosVigentesTesoreria(uid)) {
        items.add(_AvisoItem(
          id: data['id'].toString(),
          origen: 'tesoreria_apoderados',
          titulo: 'Aviso Tesorería',
          detalle: (data['mensaje_aviso'] ?? 'Mantiene un saldo vencido en Tesorería.').toString(),
          leido: data['aviso_visto_por_apoderado'] == true,
          fecha: data['actualizado'] ?? data['fecha_creacion'],
        ));
      }
    } catch (_) {}

    items.sort((a, b) => b.fechaMs.compareTo(a.fechaMs));
    return items;
  }

  Future<void> _marcarEnterado(_AvisoItem item) async {
    if (item.origen == 'avisos_apoderados') {
      await FirebaseFirestore.instance.collection('avisos_apoderados').doc(item.id).update({
        'leido': true,
        'aceptado': true,
        'fecha_lectura': Timestamp.now(),
      });
    } else if (item.origen == 'tesoreria_apoderados') {
      await FirebaseFirestore.instance.collection('tesoreria_apoderados').doc(item.id).set({
        'aviso_visto_por_apoderado': true,
        'fecha_lectura_aviso': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (mounted) setState(() => future = _cargarAvisos());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos pendientes'),
        backgroundColor: const Color(0xFF0B69B7),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<_AvisoItem>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No tienes avisos pendientes por revisar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: item.leido ? Colors.green.shade50 : Colors.red.shade50,
                    child: Icon(
                      item.leido ? Icons.check_circle : Icons.campaign_outlined,
                      color: item.leido ? Colors.green : Colors.redAccent,
                    ),
                  ),
                  title: Text(item.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(item.detalle.isEmpty ? 'Aviso pendiente de revisión.' : item.detalle),
                  ),
                  trailing: item.leido
                      ? const Text('Leído', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                      : TextButton(
                          onPressed: () => _marcarEnterado(item),
                          child: const Text('Enterado'),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AvisoItem {
  final String id;
  final String origen;
  final String titulo;
  final String detalle;
  final bool leido;
  final dynamic fecha;

  _AvisoItem({
    required this.id,
    required this.origen,
    required this.titulo,
    required this.detalle,
    required this.leido,
    required this.fecha,
  });

  int get fechaMs {
    if (fecha is Timestamp) return (fecha as Timestamp).millisecondsSinceEpoch;
    return 0;
  }
}

class ReciclajePage extends StatefulWidget {
  const ReciclajePage({super.key});

  @override
  State<ReciclajePage> createState() => _ReciclajePageState();
}

class _ReciclajePageState extends State<ReciclajePage> {
  final detalleController = TextEditingController();
  String material = 'Latas de bebidas';
  XFile? imagen;
  Uint8List? imagenBytes;
  bool cargando = false;

  Future<void> seleccionarImagen() async {
    final picker = ImagePicker();
    ImageSource source = ImageSource.gallery;
    if (!kIsWeb) {
      final elegido = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir desde galería / pantallazo'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto con cámara'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ])),
      );
      if (elegido == null) return;
      source = elegido;
    }
    final img = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1800);
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() { imagen = img; imagenBytes = bytes; });
    }
  }

  Future<void> enviarReciclaje() async {
    if (imagen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar una foto o pantallazo del reciclaje')),
      );
      return;
    }
    setState(() => cargando = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;
      final ahora = DateTime.now();
      // El ID diario por usuario + material es el único control de duplicados.
      // Evita una consulta compuesta de Firestore que requería un índice adicional.
      final materialClave = material.toLowerCase().contains('lata') ? 'latas' : 'pet';
      final fechaClave = '${ahora.year}${ahora.month.toString().padLeft(2, '0')}${ahora.day.toString().padLeft(2, '0')}';
      final envioId = '${uid}_${fechaClave}_$materialClave';
      final envioRef = FirebaseFirestore.instance.collection('reciclaje_envios').doc(envioId);
      if ((await envioRef.get()).exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Usted ya envió $material hoy. Su entrega ya se encuentra registrada.')));
        return;
      }

      final nombreArchivo = 'reciclaje/$uid-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child(nombreArchivo);
      final bytes = await imagen!.readAsBytes();

      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      String url = '';
      for (int intento = 0; intento < 3; intento++) {
        try {
          url = await uploadTask.ref.getDownloadURL();
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }

      String nombreApoderado = user.displayName ?? '';
      String beneficiarioNombre = '';
      try {
        final usuarioDoc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
        final usuarioData = usuarioDoc.data() ?? {};
        nombreApoderado = (usuarioData['nombre'] ?? usuarioData['nombre_apoderado'] ?? usuarioData['apoderadoNombre'] ?? nombreApoderado).toString();
        beneficiarioNombre = (usuarioData['beneficiario'] ?? usuarioData['beneficiario_nombre'] ?? usuarioData['nombre_beneficiario'] ?? '').toString();
      } catch (_) {}
      if (nombreApoderado.trim().isEmpty) nombreApoderado = user.email ?? 'Apoderado no informado';
      if (beneficiarioNombre.trim().isEmpty) beneficiarioNombre = 'No informado';

      await envioRef.set({
        'uid': uid,
        'email': user.email ?? '',
        'apoderadoNombre': nombreApoderado,
        'nombre_apoderado': nombreApoderado,
        'beneficiario': beneficiarioNombre,
        'beneficiario_nombre': beneficiarioNombre,
        'material': material,
        'materialPermitido': material == 'Latas de bebidas' || material == 'Botellas plásticas PET',
        'detalle': detalleController.text.trim(),
        'imagen': url,
        'imagenPath': nombreArchivo,
        'fecha': FieldValue.serverTimestamp(),
        'estado': 'pendiente',
        'afectaTesoreria': false,
        'monto': 0,
        'pesoKg': null,
        'observacionSistema': 'Módulo reciclaje: solo registro de entrega. No genera dinero, deuda, peso ni movimiento de tesorería.',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reciclaje enviado correctamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('ERROR RECICLAJE: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enviar reciclaje'),
        backgroundColor: const Color(0xFF238636),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 38),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/images/reciclaje_ninos_banner.png', height: 145, fit: BoxFit.cover),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.green.withOpacity(.35)),
              ),
              child: const Text(
                'Este módulo es solo para latas de bebidas y botellas plásticas PET. No registra dinero, peso ni deuda.',
                style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1B5E20)),
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: material,
              decoration: const InputDecoration(
                labelText: 'Tipo de reciclaje',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Latas de bebidas', child: Text('Latas de bebidas')),
                DropdownMenuItem(value: 'Botellas plásticas PET', child: Text('Botellas plásticas PET')),
              ],
              onChanged: (v) => setState(() => material = v ?? 'Latas de bebidas'),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: seleccionarImagen,
              child: Container(
                height: 230,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 1.4),
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.green.withOpacity(0.04),
                ),
                child: imagen == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/images/reciclaje_nino_foto.png', height: 90, fit: BoxFit.contain),
                          const Icon(Icons.camera_alt_rounded, size: 42, color: Color(0xFF238636)),
                          const SizedBox(height: 6),
                          const Text('TOCAR PARA AGREGAR FOTO / PANTALLAZO', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          const SizedBox(height: 6),
                          const Text('Foto de latas o botellas PET', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.memory(imagenBytes!, fit: BoxFit.cover, width: double.infinity),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: detalleController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observación opcional',
                hintText: 'Ej: latas juntadas por la familia / botellas PET limpias',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton.icon(
              onPressed: cargando ? null : enviarReciclaje,
              icon: const Icon(Icons.send),
              label: Text(cargando ? 'ENVIANDO...' : 'ENVIAR RECICLAJE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 58),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MisEnviosPage(tipo: 'reciclaje'))),
              icon: const Icon(Icons.history),
              label: const Text('MIS ENVÍOS / HISTORIAL'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 54), foregroundColor: const Color(0xFF238636)),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _paginaSimple(
  BuildContext context, {
  required String titulo,
  required IconData icono,
  required String texto,
}) {
  return Scaffold(
    appBar: AppBar(
      title: Text(titulo),
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 70, color: Colors.green),
                const SizedBox(height: 18),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff0d47a1),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ENVIAR COMPROBANTE
class ComprobantePagoPage extends StatelessWidget {
  final TesoreriaV58Gateway? gateway;
  const ComprobantePagoPage({super.key, this.gateway});

  @override
  Widget build(BuildContext context) => ComprobantePagoV58Page(
    gateway: gateway,
    onHistorial: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MisEnviosPage(tipo: 'tesoreria'))),
  );
}

class MisEnviosPage extends StatelessWidget {
  final String tipo;
  const MisEnviosPage({super.key, required this.tipo});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final esTes = tipo == 'tesoreria';
    final col = esTes ? 'comprobantes_pago' : 'reciclaje_envios';
    final titulo = esTes ? 'Mis comprobantes' : 'Mis envíos de reciclaje';
    return Scaffold(
      appBar: AppBar(title: Text(titulo), backgroundColor: esTes ? const Color(0xFF0B69B7) : const Color(0xFF238636), foregroundColor: Colors.white),
      body: u == null ? const Center(child: Text('Debes iniciar sesión.')) : StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream: FirebaseFirestore.instance.collection(col).where('uid', isEqualTo: u.uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = [...(snap.data?.docs ?? <QueryDocumentSnapshot<Map<String,dynamic>>>[])];
          docs.sort((a,b){ final af=a.data()['fecha'], bf=b.data()['fecha']; return (bf is Timestamp?bf.millisecondsSinceEpoch:0).compareTo(af is Timestamp?af.millisecondsSinceEpoch:0); });
          if (docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Aún no tienes envíos registrados.', textAlign: TextAlign.center)));
          return ListView.builder(padding: const EdgeInsets.all(16), itemCount: docs.length, itemBuilder: (context,i){
            final d=docs[i].data(); final f=d['fecha'] is Timestamp?(d['fecha'] as Timestamp).toDate():null;
            final estado=(d['estado']??'pendiente').toString(); final url=(d['imagen']??'').toString();
            final revision = d['fecha_revision'] ?? d['fecha_aprobacion'] ?? d['fecha_rechazo'];
            final responsable = [d['revisado_por'], d['revisado_por_uid'], d['aprobado_por'], d['rechazado_por']].where((v) => v != null && v.toString().trim().isNotEmpty).firstOrNull;
            final motivo = (d['motivo_rechazo'] ?? '').toString();
            final revisionTxt = esTes ? '${responsable == null ? '' : '\nRevisado por: $responsable'}${revision is Timestamp ? '\nRevisión: ${DateFormat('dd/MM/yyyy HH:mm').format(revision.toDate())}' : ''}${motivo.isEmpty ? '' : '\nMotivo de rechazo: $motivo'}' : '';
            final detalle=esTes?'Monto: \$${TesoreriaFinanzasService.toInt(d['monto'])}':'${d['material']??''}${(d['detalle']??'').toString().trim().isEmpty?'':' · ${d['detalle']}'}';
            return Card(child: ListTile(
              leading: Icon(esTes?Icons.receipt_long:Icons.recycling, color: esTes?const Color(0xFF0B69B7):const Color(0xFF238636)),
              title: Text(f==null?'Fecha pendiente':DateFormat('dd/MM/yyyy HH:mm').format(f), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('$detalle\nEstado: $estado$revisionTxt'), isThreeLine: true,
              trailing: esTes || url.isNotEmpty ? const Icon(Icons.image_outlined) : null,
              onTap: esTes ? () => verImagenComprobanteTesoreria(context, d) : url.isEmpty?null:()=>showDialog(context: context, builder:(_)=>Dialog(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain, errorBuilder:(_,__,___)=>const Padding(padding:EdgeInsets.all(30),child:Text('No fue posible abrir la imagen.')))))),
            ));
          });
        },
      ),
    );
  }
}

// ADMINISTRACIÓN
class AdministracionPage extends StatelessWidget {
  const AdministracionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          _btn(
              context,
              'TESORERÍA',
              Icons.account_balance_wallet,
              Colors.green,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TesoreriaPage(),
                ),
              ),
            ),

            _btn(
              context,
              'AGREGAR APODERADO / USUARIO',
              Icons.person_add_alt_1,
              Colors.blueGrey,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AgregarApoderadoPage(),
                ),
              ),
            ),

          _btn(
            context,
            'COMPROBANTES PENDIENTES',
            Icons.receipt_long,
            Colors.orange,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ComprobantesPendientesPage(),
              ),
            ),
          ),

          _btn(
            context,
            'ENVIAR DOCUMENTO A FIRMA',
            Icons.edit_document,
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const CrearDocumentoPage(),
              ),
            ),
          ),

          _btn(
            context,
            'TODAS LAS ÓRDENES',
            Icons.list_alt,
            Colors.blueGrey,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ListPage(col: 'ordenes'),
              ),
            ),
          ),

          _btn(
            context,
            'TODOS LOS PRESUPUESTOS',
            Icons.assignment,
            Colors.deepOrange,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ListPage(col: 'presupuestos'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(
    BuildContext ctx,
    String text,
    IconData icon,
    Color color,
    VoidCallback function,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ElevatedButton.icon(
        onPressed: function,
        icon: Icon(icon),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class ComprobantesPendientesPage extends StatelessWidget {
  final TesoreriaV58Gateway? gateway;
  const ComprobantesPendientesPage({super.key, this.gateway});

  @override
  Widget build(BuildContext context) => RevisionComprobantesV58Page(gateway: gateway);
}

// RESUMEN ÚNICO DE PENDIENTES DEL APODERADO
class AgendaPage extends StatelessWidget {
  const AgendaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFF),
      body: SafeArea(
        child: Stack(children: [
          Positioned(top: 80, right: -55, child: _pendienteBlob(const Color(0xFF79DFFF), 170)),
          Positioned(top: 330, left: -70, child: _pendienteBlob(const Color(0xFFFF9FC1), 165)),
          Positioned(bottom: 70, right: -55, child: _pendienteBlob(const Color(0xFFFFD35E), 170)),
          ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0B5795))),
              const Expanded(child: Text('Mis próximos pendientes', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF073D78)))),
              Image.asset('assets/images/inicio.jpg', width: 46, height: 46, fit: BoxFit.contain),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFD9F3FF), Color(0xFFFFEAF1), Color(0xFFFFF1CF)]),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: const Color(0xFF075D9E).withOpacity(.10), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: const Row(children: [
                CircleAvatar(radius: 27, backgroundColor: Colors.white, child: Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C4FE8), size: 29)),
                SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Todo lo importante, en un lugar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF073D78))),
                  SizedBox(height: 4),
                  Text('Aquí se reúnen terapias, copagos, reciclaje semanal y tu próximo aseo.', style: TextStyle(color: Color(0xFF526F87), fontWeight: FontWeight.w600, height: 1.3)),
                ])),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('Esta semana', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF073D78))),
            const SizedBox(height: 12),
            _pendienteCard(Icons.favorite_rounded, 'Próximas terapias', 'Revisa las terapias y actividades programadas', const Color(0xFF00B58A), const Color(0xFFDDF8EF)),
            _pendienteCard(Icons.payments_rounded, 'Copagos', 'Vencimientos y pagos que requieren tu atención', const Color(0xFFFF557D), const Color(0xFFFFE1E9)),
            _pendienteCard(Icons.recycling_rounded, 'Reciclaje semanal', 'Desaparece de pendientes cuando registras tu entrega', const Color(0xFF00B86B), const Color(0xFFDDF8E9)),
            _pendienteCard(Icons.cleaning_services_rounded, 'Aseo', 'Tu próximo turno o reemplazo agendado', const Color(0xFFFF8C16), const Color(0xFFFFE8CF)),
          ]),
        ]),
      ),
    );
  }

  static Widget _pendienteBlob(Color c, double s) => IgnorePointer(child: Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(.22))));
  static Widget _pendienteCard(IconData icon, String title, String subtitle, Color color, Color tint) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, tint.withOpacity(.86)]), borderRadius: BorderRadius.circular(23), border: Border.all(color: color.withOpacity(.12)), boxShadow: [BoxShadow(color: const Color(0xFF073D78).withOpacity(.07), blurRadius: 14, offset: const Offset(0, 6))]),
    child: Row(children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(17)), child: Icon(icon, color: color, size: 28)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF073D78))), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 12.5, color: Color(0xFF607B91), fontWeight: FontWeight.w600))])), Icon(Icons.chevron_right_rounded, color: color)]),
  );
}

// PERFIL SOCIO
class LegacyConfiguracionCredencialPage extends StatefulWidget {
  const LegacyConfiguracionCredencialPage({super.key});

  @override
  State<LegacyConfiguracionCredencialPage> createState() =>
      _LegacyConfiguracionCredencialPageState();
}

class _LegacyConfiguracionCredencialPageState
    extends State<LegacyConfiguracionCredencialPage> {
  String? _credencialBase64;
  bool guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;

      setState(() {
        _credencialBase64 = data?['credencial_digital'];
      });
    }
  }

  Future<void> _subirCredencial() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 45,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();

      setState(() {
        _credencialBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _guardar() async {
    if (_credencialBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe agregar la credencial')),
      );
      return;
    }

    setState(() {
      guardando = true;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'credencial_digital': _credencialBase64,
        'email': FirebaseAuth.instance.currentUser?.email ?? '',
        'fecha_actualizacion_credencial': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credencial guardada correctamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 15),
          const Text(
            'Credencial de discapacidad',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xff0d47a1),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aquí se agrega o actualiza la credencial. El botón principal solo la muestra.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.black54),
          ),
          const SizedBox(height: 25),
          GestureDetector(
            onTap: _subirCredencial,
            child: Container(
              height: 310,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.blueAccent, width: 1.3),
              ),
              child: _credencialBase64 == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo,
                          size: 78,
                          color: Colors.blueAccent,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'TOCAR PARA AGREGAR CREDENCIAL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(
                        base64Decode(_credencialBase64!),
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 25),
          ElevatedButton.icon(
            onPressed: guardando ? null : _guardar,
            icon: const Icon(Icons.save),
            label: Text(guardando ? 'GUARDANDO...' : 'GUARDAR CREDENCIAL'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
            ),
          ),
        ],
      ),
    );
  }
}

class PerfilApoderadoPage extends StatefulWidget {
  const PerfilApoderadoPage({super.key});

  @override
  State<PerfilApoderadoPage> createState() => _PerfilApoderadoPageState();
}

class _PerfilApoderadoPageState extends State<PerfilApoderadoPage> {
  String? _credencialBase64;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;

      setState(() {
        _credencialBase64 = data?['credencial_digital'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credencial discapacidad'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            height: 420,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.indigo,
                width: 1.3,
              ),
            ),
            child: _credencialBase64 == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.badge,
                        size: 80,
                        color: Colors.indigo,
                      ),
                      SizedBox(height: 15),
                      Text(
                        'NO HAY CREDENCIAL CARGADA',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 10),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 25),
                        child: Text(
                          'La credencial se agrega desde el botón de configuración superior.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      base64Decode(_credencialBase64!),
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// FORMULARIO
class FormPage extends StatefulWidget {
  final bool esOrden;
  final DocumentSnapshot? docExistente;
  final bool soloCierre;

  const FormPage({
    super.key,
    required this.esOrden,
    this.docExistente,
    this.soloCierre = false,
  });

  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final _n = TextEditingController();
  final _r = TextEditingController();
  final _t = TextEditingController();
  final _d = TextEditingController();
  final _com = TextEditingController();
  final _pat = TextEditingController();
  final _marca = TextEditingController();
  final _mod = TextEditingController();
  final _anio = TextEditingController();
  final _det = TextEditingController();
  final _val = TextEditingController();
  final _boleta = TextEditingController();

  String _tipo = "AUTO";
  String? _firma;
  String? _foto;
  bool _aceptaTerminos = false;
  bool _procesando = false;

  final SignatureController _sig = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();

    if (widget.docExistente != null) {
      final m = widget.docExistente!.data() as Map<String, dynamic>;

      _n.text = m['nombre'] ?? "";
      _r.text = m['rut'] ?? "";
      _t.text = m['tel'] ?? "";
      _d.text = m['dir'] ?? "";
      _com.text = m['comuna'] ?? "";
      _tipo = m['tipo_servicio'] ?? "AUTO";
      _pat.text = m['patente'] ?? "";
      _marca.text = m['marca'] ?? "";
      _mod.text = m['modelo'] ?? "";
      _anio.text = m['anio'] ?? "";
      _det.text = m['det'] ?? "";
      _val.text = m['val'] ?? "";
      _boleta.text = m['num_documento'] ?? "";
      _firma = m['firma'];
      _foto = m['foto_evidencia'];
      _aceptaTerminos = true;
    }
  }

  void _limpiarFormulario() {
    _n.clear();
    _r.clear();
    _t.clear();
    _d.clear();
    _com.clear();
    _pat.clear();
    _marca.clear();
    _mod.clear();
    _anio.clear();
    _det.clear();
    _val.clear();
    _boleta.clear();
    _sig.clear();

    setState(() {
      _foto = null;
      _firma = null;
      _aceptaTerminos = false;
    });
  }

  Future<void> _tomarFoto() async {
    if (widget.soloCierre) return;

    final XFile? photo = await ImagePicker().pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 25,
    );

    if (photo != null) {
      final bytes = await photo.readAsBytes();
      setState(() => _foto = base64Encode(bytes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editableCompleto =
        widget.docExistente == null || (!widget.soloCierre);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.esOrden ? 'Gestión Orden' : 'Gestión Presupuesto'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _titulo("DATOS DEL CLIENTE"),
          _input(_n, "NOMBRE COMPLETO", Icons.person, e: editableCompleto),
          _input(_r, "RUT CLIENTE", Icons.badge, e: editableCompleto),
          _input(_t, "TELÉFONO CLIENTE", Icons.phone,
              e: editableCompleto, soloNumeros: true),
          _input(_d, "DIRECCIÓN", Icons.location_city, e: editableCompleto),
          _input(_com, "COMUNA", Icons.map, e: editableCompleto),
          const SizedBox(height: 15),
          _titulo("TIPO DE SERVICIO"),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text("AUTO"),
                  selected: _tipo == "AUTO",
                  onSelected: (s) {
                    if (editableCompleto) setState(() => _tipo = "AUTO");
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  label: const Text("DOMICILIO"),
                  selected: _tipo == "DOMICILIO",
                  onSelected: (s) {
                    if (editableCompleto) {
                      setState(() => _tipo = "DOMICILIO");
                    }
                  },
                ),
              ),
            ],
          ),
          if (_tipo == "AUTO") ...[
            _titulo("DATOS DEL VEHÍCULO"),
            _input(_pat, "PATENTE", Icons.subtitles, e: editableCompleto),
            _input(_marca, "MARCA", Icons.branding_watermark,
                e: editableCompleto),
            _input(_mod, "MODELO", Icons.car_repair, e: editableCompleto),
            _input(_anio, "AÑO", Icons.calendar_today,
                e: editableCompleto, soloNumeros: true),
          ],
          _titulo("REGISTRO FOTOGRÁFICO"),
          GestureDetector(
            onTap: _tomarFoto,
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[400]!),
              ),
              child: _foto == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 40),
                        Text("Capturar evidencia"),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        base64Decode(_foto!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
            ),
          ),
          _titulo("TRABAJO"),
          _input(
            _det,
            "DETALLE DEL TRABAJO",
            Icons.description,
            lines: 3,
            e: editableCompleto,
          ),
          if (widget.esOrden && editableCompleto) ...[
            const Divider(height: 30),
            _titulo("ACUERDO Y FIRMA"),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "DECLARACIÓN: El cliente acepta el trabajo realizado en las condiciones actuales y declara ser propietario o estar autorizado para la intervención de este bien, liberando al técnico de toda responsabilidad posterior.",
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
              ),
            ),
            CheckboxListTile(
              title: const Text(
                "Acepto recepción de trabajo",
                style: TextStyle(fontSize: 12),
              ),
              value: _aceptaTerminos,
              onChanged: (val) =>
                  setState(() => _aceptaTerminos = val ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Container(
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                color: Colors.white,
              ),
              child: Signature(
                controller: _sig,
                backgroundColor: Colors.white,
              ),
            ),
            TextButton(
              onPressed: () => _sig.clear(),
              child: const Text("LIMPIAR FIRMA"),
            ),
          ],
          const Divider(height: 30),
          _titulo("VALORES"),
          if (widget.esOrden)
            _input(
              _boleta,
              "N° BOLETA O FACTURA",
              Icons.receipt_long,
              e: true,
            ),
          _input(
            _val,
            "VALOR TOTAL \$",
            Icons.monetization_on,
            e: true,
            soloNumeros: true,
          ),
          const SizedBox(height: 30),
          _procesando
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: () async {
                    if (widget.esOrden &&
                        widget.docExistente == null &&
                        !_aceptaTerminos) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Debe aceptar términos")),
                      );
                      return;
                    }

                    setState(() => _procesando = true);

                    if (widget.esOrden && _sig.isNotEmpty) {
                      final b = await _sig.toPngBytes();
                      if (b != null) _firma = base64Encode(b);
                    }

                    Map<String, dynamic> data = {
                      'val': _val.text,
                      'num_documento': widget.esOrden ? _boleta.text : "",
                    };

                    if (editableCompleto) {
                      data.addAll({
                        'nombre': _n.text.toUpperCase(),
                        'rut': _r.text.toUpperCase(),
                        'tel': _t.text,
                        'dir': _d.text.toUpperCase(),
                        'comuna': _com.text.toUpperCase(),
                        'tipo_servicio': _tipo,
                        'patente': _pat.text.toUpperCase(),
                        'marca': _marca.text.toUpperCase(),
                        'modelo': _mod.text.toUpperCase(),
                        'anio': _anio.text,
                        'det': _det.text,
                        'foto_evidencia': _foto,
                        'firma': _firma,
                      });
                    }

                    try {
                      if (widget.docExistente == null) {
                        data['uid'] = FirebaseAuth.instance.currentUser!.uid;
                        data['fecha'] = DateTime.now();

                        await FirebaseFirestore.instance
                            .collection(
                                widget.esOrden ? 'ordenes' : 'presupuestos')
                            .add(data);

                        _limpiarFormulario();
                      } else {
                        await widget.docExistente!.reference.update(data);
                      }

                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Error: $e")),
                      );
                    } finally {
                      if (mounted) setState(() => _procesando = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                  ),
                  child:
                      Text(widget.docExistente == null ? "GUARDAR" : "ACTUALIZAR"),
                ),
        ],
      ),
    );
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 5),
      child: Text(
        texto,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blueAccent,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    String label,
    IconData icon, {
    int lines = 1,
    bool e = true,
    bool soloNumeros = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: e,
        maxLines: lines,
        keyboardType: soloNumeros ? TextInputType.number : TextInputType.text,
        inputFormatters: [
          if (soloNumeros) FilteringTextInputFormatter.digitsOnly,
          UpperCaseTextFormatter(),
        ],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

// HISTORIAL
class ListPage extends StatefulWidget {
  final String col;

  const ListPage({super.key, required this.col});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  final _searchController = TextEditingController();
  String _filtro = "";

  bool get _esAdmin => esUsuarioAdmin();

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance.collection(widget.col);

    if (!_esAdmin) {
      query = query.where(
        'uid',
        isEqualTo: FirebaseAuth.instance.currentUser!.uid,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.col.toUpperCase()),
        backgroundColor: _esAdmin ? Colors.redAccent : Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchController,
              onChanged: (v) {
                setState(() {
                  _filtro = v.toUpperCase().trim();
                });
              },
              decoration: const InputDecoration(
                labelText: "BUSCAR POR NOMBRE, RUT, PATENTE O DIRECCIÓN",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snap.data!.docs;

                if (_filtro.isNotEmpty) {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;

                    final nombre =
                        (data['nombre'] ?? "").toString().toUpperCase();
                    final rut =
                        (data['rut'] ?? "").toString().toUpperCase();
                    final patente =
                        (data['patente'] ?? "").toString().toUpperCase();
                    final direccion =
                        (data['dir'] ?? "").toString().toUpperCase();
                    final comuna =
                        (data['comuna'] ?? "").toString().toUpperCase();

                    return nombre.contains(_filtro) ||
                        rut.contains(_filtro) ||
                        patente.contains(_filtro) ||
                        direccion.contains(_filtro) ||
                        comuna.contains(_filtro);
                  }).toList();
                }

                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;

                  final fechaA = dataA['fecha'];
                  final fechaB = dataB['fecha'];

                  if (fechaA is Timestamp && fechaB is Timestamp) {
                    return fechaB.compareTo(fechaA);
                  }

                  return 0;
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Text("No se encontraron registros"),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data() as Map<String, dynamic>;

                    final nombre = data['nombre'] ?? "S/N";
                    final rut = data['rut'] ?? "";
                    final tipo = data['tipo_servicio'] ?? "";
                    final valor = data['val'] ?? "";

                    final esAuto = tipo == "AUTO";

                    final patente = data['patente'] ?? "";
                    final marca = data['marca'] ?? "";
                    final modelo = data['modelo'] ?? "";

                    final direccion = data['dir'] ?? "";
                    final comuna = data['comuna'] ?? "";

                    final icono = esAuto ? Icons.directions_car : Icons.home;
                    final color = esAuto ? Colors.blue : Colors.green;

                    final detalle = esAuto
                        ? "Vehículo\nPatente: $patente\nMarca/Modelo: $marca $modelo\nRUT: $rut\nValor: \$$valor"
                        : "Domicilio\nDirección: $direccion\nComuna: $comuna\nRUT: $rut\nValor: \$$valor";

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: Icon(icono, color: color, size: 34),
                        title: Text(
                          nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(detalle),
                        isThreeLine: false,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ViewPage(
                              doc: d,
                              col: widget.col,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// VISTA DETALLE Y PDF
class ViewPage extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final String col;

  const ViewPage({
    super.key,
    required this.doc,
    required this.col,
  });

  Future<void> _generarPdf(BuildContext context) async {
    final m = doc.data() as Map<String, dynamic>;
    final sDoc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(m['uid'])
        .get();

    final s = sDoc.exists ? sDoc.data()! : <String, dynamic>{};

    final pdf = pw.Document();

    pw.MemoryImage? imgApoderado;
    pw.MemoryImage? imgAce;

    try {
      final aceBytes = await rootBundle.load('assets/images/logo.png');
      imgAce = pw.MemoryImage(aceBytes.buffer.asUint8List());
    } catch (e) {
      debugPrint("Error logo ace: $e");
    }

    if (s['logo_apoderado'] != null) {
      try {
        imgApoderado = pw.MemoryImage(base64Decode(s['logo_apoderado']));
      } catch (e) {
        debugPrint("Error logo apoderado: $e");
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (imgApoderado != null)
                        pw.Image(imgApoderado, width: 80, height: 80),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        s['nombre_empresa'] ?? "EMPRESA",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      pw.Text('RUT: ${s['rut_empresa'] ?? ''}'),
                      pw.Text('TEL: ${s['telefono'] ?? ''}'),
                      pw.Text('DIR: ${s['direccion'] ?? ''}'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (imgAce != null) pw.Image(imgAce, width: 110),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        col == 'ordenes'
                            ? "ORDEN DE TRABAJO"
                            : "PRESUPUESTO",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 15),
              pw.Text(
                'DATOS DEL CLIENTE',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text('CLIENTE: ${m['nombre'] ?? ''}'),
              pw.Text('RUT: ${m['rut'] ?? ""}'),
              pw.Text('TEL: ${m['tel'] ?? ""}'),
              pw.Text('DIRECCIÓN: ${m['dir'] ?? ""}, ${m['comuna'] ?? ""}'),
              pw.SizedBox(height: 15),
              if (m['tipo_servicio'] == "AUTO") ...[
                pw.Text(
                  'DATOS DEL VEHÍCULO',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text('PATENTE: ${m['patente'] ?? ""}'),
                pw.Text('MARCA: ${m['marca'] ?? ""}'),
                pw.Text('MODELO: ${m['modelo'] ?? ""}'),
                pw.Text('AÑO: ${m['anio'] ?? ""}'),
                pw.SizedBox(height: 15),
              ],
              pw.Text(
                'DETALLE DEL SERVICIO:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(m['det'] ?? ""),
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                "DECLARACIÓN: El cliente acepta el trabajo realizado en las condiciones actuales y declara ser propietario o estar autorizado para la intervención de este bien, liberando al técnico de toda responsabilidad posterior.",
                style: pw.TextStyle(
                  fontSize: 8,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'FECHA: ${m['fecha'] is Timestamp ? DateFormat('dd/MM/yyyy').format(m['fecha'].toDate()) : ''}',
                  ),
                  pw.Text(
                    'TOTAL: \$${m['val'] ?? ''}',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (m['firma'] != null)
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.SizedBox(height: 10),
                      pw.Image(
                        pw.MemoryImage(base64Decode(m['firma'])),
                        width: 140,
                      ),
                      pw.Text(
                        "FIRMA CONFORMIDAD",
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Doc_${m['nombre'] ?? 'cliente'}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = doc.data() as Map<String, dynamic>;
    final esAdmin = esUsuarioAdmin();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Resumen"),
        backgroundColor: esAdmin ? Colors.redAccent : Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          if (esAdmin)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: () async {
                final borrar = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Eliminar Registro"),
                    content: Text(
                      "¿Seguro que desea borrar este ${col == 'ordenes' ? 'orden' : 'presupuesto'} permanentemente?",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("CANCELAR"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          "ELIMINAR",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );

                if (borrar == true) {
                  await doc.reference.delete();

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Registro eliminado correctamente"),
                      ),
                    );
                  }
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _generarPdf(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            m['nombre'] ?? "S/N",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          Text("TEL: ${m['tel'] ?? ''} | RUT: ${m['rut'] ?? ''}"),
          const Divider(),
          if (m['patente'] != null && m['patente'].toString().isNotEmpty)
            Text("PATENTE: ${m['patente']}"),
          if (m['marca'] != null && m['marca'].toString().isNotEmpty)
            Text("MARCA: ${m['marca']}"),
          if (m['modelo'] != null && m['modelo'].toString().isNotEmpty)
            Text("MODELO: ${m['modelo']}"),
          const SizedBox(height: 10),
          if (m['foto_evidencia'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(m['foto_evidencia']),
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 10),
          Text("DETALLE: ${m['det'] ?? ''}"),
          Text("VALOR: \$${m['val'] ?? ''}"),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FormPage(
                  esOrden: col == 'ordenes',
                  docExistente: doc,
                  soloCierre: !esAdmin,
                ),
              ),
            ),
            icon: Icon(esAdmin ? Icons.edit : Icons.payments),
            label: Text(
              esAdmin ? "EDITAR REGISTRO" : "ACTUALIZAR PAGO / DOC",
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => _generarPdf(context),
            icon: const Icon(Icons.share),
            label: const Text("COMPARTIR PDF"),
          ),
        ],
      ),
    );
  }
}
// Páginas temporales para que la beta compile sin los módulos antiguos de ACECHILE.
class AgregarApoderadoPage extends StatelessWidget {
  const AgregarApoderadoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar apoderado / usuario')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Módulo en preparación. Aquí se registrarán apoderados, usuarios y datos familiares.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class DocumentosPage extends StatelessWidget {
  const DocumentosPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documentos')),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEAF7FF), Color(0xFFF8FBFF), Color(0xFFFFFAF1)])),
        child: Center(child: Padding(
          padding: const EdgeInsets.all(26),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: const Color(0xFF0B4778).withOpacity(.12), blurRadius: 22, offset: const Offset(0, 10))]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/images/inicio.jpg', width: 92, height: 92, fit: BoxFit.contain),
              const SizedBox(height: 18),
              const Text('Tus documentos, en un solo lugar', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF083F72))),
              const SizedBox(height: 10),
              const Text('Este módulo quedará preparado para certificados, informes y archivos importantes de la familia.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF60798E))),
              const SizedBox(height: 18),
              Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: const Color(0xFFEAF7FF), borderRadius: BorderRadius.circular(99)), child: const Text('PRÓXIMA ETAPA', style: TextStyle(color: Color(0xFF0B69B7), fontWeight: FontWeight.w900, letterSpacing: .6))),
            ]),
          ),
        )),
      ),
    );
  }
}

class CrearDocumentoPage extends StatelessWidget {
  const CrearDocumentoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear documento')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Módulo de creación de documentos disponible para una siguiente etapa.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
