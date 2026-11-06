import 'package:flutter_test/flutter_test.dart';
import 'package:autismo_rancagua/services/tesoreria_finanzas_service.dart';

void main() {
  group('Resumen financiero recibido de Firebase', () {
    test('una respuesta vacía falla y no se presenta como deuda cero', () {
      expect(
        () => TesoreriaFinanzasService.desdeRespuesta({}),
        throwsStateError,
      );
      expect(
        () => TesoreriaFinanzasService.desdeRespuesta({'resumen': {}}),
        throwsStateError,
      );
      expect(
        () => TesoreriaFinanzasService.desdeRespuesta({
          'resumen': {'cargos': 10000, 'deuda': 10000},
        }),
        throwsStateError,
      );
    });

    test('una cuenta sin cargos reales no inventa mensualidades', () {
      final resumen = TesoreriaFinanzasService.desdeRespuesta({
        'resumen': {
          'cargos': 0,
          'pagos': 0,
          'deuda': 0,
          'saldoVencido': 0,
          'cuotasMorosas': 0,
          'usaLibroMayor': true,
          'periodos': [],
        },
      });

      expect(resumen.cargos, 0);
      expect(resumen.pagos, 0);
      expect(resumen.deuda, 0);
      expect(resumen.periodos, isEmpty);
      expect(resumen.cuotasMorosas, 0);
      expect(resumen.usaLibroMayor, isTrue);
    });

    test('preserva el saldo y los abonos parciales del libro mayor', () {
      final resumen = TesoreriaFinanzasService.desdeRespuesta({
        'resumen': {
          'cargos': 20000,
          'pagos': 7500,
          'deuda': 12500,
          'saldoVencido': 12500,
          'cuotasMorosas': 1,
          'usaLibroMayor': true,
          'periodos': [
            {
              'periodo': '2026-10',
              'cargos': 20000,
              'pagos': 7500,
              'saldoMes': 12500,
              'saldo': 12500,
            },
          ],
        },
      });

      expect(resumen.cargos, 20000);
      expect(resumen.pagos, 7500);
      expect(resumen.deuda, 12500);
      expect(resumen.saldoVencido, 12500);
      expect(resumen.cuotasMorosas, 1);
      expect(resumen.periodos, hasLength(1));
      final periodo = resumen.periodos.single;
      expect(periodo.periodo, '2026-10');
      expect(periodo.cargos, 20000);
      expect(periodo.pagos, 7500);
      expect(periodo.saldoMes, 12500);
      expect(periodo.saldo, 12500);
    });

    test('un cargo futuro explícito se muestra sin marcarlo como vencido', () {
      final resumen = TesoreriaFinanzasService.desdeRespuesta({
        'resumen': {
          'cargos': 5000,
          'pagos': 0,
          'deuda': 5000,
          'saldoVencido': 0,
          'cuotasMorosas': 0,
          'usaLibroMayor': true,
          'periodos': [
            {
              'periodo': '2099-01',
              'cargos': 5000,
              'pagos': 0,
              'saldoMes': 5000,
              'saldo': 5000,
            },
          ],
        },
      });

      expect(resumen.deuda, 5000);
      expect(resumen.saldoVencido, 0);
      expect(resumen.cuotasMorosas, 0);
      expect(resumen.periodos.map((p) => p.periodo), ['2099-01']);
      expect(resumen.periodos.single.cargos, 5000);
    });

    test('las advertencias de conciliación llegan íntegras al cliente', () {
      const advertencias = [
        'Comprobante histórico sin cargo identificado: revisión manual.',
        'Dos cuentas vinculadas: seleccionar beneficiario.',
      ];
      final resumen = TesoreriaFinanzasService.desdeRespuesta({
        'resumen': {
          'cargos': 5000,
          'pagos': 1000,
          'deuda': 4000,
          'usaLibroMayor': true,
          'periodos': [],
        },
        'advertencias': advertencias,
      });

      expect(resumen.advertencias, advertencias);
      expect(resumen.deuda, 4000);
      expect(resumen.periodos, isEmpty);
    });
  });
}
