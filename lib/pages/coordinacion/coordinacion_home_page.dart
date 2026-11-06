import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auditoria_service.dart';

const Color _azul = Color(0xFF004193);
const Color _fondo = Color(0xFFEAF6FF);
const int valorMensualidadBase = 5000;
const int valorTerapiaDefault = 20000;
const int valorTallerDefault = 10000;

int _valorDefaultServicio(String tipo) {
  return tipo.toLowerCase().contains('taller') ? valorTallerDefault : valorTerapiaDefault;
}

String _limpiarRut(String v) {
  final limpio = v
      .trim()
      .replaceAll('.', '')
      .replaceAll('-', '')
      .replaceAll(' ', '')
      .toUpperCase();

  if (limpio.length < 2) return limpio;

  final cuerpo = limpio.substring(0, limpio.length - 1);
  final dv = limpio.substring(limpio.length - 1);
  return '$cuerpo-$dv';
}

List<String> _rolesUnicos(List<dynamic> actuales, String nuevoRol) {
  final roles = actuales
      .map((e) => e.toString().trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();
  roles.add(nuevoRol.trim().toLowerCase());
  return roles.toList()..sort();
}

Future<void> _upsertPerfilUsuario({
  required String uid,
  required String rol,
  required String nombre,
  required String email,
  required String rut,
  Map<String, dynamic> extra = const {},
}) async {
  final uidLimpio = _normalizarUid(uid);
  if (uidLimpio.isEmpty) return;

  final db = FirebaseFirestore.instance;
  final emailNorm = _normalizarEmail(email);
  final rutNorm = _limpiarRut(rut);
  final ref = db.collection('usuarios').doc(uidLimpio);

  // Evita duplicados: el documento principal de usuarios SIEMPRE debe ser usuarios/{uidAuth}.
  // Si antes existían documentos con ID aleatorio por el mismo correo/RUT, se marcan como fusionados
  // para que no sigan apareciendo como usuarios activos.
  Future<void> marcarDuplicados(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final d in snap.docs) {
      if (d.id == uidLimpio) continue;
      await d.reference.set({
        'activo': false,
        'duplicado': true,
        'fusionado_en': uidLimpio,
        'actualizado': FieldValue.serverTimestamp(),
        'actualizado_por': FirebaseAuth.instance.currentUser?.email,
      }, SetOptions(merge: true));
    }
  }

  if (emailNorm.isNotEmpty) {
    await marcarDuplicados(await db.collection('usuarios').where('email_normalizado', isEqualTo: emailNorm).get());
    await marcarDuplicados(await db.collection('usuarios').where('email', isEqualTo: emailNorm).get());
    await marcarDuplicados(await db.collection('usuarios').where('correo', isEqualTo: emailNorm).get());
    await marcarDuplicados(await db.collection('usuarios').where('correo electrónico', isEqualTo: emailNorm).get());
  }
  if (rutNorm.isNotEmpty) {
    await marcarDuplicados(await db.collection('usuarios').where('rut_normalizado', isEqualTo: rutNorm).get());
    await marcarDuplicados(await db.collection('usuarios').where('rut', isEqualTo: rutNorm).get());
  }

  final actual = await ref.get();
  final dataActual = actual.data() ?? {};
  final roles = _rolesUnicos((dataActual['roles'] as List?) ?? const [], rol);

  await ref.set({
    ...extra,
    'uid': uidLimpio,
    '${rol}_uid': uidLimpio,
    'nombre': nombre.trim(),
    'email': emailNorm,
    'email_normalizado': emailNorm,
    'correo': emailNorm,
    'correo electrónico': emailNorm,
    'rut': rutNorm,
    'rut_normalizado': rutNorm,
    'rol': rol,
    'roles': roles,
    'activo': true,
    'duplicado': false,
    'fusionado_en': FieldValue.delete(),
    'actualizado': FieldValue.serverTimestamp(),
    'actualizado_por': FirebaseAuth.instance.currentUser?.email,
    if (!actual.exists) 'creado': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

String _normalizarEmail(String v) {
  return v.trim().toLowerCase();
}

String _normalizarUid(String v) {
  return v.trim();
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.round();
  final limpio = v.toString()
      .replaceAll('.', '')
      .replaceAll(r'$', '')
      .replaceAll(',', '')
      .trim();
  return int.tryParse(limpio) ?? 0;
}

String _money(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final pos = s.length - i;
    b.write(s[i]);
    if (pos > 1 && pos % 3 == 1) b.write('.');
  }
  return '\$${b.toString()}';
}

class CoordinacionHomePage extends StatefulWidget {
  final int seccionInicial;
  final String tituloPanel;

  const CoordinacionHomePage({super.key, this.seccionInicial = 0, this.tituloPanel = 'Panel Coordinadora'});

  @override
  State<CoordinacionHomePage> createState() => _CoordinacionHomePageState();
}

class _CoordinacionHomePageState extends State<CoordinacionHomePage> {
  late int seccion;

  final rutUsuarioCtrl = TextEditingController();
  final nombreUsuarioCtrl = TextEditingController();
  final rutApoderadoVinculoCtrl = TextEditingController();
  final nombreApoderadoVinculoCtrl = TextEditingController();
  final telefonoApoderadoVinculoCtrl = TextEditingController();
  final emailApoderadoVinculoCtrl = TextEditingController();
  final uidApoderadoVinculoCtrl = TextEditingController();

  final rutApoderadoCtrl = TextEditingController();
  final nombreApoderadoCtrl = TextEditingController();
  final telefonoApoderadoCtrl = TextEditingController();
  final emailApoderadoCtrl = TextEditingController();
  final uidApoderadoCtrl = TextEditingController();

  final nombreProfesionalCtrl = TextEditingController();
  final especialidadProfesionalCtrl = TextEditingController();
  final correoProfesionalCtrl = TextEditingController();
  final uidProfesionalCtrl = TextEditingController();
  final rutProfesionalCtrl = TextEditingController();

  final nombreServicioCtrl = TextEditingController();
  final detalleServicioCtrl = TextEditingController();
  String tipoServicio = 'terapia';

  String? beneficiarioAsignarId;
  String? servicioAsignarId;
  String? profesionalAsignarId;

  final observacionAsignacionCtrl = TextEditingController();
  String diaAsignacion = 'Lunes';
  String horaAsignacion = '08:00';

  static const List<String> _horariosAsignacion = [
    '08:00',
    '09:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '13:15 - 14:15',
    '14:15 - 15:15',
    '15:15 - 16:15',
    '16:15 - 17:15',
    '17:15 - 18:15',
    '18:15 - 19:15',
    '19:15 - 20:15',
  ];

  bool guardandoBeneficiario = false;
  bool guardandoApoderado = false;
  bool guardandoProfesional = false;
  bool guardandoServicio = false;
  bool guardandoAsignacion = false;
  bool mostrarCrearBeneficiario = false;
  bool mostrarBeneficiariosRegistrados = false;

  @override
  void initState() {
    super.initState();
    seccion = widget.seccionInicial;
  }

  @override
  void dispose() {
    rutUsuarioCtrl.dispose();
    nombreUsuarioCtrl.dispose();
    rutApoderadoVinculoCtrl.dispose();
    nombreApoderadoVinculoCtrl.dispose();
    telefonoApoderadoVinculoCtrl.dispose();
    emailApoderadoVinculoCtrl.dispose();
    uidApoderadoVinculoCtrl.dispose();
    rutApoderadoCtrl.dispose();
    nombreApoderadoCtrl.dispose();
    telefonoApoderadoCtrl.dispose();
    emailApoderadoCtrl.dispose();
    uidApoderadoCtrl.dispose();
    nombreProfesionalCtrl.dispose();
    especialidadProfesionalCtrl.dispose();
    correoProfesionalCtrl.dispose();
    uidProfesionalCtrl.dispose();
    rutProfesionalCtrl.dispose();
    nombreServicioCtrl.dispose();
    detalleServicioCtrl.dispose();
    observacionAsignacionCtrl.dispose();
    super.dispose();
  }

  void _msg(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }


  String _primerCampo(Map<String, dynamic> data, List<String> campos) {
    for (final campo in campos) {
      final valor = data[campo];
      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString().trim();
      }
    }
    return '';
  }

  Future<String> _resolverUidProfesional(
    FirebaseFirestore db,
    String profesionalDocId,
    Map<String, dynamic> profesional,
  ) async {
    final directo = _normalizarUid(_primerCampo(profesional, const [
      'uid',
      'UID',
      'Uid',
      'profesional_uid',
      'uid_profesional',
      'auth_uid',
      'firebase_uid',
      'user_uid',
      'usuario_uid',
    ]));
    if (directo.isNotEmpty) return directo;

    final email = _normalizarEmail(_primerCampo(profesional, const [
      'email_normalizado',
      'email',
      'correo',
      'correo_normalizado',
    ]));
    if (email.isNotEmpty) {
      final porEmail = await db.collection('usuarios').where('email_normalizado', isEqualTo: email).limit(1).get();
      if (porEmail.docs.isNotEmpty) {
        return _normalizarUid(_primerCampo(porEmail.docs.first.data(), const ['uid', 'UID', 'auth_uid', 'firebase_uid', 'user_uid']));
      }
    }

    final rut = _limpiarRut(_primerCampo(profesional, const ['rut_normalizado', 'rut', 'RUT']));
    if (rut.isNotEmpty) {
      final porRut = await db.collection('usuarios').where('rut_normalizado', isEqualTo: rut).limit(1).get();
      if (porRut.docs.isNotEmpty) {
        return _normalizarUid(_primerCampo(porRut.docs.first.data(), const ['uid', 'UID', 'auth_uid', 'firebase_uid', 'user_uid']));
      }
    }

    // Compatibilidad: algunos profesionales fueron guardados con el UID como ID del documento.
    return _normalizarUid(profesionalDocId);
  }

  Future<String> _resolverUidApoderado(
    FirebaseFirestore db,
    Map<String, dynamic> beneficiario,
  ) async {
    final directo = _normalizarUid(_primerCampo(beneficiario, const [
      'apoderado_uid',
      'uid_apoderado',
      'UID_apoderado',
      'uid',
      'auth_uid_apoderado',
      'firebase_uid_apoderado',
      'user_uid_apoderado',
    ]));
    if (directo.isNotEmpty) return directo;

    final rutApoderado = _limpiarRut(_primerCampo(beneficiario, const [
      'rut_apoderado',
      'rut_apoderado_normalizado',
      'RUT_apoderado',
    ]));
    if (rutApoderado.isNotEmpty) {
      final apoderadoDoc = await db.collection('ar_apoderados').doc(rutApoderado).get();
      if (apoderadoDoc.exists) {
        final data = apoderadoDoc.data() ?? {};
        final uidApoderado = _normalizarUid(_primerCampo(data, const [
          'apoderado_uid',
          'uid_apoderado',
          'uid',
          'UID',
          'auth_uid',
          'firebase_uid',
          'user_uid',
        ]));
        if (uidApoderado.isNotEmpty) return uidApoderado;
      }

      final porRut = await db.collection('usuarios').where('rut_normalizado', isEqualTo: rutApoderado).limit(1).get();
      if (porRut.docs.isNotEmpty) {
        return _normalizarUid(_primerCampo(porRut.docs.first.data(), const ['uid', 'UID', 'auth_uid', 'firebase_uid', 'user_uid']));
      }
    }

    final email = _normalizarEmail(_primerCampo(beneficiario, const [
      'email_apoderado_normalizado',
      'email_apoderado',
      'correo_apoderado',
    ]));
    if (email.isNotEmpty) {
      final porEmail = await db.collection('usuarios').where('email_normalizado', isEqualTo: email).limit(1).get();
      if (porEmail.docs.isNotEmpty) {
        return _normalizarUid(_primerCampo(porEmail.docs.first.data(), const ['uid', 'UID', 'auth_uid', 'firebase_uid', 'user_uid']));
      }
    }

    return '';
  }

  Future<void> _crearBeneficiario() async {
    if (guardandoBeneficiario) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final rutUsuario = _limpiarRut(rutUsuarioCtrl.text);
    final nombreUsuario = nombreUsuarioCtrl.text.trim();
    final rutApoderado = _limpiarRut(rutApoderadoVinculoCtrl.text);
    final nombreApoderado = nombreApoderadoVinculoCtrl.text.trim();
    final uidApoderado = _normalizarUid(uidApoderadoVinculoCtrl.text);

    if (rutUsuario.isEmpty || nombreUsuario.isEmpty || rutApoderado.isEmpty || nombreApoderado.isEmpty || uidApoderado.isEmpty) {
      _msg('Completa RUT usuario, nombre usuario, RUT apoderado, nombre apoderado y UID del apoderado.');
      return;
    }

    final db = FirebaseFirestore.instance;
    final email = _normalizarEmail(emailApoderadoVinculoCtrl.text);
    final telefono = telefonoApoderadoVinculoCtrl.text.trim();

    setState(() => guardandoBeneficiario = true);
    try {
    await db.collection('ar_apoderados').doc(rutApoderado).set({
      'rut': rutApoderado,
      'rut_normalizado': rutApoderado,
      'uid': uidApoderado,
      'apoderado_uid': uidApoderado,
      'nombre': nombreApoderado,
      'telefono': telefono,
      'email': email,
      'email_normalizado': email,
      'activo': true,
      'actualizado': FieldValue.serverTimestamp(),
      'creado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _upsertPerfilUsuario(
      uid: uidApoderado,
      rol: 'apoderado',
      nombre: nombreApoderado,
      email: email,
      rut: rutApoderado,
      extra: {
        'telefono': telefono,
        'tipo_perfil': 'apoderado',
      },
    );

    await db.collection('ar_beneficiarios').doc(rutUsuario).set({
      'rut': rutUsuario,
      'rut_normalizado': rutUsuario,
      'nombre': nombreUsuario,
      'rut_apoderado': rutApoderado,
      'apoderado_uid': uidApoderado,
      'apoderados_uids_autorizados': [uidApoderado],
      'nombre_apoderado': nombreApoderado,
      'telefono_apoderado': telefono,
      'email_apoderado': email,
      'email_apoderado_normalizado': email,
      'estado': 'activo',
      'mensualidad_base': valorMensualidadBase,
      'cuenta_destino': 'CUENTA CORRIENTE',
      'actualizado': FieldValue.serverTimestamp(),
      'creado': FieldValue.serverTimestamp(),
      'creado_por': FirebaseAuth.instance.currentUser?.email,
    }, SetOptions(merge: true));

    // Compatibilidad con la tesorería actual: cada beneficiario queda visible como registro financiero.
    await db.collection('tesoreria_apoderados').doc(rutUsuario).set({
      'uid': rutUsuario,
      'rut_usuario': rutUsuario,
      'rut_usuario_normalizado': rutUsuario,
      'apoderado_uid': uidApoderado,
      'nombre_usuario': nombreUsuario,
      'nombre': nombreUsuario,
      'rut_apoderado': rutApoderado,
      'nombre_apoderado': nombreApoderado,
      'email': email,
      'email_normalizado': email,
      'telefono': telefono,
      'cuota_mensual': valorMensualidadBase,
      'monto_deuda': FieldValue.increment(valorMensualidadBase),
      'meses_morosos': 0,
      'estado_pago': 'pendiente',
      'estado_terapias': 'activo',
      'aviso_activo': true,
      'mensaje_aviso': 'Mantiene un cobro pendiente en Tesorería. El monto puede ser editado por Tesorería según la ficha definitiva.',
      'cuenta_destino': 'CUENTA CORRIENTE',
      'actualizado': FieldValue.serverTimestamp(),
      'fecha_creacion': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    rutUsuarioCtrl.clear();
    nombreUsuarioCtrl.clear();
    rutApoderadoVinculoCtrl.clear();
    nombreApoderadoVinculoCtrl.clear();
    telefonoApoderadoVinculoCtrl.clear();
    emailApoderadoVinculoCtrl.clear();
    uidApoderadoVinculoCtrl.clear();
    _msg('Beneficiario creado.');
    } catch (e) {
      _msg('No se pudo guardar el beneficiario: $e');
    } finally {
      if (mounted) setState(() => guardandoBeneficiario = false);
    }
  }

  Future<void> _crearApoderado() async {
    if (guardandoApoderado) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final rut = _limpiarRut(rutApoderadoCtrl.text);
    final nombre = nombreApoderadoCtrl.text.trim();
    final uid = _normalizarUid(uidApoderadoCtrl.text);
    final email = _normalizarEmail(emailApoderadoCtrl.text);
    if (rut.isEmpty || nombre.isEmpty || uid.isEmpty) {
      _msg('Completa RUT, nombre y UID del apoderado.');
      return;
    }
    setState(() => guardandoApoderado = true);
    try {
    await FirebaseFirestore.instance.collection('ar_apoderados').doc(rut).set({
      'rut': rut,
      'rut_normalizado': rut,
      'uid': uid,
      'apoderado_uid': uid,
      'nombre': nombre,
      'telefono': telefonoApoderadoCtrl.text.trim(),
      'email': email,
      'email_normalizado': email,
      'activo': true,
      'actualizado': FieldValue.serverTimestamp(),
      'creado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _upsertPerfilUsuario(
      uid: uid,
      rol: 'apoderado',
      nombre: nombre,
      email: email,
      rut: rut,
      extra: {
        'telefono': telefonoApoderadoCtrl.text.trim(),
        'tipo_perfil': 'apoderado',
      },
    );

    final nombreAudit = nombre;
    if (!mounted) return;
    rutApoderadoCtrl.clear();
    nombreApoderadoCtrl.clear();
    telefonoApoderadoCtrl.clear();
    emailApoderadoCtrl.clear();
    uidApoderadoCtrl.clear();
    await AuditoriaService.registrar(modulo: 'Coordinación', accion: 'Crear/editar apoderado', coleccion: 'ar_apoderados', documentoId: rut, detalle: nombreAudit);
    _msg('Apoderado guardado.');
    } catch (e) {
      _msg('No se pudo guardar el apoderado: $e');
    } finally {
      if (mounted) setState(() => guardandoApoderado = false);
    }
  }

  Future<void> _crearProfesional() async {
    if (guardandoProfesional) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final nombre = nombreProfesionalCtrl.text.trim();
    final especialidad = especialidadProfesionalCtrl.text.trim();
    final email = _normalizarEmail(correoProfesionalCtrl.text);
    final uid = _normalizarUid(uidProfesionalCtrl.text);
    final rut = _limpiarRut(rutProfesionalCtrl.text);
    if (nombre.isEmpty || uid.isEmpty || email.isEmpty) {
      _msg('Ingresa nombre, UID y correo del profesional.');
      return;
    }

    setState(() => guardandoProfesional = true);
    try {
      await FirebaseFirestore.instance.collection('ar_profesionales').doc(uid).set({
        'uid': uid,
        'profesional_uid': uid,
        'rut': rut,
        'rut_normalizado': rut,
        'nombre': nombre,
        'especialidad': especialidad,
        'email': email,
        'email_normalizado': email,
        'correo': email,
        'correo electrónico': email,
        'activo': true,
        'actualizado': FieldValue.serverTimestamp(),
        'creado': FieldValue.serverTimestamp(),
        'creado_por': FirebaseAuth.instance.currentUser?.email,
      }, SetOptions(merge: true));

      await _upsertPerfilUsuario(
        uid: uid,
        rol: 'profesional',
        nombre: nombre,
        email: email,
        rut: rut,
        extra: {
          'especialidad': especialidad,
          'tipo_perfil': 'profesional',
        },
      );
      if (!mounted) return;
      nombreProfesionalCtrl.clear();
      especialidadProfesionalCtrl.clear();
      correoProfesionalCtrl.clear();
      uidProfesionalCtrl.clear();
      rutProfesionalCtrl.clear();
      _msg('Profesional guardado.');
    } catch (e) {
      _msg('No se pudo guardar el profesional: $e');
    } finally {
      if (mounted) setState(() => guardandoProfesional = false);
    }
  }

  Future<void> _crearServicio() async {
    if (guardandoServicio) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final nombre = nombreServicioCtrl.text.trim();
    if (nombre.isEmpty) {
      _msg('Completa el nombre de la terapia o taller.');
      return;
    }
    setState(() => guardandoServicio = true);
    try {
    await FirebaseFirestore.instance.collection('ar_servicios_mensuales').add({
      'nombre': nombre,
      'tipo': tipoServicio,
      'detalle': detalleServicioCtrl.text.trim(),
      'activo': true,
      'creado': FieldValue.serverTimestamp(),
      'creado_por': FirebaseAuth.instance.currentUser?.email,
      'valor_default': _valorDefaultServicio(tipoServicio),
      'valor_editable_tesoreria': false,
      'nota': 'Valor oficial: terapia \$20.000 / taller \$10.000.',
    });
    final nombreAudit = nombre;
    if (!mounted) return;
    nombreServicioCtrl.clear();
    detalleServicioCtrl.clear();
    await AuditoriaService.registrar(modulo: 'Coordinación', accion: 'Crear terapia/taller con valor base referencial', coleccion: 'ar_servicios_mensuales', documentoId: nombreAudit, detalle: tipoServicio);
    _msg('Terapia/taller creado con el valor oficial correspondiente.');
    } catch (e) {
      _msg('No se pudo crear terapia/taller: $e');
    } finally {
      if (mounted) setState(() => guardandoServicio = false);
    }
  }

  Future<void> _asignarServicio() async {
    if (guardandoAsignacion) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (beneficiarioAsignarId == null || servicioAsignarId == null || profesionalAsignarId == null) {
      _msg('Selecciona beneficiario, terapia/taller y profesional.');
      return;
    }

    final db = FirebaseFirestore.instance;
    setState(() => guardandoAsignacion = true);
    try {
    final beneficiarioSnap = await db.collection('ar_beneficiarios').doc(beneficiarioAsignarId).get();
    final servicioSnap = await db.collection('ar_servicios_mensuales').doc(servicioAsignarId).get();
    final profesionalSnap = await db.collection('ar_profesionales').doc(profesionalAsignarId).get();

    if (!beneficiarioSnap.exists || !servicioSnap.exists || !profesionalSnap.exists) {
      _msg('No se encontró beneficiario, terapia/taller o profesional seleccionado.');
      return;
    }

    final beneficiario = beneficiarioSnap.data()!;
    final servicio = servicioSnap.data()!;
    final profesional = profesionalSnap.data()!;
    final tipo = (servicio['tipo'] ?? 'terapia').toString();
    final servicioNombre = (servicio['nombre'] ?? '').toString();
    final beneficiarioNombre = (beneficiario['nombre'] ?? '').toString();
    final apoderadoNombre = (beneficiario['nombre_apoderado'] ?? '').toString();
    final profesionalNombre = (profesional['nombre'] ?? '').toString();
    final profesionalEmail = _normalizarEmail((profesional['email_normalizado'] ?? profesional['email'] ?? '').toString());
    final profesionalUid = await _resolverUidProfesional(db, profesionalAsignarId!, profesional);
    final valorBase = _valorDefaultServicio(tipo);
    final tipoCobroTexto = tipo == 'taller' ? 'taller' : 'terapia';
    final emailApoderado = _normalizarEmail((beneficiario['email_apoderado_normalizado'] ?? beneficiario['email_apoderado'] ?? '').toString());
    final apoderadoUid = await _resolverUidApoderado(db, beneficiario);
    final accesoApoderados = <String>{apoderadoUid};
    final apoyosAutorizados = beneficiario['apoyos_autorizados'];
    if (apoyosAutorizados is List) {
      for (final apoyo in apoyosAutorizados) {
        if (apoyo is Map) {
          final uidApoyo = _normalizarUid((apoyo['uid'] ?? apoyo['apoyo_uid'] ?? '').toString());
          if (uidApoyo.isNotEmpty) accesoApoderados.add(uidApoyo);
        }
      }
    }

    if (profesionalUid.isEmpty || apoderadoUid.isEmpty) {
      _msg('No se pudo resolver el UID. Revisa que el profesional tenga UID o correo, y que el beneficiario tenga apoderado_uid, RUT o correo del apoderado.');
      return;
    }

    final asignacionPayload = <String, dynamic>{
      'beneficiario_id': beneficiarioAsignarId,
      'beneficiario_nombre': beneficiarioNombre,
      'rut_beneficiario': beneficiarioAsignarId,
      'rut_apoderado': beneficiario['rut_apoderado'],
      'apoderado_uid': apoderadoUid,
      'apoderados_uids_autorizados': accesoApoderados.toList(),
      'nombre_apoderado': apoderadoNombre,
      'servicio_id': servicioAsignarId,
      'servicio_nombre': servicioNombre,
      'terapia': servicioNombre,
      'tipo': tipo,
      'profesional_id': profesionalAsignarId,
      'profesional_uid': profesionalUid,
      'profesional_nombre': profesionalNombre,
      'profesional_email': profesionalEmail,
      'email_profesional_normalizado': profesionalEmail,
      'email_apoderado': emailApoderado,
      'email_apoderado_normalizado': emailApoderado,
      'telefono_apoderado': beneficiario['telefono_apoderado'],
      'estado': 'activa',
      'dia': diaAsignacion,
      'hora': horaAsignacion,
      'horario': horaAsignacion,
      'clave_sesion': '$beneficiarioAsignarId|$servicioAsignarId|$profesionalAsignarId|$diaAsignacion|$horaAsignacion',
      'sesion_independiente': true,
      'observacion': observacionAsignacionCtrl.text.trim(),
      'valor_base': valorBase,
      'valor_definitivo': valorBase,
      'valor_editable_tesoreria': false,
      'nota_valor': 'Valor oficial automático: terapia \$20.000 / taller \$10.000.',
      'actualizado': FieldValue.serverTimestamp(),
      'actualizado_por': FirebaseAuth.instance.currentUser?.email,
    };

    QueryDocumentSnapshot<Map<String, dynamic>>? existente;
    final posibles = await db
        .collection('ar_asignaciones_mensuales')
        .where('beneficiario_id', isEqualTo: beneficiarioAsignarId)
        .get();
    for (final d in posibles.docs) {
      final m = d.data();
      final mismoServicio = (m['servicio_id'] ?? '').toString() == servicioAsignarId;
      final mismoProfesional = (m['profesional_id'] ?? '').toString() == profesionalAsignarId;
      final mismoDia = (m['dia'] ?? '').toString() == diaAsignacion;
      final mismoHorario = ((m['hora'] ?? m['horario'] ?? '').toString()) == horaAsignacion;
      final estado = (m['estado'] ?? 'activa').toString().toLowerCase();
      // Se actualiza solo si coincide la misma sesión exacta.
      // Esto permite segunda/tercera hora semanal con el mismo terapeuta sin pisar la primera.
      if (mismoServicio && mismoProfesional && mismoDia && mismoHorario && estado != 'eliminada' && estado != 'inactiva') {
        existente = d;
        break;
      }
    }

    late final DocumentReference<Map<String, dynamic>> asignacionRef;
    var creoNuevaAsignacion = false;
    if (existente != null) {
      asignacionRef = db.collection('ar_asignaciones_mensuales').doc(existente.id);
      await asignacionRef.update({
        ...asignacionPayload,
        'editado_sin_cobro_extra': true,
        'motivo_actualizacion': 'Actualización de horario/asignación existente desde Coordinación',
      });
    } else {
      asignacionRef = await db.collection('ar_asignaciones_mensuales').add({
        ...asignacionPayload,
        'creado': FieldValue.serverTimestamp(),
        'creado_por': FirebaseAuth.instance.currentUser?.email,
      });
      creoNuevaAsignacion = true;
    }

    final tesoreriaPayload = <String, dynamic>{
      'uid': beneficiarioAsignarId,
      'rut_usuario': beneficiarioAsignarId,
      'nombre_usuario': beneficiarioNombre,
      'nombre': beneficiarioNombre,
      'rut_apoderado': beneficiario['rut_apoderado'],
      'apoderado_uid': apoderadoUid,
      'apoderados_uids_autorizados': accesoApoderados.toList(),
      'nombre_apoderado': apoderadoNombre,
      'email': emailApoderado,
      'telefono': beneficiario['telefono_apoderado'],
      'estado_pago': 'pendiente',
      'estado_terapias': 'activo',
      'aviso_activo': true,
      'mensaje_aviso': 'Mantiene pendiente $tipoCobroTexto: $servicioNombre.',
      'ultima_asignacion_profesional_id': asignacionRef.id,
      'actualizado': FieldValue.serverTimestamp(),
      'fecha_creacion': FieldValue.serverTimestamp(),
    };

    // Reflejo para Tesorería: solo una asignación nueva genera incremento.
    // Si se actualiza horario/perfil/asignación existente, NO se suma un nuevo cobro.
    if (creoNuevaAsignacion) {
      tesoreriaPayload['cuota_mensual'] = FieldValue.increment(valorBase);
      tesoreriaPayload['monto_deuda'] = FieldValue.increment(valorBase);
    } else {
      tesoreriaPayload['ultima_edicion_asignacion_sin_cobro_extra'] = FieldValue.serverTimestamp();
    }
    await db.collection('tesoreria_apoderados').doc(beneficiarioAsignarId).set(tesoreriaPayload, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      servicioAsignarId = null;
      profesionalAsignarId = null;
      diaAsignacion = 'Lunes';
      horaAsignacion = '08:00';
      observacionAsignacionCtrl.clear();
    });
    await AuditoriaService.registrar(modulo: 'Coordinación', accion: creoNuevaAsignacion ? 'Asignar beneficiario a profesional con valor base para Tesorería' : 'Actualizar asignación existente sin cobro extra', coleccion: 'ar_asignaciones_mensuales', documentoId: asignacionRef.id, detalle: 'Beneficiario: $beneficiarioNombre / Profesional: $profesionalNombre');
    _msg(creoNuevaAsignacion ? 'Asignación creada con el valor oficial correspondiente.' : 'Asignación actualizada en Firebase sin duplicar ni sumar cobro en Tesorería.');
    } catch (e) {
      _msg('No se pudo crear la asignación: $e');
    } finally {
      if (mounted) setState(() => guardandoAsignacion = false);
    }
  }

  Widget _chip(int i, String texto, IconData icono) {
    final activo = seccion == i;
    final colores = <Color>[
      const Color(0xFFDDF2FF),
      const Color(0xFFFFE3EC),
      const Color(0xFFEDE3FF),
      const Color(0xFFDCF8EE),
      const Color(0xFFFFF0C9),
    ];
    final iconColors = <Color>[
      const Color(0xFF168DE2),
      const Color(0xFFE91E63),
      const Color(0xFF6A4BC3),
      const Color(0xFF00A884),
      const Color(0xFFE29A16),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        seccion = i;
        if (i != 0) {
          mostrarCrearBeneficiario = false;
          mostrarBeneficiariosRegistrados = false;
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 166,
        margin: const EdgeInsets.only(right: 10, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: colores[i],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: activo ? iconColors[i] : Colors.white, width: activo ? 2 : 1),
          boxShadow: [BoxShadow(color: iconColors[i].withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Icon(icono, color: iconColors[i], size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: const TextStyle(color: _azul, fontWeight: FontWeight.w900, fontSize: 14))),
            Icon(Icons.chevron_right, color: iconColors[i]),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _campo(TextEditingController c, String hint, IconData icono, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          prefixIcon: Icon(icono),
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF7FAFF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _titulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        t,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF063E83)),
      ),
    );
  }

  Widget _beneficiarios() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _accionBeneficiario(
                titulo: 'Crear beneficiario / usuario',
                icono: Icons.person_add_alt_1,
                color: _azul,
                fondo: const Color(0xFFE4F2FF),
                onTap: () => setState(() {
                  mostrarCrearBeneficiario = !mostrarCrearBeneficiario;
                  mostrarBeneficiariosRegistrados = false;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FutureBuilder<int>(
                future: _contarCoordinacion('ar_beneficiarios'),
                builder: (context, snap) => _accionBeneficiario(
                  titulo: 'Beneficiarios registrados${snap.hasData ? ' (${snap.data})' : ''}',
                  icono: Icons.groups,
                  color: const Color(0xFF0B559F),
                  fondo: Colors.white,
                  onTap: () => setState(() {
                    mostrarBeneficiariosRegistrados = !mostrarBeneficiariosRegistrados;
                    mostrarCrearBeneficiario = false;
                  }),
                ),
              ),
            ),
          ],
        ),
        if (mostrarCrearBeneficiario)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titulo('Crear beneficiario / usuario'),
                const Text(
                  'El beneficiario será el centro del sistema. Esta ficha permite vincular usuario y apoderado para los módulos internos.',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF46627A)),
                ),
                const SizedBox(height: 12),
                _campo(rutUsuarioCtrl, 'RUT usuario / beneficiario', Icons.badge),
                _campo(nombreUsuarioCtrl, 'Nombre usuario / beneficiario', Icons.person),
                _campo(rutApoderadoVinculoCtrl, 'RUT apoderado principal', Icons.assignment_ind),
                _campo(nombreApoderadoVinculoCtrl, 'Nombre apoderado principal', Icons.groups),
                _campo(telefonoApoderadoVinculoCtrl, 'Teléfono apoderado', Icons.phone, keyboard: TextInputType.phone),
                _campo(emailApoderadoVinculoCtrl, 'Correo apoderado', Icons.email, keyboard: TextInputType.emailAddress),
                _campo(uidApoderadoVinculoCtrl, 'UID Firebase del apoderado', Icons.key),
                ElevatedButton.icon(
                  onPressed: guardandoBeneficiario ? null : _crearBeneficiario,
                  icon: const Icon(Icons.save),
                  label: Text(guardandoBeneficiario ? 'Guardando...' : 'Guardar beneficiario'),
                  style: ElevatedButton.styleFrom(backgroundColor: _azul, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        if (mostrarBeneficiariosRegistrados)
          _lista('ar_beneficiarios', 'Beneficiarios registrados', Icons.groups),
      ],
    );
  }

  Widget _accionBeneficiario({required String titulo, required IconData icono, required Color color, required Color fondo, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withOpacity(0.12)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, color: color, size: 30),
            const SizedBox(height: 8),
            Row(children: [Expanded(child: Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16))), Icon(Icons.chevron_right, color: color)]),
          ],
        ),
      ),
    );
  }

  Widget _apoderados() {
    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titulo('Crear apoderado'),
              _campo(rutApoderadoCtrl, 'RUT apoderado', Icons.badge),
              _campo(nombreApoderadoCtrl, 'Nombre apoderado', Icons.person),
              _campo(telefonoApoderadoCtrl, 'Teléfono', Icons.phone, keyboard: TextInputType.phone),
              _campo(emailApoderadoCtrl, 'Correo', Icons.email, keyboard: TextInputType.emailAddress),
              _campo(uidApoderadoCtrl, 'UID Firebase del apoderado', Icons.key),
              ElevatedButton.icon(
                onPressed: guardandoApoderado ? null : _crearApoderado,
                icon: const Icon(Icons.save),
                label: Text(guardandoApoderado ? 'Guardando...' : 'Guardar apoderado'),
                style: ElevatedButton.styleFrom(backgroundColor: _azul, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        _lista('ar_apoderados', 'Apoderados registrados', Icons.groups),
      ],
    );
  }

  Widget _profesionales() {
    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titulo('Crear profesional'),
              _campo(nombreProfesionalCtrl, 'Nombre profesional', Icons.person),
              _campo(especialidadProfesionalCtrl, 'Especialidad: fonoaudiología, TO, psicología...', Icons.medical_services),
              _campo(correoProfesionalCtrl, 'Correo profesional', Icons.email, keyboard: TextInputType.emailAddress),
              _campo(uidProfesionalCtrl, 'UID Firebase del profesional', Icons.key),
              _campo(rutProfesionalCtrl, 'RUT profesional (opcional)', Icons.badge),
              ElevatedButton.icon(
                onPressed: guardandoProfesional ? null : _crearProfesional,
                icon: const Icon(Icons.save),
                label: Text(guardandoProfesional ? 'Guardando...' : 'Guardar profesional'),
                style: ElevatedButton.styleFrom(backgroundColor: _azul, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        _lista('ar_profesionales', 'Profesionales registrados', Icons.psychology_alt),
      ],
    );
  }

  Widget _servicios() {
    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titulo('Crear terapia / taller'),
              DropdownButtonFormField<String>(
                value: tipoServicio,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF7FAFF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                items: const [
                  DropdownMenuItem(value: 'terapia', child: Text('Terapia / Profesional')),
                  DropdownMenuItem(value: 'taller', child: Text('Taller')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => tipoServicio = v);
                },
              ),
              const SizedBox(height: 12),
              _campo(nombreServicioCtrl, 'Nombre del taller o terapia', Icons.title),
              _campo(detalleServicioCtrl, 'Profesionales y detalles', Icons.notes),
              ElevatedButton.icon(
                onPressed: guardandoServicio ? null : _crearServicio,
                icon: const Icon(Icons.add),
                label: Text(guardandoServicio ? 'Guardando...' : 'Crear servicio mensual'),
                style: ElevatedButton.styleFrom(backgroundColor: _azul, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        _lista('ar_servicios_mensuales', 'Servicios mensuales creados', Icons.add_business),
      ],
    );
  }

  Widget _asignaciones() {
    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titulo('Asignar usuario a profesional'),
              const Text(
                'La encargada asigna usuario, terapia/taller, profesional, día y horario. La encargada no edita montos. Tesorería recibe valor base automático: terapia \$20.000 / taller \$10.000, editable desde Tesorería.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF46627A)),
              ),
              const SizedBox(height: 12),
              _selectorDoc(
                coleccion: 'ar_beneficiarios',
                value: beneficiarioAsignarId,
                hint: 'Seleccionar usuario por nombre o RUT',
                icono: Icons.person,
                onChanged: (v) => setState(() => beneficiarioAsignarId = v),
              ),
              _selectorDoc(
                coleccion: 'ar_servicios_mensuales',
                value: servicioAsignarId,
                hint: 'Seleccionar terapia o taller por nombre',
                icono: Icons.add_business,
                onChanged: (v) => setState(() => servicioAsignarId = v),
              ),
              _selectorDoc(
                coleccion: 'ar_profesionales',
                value: profesionalAsignarId,
                hint: 'Seleccionar profesional por nombre',
                icono: Icons.psychology_alt,
                onChanged: (v) => setState(() => profesionalAsignarId = v),
                permitirVacio: true,
              ),
              Row(
                children: [
                  Expanded(
                    child: _dropdownSimple(
                      valor: diaAsignacion,
                      valores: const ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'],
                      icono: Icons.calendar_today,
                      onChanged: (v) => setState(() => diaAsignacion = v ?? 'Lunes'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _dropdownSimple(
                      valor: horaAsignacion,
                      valores: _horariosAsignacion,
                      icono: Icons.schedule,
                      onChanged: (v) => setState(() => horaAsignacion = v ?? '08:00'),
                    ),
                  ),
                ],
              ),
              _campo(observacionAsignacionCtrl, 'Observaciones internas', Icons.notes),
              ElevatedButton.icon(
                onPressed: guardandoAsignacion ? null : _asignarServicio,
                icon: const Icon(Icons.link),
                label: Text(guardandoAsignacion ? 'Asignando...' : 'Asignar profesional'),
                style: ElevatedButton.styleFrom(backgroundColor: _azul, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
        _lista('ar_asignaciones_mensuales', 'Asignaciones activas', Icons.link),
      ],
    );
  }


  Widget _dropdownSimple({
    required String valor,
    required List<String> valores,
    required IconData icono,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: valor,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: Icon(icono),
          filled: true,
          fillColor: const Color(0xFFF7FAFF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        items: valores.map((v) => DropdownMenuItem<String>(value: v, child: Text(v))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _selectorDoc({
    required String coleccion,
    required String? value,
    required String hint,
    required IconData icono,
    required ValueChanged<String?> onChanged,
    bool permitirVacio = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection(coleccion).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          String texto = hint;
          if (value != null) {
            for (final d in docs) {
              if (d.id == value) {
                final data = d.data() as Map<String, dynamic>;
                texto = _nombreDocumento(d, data);
                break;
              }
            }
          }
          return InkWell(
            onTap: () => _abrirBuscadorDocs(
              coleccion: coleccion,
              titulo: hint,
              docs: docs,
              permitirVacio: permitirVacio,
              onChanged: onChanged,
            ),
            child: InputDecorator(
              decoration: InputDecoration(
                prefixIcon: Icon(icono),
                suffixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF7FAFF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                texto,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: value == null ? FontWeight.w500 : FontWeight.w900,
                  color: value == null ? Colors.black54 : Colors.black87,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _abrirBuscadorDocs({
    required String coleccion,
    required String titulo,
    required List<QueryDocumentSnapshot> docs,
    required ValueChanged<String?> onChanged,
    bool permitirVacio = false,
  }) async {
    final buscarCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = buscarCtrl.text.trim().toLowerCase();
            final filtrados = docs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final texto = '${_nombreDocumento(d, data)} ${data['rut'] ?? ''} ${data['especialidad'] ?? ''} ${data['detalle'] ?? ''}'.toLowerCase();
              return q.isEmpty || texto.contains(q);
            }).toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _azul)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: buscarCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Buscar por nombre o RUT',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (permitirVacio)
                      ListTile(
                        leading: const Icon(Icons.block),
                        title: const Text('Sin profesional'),
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          onChanged(null);
                          Navigator.of(ctx).pop();
                        },
                      ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtrados.length,
                        itemBuilder: (ctx, i) {
                          final d = filtrados[i];
                          final data = d.data() as Map<String, dynamic>;
                          return ListTile(
                            leading: const CircleAvatar(backgroundColor: _azul, foregroundColor: Colors.white, child: Icon(Icons.check)),
                            title: Text(_nombreDocumento(d, data), style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(_detalle(data), maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              onChanged(d.id);
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    buscarCtrl.dispose();
  }

  String _nombreDocumento(QueryDocumentSnapshot d, Map<String, dynamic> data) {
    final nombre = (data['nombre'] ?? data['servicio_nombre'] ?? data['beneficiario_nombre'] ?? d.id).toString();
    if (data['rut'] != null && data['rut'].toString().isNotEmpty) return '$nombre - RUT ${data['rut']}';
    if (data['tipo'] != null) return '$nombre - ${data['tipo']}';
    return nombre;
  }

  Widget _dropdownDocs({
    required String coleccion,
    required String? value,
    required String hint,
    required IconData icono,
    required ValueChanged<String?> onChanged,
    bool permitirVacio = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection(coleccion).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          final ids = docs.map((e) => e.id).toSet();
          final safeValue = value != null && ids.contains(value) ? value : null;
          return DropdownButtonFormField<String>(
            value: safeValue,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon: Icon(icono),
              filled: true,
              fillColor: const Color(0xFFF7FAFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            hint: Text(hint),
            items: [
              if (permitirVacio) const DropdownMenuItem<String>(value: null, child: Text('Sin profesional')),
              ...docs.map((d) {
                final data = d.data() as Map<String, dynamic>;
                final nombre = (data['nombre'] ?? data['servicio_nombre'] ?? data['beneficiario_nombre'] ?? d.id).toString();
                final subtitulo = data['tipo'] != null ? ' - ${data['tipo']}' : '';
                return DropdownMenuItem<String>(
                  value: d.id,
                  child: Text('$nombre$subtitulo', overflow: TextOverflow.ellipsis),
                );
              }),
            ],
            onChanged: onChanged,
          );
        },
      ),
    );
  }



  List<String> _camposEditables(String coleccion, Map<String, dynamic> data) {
    switch (coleccion) {
      case 'ar_beneficiarios':
        return ['nombre', 'rut_apoderado', 'apoderado_uid', 'nombre_apoderado', 'telefono_apoderado', 'email_apoderado'];
      case 'ar_apoderados':
        return ['nombre', 'rut', 'uid', 'telefono', 'email'];
      case 'ar_profesionales':
        return ['nombre', 'rut', 'uid', 'especialidad', 'email'];
      case 'ar_servicios_mensuales':
        return ['nombre', 'tipo', 'detalle'];
      case 'ar_asignaciones_mensuales':
        return [
          'beneficiario_nombre',
          'nombre_apoderado',
          'email_apoderado',
          'apoderado_uid',
          'profesional_nombre',
          'profesional_email',
          'profesional_uid',
          'terapia',
          'servicio_nombre',
          'dia',
          'hora',
          'observacion',
          'estado',
        ];
      default:
        return data.keys.where((k) {
          final v = data[k];
          return v is String || v is int || v is double || v is bool;
        }).take(8).toList();
    }
  }

  Future<void> _editarRegistroGenerico(String coleccion, DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final campos = _camposEditables(coleccion, data);
    if (campos.isEmpty) {
      _msg('Este registro no tiene campos editables desde este panel.');
      return;
    }
    final ctrls = <String, TextEditingController>{
      for (final c in campos) c: TextEditingController(text: (data[c] ?? '').toString()),
    };

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar registro'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: campos.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctrls[c],
                    decoration: InputDecoration(
                      labelText: c,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (guardar != true) return;

    final cambios = <String, dynamic>{};
    for (final c in campos) {
      var valor = ctrls[c]!.text.trim();
      final lc = c.toLowerCase();
      if (lc.contains('email') || lc.contains('correo')) valor = _normalizarEmail(valor);
      if (lc.contains('rut')) valor = _limpiarRut(valor);
      if (lc == 'uid' || lc.endsWith('_uid')) valor = _normalizarUid(valor);
      cambios[c] = valor;
      if (lc == 'email' || lc == 'correo' || lc == 'correo electrónico') {
        cambios['email'] = valor;
        cambios['email_normalizado'] = valor;
        cambios['correo'] = valor;
        cambios['correo electrónico'] = valor;
      }
      if (lc == 'email_apoderado') cambios['email_apoderado_normalizado'] = valor;
      if (lc == 'profesional_email') cambios['email_profesional_normalizado'] = valor;
      if (lc == 'rut') cambios['rut_normalizado'] = valor;
      if (lc == 'uid') {
        cambios['apoderado_uid'] = valor;
        cambios['profesional_uid'] = valor;
      }
    }
    if (coleccion == 'ar_asignaciones_mensuales' && cambios.containsKey('hora')) {
      cambios['horario'] = cambios['hora'];
      cambios['editado_sin_cobro_extra'] = true;
      cambios['nota_edicion'] = 'Horario editado sobre la misma asignación. No genera cobro adicional en Tesorería.';
    }
    cambios['actualizado'] = FieldValue.serverTimestamp();
    cambios['actualizado_por'] = FirebaseAuth.instance.currentUser?.email;

    try {
      final db = FirebaseFirestore.instance;
      await db.collection(coleccion).doc(doc.id).update(cambios);

      if (coleccion == 'ar_profesionales') {
        final uid = _normalizarUid((cambios['uid'] ?? data['uid'] ?? data['profesional_uid'] ?? doc.id).toString());
        await _upsertPerfilUsuario(
          uid: uid,
          rol: 'profesional',
          nombre: (cambios['nombre'] ?? data['nombre'] ?? '').toString(),
          email: (cambios['email'] ?? data['email'] ?? data['email_normalizado'] ?? '').toString(),
          rut: (cambios['rut'] ?? data['rut'] ?? '').toString(),
          extra: {
            'especialidad': (cambios['especialidad'] ?? data['especialidad'] ?? '').toString(),
            'tipo_perfil': 'profesional',
          },
        );
      }

      if (coleccion == 'ar_apoderados') {
        final uid = _normalizarUid((cambios['uid'] ?? data['uid'] ?? data['apoderado_uid'] ?? doc.id).toString());
        await _upsertPerfilUsuario(
          uid: uid,
          rol: 'apoderado',
          nombre: (cambios['nombre'] ?? data['nombre'] ?? '').toString(),
          email: (cambios['email'] ?? data['email'] ?? data['email_normalizado'] ?? '').toString(),
          rut: (cambios['rut'] ?? data['rut'] ?? '').toString(),
          extra: {
            'telefono': (cambios['telefono'] ?? data['telefono'] ?? '').toString(),
            'tipo_perfil': 'apoderado',
          },
        );
      }


      if (coleccion == 'ar_beneficiarios') {
        final nombre = (cambios['nombre'] ?? data['nombre'] ?? '').toString();
        final rutApoderado = (cambios['rut_apoderado'] ?? data['rut_apoderado'] ?? '').toString();
        final apoderadoUid = _normalizarUid((cambios['apoderado_uid'] ?? data['apoderado_uid'] ?? '').toString());
        final nombreApoderado = (cambios['nombre_apoderado'] ?? data['nombre_apoderado'] ?? '').toString();
        final telefono = (cambios['telefono_apoderado'] ?? data['telefono_apoderado'] ?? '').toString();
        final email = _normalizarEmail((cambios['email_apoderado'] ?? data['email_apoderado'] ?? '').toString());
        await db.collection('tesoreria_apoderados').doc(doc.id).set({
          'rut_usuario': doc.id,
          'nombre_usuario': nombre,
          'nombre': nombre,
          'rut_apoderado': rutApoderado,
          'apoderado_uid': apoderadoUid,
          'nombre_apoderado': nombreApoderado,
          'telefono': telefono,
          'email': email,
          'actualizado': FieldValue.serverTimestamp(),
          'ultima_edicion_perfil_sin_cobro_extra': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final asignaciones = await db.collection('ar_asignaciones_mensuales').where('beneficiario_id', isEqualTo: doc.id).get();
        for (final a in asignaciones.docs) {
          await a.reference.update({
            'beneficiario_nombre': nombre,
            'nombre_beneficiario': nombre,
            'nombre_usuario': nombre,
            'rut_apoderado': rutApoderado,
            'apoderado_uid': apoderadoUid,
            'uid_apoderado': apoderadoUid,
            'nombre_apoderado': nombreApoderado,
            'apoderado_nombre': nombreApoderado,
            'telefono_apoderado': telefono,
            'email_apoderado': email,
            'email_apoderado_normalizado': email,
            'actualizado': FieldValue.serverTimestamp(),
            'editado_sin_cobro_extra': true,
          });
        }
      }

      if (coleccion == 'ar_profesionales') {
        final nombre = (cambios['nombre'] ?? data['nombre'] ?? '').toString();
        final uid = _normalizarUid((cambios['uid'] ?? data['uid'] ?? data['profesional_uid'] ?? doc.id).toString());
        final email = _normalizarEmail((cambios['email'] ?? data['email'] ?? data['email_normalizado'] ?? '').toString());
        final asignaciones = await db.collection('ar_asignaciones_mensuales').where('profesional_id', isEqualTo: doc.id).get();
        for (final a in asignaciones.docs) {
          await a.reference.update({
            'profesional_nombre': nombre,
            'profesional_uid': uid,
            'profesional_email': email,
            'email_profesional_normalizado': email,
            'actualizado': FieldValue.serverTimestamp(),
            'editado_sin_cobro_extra': true,
          });
        }
      }

      if (coleccion == 'ar_asignaciones_mensuales') {
        final beneficiarioId = (data['beneficiario_id'] ?? data['rut_beneficiario'] ?? '').toString();
        if (beneficiarioId.isNotEmpty) {
          await db.collection('tesoreria_apoderados').doc(beneficiarioId).set({
            'ultima_asignacion_profesional_id': doc.id,
            'actualizado': FieldValue.serverTimestamp(),
            'ultima_edicion_asignacion_sin_cobro_extra': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      await AuditoriaService.registrar(
        modulo: 'Coordinación',
        accion: 'Editar registro',
        coleccion: coleccion,
        documentoId: doc.id,
        detalle: 'Campos editados: ${campos.join(', ')}',
      );
      _msg('Registro actualizado.');
    } catch (e) {
      _msg('No se pudo actualizar: $e');
    }
  }

  Future<void> _eliminarRegistroGenerico(String coleccion, DocumentSnapshot doc) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: const Text('¿Seguro que deseas eliminar este registro? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await FirebaseFirestore.instance.collection(coleccion).doc(doc.id).delete();
      await AuditoriaService.registrar(
        modulo: 'Coordinación',
        accion: 'Eliminar registro',
        coleccion: coleccion,
        documentoId: doc.id,
        detalle: 'Registro eliminado desde panel de coordinación',
      );
      _msg('Registro eliminado.');
    } catch (e) {
      _msg('No se pudo eliminar: $e');
    }
  }

  Widget _lista(String coleccion, String titulo, IconData icono) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titulo(titulo),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection(coleccion).limit(30).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text('Sin registros todavía.');
              }
              return Column(
                children: docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final nombre = (data['nombre'] ?? data['beneficiario_nombre'] ?? data['servicio_nombre'] ?? d.id).toString();
                  final detalle = _detalle(data);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.withOpacity(0.12)),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: _azul, foregroundColor: Colors.white, child: Icon(icono)),
                      title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(detalle),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editarRegistroGenerico(coleccion, d),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _eliminarRegistroGenerico(coleccion, d),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _detalle(Map<String, dynamic> data) {
    final partes = <String>[];
    if (data['rut'] != null) partes.add('RUT: ${data['rut']}');
    if (data['uid'] != null && data['uid'].toString().isNotEmpty) partes.add('UID: ${data['uid']}');
    if (data['nombre_apoderado'] != null) partes.add('Apoderado: ${data['nombre_apoderado']}');
    if (data['especialidad'] != null && data['especialidad'].toString().isNotEmpty) partes.add('Especialidad: ${data['especialidad']}');
    if (data['tipo'] != null) partes.add('Tipo: ${data['tipo']}');
    if (data['profesional_nombre'] != null && data['profesional_nombre'].toString().isNotEmpty) partes.add('Profesional: ${data['profesional_nombre']}');
    if (data['dia'] != null) partes.add('Día: ${data['dia']}');
    if (data['hora'] != null) partes.add('Hora: ${data['hora']}');
    if (data['detalle'] != null && data['detalle'].toString().isNotEmpty) partes.add('Detalle: ${data['detalle']}');
    if (partes.isEmpty) return 'Registro activo';
    return partes.join('\n');
  }


  Future<int> _contarCoordinacion(String coleccion) async {
    final snap = await FirebaseFirestore.instance.collection(coleccion).get();
    return snap.docs.length;
  }

  Future<Map<String, int>> _resumenCoordinacion() async {
    return {
      'beneficiarios': await _contarCoordinacion('ar_beneficiarios'),
      'apoderados': await _contarCoordinacion('ar_apoderados'),
      'profesionales': await _contarCoordinacion('ar_profesionales'),
      'servicios': await _contarCoordinacion('ar_servicios_mensuales'),
      'asignaciones': await _contarCoordinacion('ar_asignaciones_mensuales'),
      'trabajoCasa': await _contarCoordinacion('ar_trabajo_casa'),
    };
  }

  Widget _miniEstadistica(String titulo, String valor, IconData icono, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.10)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color),
          const SizedBox(height: 8),
          Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _dashboardCoordinacion() {
    return FutureBuilder<Map<String, int>>(
      future: _resumenCoordinacion(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _card(child: const Center(child: CircularProgressIndicator()));
        }
        final r = snap.data!;
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titulo('Estadísticas de coordinación'),
              const Text(
                'Resumen rápido de beneficiarios, apoderados, profesionales, servicios y asignaciones.',
                style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF46627A)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _miniEstadistica('Beneficiarios', '${r['beneficiarios']}', Icons.child_care, Colors.blue),
                  _miniEstadistica('Apoderados', '${r['apoderados']}', Icons.groups, Colors.teal),
                  _miniEstadistica('Profesionales', '${r['profesionales']}', Icons.psychology_alt, Colors.purple),
                  _miniEstadistica('Servicios', '${r['servicios']}', Icons.medical_services, Colors.cyan),
                  _miniEstadistica('Asignaciones', '${r['asignaciones']}', Icons.link, Colors.indigo),
                  _miniEstadistica('Trabajo casa', '${r['trabajoCasa']}', Icons.home_work, Colors.pink),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _contenido() {
    switch (seccion) {
      case 0:
        return _beneficiarios();
      case 1:
        return _apoderados();
      case 2:
        return _profesionales();
      case 3:
        return _servicios();
      default:
        return _asignaciones();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _azul,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.tituloPanel, style: const TextStyle(fontWeight: FontWeight.w900)),
            const Text('Autismo Rancagua', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFE9F8FF), Color(0xFFF3FFF1)]),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFCDEEFF)),
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coordinación general', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
                SizedBox(height: 8),
                Text(
                  'Desde aquí se crean beneficiarios, apoderados, profesionales y asignaciones operativas. La encargada no escribe montos. Los valores base los recibe Tesorería automáticamente y puede editarlos.',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF46627A), height: 1.35),
                ),
              ],
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              _chip(0, 'Beneficiarios', Icons.child_care),
              _chip(1, 'Apoderados', Icons.groups),
              _chip(2, 'Profesionales', Icons.psychology_alt),
              _chip(3, 'Terapias/Talleres', Icons.medical_services),
              _chip(4, 'Asignaciones', Icons.calendar_month),
            ],
          ),
          const SizedBox(height: 8),
          _dashboardCoordinacion(),
          const SizedBox(height: 8),
          _contenido(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
