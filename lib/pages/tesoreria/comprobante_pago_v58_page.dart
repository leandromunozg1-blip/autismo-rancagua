import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/tesoreria_v58_gateway.dart';
import 'comprobante_widgets_v58.dart';

/// Pantalla real del apoderado. Toda operación externa pasa por el mismo
/// adaptador utilizado en producción y puede sustituirse en pruebas de widgets.
class ComprobantePagoV58Page extends StatefulWidget {
  final TesoreriaV58Gateway? gateway;
  final VoidCallback? onHistorial;
  final ValueChanged<String>? onEnviado;

  const ComprobantePagoV58Page({
    super.key,
    this.gateway,
    this.onHistorial,
    this.onEnviado,
  });

  @override
  State<ComprobantePagoV58Page> createState() => _ComprobantePagoV58PageState();
}

class _ComprobantePagoV58PageState extends State<ComprobantePagoV58Page> {
  final _monto = TextEditingController();
  final _observacion = TextEditingController();
  late final TesoreriaV58Gateway _gateway;
  late String _solicitudId;
  List<Map<String, dynamic>> _cuentas = [];
  List<Map<String, dynamic>> _cargos = [];
  Map<String, dynamic>? _envioPendiente;
  String? _cuentaId;
  String? _cargoId;
  Uint8List? _imagen;
  String? _extension;
  String? _mime;
  String? _error;
  String? _informacion;
  bool _cargando = true;
  bool _requiereConciliacion = false;
  bool _enviando = false;
  bool _seleccionandoImagen = false;
  bool _archivoSubido = false;
  bool _puedeCorregir = false;
  bool _enviado = false;
  int _consulta = 0;

