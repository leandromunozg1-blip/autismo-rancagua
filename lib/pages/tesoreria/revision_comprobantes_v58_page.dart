import 'package:flutter/material.dart';

import '../../services/tesoreria_v58_gateway.dart';
import 'comprobante_widgets_v58.dart';

/// Aviso visible desde la portada real de Tesorería. El mismo stream alimenta
/// la bandeja: un comprobante revisado deja de figurar pendiente de inmediato.
class AvisoComprobantesPendientesV58 extends StatefulWidget {
  final TesoreriaV58Gateway? gateway;
  final VoidCallback onAbrir;
  const AvisoComprobantesPendientesV58({super.key, this.gateway, required this.onAbrir});

  @override
  State<AvisoComprobantesPendientesV58> createState() => _AvisoComprobantesPendientesV58State();
}

class _AvisoComprobantesPendientesV58State extends State<AvisoComprobantesPendientesV58> {
  late final Stream<List<Map<String, dynamic>>> _pendientes;

  @override
  void initState() {
    super.initState();
    _pendientes = (widget.gateway ?? FirebaseTesoreriaV58Gateway()).comprobantesPendientes();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: _pendientes,
    builder: (context, snap) {
      if (snap.hasError) return const Padding(padding: EdgeInsets.all(8), child: Text('No se pudo consultar el aviso de comprobantes pendientes.'));
      if (!snap.hasData) return const LinearProgressIndicator();
      final cantidad = snap.data!.length;
      if (cantidad == 0) return const SizedBox.shrink();
      return Material(color: const Color(0xFFFFF0D6), child: ListTile(
        key: const Key('tesoreria-aviso-comprobantes'),
        leading: const Icon(Icons.notifications_active_outlined),
        title: Text('$cantidad comprobante${cantidad == 1 ? '' : 's'} pendiente${cantidad == 1 ? '' : 's'} de revisión'),
        subtitle: const Text('Verifica el depósito y aprueba o rechaza con motivo.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onAbrir,
      ));
    },
  );
}

class RevisionComprobantesV58Page extends StatefulWidget {
  final bool embedded;
  final TesoreriaV58Gateway? gateway;
  const RevisionComprobantesV58Page({super.key, this.embedded = false, this.gateway});

  @override
  State<RevisionComprobantesV58Page> createState() => _RevisionComprobantesV58PageState();
}

class _RevisionComprobantesV58PageState extends State<RevisionComprobantesV58Page> {
  late final TesoreriaV58Gateway _gateway;
  late final Stream<List<Map<String, dynamic>>> _pendientes;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseTesoreriaV58Gateway();
    _pendientes = _gateway.comprobantesPendientes();
  }

  @override
  Widget build(BuildContext context) {
    final contenido = StreamBuilder<List<Map<String, dynamic>>>(
      stream: _pendientes,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No se pudieron consultar los comprobantes: ${mensajeErrorTesoreria(snap.error!)}')));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = [...snap.data!];
        docs.sort((a, b) => fechaComprobanteTesoreria(a['fecha']).compareTo(fechaComprobanteTesoreria(b['fecha'])));
        if (docs.isEmpty) return const Center(child: Text('No hay comprobantes pendientes de revisión.'));
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          itemBuilder: (context, index) => _ComprobanteCard(
            key: ValueKey(docs[index]['id']), id: docs[index]['id'].toString(),
            data: docs[index], gateway: _gateway,
          ),
        );
      },
    );
    return widget.embedded ? contenido : Scaffold(appBar: AppBar(title: const Text('Comprobantes pendientes')), body: contenido);
  }
}

