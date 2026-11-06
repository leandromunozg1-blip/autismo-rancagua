import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const String adminGeneralEmail = String.fromEnvironment('AR_ADMIN_GENERAL_EMAIL');

/// Roles oficiales de la app Autismo Rancagua.
///
/// Para dar acceso por Firebase/Firestore, crear/editar documento en:
/// usuarios/{uid}
/// con el campo:
/// rol: apoderado | admin_general | admin_asociacion | tesoreria | aseo | reciclaje | eventos | coordinacion | profesionales
class AppRoles {
  static const String apoderado = 'apoderado';
  static const String adminGeneral = 'admin_general';
  static const String adminAsociacion = 'admin_asociacion';
  static const String tesoreria = 'tesoreria';
  static const String aseo = 'aseo';
  static const String reciclaje = 'reciclaje';
  static const String eventos = 'eventos';
  static const String coordinacion = 'coordinacion';
  static const String profesionales = 'profesionales';
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
    case 'profesional':
    case 'profesionales':
      return AppRoles.profesionales;
    default:
      return AppRoles.apoderado;
  }
}

bool esAdminGlobalPorRol(String rol) {
  return rol == AppRoles.adminGeneral || rol == AppRoles.adminAsociacion;
}


Future<String?> _rolDesdePerfilPorCorreo({
  required FirebaseFirestore db,
  required User user,
  required String email,
  required String coleccion,
  required String rol,
}) async {
  if (email.isEmpty) return null;
  for (final campo in ['email_normalizado', 'email', 'correo_normalizado', 'correo']) {
    final q = await db.collection(coleccion).where(campo, isEqualTo: email).limit(1).get();
    if (q.docs.isNotEmpty) {
      final data = q.docs.first.data();
      await db.collection('usuarios').doc(user.uid).set({
        ...data,
        'uid': user.uid,
        'auth_uid': user.uid,
        'email': email,
        'correo': email,
        'email_normalizado': email,
        'correo_normalizado': email,
        'rol': rol,
        'roles': [rol],
        'activo': true,
        'perfil_origen': coleccion,
        'perfil_origen_id': q.docs.first.id,
        'actualizado': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await db.collection(coleccion).doc(q.docs.first.id).set({
        'uid': user.uid,
        'auth_uid': user.uid,
        if (rol == AppRoles.profesionales || rol == AppRoles.profesional) 'profesional_uid': user.uid,
        if (rol == AppRoles.apoderado) 'apoderado_uid': user.uid,
        'email': email,
        'email_normalizado': email,
        'actualizado': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return rol;
    }
  }
  return null;
}

Future<String> obtenerRolActual() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return AppRoles.apoderado;

  final email = user.email?.toLowerCase().trim() ?? '';
  if (email.isNotEmpty && email == adminGeneralEmail) return AppRoles.adminGeneral;

  final db = FirebaseFirestore.instance;

  final docUid = await db.collection('usuarios').doc(user.uid).get();
  if (docUid.exists) {
    final data = docUid.data() ?? {};
    return normalizarRol(data['rol']?.toString());
  }

  if (email.isNotEmpty) {
    final query = await db
        .collection('usuarios')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      return normalizarRol(query.docs.first.data()['rol']?.toString());
    }

    final rolProfesional = await _rolDesdePerfilPorCorreo(
      db: db,
      user: user,
      email: email,
      coleccion: 'ar_profesionales',
      rol: AppRoles.profesionales,
    );
    if (rolProfesional != null) return normalizarRol(rolProfesional);

    final rolApoderado = await _rolDesdePerfilPorCorreo(
      db: db,
      user: user,
      email: email,
      coleccion: 'ar_apoderados',
      rol: AppRoles.apoderado,
    );
    if (rolApoderado != null) return normalizarRol(rolApoderado);
  }

  return AppRoles.apoderado;
}
