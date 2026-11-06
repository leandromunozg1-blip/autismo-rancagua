import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Set<String> adminGeneralEmails = {
  String.fromEnvironment('AR_ADMIN_GENERAL_EMAIL'),
  String.fromEnvironment('AR_ADMIN_TEST_EMAIL'),
};

const String usuarioTestEmail = String.fromEnvironment('AR_USUARIO_TEST_EMAIL');
const String aseoAccesoEmail = String.fromEnvironment('AR_ASEO_EMAIL');

/// Roles oficiales de la app Autismo Rancagua.
///
/// Para dar acceso por Firebase/Firestore, crear/editar documento en:
/// usuarios/{uid}
/// o buscar por email/correo.
/// con el campo:
/// rol: apoderado | admin_general | admin_asociacion | secretaria | tesoreria | aseo | reciclaje | eventos | coordinacion | profesional
class AppRoles {
  static const String apoderado = 'apoderado';
  static const String adminGeneral = 'admin_general';
  static const String adminAsociacion = 'admin_asociacion';
  static const String secretaria = 'secretaria';
  static const String tesoreria = 'tesoreria';
  static const String aseo = 'aseo';
  static const String reciclaje = 'reciclaje';
  static const String eventos = 'eventos';
  static const String coordinacion = 'coordinacion';
  static const String profesional = 'profesional';
}

String normalizarRol(String? rol) {
  final r = (rol ?? '').trim().toLowerCase();
  switch (r) {
    case 'admin':
    case 'administrador':
    case 'admin_general':
      return AppRoles.adminGeneral;
    case 'admin_asociacion':
    case 'administrador_asociacion':
    case 'asociacion':
      return AppRoles.adminAsociacion;
    case 'secretario':
    case 'secretaria':
      return AppRoles.secretaria;
    case 'tesorero':
    case 'tesoreria':
      return AppRoles.tesoreria;
    case 'utiles_aseo':
    case 'aseo':
      return AppRoles.aseo;
    case 'reciclaje':
      return AppRoles.reciclaje;
    case 'evento':
    case 'eventos':
      return AppRoles.eventos;
    case 'coordinadora':
    case 'coordinacion':
      return AppRoles.coordinacion;
    case 'admin_profesionales':
    case 'administradora_profesionales':
    case 'jefa_profesionales':
    case 'profesionales':
      // Rol eliminado temporalmente: hasta definir funciones, se trata como profesional individual.
      return AppRoles.profesional;
    case 'profesional':
    case 'terapeuta':
      return AppRoles.profesional;
    default:
      return AppRoles.apoderado;
  }
}

bool esAdminGlobalPorRol(String rol) {
  return rol == AppRoles.adminGeneral || rol == AppRoles.adminAsociacion;
}

String _rolDesdeData(Map<String, dynamic> data) {
  final roles = ((data['roles'] as List?) ?? const [])
      .map((e) => normalizarRol(e.toString()))
      .toSet();

  final rolPrincipal = normalizarRol(data['rol']?.toString());
  roles.add(rolPrincipal);

  const prioridad = [
    AppRoles.adminGeneral,
    AppRoles.adminAsociacion,
    AppRoles.coordinacion,
    AppRoles.tesoreria,
    AppRoles.secretaria,
    AppRoles.aseo,
    AppRoles.reciclaje,
    AppRoles.eventos,
    AppRoles.profesional,
    AppRoles.apoderado,
  ];

  for (final rol in prioridad) {
    if (roles.contains(rol)) return rol;
  }

  return AppRoles.apoderado;
}


