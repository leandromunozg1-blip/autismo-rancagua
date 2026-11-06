import 'tesoreria_v58_service.dart';

class PeriodoFinancieroTesoreria {
  final String periodo;
  final int cargos;
  final int pagos;
  final int saldoMes;
  final int saldo;

  const PeriodoFinancieroTesoreria({
    required this.periodo,
    required this.cargos,
    required this.pagos,
    required this.saldoMes,
    required this.saldo,
  });
}

class ResumenFinancieroTesoreria {
  final int cargos;
  final int pagos;
  final int deuda;
  final int saldoVencido;
  final int cuotasMorosas;
  final bool usaLibroMayor;
  final List<PeriodoFinancieroTesoreria> periodos;
  final List<String> advertencias;

  const ResumenFinancieroTesoreria({
    required this.cargos,
    required this.pagos,
    required this.deuda,
    this.saldoVencido = 0,
    required this.cuotasMorosas,
    required this.usaLibroMayor,
    this.periodos = const [],
    this.advertencias = const [],
  });
}

/// Adaptador del libro mayor de Firebase. No genera cargos ni modifica fichas.
/// Una consulta fallida se muestra como error, nunca como saldo cero.
class TesoreriaFinanzasService {
  static int toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(
          (value ?? '').toString().replaceAll(RegExp(r'[^0-9-]'), ''),
        ) ??
        0;
  }

  static ResumenFinancieroTesoreria desdeRespuesta(
      Map<String, dynamic> respuesta) {
    final resumen = TesoreriaV58Service.mapa(respuesta['resumen']);
    if (!resumen.containsKey('deuda') || !resumen.containsKey('cargos') ||
        !resumen.containsKey('pagos')) {
      throw StateError('Firebase no devolvió un resumen contable válido.');
    }
    return ResumenFinancieroTesoreria(
      cargos: toInt(resumen['cargos']),
      pagos: toInt(resumen['pagos']),
      deuda: toInt(resumen['deuda']),
      saldoVencido: toInt(resumen['saldoVencido']),
      cuotasMorosas: toInt(resumen['cuotasMorosas']),
      usaLibroMayor: resumen['usaLibroMayor'] == true,
      periodos: TesoreriaV58Service.mapas(resumen['periodos'])
          .map((p) => PeriodoFinancieroTesoreria(
                periodo: (p['periodo'] ?? 'sin_periodo').toString(),
                cargos: toInt(p['cargos']),
                pagos: toInt(p['pagos']),
                saldoMes: toInt(p['saldoMes']),
                saldo: toInt(p['saldo']),
              ))
          .toList(),
      advertencias: ((respuesta['advertencias'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  static Future<ResumenFinancieroTesoreria> calcular(String apoderadoId,
      {Map<String, dynamic>? ficha}) async {
    return desdeRespuesta(await TesoreriaV58Service.consultar(apoderadoId));
  }
}
