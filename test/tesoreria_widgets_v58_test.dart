import 'dart:async';

import 'package:autismo_rancagua/main.dart' as app;
import 'package:autismo_rancagua/pages/tesoreria/comprobante_pago_v58_page.dart';
import 'package:autismo_rancagua/pages/tesoreria/revision_comprobantes_v58_page.dart';
import 'package:autismo_rancagua/services/tesoreria_v58_gateway.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_tesoreria_gateway.dart';

const _cuenta = Key('comprobante-cuenta');
const _cargo = Key('comprobante-cargo');
const _monto = Key('comprobante-monto');
const _imagen = Key('comprobante-imagen');
const _enviar = Key('comprobante-enviar');
const _confirmar = Key('revision-confirmar');

Map<String, dynamic> recibo({String id = 'recibo-1', bool historico = false}) => {
      'id': id,
      'uid': 'padre-pruebas',
      'monto': 1500,
      'estado': 'pendiente',
      'fecha': '2026-11-20T12:00:00Z',
      if (!historico) 'cuenta_id': 'beneficiario-a',
      if (!historico) 'cargo_id': 'tesoreria_movimientos/cargo-a',
      'observacion': 'Abono de prueba',
    };

Future<void> montar(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

Future<void> pulsar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> elegirCuentaCargo(WidgetTester tester) async {
  await pulsar(tester, find.byKey(_cuenta));
  await pulsar(tester, find.text('Beneficiario A · beneficiario-a').last);
  await pulsar(tester, find.byKey(_cargo));
  await pulsar(tester, find.textContaining('Mensualidad diciembre').last);
  await tester.enterText(find.byKey(_monto), '1500');
}

Future<void> elegirImagen(WidgetTester tester, {bool camara = false}) async {
  await pulsar(tester, find.byKey(_imagen));
  await pulsar(tester, find.text(camara
      ? 'Tomar fotografía'
      : 'Seleccionar captura de la galería'));
}

void main() {
  testWidgets('ruta real del apoderado permite cámara y envía un abono al cargo elegido',
      (tester) async {
    final gateway = FakeTesoreriaGateway();
    addTearDown(gateway.dispose);
    // Construye el wrapper usado por la navegación existente; no llama main().
    await montar(tester, app.ComprobantePagoPage(gateway: gateway));
    await elegirCuentaCargo(tester);
    await elegirImagen(tester, camara: true);
    await pulsar(tester, find.byKey(_enviar));

    expect(gateway.origenesSeleccionados, [TesoreriaImagenOrigen.camara]);
    expect(gateway.subidas, hasLength(1));
    expect(gateway.subidas.single['mime'], 'image/png');
    expect(gateway.envios, hasLength(1));
    expect(gateway.envios.single, containsPair('cuentaId', 'beneficiario-a'));
    expect(gateway.envios.single,
        containsPair('cargoId', 'tesoreria_movimientos/cargo-a'));
    expect(gateway.envios.single, containsPair('monto', 1500));
    expect(gateway.envios.single['storagePath'],
        'comprobantes_v58/padre-pruebas/${gateway.envios.single['solicitudId']}.png');
    expect(gateway.borradoresGuardados, isNotEmpty);
    expect(gateway.borrador, isNull);
  });

  testWidgets('galería conserva MIME y un error de red reintenta la misma solicitud',
      (tester) async {
    final gateway = FakeTesoreriaGateway()
      ..erroresEnvio.add(FirebaseException(
          plugin: 'cloud_functions', code: 'unavailable', message: 'Sin conexión'));
    addTearDown(gateway.dispose);
    await montar(tester, ComprobantePagoV58Page(gateway: gateway));
    await elegirCuentaCargo(tester);
    await elegirImagen(tester);
    await pulsar(tester, find.byKey(_enviar));

    expect(gateway.origenesSeleccionados, [TesoreriaImagenOrigen.galeria]);
    expect(gateway.envios, hasLength(1));
    final primero = Map<String, dynamic>.from(gateway.envios.single);
    expect(gateway.borrador?['solicitudId'], primero['solicitudId']);
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    await pulsar(tester, find.byKey(_enviar));

    expect(gateway.envios, hasLength(2));
    expect(gateway.envios[1], primero);
    expect(gateway.subidas, hasLength(1));
    expect(gateway.borrador, isNull);
  });

  testWidgets('doble pulsación mientras Firebase responde no envía dos operaciones',
      (tester) async {
    final gateway = FakeTesoreriaGateway()
      ..envioBloqueado = Completer<String>();
    addTearDown(gateway.dispose);
    await montar(tester, ComprobantePagoV58Page(gateway: gateway));
    await elegirCuentaCargo(tester);
    await elegirImagen(tester);
    await tester.ensureVisible(find.byKey(_enviar));
    await tester.tap(find.byKey(_enviar));
    await tester.pump();
    await tester.pump();

    expect(gateway.envios, hasLength(1));
    final boton = tester.widget<ElevatedButton>(find.byKey(_enviar));
    expect(boton.onPressed, isNull);
    await tester.tap(find.byKey(_enviar));
    await tester.pump();
    expect(gateway.envios, hasLength(1));
    gateway.envioBloqueado!.complete('recibo-confirmado');
    await tester.pumpAndSettle();
    expect(gateway.borrador, isNull);
  });

  testWidgets('borrador recuperado conserva ID, cuenta, cargo y monto sin nueva subida',
      (tester) async {
    final gateway = FakeTesoreriaGateway()
      ..borrador = {
        'uid': 'padre-pruebas',
        'solicitudId': 'solicitud_guardada_0001',
        'cuentaId': 'beneficiario-a',
        'cargoId': 'tesoreria_movimientos/cargo-a',
        'monto': 1500,
        'observacion': 'Recuperado',
        'storagePath':
            'comprobantes_v58/padre-pruebas/solicitud_guardada_0001.png',
        'extension': 'png',
        'mime': 'image/png',
        'archivoSubido': true,
      };
    addTearDown(gateway.dispose);
    await montar(tester, ComprobantePagoV58Page(gateway: gateway));
    await pulsar(tester, find.byKey(_enviar));

    expect(gateway.envios, hasLength(1));
    expect(gateway.envios.single['solicitudId'], 'solicitud_guardada_0001');
    expect(gateway.envios.single['monto'], 1500);
    expect(gateway.envios.single['cuentaId'], 'beneficiario-a');
    expect(gateway.subidas, isEmpty);
    expect(gateway.borrador, isNull);
  });

  testWidgets('imagen recuperada de Android se muestra sin volver a abrir galería',
      (tester) async {
    final gateway = FakeTesoreriaGateway()
      ..imagenRecuperada = FakeTesoreriaGateway.png;
    addTearDown(gateway.dispose);
    await montar(tester, ComprobantePagoV58Page(gateway: gateway));
    await elegirCuentaCargo(tester);
    await pulsar(tester, find.byKey(_enviar));

    expect(gateway.recuperacionesImagen, 1);
    expect(gateway.origenesSeleccionados, isEmpty);
    expect(gateway.subidas, hasLength(1));
    expect(gateway.envios, hasLength(1));
  });

  testWidgets('no se sube comprobante por cero, exceso o cuenta sin cargo',
      (tester) async {
    final gateway = FakeTesoreriaGateway();
    addTearDown(gateway.dispose);
    await montar(tester, ComprobantePagoV58Page(gateway: gateway));
    await elegirCuentaCargo(tester);
    await elegirImagen(tester);
    for (final valor in ['0', '5001']) {
      await tester.enterText(find.byKey(_monto), valor);
      await pulsar(tester, find.byKey(_enviar));
      expect(gateway.envios, isEmpty);
      expect(gateway.subidas, isEmpty);
    }
    await pulsar(tester, find.byKey(_cuenta));
    await pulsar(tester, find.text('Beneficiario B · beneficiario-b').last);
    await pulsar(tester, find.byKey(_enviar));
    expect(gateway.envios, isEmpty);
    expect(gateway.subidas, isEmpty);
  });

  testWidgets('ruta real Tesorería aprueba el cargo canónico desde la bandeja',
      (tester) async {
    final gateway = FakeTesoreriaGateway()..pendientes = [recibo()];
    addTearDown(gateway.dispose);
    await montar(tester, app.ComprobantesPendientesPage(gateway: gateway));
    await pulsar(tester, find.byKey(const Key('revision-aprobar-recibo-1')));
    await pulsar(tester, find.byKey(_confirmar));

    expect(gateway.revisiones, hasLength(1));
    expect(gateway.revisiones.single, {
      'comprobanteId': 'recibo-1',
      'decision': 'aprobado',
      'motivo': '',
      'cuentaId': 'beneficiario-a',
      'cargoId': 'tesoreria_movimientos/cargo-a',
    });
    expect(gateway.pendientes, isEmpty);
  });

  testWidgets('rechazo exige motivo y lo transmite al backend sin aprobar',
      (tester) async {
    final gateway = FakeTesoreriaGateway()..pendientes = [recibo()];
    addTearDown(gateway.dispose);
    await montar(tester, RevisionComprobantesV58Page(gateway: gateway));
    await pulsar(tester, find.byKey(const Key('revision-rechazar-recibo-1')));
    await pulsar(tester, find.byKey(_confirmar));
    expect(gateway.revisiones, isEmpty);
    await tester.enterText(find.byKey(const Key('revision-motivo')),
        'No se recibió la transferencia.');
    await pulsar(tester, find.byKey(_confirmar));

    expect(gateway.revisiones, hasLength(1));
    expect(gateway.revisiones.single['decision'], 'rechazado');
    expect(gateway.revisiones.single['motivo'], 'No se recibió la transferencia.');
    expect(gateway.envios, isEmpty);
  });

  testWidgets('comprobante histórico no se aprueba sin elegir cuenta y cargo',
      (tester) async {
    final gateway = FakeTesoreriaGateway()
      ..pendientes = [recibo(historico: true)];
    addTearDown(gateway.dispose);
    await montar(tester, RevisionComprobantesV58Page(gateway: gateway));
    await pulsar(tester, find.byKey(const Key('revision-aprobar-recibo-1')));
    await pulsar(tester, find.byKey(_confirmar));
    expect(gateway.revisiones, isEmpty);

    await pulsar(tester, find.byKey(const Key('revision-cuenta')));
    await pulsar(tester, find.text('Beneficiario A · beneficiario-a').last);
    await pulsar(tester, find.byKey(const Key('revision-cargo')));
    await pulsar(tester, find.textContaining('Mensualidad diciembre').last);
    await pulsar(tester, find.byKey(_confirmar));
    expect(gateway.revisiones.single['cuentaId'], 'beneficiario-a');
    expect(gateway.revisiones.single['cargoId'], 'tesoreria_movimientos/cargo-a');
  });

  testWidgets('error del servidor mantiene el comprobante pendiente y visible',
      (tester) async {
    final gateway = FakeTesoreriaGateway()
      ..pendientes = [recibo()]
      ..erroresRevision.add(FirebaseException(
          plugin: 'cloud_functions',
          code: 'failed-precondition',
          message: 'El saldo cambió. Vuelva a consultar.'));
    addTearDown(gateway.dispose);
    await montar(tester, RevisionComprobantesV58Page(gateway: gateway));
    await pulsar(tester, find.byKey(const Key('revision-aprobar-recibo-1')));
    await pulsar(tester, find.byKey(_confirmar));

    expect(gateway.revisiones, hasLength(1));
    expect(gateway.pendientes, hasLength(1));
    expect(find.textContaining('El saldo cambió'), findsOneWidget);
    expect(find.byKey(_confirmar), findsOneWidget);
  });

  testWidgets('aviso Tesorería cuenta pendientes en tiempo real y abre revisión',
      (tester) async {
    final gateway = FakeTesoreriaGateway()
      ..pendientes = [recibo(), recibo(id: 'recibo-2')];
    addTearDown(gateway.dispose);
    var aperturas = 0;
    await montar(
        tester,
        Scaffold(
            body: AvisoComprobantesPendientesV58(
                gateway: gateway, onAbrir: () => aperturas++)));
    expect(find.text('2 comprobantes pendientes de revisión'), findsOneWidget);
    await pulsar(tester, find.text('2 comprobantes pendientes de revisión'));
    expect(aperturas, 1);

    gateway.actualizarPendientes([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('pendientes de revisión'), findsNothing);
  });
}
