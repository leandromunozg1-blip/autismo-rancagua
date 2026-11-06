import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:autismo_rancagua/services/tesoreria_v58_gateway.dart';

/// Fake de frontera para widgets. No inicializa Firebase ni plugins nativos.
/// Los descuentos, transacciones y autorización reales se prueban en Functions.
class FakeTesoreriaGateway implements TesoreriaV58Gateway {
  FakeTesoreriaGateway();

  String? usuarioUid = 'padre-pruebas';
  int solicitudesCreadas = 0;
  int recuperacionesImagen = 0;
  int lecturasImagen = 0;
  Uint8List? imagenRecuperada;
  Map<String, dynamic>? borrador;
  Completer<String>? envioBloqueado;
  final erroresEnvio = <Object>[];
  final erroresRevision = <Object>[];
  final origenesSeleccionados = <TesoreriaImagenOrigen>[];
  final envios = <Map<String, dynamic>>[];
  final revisiones = <Map<String, dynamic>>[];
  final subidas = <Map<String, dynamic>>[];
  final borradoresGuardados = <Map<String, dynamic>>[];
  final consultas = <String>[];
  final cuentasData = <Map<String, dynamic>>[
    {'id': 'beneficiario-a', 'nombre_usuario': 'Beneficiario A'},
    {'id': 'beneficiario-b', 'nombre_usuario': 'Beneficiario B'},
  ];
  final detalles = <String, Map<String, dynamic>>{
    'beneficiario-a': {
      'cuenta': {'id': 'beneficiario-a', 'nombre_usuario': 'Beneficiario A'},
      'cargos': [
        {
          'id': 'tesoreria_movimientos/cargo-a',
          'periodo': '2026-12',
          'concepto': 'Mensualidad diciembre',
          'monto': 5000,
          'pagado': 0,
          'saldo': 5000,
          'tipo': 'cargo_mensual',
        },
      ],
      'resumen': {
        'cargos': 5000,
        'pagos': 0,
        'deuda': 5000,
        'saldoVencido': 0,
        'cuotasMorosas': 0,
        'usaLibroMayor': true,
        'periodos': [],
      },
      'advertencias': <String>[],
    },
    'beneficiario-b': {
      'cuenta': {'id': 'beneficiario-b', 'nombre_usuario': 'Beneficiario B'},
      'cargos': <Map<String, dynamic>>[],
      'resumen': {
        'cargos': 0,
        'pagos': 0,
        'deuda': 0,
        'saldoVencido': 0,
        'cuotasMorosas': 0,
        'usaLibroMayor': false,
        'periodos': [],
      },
      'advertencias': <String>[],
    },
  };

  static Uint8List get png => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=');

  List<Map<String, dynamic>> pendientes = [];
  final _pendientes = StreamController<List<Map<String, dynamic>>>.broadcast();

  @override
  String? get uidActual => usuarioUid;

  @override
  String nuevaSolicitudId() =>
      'solicitud_pruebas_${(++solicitudesCreadas).toString().padLeft(4, '0')}';

  @override
  Future<List<Map<String, dynamic>>> cuentas() async =>
      cuentasData.map((c) => Map<String, dynamic>.from(c)).toList();

  @override
  Future<Map<String, dynamic>> consultar(String cuentaId) async {
    consultas.add(cuentaId);
    final detalle = detalles[cuentaId];
    if (detalle == null) throw StateError('Cuenta desconocida en la prueba.');
    return Map<String, dynamic>.from(detalle);
  }

  @override
  Stream<List<Map<String, dynamic>>> comprobantesPendientes() async* {
    yield pendientes.map((p) => Map<String, dynamic>.from(p)).toList();
    yield* _pendientes.stream;
  }

  void actualizarPendientes(List<Map<String, dynamic>> datos) {
    pendientes = datos;
    _pendientes.add(datos.map((p) => Map<String, dynamic>.from(p)).toList());
  }

  @override
  Future<String> enviarComprobante({
    required String solicitudId,
    required String cuentaId,
    required String cargoId,
    required String storagePath,
    required int monto,
    String observacion = '',
  }) async {
    envios.add({
      'solicitudId': solicitudId,
      'cuentaId': cuentaId,
      'cargoId': cargoId,
      'storagePath': storagePath,
      'monto': monto,
      'observacion': observacion,
    });
    if (erroresEnvio.isNotEmpty) throw erroresEnvio.removeAt(0);
    if (envioBloqueado != null) return envioBloqueado!.future;
    return 'recibo-$solicitudId';
  }

  @override
  Future<void> revisarComprobante({
    required String comprobanteId,
    required String decision,
    String motivo = '',
    String? cuentaId,
    String? cargoId,
  }) async {
    revisiones.add({
      'comprobanteId': comprobanteId,
      'decision': decision,
      'motivo': motivo,
      'cuentaId': cuentaId,
      'cargoId': cargoId,
    });
    if (erroresRevision.isNotEmpty) throw erroresRevision.removeAt(0);
    actualizarPendientes(
        pendientes.where((p) => p['id'] != comprobanteId).toList());
  }

  @override
  Future<Uint8List?> seleccionarImagen(TesoreriaImagenOrigen origen) async {
    origenesSeleccionados.add(origen);
    return png;
  }

  @override
  Future<Uint8List?> recuperarImagenPerdida() async {
    recuperacionesImagen++;
    return imagenRecuperada;
  }

  @override
  Future<String> subirImagen({
    required String solicitudId,
    required Uint8List bytes,
    required String extension,
    required String mime,
  }) async {
    subidas.add({
      'solicitudId': solicitudId,
      'bytes': Uint8List.fromList(bytes),
      'extension': extension,
      'mime': mime,
    });
    return 'comprobantes_v58/$uidActual/$solicitudId.$extension';
  }

  @override
  Future<Uint8List?> leerImagen(String path) async {
    lecturasImagen++;
    return png;
  }

  @override
  Future<Map<String, dynamic>?> recuperarEnvioPendiente() async =>
      borrador == null ? null : Map<String, dynamic>.from(borrador!);

  @override
  Future<void> guardarEnvioPendiente(Map<String, dynamic> envio) async {
    borrador = Map<String, dynamic>.from(envio);
    borradoresGuardados.add(Map<String, dynamic>.from(envio));
  }

  @override
  Future<void> borrarEnvioPendiente() async {
    borrador = null;
  }

  Future<void> dispose() => _pendientes.close();
}
