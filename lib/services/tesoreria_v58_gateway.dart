import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'tesoreria_v58_service.dart';

enum TesoreriaImagenOrigen { camara, galeria }

/// Puerto de las pantallas reales. Las pruebas usan un fake sin SDKs ni red.
abstract class TesoreriaV58Gateway {
  String? get uidActual;
  String nuevaSolicitudId();
  Future<List<Map<String, dynamic>>> cuentas();
  Future<Map<String, dynamic>> consultar(String cuentaId);
  Stream<List<Map<String, dynamic>>> comprobantesPendientes();
  Future<String> enviarComprobante({
    required String solicitudId,
    required String cuentaId,
    required String cargoId,
    required String storagePath,
    required int monto,
    String observacion = '',
  });
  Future<void> revisarComprobante({
    required String comprobanteId,
    required String decision,
    String motivo = '',
    String? cuentaId,
    String? cargoId,
  });
  Future<Uint8List?> seleccionarImagen(TesoreriaImagenOrigen origen);
  Future<Uint8List?> recuperarImagenPerdida();
  Future<String> subirImagen({
    required String solicitudId,
    required Uint8List bytes,
    required String extension,
    required String mime,
  });
  Future<Uint8List?> leerImagen(String path);
  Future<Map<String, dynamic>?> recuperarEnvioPendiente();
  Future<void> guardarEnvioPendiente(Map<String, dynamic> envio);
  Future<void> borrarEnvioPendiente();
}

class FirebaseTesoreriaV58Gateway implements TesoreriaV58Gateway {
  static const int maxImagenBytes = 10 * 1024 * 1024;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  String? get uidActual => FirebaseAuth.instance.currentUser?.uid;

  String _uid() {
    final uid = uidActual;
    if (uid == null) throw StateError('Debes iniciar sesión.');
    return uid;
  }

  String get _draftKey =>
      'tesoreria_v58_envio_${Firebase.app().options.projectId}_${_uid()}';

  @override
  String nuevaSolicitudId() =>
      FirebaseFirestore.instance.collection('comprobantes_pago').doc().id;

  @override
  Future<List<Map<String, dynamic>>> cuentas() => TesoreriaV58Service.cuentas();

  @override
  Future<Map<String, dynamic>> consultar(String cuentaId) =>
      TesoreriaV58Service.consultar(cuentaId);

  @override
  Stream<List<Map<String, dynamic>>> comprobantesPendientes() =>
      FirebaseFirestore.instance
          .collection('comprobantes_pago')
          .where('estado', isEqualTo: 'pendiente')
          .snapshots()
          .map((snap) => snap.docs
              .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
              .toList());

  @override
  Future<String> enviarComprobante({
    required String solicitudId,
    required String cuentaId,
    required String cargoId,
    required String storagePath,
    required int monto,
    String observacion = '',
  }) =>
      TesoreriaV58Service.enviarComprobante(
        solicitudId: solicitudId,
        cuentaId: cuentaId,
        cargoId: cargoId,
        storagePath: storagePath,
        monto: monto,
        observacion: observacion,
      );

  @override
  Future<void> revisarComprobante({
    required String comprobanteId,
    required String decision,
    String motivo = '',
    String? cuentaId,
    String? cargoId,
  }) =>
      TesoreriaV58Service.revisarComprobante(
        comprobanteId: comprobanteId,
        decision: decision,
        motivo: motivo,
        cuentaId: cuentaId,
        cargoId: cargoId,
      );

  @override
  Future<Uint8List?> seleccionarImagen(TesoreriaImagenOrigen origen) async {
    final image = await ImagePicker().pickImage(
      source: origen == TesoreriaImagenOrigen.camara
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2200,
    );
    return image?.readAsBytes();
  }

  @override
  Future<Uint8List?> recuperarImagenPerdida() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await ImagePicker().retrieveLostData();
    if (response.isEmpty) return null;
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    if (files == null || files.isEmpty) return null;
    return files.first.readAsBytes();
  }

  @override
  Future<String> subirImagen({
    required String solicitudId,
    required Uint8List bytes,
    required String extension,
    required String mime,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(solicitudId) ||
        !const {'jpg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp'}
            .entries.any((e) => e.key == extension && e.value == mime) ||
        bytes.isEmpty || bytes.length > maxImagenBytes) {
      throw const FormatException('El archivo del comprobante no es válido.');
    }
    final path = 'comprobantes_v58/${_uid()}/$solicitudId.$extension';
    final ref = FirebaseStorage.instance.ref(path);
    final hash = base64Encode(md5.convert(bytes).bytes);
    try {
      final metadata = await ref.getMetadata();
      // Una subida puede confirmarse aunque su respuesta se pierda. Reutilizar
      // únicamente los mismos bytes; jamás sustituir una evidencia ya enviada.
      if (metadata.md5Hash != hash || metadata.size != bytes.length ||
          metadata.contentType != mime) {
        throw const FormatException(
            'La imagen ya subida no coincide con este envío. Conserva el comprobante y revisa el historial.');
      }
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
      await ref.putData(bytes, SettableMetadata(contentType: mime));
    }
    return path;
  }

  @override
  Future<Uint8List?> leerImagen(String path) =>
      FirebaseStorage.instance.ref(path).getData(maxImagenBytes);

  @override
  Future<Map<String, dynamic>?> recuperarEnvioPendiente() async {
    final raw = await _storage.read(key: _draftKey);
    if (raw == null) return null;
    final result = TesoreriaV58Service.mapa(jsonDecode(raw));
    if (result['uid'] != _uid()) {
      throw StateError('El borrador no pertenece a la sesión actual.');
    }
    return result;
  }

  @override
  Future<void> guardarEnvioPendiente(Map<String, dynamic> envio) {
    if (envio['uid'] != _uid()) {
      throw StateError('No se puede conservar el envío de otra sesión.');
    }
    // Solo referencias/datos del envío; nunca bytes de fotos ni credenciales.
    return _storage.write(key: _draftKey, value: jsonEncode(envio));
  }

  @override
  Future<void> borrarEnvioPendiente() => _storage.delete(key: _draftKey);
}
