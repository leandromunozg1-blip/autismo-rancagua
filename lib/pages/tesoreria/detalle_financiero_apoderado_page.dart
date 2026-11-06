import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/tesoreria_finanzas_service.dart';
import '../../services/tesoreria_v58_service.dart';

class DetalleFinancieroApoderadoPage extends StatefulWidget {
  final String apoderadoId;
  final String nombreApoderado;
  final String emailApoderado;
  final String telefonoApoderado;

  const DetalleFinancieroApoderadoPage({
    super.key,
    required this.apoderadoId,
    required this.nombreApoderado,
    required this.emailApoderado,
    required this.telefonoApoderado,
  });

  @override
  State<DetalleFinancieroApoderadoPage> createState() => _DetalleFinancieroApoderadoPageState();
}

class _DetalleFinancieroApoderadoPageState extends State<DetalleFinancieroApoderadoPage> {
  late Future<_DetalleFinanciero> future;

  @override
  void initState() {
    super.initState();
    future = _cargarDetalle();
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }

  String _money(dynamic valor) {
    final n = _toInt(valor);
    return '\$${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  DateTime? _fecha(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is Map && v['_seconds'] is num) {
      return DateTime.fromMillisecondsSinceEpoch((v['_seconds'] as num).toInt() * 1000);
    }
    return DateTime.tryParse(v.toString());
  }

  String _fechaTxt(dynamic v) {
    final f = _fecha(v);
    if (f == null) return '';
    return DateFormat('dd-MM-yyyy HH:mm').format(f);
  }

  // La cuenta financiera es el beneficiario. Nunca unir por nombre/correo
  // ni por UID del padre, que puede tener varias cuentas.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _asignacionesCuenta() async {
    final snap = await FirebaseFirestore.instance
        .collection('ar_asignaciones_mensuales')
        .where('beneficiario_id', isEqualTo: widget.apoderadoId)
        .get();
    return snap.docs;
  }

  _Linea _linea({
    required String categoria,
    required String concepto,
    required int monto,
    required String estado,
    required dynamic fecha,
    required bool afectaTesoreria,
    String origen = '',
    String observacion = '',
    String docId = '',
  }) {
    return _Linea(
      categoria: categoria,
      concepto: concepto,
      monto: monto,
      estado: estado,
      fecha: _fecha(fecha),
      afectaTesoreria: afectaTesoreria,
      origen: origen,
      observacion: observacion,
      docId: docId,
    );
  }

  Future<_DetalleFinanciero> _cargarDetalle() async {
    final respuesta = await TesoreriaV58Service.consultar(widget.apoderadoId);
    final apoderado = TesoreriaV58Service.mapa(respuesta['cuenta']);
    final resumen = TesoreriaFinanzasService.desdeRespuesta(respuesta);
    final lineas = <_Linea>[];
    for (final cargo in TesoreriaV58Service.mapas(respuesta['cargos'])) {
      final saldo = _toInt(cargo['saldo']);
      lineas.add(_linea(
        categoria: (cargo['tipo'] ?? '').toString().contains('multa') ? 'Multa' : 'Deuda / cargo',
        concepto: (cargo['concepto'] ?? cargo['tipo'] ?? 'Cargo').toString(),
        monto: _toInt(cargo['monto']),
        estado: saldo == 0 ? 'pagado' : (_toInt(cargo['pagado']) > 0 ? 'abono' : 'pendiente'),
        fecha: cargo['fecha'],
        afectaTesoreria: true,
        origen: (cargo['id'] ?? '').toString(),
        observacion: 'Período: ${cargo['periodo'] ?? 'sin_periodo'} · Abonado: ${_money(cargo['pagado'])} · Saldo: ${_money(saldo)}',
      ));
    }
    // La respuesta canónica ya deduplica por identidad; no sumar nuevamente
    // los espejos de tesoreria_movimientos / tesoreria_pagos / comprobantes.
    for (final pago in TesoreriaV58Service.mapas(respuesta['pagos'])) {
      lineas.add(_linea(
        categoria: 'Ingreso tesorería',
        concepto: 'Pago aprobado',
        monto: _toInt(pago['monto']),
        estado: 'aprobado',
        fecha: pago['fecha'],
        afectaTesoreria: true,
        origen: (pago['id'] ?? '').toString(),
        observacion: (pago['periodo'] ?? '').toString(),
      ));
    }
    for (final doc in await _asignacionesCuenta()) {
      final d = doc.data();
      final estado = (d['estado'] ?? 'activa').toString();
      if (['eliminada', 'inactiva'].contains(estado.toLowerCase())) continue;
      lineas.add(_linea(
        categoria: 'Sesión mensual (referencia)',
        concepto: (d['servicio_nombre'] ?? d['terapia'] ?? 'Terapia').toString(),
        monto: _toInt(d['valor_definitivo'] ?? d['valor_base']),
        estado: estado,
        fecha: d['actualizado'] ?? d['creado'],
        afectaTesoreria: false,
        origen: 'ar_asignaciones_mensuales',
        docId: doc.id,
        observacion: 'Define próximos cargos; no constituye una deuda por sí sola.',
      ));
    }
    lineas.sort((a, b) => (b.fecha ?? DateTime(1900)).compareTo(a.fecha ?? DateTime(1900)));
    return _DetalleFinanciero(apoderado: apoderado, lineas: lineas, resumen: resumen);
  }

  int _total(List<_Linea> lineas, bool Function(_Linea) test) {
    return lineas.where(test).fold<int>(0, (s, l) => s + l.monto);
  }

  Future<void> _generarPdf(_DetalleFinanciero detalle) async {
    final pdf = pw.Document();
    final lineas = detalle.lineas;
    final deudaActual = detalle.resumen.deuda;
    final ingresos = detalle.resumen.pagos;
    final multas = _total(lineas, (l) => l.afectaTesoreria && l.categoria.toLowerCase().contains('multa'));
    final reemplazos = _total(lineas, (l) => !l.afectaTesoreria && l.categoria.toLowerCase().contains('aseo'));

    pdf.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('Autismo Rancagua', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Detalle financiero por apoderado', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Generado el ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}'),
          pw.SizedBox(height: 10),
          pw.Text('Apoderado: ${widget.nombreApoderado}'),
          pw.Text('Teléfono: ${widget.telefonoApoderado}'),
          pw.Text('Correo: ${widget.emailApoderado}'),
          pw.SizedBox(height: 10),
          ...detalle.resumen.advertencias.map((mensaje) => pw.Text('Conciliación pendiente: $mensaje')),
          pw.Text('Resumen', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Ingresos registrados en tesorería: ${_money(ingresos)}'),
          pw.Text('Deuda vigente: ${_money(deudaActual)}'),
          pw.Text('Multas registradas: ${_money(multas)}'),
          pw.Text('Pagos reemplazo aseo informativos: ${_money(reemplazos)}'),
          pw.Text('Nota: los pagos por reemplazo de aseo se muestran como control interno, pero no ingresan a tesorería.'),
          pw.SizedBox(height: 12),
          if (lineas.isEmpty)
            pw.Text('No hay movimientos registrados para este apoderado.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Fecha', 'Categoría', 'Concepto', 'Monto', 'Estado', 'Tesorería', 'Observación'],
              data: lineas.map((l) => [
                l.fecha == null ? '' : DateFormat('dd-MM-yyyy').format(l.fecha!),
                l.categoria,
                l.concepto,
                _money(l.monto),
                l.estado,
                l.afectaTesoreria ? 'Sí' : 'No',
                l.observacion,
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7),
              border: pw.TableBorder.all(),
              cellAlignment: pw.Alignment.centerLeft,
            ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }


  Future<void> _editarFichaTesoreria(_DetalleFinanciero detalle) async {
    final cuotaCtrl = TextEditingController(text: _toInt(detalle.apoderado['cuota_mensual']).toString());
    final mensajeCtrl = TextEditingController(text: (detalle.apoderado['mensaje_aviso'] ?? '').toString());
    bool avisoActivo = detalle.apoderado['aviso_activo'] == true;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Editar ficha Tesorería'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cuotaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor mensual / terapia definido por Tesorería',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFEAF6FF), borderRadius: BorderRadius.circular(12)),
                  child: Text('Deuda calculada desde Firebase: ${_money(detalle.resumen.deuda)}\nLa deuda no se edita manualmente; se obtiene de cargos menos pagos/abonos.', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar aviso al apoderad@'),
                  value: avisoActivo,
                  onChanged: (v) => setLocal(() => avisoActivo = v),
                ),
                TextField(
                  controller: mensajeCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Mensaje de aviso'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (guardar != true) return;
    if (!RegExp(r'^\d{1,9}$').hasMatch(cuotaCtrl.text.trim())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un monto entero no negativo.')));
      return;
    }
    final cuota = _toInt(cuotaCtrl.text);
    final deuda = detalle.resumen.deuda;
    final mensaje = mensajeCtrl.text.trim().isEmpty
        ? 'Mantiene un cobro pendiente en Tesorería.'
        : mensajeCtrl.text.trim();

    await FirebaseFirestore.instance.collection('tesoreria_apoderados').doc(widget.apoderadoId).set({
      'cuota_mensual': cuota,
      'aviso_activo': avisoActivo && deuda > 0,
      'mensaje_aviso': (avisoActivo && deuda > 0) ? mensaje : '',
      'actualizado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() => future = _cargarDetalle());
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ficha actualizada por Tesorería.')));
  }

  Widget _resumenCard(String titulo, int monto, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: Colors.white),
          const SizedBox(height: 4),
          Text(_money(monto), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Future<void> _editarValorSesion(_Linea l) async {
    if (l.docId.trim().isEmpty) return;
    final valorCtrl = TextEditingController(text: l.monto.toString());
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar valor de sesión'),
        content: TextField(
          controller: valorCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Valor definitivo', prefixText: '\$ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true) return;
    if (!RegExp(r'^\d{1,9}$').hasMatch(valorCtrl.text.trim())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un monto entero no negativo.')));
      return;
    }
    final nuevoValor = _toInt(valorCtrl.text);
    await FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').doc(l.docId).set({
      'valor_definitivo': nuevoValor,
      'valor_editado_tesoreria': true,
      'fecha_edicion_valor': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final asignaciones = await _asignacionesCuenta();
    var totalSesiones = 0;
    for (final doc in asignaciones) {
      final d = doc.data();
      final estado = (d['estado'] ?? 'activa').toString().toLowerCase();
      if (estado == 'eliminada' || estado == 'inactiva') continue;
      totalSesiones += _toInt(d['valor_definitivo'] ?? d['valor_base']);
    }
    await FirebaseFirestore.instance.collection('tesoreria_apoderados').doc(widget.apoderadoId).set({
      // Cambiar una asignación modifica el valor base de próximos cargos, nunca reescribe deuda histórica.
      'cuota_mensual': totalSesiones,
      'actualizado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() => future = _cargarDetalle());
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valor de sesión actualizado.')));
  }

  Widget _lineaTile(_Linea l) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: l.afectaTesoreria ? const Color(0xFF004193) : const Color(0xFF6A1B9A),
          child: Icon(l.afectaTesoreria ? Icons.account_balance : Icons.cleaning_services, color: Colors.white),
        ),
        title: Text('${l.categoria} · ${_money(l.monto)}', style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(
          '${l.concepto}\nEstado: ${l.estado} | Fecha: ${l.fecha == null ? 'Sin fecha' : _fechaTxt(l.fecha)}\n${l.afectaTesoreria ? 'Afecta tesorería' : 'NO afecta tesorería'}${l.observacion.isEmpty ? '' : '\n${l.observacion}'}',
        ),
        isThreeLine: true,
        trailing: l.origen == 'ar_asignaciones_mensuales'
            ? IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Editar valor de esta sesión',
                onPressed: () => _editarValorSesion(l),
              )
            : null,
      ),
    );
  }

  String _nombrePeriodo(String periodo) {
    if (periodo == 'sin_periodo') return 'Sin período informado';
    final partes = periodo.split('-');
    if (partes.length != 2) return periodo;
    final mes = int.tryParse(partes[1]);
    const meses = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    if (mes == null || mes < 1 || mes > 12) return periodo;
    return '${meses[mes]} ${partes[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
        title: const Text('Detalle por apoderado', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          FutureBuilder<_DetalleFinanciero>(
            future: future,
            builder: (context, snap) => IconButton(
              onPressed: snap.hasData ? () => _generarPdf(snap.data!) : null,
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Generar PDF',
            ),
          ),
        ],
      ),
      body: FutureBuilder<_DetalleFinanciero>(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No fue posible consultar el libro: ${snap.error}')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final detalle = snap.data!;
          final lineas = detalle.lineas;
          final deudaActual = detalle.resumen.deuda;
          final ingresos = detalle.resumen.pagos;
          final multas = _total(lineas, (l) => l.afectaTesoreria && l.categoria.toLowerCase().contains('multa'));
          final reemplazos = _total(lineas, (l) => !l.afectaTesoreria && l.categoria.toLowerCase().contains('aseo'));

          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              ...detalle.resumen.advertencias.map((mensaje) => Card(color: const Color(0xFFFFF3CD), child: Padding(padding: const EdgeInsets.all(12), child: Text(mensaje)))),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.nombreApoderado, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
                    Text(widget.telefonoApoderado),
                    Text(widget.emailApoderado),
                    const SizedBox(height: 8),
                    Text('Valor mensual/ficha: ${_money(detalle.apoderado['cuota_mensual'])}', style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text('Los pagos por reemplazo de aseo se consultan en su módulo; no se descuentan de cargos de Tesorería.', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _editarFichaTesoreria(detalle),
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar ficha / valor Tesorería'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.05,
                children: [
                  _resumenCard('Ingresos tesorería', ingresos, Icons.payments, const Color(0xFF2E7D32)),
                  _resumenCard('Deuda vigente', deudaActual, Icons.warning_amber, const Color(0xFFC62828)),
                  _resumenCard('Multas', multas, Icons.gavel, const Color(0xFFE65100)),
                  _resumenCard('Reemplazo aseo', reemplazos, Icons.cleaning_services, const Color(0xFF6A1B9A)),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Saldo mes a mes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
              const SizedBox(height: 8),
              if (!detalle.resumen.usaLibroMayor)
                const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('No hay un libro de cargos explícitos. El caché de deuda V57 no se convierte automáticamente en obligaciones; requiere conciliación.', style: TextStyle(fontWeight: FontWeight.w700))))
              else if (detalle.resumen.periodos.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Sin cargos ni pagos registrados por período.')))
              else
                ...detalle.resumen.periodos.reversed.map((p) => Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFDCE8F2))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      const CircleAvatar(radius: 18, backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.calendar_month, size: 19, color: Color(0xFF004193))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_nombrePeriodo(p.periodo), style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('Cargo ${_money(p.cargos)}  ·  Pagado ${_money(p.pagos)}', style: const TextStyle(fontSize: 12)),
                        Text('Saldo mes ${_money(p.saldoMes)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.saldoMes > 0 ? const Color(0xFFC62828) : const Color(0xFF2E7D32))),
                      ])),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const Text('Acumulado', style: TextStyle(fontSize: 10, color: Colors.black54)),
                        Text(_money(p.saldo), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: p.saldo > 0 ? const Color(0xFFC62828) : const Color(0xFF2E7D32))),
                      ]),
                    ]),
                  ),
                )),
              const SizedBox(height: 14),
              const Text('Movimientos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
              const SizedBox(height: 8),
              if (lineas.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No hay movimientos registrados.')))
              else
                ...lineas.map(_lineaTile),
            ],
          );
        },
      ),
    );
  }
}

class _DetalleFinanciero {
  final Map<String, dynamic> apoderado;
  final List<_Linea> lineas;
  final ResumenFinancieroTesoreria resumen;

  _DetalleFinanciero({required this.apoderado, required this.lineas, required this.resumen});
}

class _Linea {
  final String categoria;
  final String concepto;
  final int monto;
  final String estado;
  final DateTime? fecha;
  final bool afectaTesoreria;
  final String origen;
  final String observacion;
  final String docId;

  _Linea({
    required this.categoria,
    required this.concepto,
    required this.monto,
    required this.estado,
    required this.fecha,
    required this.afectaTesoreria,
    required this.origen,
    required this.observacion,
    this.docId = '',
  });
}