class _ComprobanteCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final TesoreriaV58Gateway gateway;
  const _ComprobanteCard({super.key, required this.id, required this.data, required this.gateway});

  Future<void> _revisar(BuildContext context, bool aprobar) => showDialog<void>(
    context: context, barrierDismissible: false,
    builder: (_) => _RevisionDialog(id: id, data: data, aprobar: aprobar, gateway: gateway),
  );

  @override
  Widget build(BuildContext context) {
    final cuenta = (data['cuenta_id'] ?? '').toString();
    final cargo = (data['cargo_id'] ?? '').toString();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text((data['beneficiario_nombre'] ?? data['apoderado_nombre'] ?? data['nombre_apoderado'] ?? data['email'] ?? 'Comprobante de pago').toString(), style: Theme.of(context).textTheme.titleMedium),
      Text('Monto informado: \$${montoTesoreria(data['monto'])}'),
      Text('Cuenta: ${cuenta.isEmpty ? 'Histórico: seleccionar cuenta al aprobar' : cuenta}'),
      Text('Cargo: ${cargo.isEmpty ? 'Histórico: seleccionar cargo al aprobar' : cargo}'),
      if ((data['periodo'] ?? '').toString().isNotEmpty) Text('Período: ${data['periodo']}'),
      if ((data['observacion'] ?? '').toString().isNotEmpty) Text('Observación: ${data['observacion']}'),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: () => verImagenComprobanteTesoreria(context, data, gateway: gateway), icon: const Icon(Icons.image_outlined), label: const Text('Ver comprobante')),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 8, children: [
        ElevatedButton.icon(key: Key('revision-aprobar-$id'), onPressed: () => _revisar(context, true), icon: const Icon(Icons.check), label: const Text('Aprobar')),
        OutlinedButton.icon(key: Key('revision-rechazar-$id'), onPressed: () => _revisar(context, false), icon: const Icon(Icons.close), label: const Text('Rechazar')),
      ]),
    ])));
  }
}

class _RevisionDialog extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  final bool aprobar;
  final TesoreriaV58Gateway gateway;
  const _RevisionDialog({required this.id, required this.data, required this.aprobar, required this.gateway});

  @override
  State<_RevisionDialog> createState() => _RevisionDialogState();
}

class _RevisionDialogState extends State<_RevisionDialog> {
  final _motivo = TextEditingController();
  List<Map<String, dynamic>> _cuentas = [];
  List<Map<String, dynamic>> _cargos = [];
  String? _cuentaId;
  String? _cargoId;
  String? _error;
  List<String> _advertencias = [];
  bool _cargando = false;
  bool _guardando = false;
  int _consulta = 0;

