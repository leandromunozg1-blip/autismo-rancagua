import 'package:cloud_functions/cloud_functions.dart';

/// Toda mutación contable se autoriza y ejecuta en Firebase, nunca en el cliente.
class TesoreriaV58Service {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'southamerica-west1');

  static Map<String, dynamic> mapa(dynamic value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};

  static List<Map<String, dynamic>> mapas(dynamic value) => value is List
      ? value.map(mapa).toList()
      : <Map<String, dynamic>>[];

  static Future<Map<String, dynamic>> _llamar(
      String nombre, Map<String, dynamic> datos) async {
    final respuesta = await _functions.httpsCallable(nombre).call(datos);
    return mapa(respuesta.data);
  }

  static Future<List<Map<String, dynamic>>> cuentas() async =>
      mapas((await _llamar('tesoreriaConsultar', {}))['cuentas']);

  static Future<Map<String, dynamic>> consultar(String cuentaId) =>
      _llamar('tesoreriaConsultar', {'cuentaId': cuentaId});

  static Future<String> enviarComprobante({
    required String solicitudId,
    required String cuentaId,
    required String cargoId,
    required String storagePath,
    required int monto,
    String observacion = '',
  }) async {
    final respuesta = await _llamar('tesoreriaEnviarComprobante', {
      'solicitudId': solicitudId,
      'cuentaId': cuentaId,
      'cargoId': cargoId,
      'storagePath': storagePath,
      'monto': monto,
      'observacion': observacion,
    });
    final id = (respuesta['comprobanteId'] ?? respuesta['id'] ?? '').toString();
    if (id.isEmpty) {
      throw StateError('Firebase no confirmó la recepción del comprobante.');
    }
    return id;
  }

  static Future<void> revisarComprobante({
    required String comprobanteId,
    required String decision,
    String motivo = '',
    String? cuentaId,
    String? cargoId,
  }) async {
    await _llamar('tesoreriaRevisarComprobante', {
      'comprobanteId': comprobanteId,
      'decision': decision,
      'motivo': motivo,
      if (cuentaId != null) 'cuentaId': cuentaId,
      if (cargoId != null) 'cargoId': cargoId,
    });
  }
}
