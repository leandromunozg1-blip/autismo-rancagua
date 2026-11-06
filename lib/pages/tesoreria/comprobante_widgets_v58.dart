import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/tesoreria_v58_gateway.dart';
import 'package:flutter/material.dart';

const limiteImagenTesoreria = 10 * 1024 * 1024;

int montoTesoreria(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

List<Map<String, dynamic>> mapasTesoreria(dynamic value) => value is List
    ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : [];

String mensajeErrorTesoreria(Object error) {
  if (error is FirebaseException) return error.message ?? error.code;
  if (error is FormatException) return error.message;
  return error.toString();
}

String nombreCuentaTesoreria(Map<String, dynamic> cuenta) {
  final nombre = cuenta['beneficiario_nombre'] ?? cuenta['nombre_beneficiario'] ?? cuenta['nombre_usuario'] ?? cuenta['nombre'] ?? cuenta['nombre_apoderado'] ?? 'Cuenta';
  return '$nombre · ${cuenta['id']}';
}

String etiquetaCargoTesoreria(Map<String, dynamic> cargo) => '${cargo['periodo'] ?? cargo['mes'] ?? ''} · ${cargo['concepto'] ?? cargo['tipo'] ?? 'Cargo'} · saldo \$${montoTesoreria(cargo['saldo'])}';

({String extension, String mime})? formatoImagenTesoreria(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) return (extension: 'jpg', mime: 'image/jpeg');
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length >= png.length && Iterable<int>.generate(png.length).every((i) => bytes[i] == png[i])) return (extension: 'png', mime: 'image/png');
  if (bytes.length >= 12 && String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') return (extension: 'webp', mime: 'image/webp');
  return null;
}

int fechaComprobanteTesoreria(dynamic value) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is String) return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
  if (value is Map && value['_seconds'] is num) return (value['_seconds'] as num).toInt() * 1000;
  return 0;
}

Future<void> verImagenComprobanteTesoreria(BuildContext context, Map<String, dynamic> comprobante, {TesoreriaV58Gateway? gateway}) async {
  final path = (comprobante['storage_path'] ?? comprobante['imagenPath'] ?? '').toString();
  final url = (comprobante['imagen'] ?? comprobante['imagen_url'] ?? comprobante['comprobante_url'] ?? '').toString();
  final adapter = gateway ?? FirebaseTesoreriaV58Gateway();
  final image = path.isEmpty ? null : adapter.leerImagen(path);
  await showDialog<void>(context: context, builder: (ctx) => Dialog(
    child: SizedBox(
      height: MediaQuery.sizeOf(ctx).height * .8,
      width: MediaQuery.sizeOf(ctx).width * .9,
      child: Column(children: [
        Row(children: [const Expanded(child: Padding(padding: EdgeInsets.all(12), child: Text('Comprobante de pago'))), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
        Expanded(child: path.isNotEmpty
            ? FutureBuilder<Uint8List?>(
                future: image,
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('No se pudo abrir el archivo. ${mensajeErrorTesoreria(snap.error!)}')));
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snap.data == null) return const Center(child: Text('No se encontró la imagen.'));
                  return InteractiveViewer(child: Image.memory(snap.data!, errorBuilder: (_, __, ___) => const Center(child: Text('La imagen no es válida.'))));
                },
              )
            : url.isNotEmpty
                ? InteractiveViewer(child: Image.network(url, errorBuilder: (_, __, ___) => const Center(child: Text('No se pudo cargar la imagen histórica.'))))
                : const Center(child: Text('Este registro no contiene imagen.'))),
      ]),
    ),
  ));
}