  bool get _canonico => (widget.data['cuenta_id'] ?? '').toString().isNotEmpty && (widget.data['cargo_id'] ?? '').toString().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.aprobar) _cargar();
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final cuentas = await widget.gateway.cuentas();
      if (!mounted) return;
      setState(() { _cuentas = cuentas; _cargando = false; });
      if (_canonico) {
        final id = widget.data['cuenta_id'].toString();
        if (!_cuentas.any((c) => c['id'] == id)) throw const FormatException('La cuenta del comprobante no está disponible. Revisa sus vínculos antes de aprobar.');
        await _elegirCuenta(id);
      }
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = mensajeErrorTesoreria(e); });
    }
  }

  Future<void> _elegirCuenta(String? id) async {
    final consulta = ++_consulta;
    setState(() { _cuentaId = id; _cargoId = null; _cargos = []; _advertencias = []; _cargando = true; _error = null; });
    try {
      final detalle = id == null ? <String, dynamic>{} : await widget.gateway.consultar(id);
      if (!mounted || consulta != _consulta) return;
      final cargos = mapasTesoreria(detalle['cargos']);
      final fijo = _canonico ? widget.data['cargo_id'].toString() : null;
      if (fijo != null && !cargos.any((c) => c['id'] == fijo)) throw const FormatException('No se encontró el cargo de este comprobante. No se aplicó ningún pago.');
      setState(() {
        _cargos = cargos.where((c) => c['id'] == fijo || montoTesoreria(c['saldo']) > 0).toList();
        _cargoId = fijo;
        _advertencias = ((detalle['advertencias'] as List?) ?? const []).map((e) => e.toString()).toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted && consulta == _consulta) setState(() { _cargando = false; _error = mensajeErrorTesoreria(e); });
    }
  }

  Future<void> _guardar() async {
    if (_guardando || _cargando) return;
    if (widget.aprobar && (_cuentaId == null || _cargoId == null)) {
      setState(() => _error = 'Selecciona explícitamente la cuenta y el cargo correspondiente.');
      return;
    }
    if (widget.aprobar) {
      if (_advertencias.isNotEmpty) {
        setState(() => _error = 'La cuenta requiere conciliación antes de aprobar otro abono. No se cambió el estado del comprobante.');
        return;
      }
      final cargo = _cargos.where((c) => c['id'] == _cargoId).firstOrNull;
      final monto = montoTesoreria(widget.data['monto']);
      if (cargo == null || monto <= 0 || monto > montoTesoreria(cargo['saldo'])) {
        setState(() => _error = 'El monto debe ser positivo y no superar el saldo actual del cargo. Vuelve a consultar antes de aprobar.');
        return;
      }
    }
    if (!widget.aprobar && _motivo.text.trim().length < 3) {
      setState(() => _error = 'Escribe un motivo de rechazo de al menos 3 caracteres para informar al apoderado.');
      return;
    }
    setState(() { _guardando = true; _error = null; });
    try {
      await widget.gateway.revisarComprobante(
        comprobanteId: widget.id, decision: widget.aprobar ? 'aprobado' : 'rechazado',
        motivo: _motivo.text.trim(), cuentaId: _cuentaId, cargoId: _cargoId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.aprobar ? 'Pago aprobado y saldo actualizado. El apoderado recibirá un aviso.' : 'Comprobante rechazado. Se informó el motivo al apoderado.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeErrorTesoreria(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cargo = _cargos.where((c) => c['id'] == _cargoId).firstOrNull;
    return PopScope(
      canPop: !_guardando,
      child: AlertDialog(
        title: Text(widget.aprobar ? 'Verificar y aprobar pago' : 'Rechazar comprobante'),
        content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Monto informado: \$${montoTesoreria(widget.data['monto'])}'),
          if (widget.aprobar) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Confirma que el abono se recibió efectivamente en el banco y corresponde a este cargo. Solo se descontará el monto aprobado.')),
            if (!_canonico) const Text('Comprobante histórico: selecciona la cuenta y el cargo sin deducirlos del correo o nombre.'),
            if (_cargando) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              key: const Key('revision-cuenta'), value: _cuentaId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cuenta / beneficiario'),
              items: _cuentas.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(nombreCuentaTesoreria(c), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _canonico || _guardando || _cargando ? null : _elegirCuenta,
            ),
            DropdownButtonFormField<String>(
              key: const Key('revision-cargo'), value: _cargoId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cargo al que aplicar el abono'),
              items: _cargos.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(etiquetaCargoTesoreria(c), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _canonico || _guardando || _cargando ? null : (id) => setState(() => _cargoId = id),
            ),
            if (cargo != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Saldo consultado: \$${montoTesoreria(cargo['saldo'])}. Abono a aprobar: \$${montoTesoreria(widget.data['monto'])}.')),
            ..._advertencias.map((aviso) => Padding(padding: const EdgeInsets.only(top: 8), child: Text('Requiere conciliación: $aviso', style: const TextStyle(color: Color(0xFF8A5600))))),
          ] else ...[
            const SizedBox(height: 12),
            TextField(key: const Key('revision-motivo'), controller: _motivo, enabled: !_guardando, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Motivo de rechazo (obligatorio)', border: OutlineInputBorder())),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (widget.aprobar && _error != null && !_guardando) TextButton(onPressed: _cargar, child: const Text('Volver a consultar')),
        ]))),
        actions: [
          TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(key: const Key('revision-confirmar'), onPressed: _guardando || _cargando ? null : _guardar, child: Text(_guardando ? 'Guardando…' : widget.aprobar ? 'Confirmar aprobación' : 'Confirmar rechazo')),
        ],
      ),
    );
  }
}