  bool get _envioIniciado => _envioPendiente != null;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseTesoreriaV58Gateway();
    _solicitudId = _gateway.nuevaSolicitudId();
    _iniciar();
  }

  @override
  void dispose() {
    _monto.dispose();
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      final guardado = await _gateway.recuperarEnvioPendiente();
      if (!mounted) return;
      if (guardado != null) {
        if (guardado['uid'] != _gateway.uidActual) {
          throw const FormatException('El envío guardado pertenece a otra sesión. Vuelve a iniciar sesión con su propietario.');
        }
        final claves = ['solicitudId', 'cuentaId', 'cargoId', 'storagePath', 'extension', 'mime'];
        if (claves.any((k) => (guardado[k] ?? '').toString().isEmpty) || montoTesoreria(guardado['monto']) <= 0) {
          throw const FormatException('El envío guardado está incompleto. Revisa tu historial antes de solicitar su recuperación.');
        }
        setState(() {
          _envioPendiente = Map<String, dynamic>.from(guardado);
          _solicitudId = guardado['solicitudId'].toString();
          _cuentaId = guardado['cuentaId'].toString();
          _cargoId = guardado['cargoId'].toString();
          _monto.text = guardado['monto'].toString();
          _observacion.text = (guardado['observacion'] ?? '').toString();
          _extension = guardado['extension'].toString();
          _mime = guardado['mime'].toString();
          _archivoSubido = guardado['archivoSubido'] == true;
          _informacion = 'Se recuperó un envío interrumpido. Se conserva su identificador para consultar o reintentar sin duplicarlo.';
        });
        try {
          final bytes = await _gateway.leerImagen(guardado['storagePath'].toString());
          if (!mounted) return;
          if (bytes != null) setState(() { _imagen = bytes; _archivoSubido = true; });
        } catch (e) {
          // Una falla al mostrar la imagen no prueba que el envío no se registró.
          if (mounted) setState(() => _informacion = 'Envío recuperado. No fue posible mostrar la imagen: ${mensajeErrorTesoreria(e)}. Conserva este envío para reintentarlo o revisa el historial.');
        }
      } else {
        final recuperada = await _gateway.recuperarImagenPerdida();
        if (!mounted) return;
        if (recuperada != null) {
          _aceptarImagen(recuperada);
          setState(() => _informacion = 'Se recuperó la imagen de cámara/galería interrumpida por Android. Confirma beneficiario, cargo y monto antes de enviarla.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeErrorTesoreria(e));
    }
    await _cargarCuentas();
  }

  Future<void> _cargarCuentas() async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final cuentas = await _gateway.cuentas();
      if (!mounted) return;
      setState(() { _cuentas = cuentas; _cargando = false; });
      if (_envioIniciado) {
        // La operación guardada se reintenta con sus datos originales. El saldo
        // puede haber cambiado tras una respuesta perdida: Firebase decide si ya existe.
        try {
          final detalle = await _gateway.consultar(_cuentaId!);
          if (mounted) setState(() => _cargos = mapasTesoreria(detalle['cargos']));
        } catch (_) {
          // No invalida un envío ya guardado ni lo convierte en otro depósito.
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = mensajeErrorTesoreria(e); _cargando = false; });
    }
  }

  Future<void> _elegirCuenta(String? id) async {
    final consulta = ++_consulta;
    setState(() { _cuentaId = id; _cargoId = null; _cargos = []; _requiereConciliacion = false; _error = null; _cargando = true; });
    try {
      final detalle = id == null ? <String, dynamic>{} : await _gateway.consultar(id);
      if (!mounted || consulta != _consulta) return;
      setState(() {
        final advertencias = (detalle['advertencias'] as List?) ?? const [];
        _requiereConciliacion = advertencias.isNotEmpty;
        if (_requiereConciliacion) _error = 'Esta cuenta requiere conciliación de Tesorería antes de recibir otro comprobante: ${advertencias.join(' · ')}';
        _cargos = mapasTesoreria(detalle['cargos']).where((c) => montoTesoreria(c['saldo']) > 0).toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted && consulta == _consulta) setState(() { _error = mensajeErrorTesoreria(e); _cargando = false; });
    }
  }

  void _aceptarImagen(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > limiteImagenTesoreria) {
      throw const FormatException('La imagen debe contener entre 1 byte y 10 MiB.');
    }
    final formato = formatoImagenTesoreria(bytes);
    if (formato == null) throw const FormatException('Selecciona una imagen JPEG, PNG o WebP.');
    if (_envioIniciado && (formato.extension != _extension || formato.mime != _mime)) {
      throw const FormatException('Para recuperar este envío selecciona el mismo archivo y formato. No se sustituye el comprobante ya iniciado.');
    }
    setState(() { _imagen = bytes; _extension = formato.extension; _mime = formato.mime; });
  }

  Future<void> _seleccionarImagen() async {
    if ((_envioIniciado && (_imagen != null || _archivoSubido)) || _seleccionandoImagen || _enviando) return;
    setState(() { _seleccionandoImagen = true; _error = null; });
    try {
      final origen = await showModalBottomSheet<TesoreriaImagenOrigen>(
        context: context,
        builder: (ctx) => SafeArea(child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Seleccionar captura de la galería'), onTap: () => Navigator.pop(ctx, TesoreriaImagenOrigen.galeria)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(kIsWeb ? 'Tomar foto (según navegador)' : 'Tomar fotografía'), onTap: () => Navigator.pop(ctx, TesoreriaImagenOrigen.camara)),
        ])),
      );
      if (origen == null || !mounted) return;
      final bytes = await _gateway.seleccionarImagen(origen);
      if (!mounted || bytes == null) return;
      _aceptarImagen(bytes);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo abrir la imagen. Revisa los permisos de cámara o galería. ${mensajeErrorTesoreria(e)}');
    } finally {
      if (mounted) setState(() => _seleccionandoImagen = false);
    }
  }

  bool _rechazoDefinitivo(Object error) => error is FirebaseException &&
      ['invalid-argument', 'failed-precondition', 'permission-denied', 'already-exists', 'not-found']
          .contains(error.code.replaceFirst('functions/', ''));

  Future<void> _enviar() async {
    if (_enviando || _cargando || _requiereConciliacion || _enviado) return;
    final monto = int.tryParse(_monto.text.trim());
    final cargo = _cargos.where((c) => c['id'] == _cargoId).firstOrNull;
    final uid = _gateway.uidActual;
    if (!_envioIniciado && (uid == null || _cuentaId == null || cargo == null || _imagen == null || monto == null || monto <= 0 || monto > montoTesoreria(cargo['saldo']))) {
      setState(() => _error = 'Selecciona una cuenta, un cargo pendiente, una imagen y un monto entero positivo que no supere el saldo del cargo.');
      return;
    }
    setState(() { _enviando = true; _puedeCorregir = false; _error = null; });
    var registroIntentado = false;
    try {
      if (!_envioIniciado) {
        final envio = <String, dynamic>{
          'uid': uid, 'solicitudId': _solicitudId, 'cuentaId': _cuentaId,
          'cargoId': _cargoId, 'monto': monto,
          'storagePath': 'comprobantes_v58/$uid/$_solicitudId.$_extension',
          'observacion': _observacion.text.trim(), 'extension': _extension,
          'mime': _mime, 'archivoSubido': false,
        };
        // Guardar primero permite conservar el ID aun si Android cierra la app.
        await _gateway.guardarEnvioPendiente(envio);
        _envioPendiente = envio;
      }
      final envio = _envioPendiente!;
      if (!_archivoSubido) {
        if (_imagen == null) throw const FormatException('Recupera la misma imagen para completar la subida pendiente.');
        final path = await _gateway.subirImagen(
          solicitudId: envio['solicitudId'].toString(), bytes: _imagen!,
          extension: envio['extension'].toString(), mime: envio['mime'].toString(),
        );
        if (path != envio['storagePath']) throw StateError('Storage no confirmó la ruta original de este envío.');
        _archivoSubido = true;
        _envioPendiente = {...envio, 'archivoSubido': true};
        await _gateway.guardarEnvioPendiente(_envioPendiente!);
      }
      registroIntentado = true;
      final id = await _gateway.enviarComprobante(
        solicitudId: envio['solicitudId'].toString(), cuentaId: envio['cuentaId'].toString(),
        cargoId: envio['cargoId'].toString(), storagePath: envio['storagePath'].toString(),
        monto: montoTesoreria(envio['monto']), observacion: envio['observacion'].toString(),
      );
      // Si el registro ya se confirmó, un error del almacén local no lo convierte
      // en un pago fallido ni autoriza otro depósito.
      try { await _gateway.borrarEnvioPendiente(); } catch (_) {}
      if (!mounted) return;
      setState(() => _enviado = true);
      widget.onEnviado?.call(id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comprobante enviado. Tesorería recibió el aviso; el saldo cambia al aprobarlo.')));
      await Navigator.maybePop(context);
    } catch (e) {
      if (mounted) setState(() {
        _puedeCorregir = registroIntentado && _rechazoDefinitivo(e);
        _error = '${mensajeErrorTesoreria(e)}\n${_puedeCorregir ? 'El servidor rechazó este registro. Puedes revisar el historial o corregir los datos.' : 'Conserva este envío y su identificador para reintentarlo sin duplicarlo.'}';
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _corregirEnvio() async {
    if (!_puedeCorregir || _enviando) return;
    final confirmar = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Corregir el envío rechazado'),
      content: const Text('Antes de iniciar otro envío, revisa que el mismo depósito no aparezca en el historial. Esto solo descarta el borrador local: no borra archivos, comprobantes ni pagos del servidor.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Conservar borrador')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Corregir datos')),
      ],
    ));
    if (confirmar != true || !mounted) return;
    try {
      await _gateway.borrarEnvioPendiente();
      if (!mounted) return;
      setState(() {
        _solicitudId = _gateway.nuevaSolicitudId(); _envioPendiente = null;
        _archivoSubido = false; _puedeCorregir = false; _error = null;
        _informacion = 'Borrador descartado localmente. Verifica los datos y el historial antes de volver a enviar.';
      });
      if (_cuentaId != null) await _elegirCuenta(_cuentaId);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cerrar el borrador: ${mensajeErrorTesoreria(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = _envioIniciado || _cargando || _enviando || _enviado;
    final cuentas = [..._cuentas];
    final cargos = [..._cargos];
    if (_envioIniciado && !cuentas.any((c) => c['id'] == _cuentaId)) cuentas.add({'id': _cuentaId, 'nombre': 'Cuenta del envío guardado'});
    if (_envioIniciado && !cargos.any((c) => c['id'] == _cargoId)) cargos.add({'id': _cargoId, 'concepto': 'Cargo del envío guardado', 'saldo': 0});
    final puedeRecuperarImagen = _envioIniciado && !_archivoSubido && _imagen == null;
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Enviar comprobante'), backgroundColor: const Color(0xFF0B69B7), foregroundColor: Colors.white),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Selecciona el beneficiario y el cargo al que corresponde el pago. Puedes abonar una parte del saldo.'),
          const SizedBox(height: 16),
          if (_cargando) const LinearProgressIndicator(),
          if (_informacion != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_informacion!))),
          if (_enviado) const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Envío confirmado. Puedes consultar su estado en el historial.'))),
          if (_cuentas.isEmpty && !_cargando && !_envioIniciado) ...[
            const Text('No hay cuentas de Tesorería vinculadas a tu usuario. Solicita a Tesorería revisar el vínculo con tu beneficiario.'),
            TextButton(onPressed: _cargarCuentas, child: const Text('Volver a consultar')),
          ],
          DropdownButtonFormField<String>(
            key: const Key('comprobante-cuenta'), value: _cuentaId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cuenta / beneficiario'),
            items: cuentas.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(nombreCuentaTesoreria(c), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: bloqueado ? null : _elegirCuenta,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const Key('comprobante-cargo'), value: _cargoId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Cargo pendiente'),
            items: cargos.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(etiquetaCargoTesoreria(c), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: bloqueado ? null : (id) => setState(() => _cargoId = id),
          ),
          if (_cuentaId != null && _cargos.isEmpty && !_cargando && !_requiereConciliacion && !_envioIniciado) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Esta cuenta no tiene cargos con saldo pendiente.')),
          const SizedBox(height: 16),
          TextField(key: const Key('comprobante-monto'), controller: _monto, enabled: !bloqueado, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto abonado (pesos, sin puntos)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          OutlinedButton.icon(key: const Key('comprobante-imagen'), onPressed: ((bloqueado && !puedeRecuperarImagen) || _seleccionandoImagen || _enviando) ? null : _seleccionarImagen, icon: const Icon(Icons.add_a_photo_outlined), label: Text(_seleccionandoImagen ? 'Abriendo imagen…' : puedeRecuperarImagen ? 'Recuperar la misma imagen' : 'Fotografía o captura de galería')),
          if (_imagen != null) SizedBox(height: 230, child: Image.memory(_imagen!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('No se pudo mostrar la imagen seleccionada.')))),
          const SizedBox(height: 16),
          TextField(key: const Key('comprobante-observacion'), controller: _observacion, enabled: !bloqueado, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Observación (opcional)', border: OutlineInputBorder())),
          if (_envioIniciado && !_enviado) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Este envío se conserva aunque cierres la pantalla. Un error de conexión no prueba que haya fallado; reintenta el mismo envío o consulta el historial.')),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ElevatedButton.icon(key: const Key('comprobante-enviar'), onPressed: _enviando || _cargando || _seleccionandoImagen || _requiereConciliacion || _enviado ? null : _enviar, icon: const Icon(Icons.send), label: Text(_enviando ? 'Enviando…' : _envioIniciado ? 'Reintentar el mismo envío' : 'Enviar comprobante')),
          if (_puedeCorregir && !_enviado) TextButton(onPressed: _enviando ? null : _corregirEnvio, child: const Text('Corregir datos del envío rechazado')),
          if (widget.onHistorial != null) TextButton.icon(onPressed: _enviando ? null : widget.onHistorial, icon: const Icon(Icons.history), label: const Text('Mis comprobantes / historial')),
        ]),
      ),
    );
  }
}
