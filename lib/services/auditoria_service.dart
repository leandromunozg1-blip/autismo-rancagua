import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_roles.dart';

class AuditoriaService {
  static Future<void> registrar({
    required String modulo,
    required String accion,
    required String coleccion,
    required String documentoId,
    String detalle = '',
    Map<String, dynamic>? antes,
    Map<String, dynamic>? despues,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final rol = await obtenerRolActual();
    await FirebaseFirestore.instance.collection('auditoria_cambios').add({
      'modulo': modulo,
      'accion': accion,
      'coleccion': coleccion,
      'documento_id': documentoId,
      'detalle': detalle,
      'antes': antes,
      'despues': despues,
      'usuario_uid': user?.uid,
      'usuario_email': user?.email,
      'usuario_rol': rol,
      'fecha': FieldValue.serverTimestamp(),
    });
  }
}