Future<String?> _vincularRolDesdeColeccionPerfil({
  required FirebaseFirestore db,
  required User user,
  required String email,
  required String coleccion,
  required String rol,
}) async {
  if (email.isEmpty) return null;

  QuerySnapshot<Map<String, dynamic>>? q;

  for (final campo in ['email_normalizado', 'email', 'correo_normalizado', 'correo']) {
    q = await db.collection(coleccion).where(campo, isEqualTo: email).limit(1).get();
    if (q.docs.isNotEmpty) break;
  }

  if (q == null || q.docs.isEmpty) return null;

  final data = q.docs.first.data();
  final nombre = (data['nombre'] ?? data['nombre_completo'] ?? '').toString();
  final rut = (data['rut_normalizado'] ?? data['rut'] ?? '').toString();
  final rolesActuales = ((data['roles'] as List?) ?? const [])
      .map((e) => normalizarRol(e.toString()))
      .where((e) => e.isNotEmpty)
      .toSet();
  rolesActuales.add(rol);

  await db.collection('usuarios').doc(user.uid).set({
    ...data,
    'uid': user.uid,
    'auth_uid': user.uid,
    'email': email,
    'correo': email,
    'email_normalizado': email,
    'correo_normalizado': email,
    'rut': rut,
    'rut_normalizado': rut,
    'nombre': nombre,
    'rol': rol,
    'roles': rolesActuales.toList(),
    'activo': true,
    'perfil_origen': coleccion,
    'perfil_origen_id': q.docs.first.id,
    'actualizado': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // También dejamos el UID real en la ficha de origen para futuras asignaciones.
  await db.collection(coleccion).doc(q.docs.first.id).set({
    'uid': user.uid,
    'auth_uid': user.uid,
    if (rol == AppRoles.profesional) 'profesional_uid': user.uid,
    if (rol == AppRoles.apoderado) 'apoderado_uid': user.uid,
    'email': email,
    'email_normalizado': email,
    'actualizado': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  return rol;
}

Future<String> obtenerRolActual() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return AppRoles.apoderado;

  final email = user.email?.toLowerCase().trim() ?? '';
  if (email.isNotEmpty && adminGeneralEmails.contains(email)) return AppRoles.adminGeneral;
  if (email.isNotEmpty && email == aseoAccesoEmail) return AppRoles.aseo;
  if (email.isNotEmpty && email == usuarioTestEmail) return AppRoles.apoderado;

  final db = FirebaseFirestore.instance;

  // 1) Fuente principal: usuarios/{uid}
  final docUid = await db.collection('usuarios').doc(user.uid).get();
  if (docUid.exists) {
    final data = docUid.data() ?? {};
    return _rolDesdeData(data);
  }

  // 2) Compatibilidad: perfiles antiguos creados por correo/campos de correo.
  // Si existe, lo vinculamos automáticamente al UID real de Firebase Auth.
  if (email.isNotEmpty) {
    final camposCorreo = ['email', 'correo', 'email_normalizado', 'correo_normalizado'];
    for (final campo in camposCorreo) {
      final q = await db
          .collection('usuarios')
          .where(campo, isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final data = q.docs.first.data();
        final rol = _rolDesdeData(data);
        await db.collection('usuarios').doc(user.uid).set({
          ...data,
          'uid': user.uid,
          'email': email,
          'correo': email,
          'email_normalizado': email,
          'correo_normalizado': email,
          'rol': rol,
          'roles': ((data['roles'] as List?) ?? [rol]).map((e) => normalizarRol(e.toString())).toSet().toList(),
          'activo': true,
          'actualizado': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return rol;
      }
    }

    // 3) Fuente real del panel de coordinación: profesionales/apoderados creados en la app.
    // Si el correo existe en ar_profesionales, entra directo al panel profesional.
    final rolProfesional = await _vincularRolDesdeColeccionPerfil(
      db: db,
      user: user,
      email: email,
      coleccion: 'ar_profesionales',
      rol: AppRoles.profesional,
    );
    if (rolProfesional != null) return rolProfesional;

    // Si el correo existe en ar_apoderados, entra como apoderado.
    final rolApoderado = await _vincularRolDesdeColeccionPerfil(
      db: db,
      user: user,
      email: email,
      coleccion: 'ar_apoderados',
      rol: AppRoles.apoderado,
    );
    if (rolApoderado != null) return rolApoderado;

    // 4) Rol pendiente por correo: permite crear primero el usuario en Authentication
    // y luego autorizarlo por correo sin escribir manualmente el UID en la app.
    final pendiente = await db.collection('usuarios_roles_pendientes').doc(email).get();
    if (pendiente.exists) {
      final data = pendiente.data() ?? {};
      final rol = normalizarRol((data['rol'] ?? data['perfil'] ?? AppRoles.apoderado).toString());
      await db.collection('usuarios').doc(user.uid).set({
        'uid': user.uid,
        'nombre': (data['nombre'] ?? '').toString(),
        'email': email,
        'correo': email,
        'email_normalizado': email,
        'correo_normalizado': email,
        'rol': rol,
        'roles': [rol],
        'profesional_id': data['profesional_id'] ?? '',
        'activo': true,
        'creado': FieldValue.serverTimestamp(),
        'actualizado': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await db.collection('usuarios_roles_pendientes').doc(email).set({
        'uid': user.uid,
        'estado': 'vinculado',
        'actualizado': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return rol;
    }
  }

  return AppRoles.apoderado;
}
