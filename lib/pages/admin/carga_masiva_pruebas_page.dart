import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CargaMasivaPruebasPage extends StatefulWidget {
  const CargaMasivaPruebasPage({super.key});

  @override
  State<CargaMasivaPruebasPage> createState() =>
      _CargaMasivaPruebasPageState();
}

class _CargaMasivaPruebasPageState extends State<CargaMasivaPruebasPage> {
  bool cargando = false;

  String _uid(int i) => 'test_padre_$i';
  String _email(int i) => '$i@test.cl';
  String _telefono(int i) => '+569${(10000000 + i * 111111).toString()}';

  Future<void> cargarDatosFicticios() async {
    setState(() => cargando = true);

    try {
      final firestore = FirebaseFirestore.instance;

      final nombres = [
        'María González',
        'Juan Pérez',
        'Carolina Soto',
        'Pedro Ramírez',
        'Camila Torres',
        'Luis Hernández',
        'Fernanda Rojas',
        'Marcelo Díaz',
        'Valentina Morales',
        'Andrés Fuentes',
      ];

      final deudas = [
        0,
        15000,
        30000,
        45000,
        0,
        60000,
        15000,
        0,
        75000,
        30000,
      ];

      final cuotasMorosas = [
        0,
        1,
        2,
        3,
        0,
        4,
        1,
        0,
        5,
        2,
      ];

      for (int i = 1; i <= 10; i++) {
        final uid = _uid(i);
        final nombre = nombres[i - 1];
        final email = _email(i);
        final telefono = _telefono(i);
        final deuda = deudas[i - 1];
        final cuotas = cuotasMorosas[i - 1];
        final estaMoroso = deuda > 0;

        await firestore.collection('usuarios').doc(uid).set({
          'nombre': nombre,
          'nombre_apoderado': nombre,
          'email': email,
          'telefono': telefono,
          'rol': 'apoderado',
          'estado': 'activo',
          'es_prueba': true,
          'fecha_creacion': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await firestore.collection('tesoreria_apoderados').doc(uid).set({
          'nombre': nombre,
          'nombre_apoderado': nombre,
          'email': email,
          'telefono': telefono,
          'cuota_mensual': 15000,
          'monto_deuda': deuda,
          'meses_morosos': cuotas,
          'estado_pago': estaMoroso ? 'pendiente' : 'al_dia',
          'estado_terapias':
              estaMoroso ? 'suspendido_por_morosidad' : 'activo',
          'aviso_activo': estaMoroso,
          'mensaje_aviso': estaMoroso
              ? 'Mantiene $cuotas cuota(s) pendiente(s). Regularice para activar terapias.'
              : '',
          'ultimo_mes_procesado': '',
          'fecha_creacion': FieldValue.serverTimestamp(),
          'actualizado': FieldValue.serverTimestamp(),
          'es_prueba': true,
        }, SetOptions(merge: true));
      }

      const eventoId = 'evento_prueba_completada_5000';
      final fechaLimite = DateTime.now().add(const Duration(days: 7));

      await firestore.collection('tesoreria_eventos').doc(eventoId).set({
        'titulo': 'Completada de prueba',
        'monto': 5000,
        'fecha_limite': Timestamp.fromDate(fechaLimite),
        'activo': true,
        'creado_por': 'sistema_prueba',
        'fecha_creacion': FieldValue.serverTimestamp(),
        'es_prueba': true,
      }, SetOptions(merge: true));

      for (int i = 1; i <= 10; i++) {
        final uid = _uid(i);
        final nombre = nombres[i - 1];
        final email = _email(i);
        final telefono = _telefono(i);
        final pagado = i <= 5;

        await firestore
            .collection('tesoreria_evento_cargos')
            .doc('${eventoId}_$uid')
            .set({
          'evento_id': eventoId,
          'evento_titulo': 'Completada de prueba',
          'apoderado_id': uid,
          'apoderado_nombre': nombre,
          'apoderado_email': email,
          'telefono': telefono,
          'monto': 5000,
          'estado': pagado ? 'pagado' : 'pendiente',
          'fecha_limite': Timestamp.fromDate(fechaLimite),
          'fecha_creacion': FieldValue.serverTimestamp(),
          'fecha_pago': pagado ? FieldValue.serverTimestamp() : null,
          'monto_pagado': pagado ? 5000 : 0,
          'es_prueba': true,
        }, SetOptions(merge: true));

        if (pagado) {
          await firestore
              .collection('tesoreria_pagos')
              .doc('pago_${eventoId}_$uid')
              .set({
            'apoderado_id': uid,
            'apoderado_nombre': nombre,
            'email': email,
            'telefono': telefono,
            'monto': 5000,
            'tipo': 'evento',
            'evento_id': eventoId,
            'evento_titulo': 'Completada de prueba',
            'estado': 'aprobado',
            'fecha': FieldValue.serverTimestamp(),
            'aprobado_por': 'sistema_prueba',
            'es_prueba': true,
          }, SetOptions(merge: true));
        } else {
          await firestore.collection('avisos_apoderados').doc('aviso_${eventoId}_$uid').set({
            'apoderado_id': uid,
            'email': email,
            'titulo': 'Nueva cuota: Completada de prueba',
            'mensaje': 'Monto: \$5.000. Fecha límite próxima.',
            'leido': false,
            'tipo': 'tesoreria_evento',
            'fecha': FieldValue.serverTimestamp(),
            'es_prueba': true,
          }, SetOptions(merge: true));
        }
      }

      for (int i = 6; i <= 8; i++) {
        final uid = _uid(i);
        await firestore.collection('tesoreria_comprobantes').doc('comp_prueba_$i').set({
          'apoderado_id': uid,
          'uid': uid,
          'apoderado_nombre': nombres[i - 1],
          'email': _email(i),
          'telefono': _telefono(i),
          'monto': i == 6 ? 15000 : 5000,
          'estado': 'pendiente',
          'observacion': i == 6
              ? 'Comprobante ficticio mensualidad'
              : 'Comprobante ficticio evento completada',
          'evento_id': i == 6 ? '' : eventoId,
          'fecha': FieldValue.serverTimestamp(),
          'es_prueba': true,
        }, SetOptions(merge: true));
      }

      await firestore.collection('tesoreria_auditoria').add({
        'accion': 'carga_datos_ficticios',
        'detalle':
            'Se cargaron 10 apoderados ficticios y evento Completada de prueba por \$5.000.',
        'usuario_email': 'sistema_prueba',
        'fecha': FieldValue.serverTimestamp(),
        'es_prueba': true,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Datos ficticios cargados: 10 padres + evento completada \$5.000.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar datos ficticios: $e')),
      );
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Future<void> eliminarDatosFicticios() async {
    setState(() => cargando = true);

    try {
      final firestore = FirebaseFirestore.instance;
      const eventoId = 'evento_prueba_completada_5000';

      for (int i = 1; i <= 10; i++) {
        final uid = _uid(i);

        await firestore.collection('usuarios').doc(uid).delete();
        await firestore.collection('tesoreria_apoderados').doc(uid).delete();
        await firestore
            .collection('tesoreria_evento_cargos')
            .doc('${eventoId}_$uid')
            .delete();
        await firestore
            .collection('tesoreria_pagos')
            .doc('pago_${eventoId}_$uid')
            .delete();
        await firestore
            .collection('avisos_apoderados')
            .doc('aviso_${eventoId}_$uid')
            .delete();
        await firestore
            .collection('tesoreria_comprobantes')
            .doc('comp_prueba_$i')
            .delete();
      }

      await firestore.collection('tesoreria_eventos').doc(eventoId).delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos ficticios eliminados.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar datos ficticios: $e')),
      );
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Datos Ficticios Tesorería',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Text(
              'Esta herramienta NO crea cuentas de inicio de sesión.\n\n'
              'Solo carga datos ficticios en Firestore para probar Tesorería y PDFs:\n\n'
              '• 10 apoderados ficticios: 1@test.cl a 10@test.cl\n'
              '• algunos al día\n'
              '• algunos con 1 a 5 cuotas morosas\n'
              '• evento ficticio: Completada de prueba \$5.000\n'
              '• 5 pagados y 5 pendientes del evento\n'
              '• comprobantes ficticios pendientes',
              style: TextStyle(
                color: Color(0xFF063E83),
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: cargando ? null : cargarDatosFicticios,
            icon: const Icon(Icons.group_add),
            label: Text(
              cargando ? 'Cargando...' : 'Cargar datos ficticios',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004193),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: cargando ? null : eliminarDatosFicticios,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Eliminar datos ficticios'),
          ),
        ],
      ),
    );
  }
}
