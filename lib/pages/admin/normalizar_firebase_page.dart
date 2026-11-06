import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NormalizarFirebasePage extends StatefulWidget {
  const NormalizarFirebasePage({super.key});

  @override
  State<NormalizarFirebasePage> createState() => _NormalizarFirebasePageState();
}

class _NormalizarFirebasePageState extends State<NormalizarFirebasePage> {
  final rutCtrl = TextEditingController();
  bool _cargando = false;
  String _resultado = 'Ingrese un RUT y ejecute la corrección. No se hace barrido general para evitar que Firebase devuelva 0 documentos por reglas o caché.';

  @override
  void dispose() {
    rutCtrl.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.replaceAll('.', '').replaceAll('\$', '').trim()) ?? 0;
    return 0;
  }

  String _rut(dynamic value) {
    final raw = (value ?? '').toString().trim().toUpperCase();
    if (raw.isEmpty) return '';
    return raw.replaceAll('RUT:', '').replaceAll('.', '').replaceAll(' ', '').trim();
  }

  Future<int> _sumarMovimientosPendientes(String rut) async {
    var total = 0;
    final db = FirebaseFirestore.instance;

    final campos = ['apoderado_id', 'rutina_usuario', 'rutina_usuario_normalizado', 'uid'];
    final vistos = <String>{};
    for (final campo in campos) {
      final snap = await db
          .collection('tesoros_movimientos')
          .where(campo, isEqualTo: rut)
          .where('estado', isEqualTo: 'pendiente')
          .get();
      for (final doc in snap.docs) {
        if (vistos.add(doc.id)) total += _toInt(doc.data()['monto']);
      }
    }
    return total;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _buscarDocTesoro(String rut) async {
    final db = FirebaseFirestore.instance;

    final directo = await db.collection('tesoro_apoderados').doc(rut).get(const GetOptions(source: Source.server));
    if (directo.exists) return directo;

    for (final campo in ['rutina_usuario', 'rutina_usuario_normalizado', 'uid', 'rut_usuario']) {
      final q = await db
          .collection('tesoro_apoderados')
          .where(campo, isEqualTo: rut)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (q.docs.isNotEmpty) return q.docs.first;
    }
    return null;
  }

  Future<void> _normalizarRut() async {
    final rut = _rut(rutCtrl.text);
    if (rut.isEmpty) {
      setState(() => _resultado = 'Debe ingresar un RUT, por ejemplo RUT de la persona.');
      return;
    }

    setState(() {
      _cargando = true;
      _resultado = 'Corrigiendo $rut directamente en Firebase...';
    });

    try {
      final db = FirebaseFirestore.instance;
      final doc = await _buscarDocTesoro(rut);
      final data = doc?.data() ?? <String, dynamic>{};

      final deudaMovimientos = await _sumarMovimientosPendientes(rut);
      final deudaActual = _toInt(data['monto_deuda']);
      final deuda = deudaMovimientos > 0 ? deudaMovimientos : deudaActual;
      final moroso = deuda > 0;
      final mes = (data['ultimo_mes_procesado'] ?? data['mes'] ?? '').toString();
      final nombreUsuario = (data['nombre_usuario'] ?? data['nombre'] ?? '').toString();
      final nombreApoderado = (data['nombre_apoderado'] ?? '').toString();
      final mensaje = moroso
          ? 'Mantiene pendiente la mensualidad de ${mes.isEmpty ? 'este periodo' : mes}. Regularice su pago para mantener terapias activas.'
          : '';

      final payload = <String, dynamic>{
        'uid': rut,
        'rutina_usuario': rut,
        'rutina_usuario_normalizado': rut,
        'nombre': nombreUsuario,
        'nombre_usuario': nombreUsuario,
        'nombre_apoderado': nombreApoderado,
        'monto_deuda': deuda,
        'meses_morosos': moroso ? (_toInt(data['meses_morosos']) <= 0 ? 1 : _toInt(data['meses_morosos'])) : 0,
        'estado_pago': moroso ? 'pendiente' : 'al_dia',
        'estado_terapias': moroso ? 'suspendido_por_morosidad' : 'activo',
        'aviso_activo': moroso,
        'mensaje_aviso': mensaje,
        'actualizado': FieldValue.serverTimestamp(),
        'normalizado_por_app': true,
        'llave_principal': 'rut',
      };

      // Conserva datos existentes si estaban en el documento encontrado.
      if ((data['rut_apoderado'] ?? '').toString().isNotEmpty) payload['rut_apoderado'] = data['rut_apoderado'];
      if ((data['telefono'] ?? '').toString().isNotEmpty) payload['telefono'] = data['telefono'];
      if ((data['email'] ?? '').toString().isNotEmpty) payload['email'] = data['email'];
      if ((data['cuota_mensual'] ?? '').toString().isNotEmpty) payload['cuota_mensual'] = _toInt(data['cuota_mensual']);
      if (mes.isNotEmpty) payload['ultimo_mes_procesado'] = mes;

      await db.collection('tesoro_apoderados').doc(rut).set(payload, SetOptions(merge: true));

      await db.collection('tesoreria_auditoria').add({
        'tipo': 'normalizacion_manual_rut',
        'rut': rut,
        'documento_origen': doc?.id ?? 'no_existia',
        'deuda_movimientos': deudaMovimientos,
        'deuda_final': deuda,
        'fecha': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _resultado = 'Listo. RUT $rut corregido en tesoro_apoderados/$rut. Deuda final: \$${deuda.toString()}. Aviso activo: ${moroso ? 'sí' : 'no'}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _resultado = 'Error al corregir RUT: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _normalizarDesdeMovimientos() async {
    setState(() {
      _cargando = true;
      _resultado = 'Leyendo tesoros_movimientos pendientes...';
    });

    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('tesoros_movimientos')
          .where('estado', isEqualTo: 'pendiente')
          .get(const GetOptions(source: Source.server));

      final ruts = <String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final rut = _rut(d['apoderado_id'] ?? d['rutina_usuario'] ?? d['uid']);
        if (rut.isNotEmpty) ruts.add(rut);
      }

      for (final rut in ruts) {
        rutCtrl.text = rut;
        await _normalizarRut();
      }

      if (!mounted) return;
      setState(() => _resultado = 'Listo. RUTs corregidos desde movimientos pendientes: ${ruts.length}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _resultado = 'Error leyendo movimientos pendientes: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Normalizar Firebase'),
        backgroundColor: const Color(0xFF0047B3),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            const Text(
              'Corrección segura por RUT. Esta versión NO depende de listar toda la colección tesoro_apoderados. Corrige directamente el documento del RUT y recalcula la deuda desde tesoros_movimientos pendientes.',
              style: TextStyle(fontSize: 16, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: rutCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'RUT beneficiario',
                hintText: 'Ej: RUT de la persona',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _cargando ? null : _normalizarRut,
              icon: _cargando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_cargando ? 'Corrigiendo...' : 'Corregir este RUT en Firebase'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _cargando ? null : _normalizarDesdeMovimientos,
              icon: const Icon(Icons.sync),
              label: const Text('Corregir RUTs con movimientos pendientes'),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_resultado, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
