import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/tesoreria_finanzas_service.dart';
import 'services/tesoreria_v58_service.dart';
import 'services/tesoreria_v58_gateway.dart';

import 'pages/tesoreria/detalle_financiero_apoderado_page.dart';
import 'pages/tesoreria/revision_comprobantes_v58_page.dart';

const int cuotaMensualDefault = 5000;
const int valorTerapiaProfesionalDefault = 20000;
const int valorTallerDefault = 10000;
const int multaInasistenciaDefault = 10000;
const String cuentaCorrienteTesoreria = 'CUENTA CORRIENTE';
const String cuentaVistaTesoreria = 'CUENTA VISTA';

// Solo lectura: nunca materializa mensualidades ni actualiza saldos al abrir la app.
Future<Map<String, ResumenFinancieroTesoreria>> _saldosCuentasTesoreria(
  List<QueryDocumentSnapshot> docs,
) async {
  final resultados = <String, ResumenFinancieroTesoreria>{};
  // Limita llamadas simultáneas para listados grandes.
  for (var inicio = 0; inicio < docs.length; inicio += 6) {
    final lote = docs.skip(inicio).take(6);
    await Future.wait(lote.map((doc) async {
      resultados[doc.id] = await TesoreriaFinanzasService.calcular(doc.id);
    }));
  }
  return resultados;
}

class TesoreriaPage extends StatefulWidget {
  final String vistaInicial;
  final TesoreriaV58Gateway? gateway;

  const TesoreriaPage({
    super.key,
    this.vistaInicial = 'inicio',
    this.gateway,
  });

  @override
  State<TesoreriaPage> createState() => _TesoreriaPageState();
}

class _TesoreriaPageState extends State<TesoreriaPage> {
  String vista = 'inicio';
  String? filtroApoderados;

  @override
  void initState() {
    super.initState();
    vista = widget.vistaInicial;
  }

  String _money(dynamic valor) {
    final n = _toInt(valor);
    return '\$${n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    )}';
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }

  Future<void> _auditar({
    required String accion,
    required String detalle,
    Map<String, dynamic>? extra,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance.collection('tesoreria_auditoria').add({
      'accion': accion,
      'detalle': detalle,
      'extra': extra ?? {},
      'usuario_email': user?.email,
      'usuario_uid': user?.uid,
      'fecha': FieldValue.serverTimestamp(),
    });
  }

  Color _colorModulo(String id) {
    switch (id) {
      case 'resumen': return const Color(0xFF2D9CDB);
      case 'apoderados': return const Color(0xFF39B98A);
      case 'comprobantes': return const Color(0xFFF2994A);
      case 'eventos': return const Color(0xFF9B72CF);
      case 'cuentas': return const Color(0xFF4F7FD8);
      case 'aseo_reemplazos': return const Color(0xFFEB6F92);
      case 'reportes': return const Color(0xFF32A7A0);
      default: return const Color(0xFF2D9CDB);
    }
  }

  Widget _chip(String id, String texto, IconData icono) {
    final activo = vista == id;
    final color = _colorModulo(id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() {
          vista = id;
          if (id != 'apoderados') filtroApoderados = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: color.withOpacity(activo ? .18 : .10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(activo ? .48 : .20)),
            boxShadow: activo
                ? [BoxShadow(color: color.withOpacity(.13), blurRadius: 9, offset: const Offset(0, 3))]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: activo ? color : color.withOpacity(.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, size: 18, color: activo ? Colors.white : color),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.2, color: Color(0xFF174F79), fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _bannerAsset() {
    switch (vista) {
      case 'apoderados': return 'assets/images/tesoreria_v25/apoderados.png';
      case 'comprobantes': return 'assets/images/tesoreria_v25/comprobantes.png';
      case 'eventos': return 'assets/images/tesoreria_v25/eventos.png';
      case 'cuentas': return 'assets/images/tesoreria_v25/cuentas.png';
      case 'aseo_reemplazos': return 'assets/images/tesoreria_v25/aseo_reemplazos.png';
      case 'reportes': return 'assets/images/tesoreria_v25/reportes.png';
      case 'inicio': return 'assets/images/tesoreria_v25/resumen.png';
      default: return 'assets/images/tesoreria_v25/resumen.png';
    }
  }

  Widget _bannerTesoreria() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      height: 82,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFDDF3FF),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x22004193), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Image.asset(_bannerAsset(), fit: BoxFit.cover, alignment: Alignment.center, errorBuilder: (_, __, ___) => Image.asset('assets/images/tesoreria_casa_autismo.png', fit: BoxFit.cover)),
    );
  }

  Widget _contenido() {
    switch (vista) {
      case 'apoderados':
        return _ApoderadosTesoreria(
          onMoney: _money,
          filtroInicial: filtroApoderados,
          onLimpiarFiltro: () => setState(() => filtroApoderados = null),
        );
      case 'comprobantes':
        return RevisionComprobantesV58Page(embedded: true, gateway: widget.gateway);
      case 'eventos':
        return _EventosTesoreria(onMoney: _money, auditar: _auditar);
      case 'reportes':
        return _ReportesTesoreria(onMoney: _money);
      case 'cuentas':
        return _CuentasTesoreria(onMoney: _money);
      case 'aseo_reemplazos':
        return _ReemplazosAseoTesoreria(onMoney: _money);
      default:
        return _ResumenTesoreria(
          onMoney: _money,
          cambiarVista: (v) => setState(() {
            vista = v;
            if (v != 'apoderados') filtroApoderados = null;
          }),
          verApoderadosFiltrados: (filtro) => setState(() {
            vista = 'apoderados';
            filtroApoderados = filtro;
          }),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
        title: const Text(
          'Tesorería · Autismo Rancagua',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _bannerTesoreria(),
          AvisoComprobantesPendientesV58(
            gateway: widget.gateway,
            onAbrir: () => setState(() => vista = 'comprobantes'),
          ),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 8) / 2;
                Widget item(String id, String texto, IconData icono) => SizedBox(width: w, child: _chip(id, texto, icono));
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    item('resumen', 'Resumen', Icons.dashboard_rounded),
                    item('apoderados', 'Apoderados', Icons.groups_rounded),
                    item('comprobantes', 'Comprobantes', Icons.receipt_long_rounded),
                    item('eventos', 'Eventos', Icons.event_available_rounded),
                    item('cuentas', 'Cuentas', Icons.account_balance_rounded),
                    item('aseo_reemplazos', 'Reemplazos aseo', Icons.cleaning_services_rounded),
                    item('reportes', 'PDF / Reportes', Icons.picture_as_pdf_rounded),
                  ],
                );
              },
            ),
          ),
          Expanded(child: _contenido()),
        ],
      ),
    );
  }
}

class _ResumenTesoreria extends StatelessWidget {
  final String Function(dynamic) onMoney;
  final void Function(String) cambiarVista;
  final void Function(String) verApoderadosFiltrados;

  const _ResumenTesoreria({
    required this.onMoney,
    required this.cambiarVista,
    required this.verApoderadosFiltrados,
  });

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }

  bool _esMesActual(dynamic fecha) {
    if (fecha == null) return false;
    DateTime? dt;
    if (fecha is Timestamp) {
      dt = fecha.toDate();
    } else if (fecha is DateTime) {
      dt = fecha;
    } else {
      dt = DateTime.tryParse(fecha.toString());
    }
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month;
  }

  String _normalizarCuenta(dynamic cuenta, dynamic tipo) {
    final c = (cuenta ?? '').toString().trim().toUpperCase();
    final t = (tipo ?? '').toString().trim().toLowerCase();
    if (c.contains('VISTA')) return 'CUENTA VISTA';
    if (c.contains('CORRIENTE')) return 'CUENTA CORRIENTE';
    if (t == 'evento' || t == 'eventos') return 'CUENTA VISTA';
    return 'CUENTA CORRIENTE';
  }

  Future<Map<String, int>> _resumenRecaudacionMes() async {
    int cuentaCorriente = 0;
    int cuentaVista = 0;

    // Usar ingresos canónicos, no sumar todos los espejos y reintentos V57.
    final cuentas = await TesoreriaV58Service.cuentas();
    final pagosContados = <String>{};
    for (final cuentaFicha in cuentas) {
      final detalle = await TesoreriaV58Service.consultar(cuentaFicha['id'].toString());
      if (((detalle['advertencias'] as List?) ?? const []).isNotEmpty) {
        throw StateError('La recaudación requiere conciliar las cuentas con advertencias antes de presentar un total definitivo.');
      }
      final hoyChile = (detalle['fechaChile'] ?? '').toString();
      if (hoyChile.length < 7) throw StateError('Firebase no confirmó la fecha contable de Chile.');
      final mes = hoyChile.substring(0, 7);
      for (final pago in TesoreriaV58Service.mapas(detalle['pagos'])) {
        final fecha = (pago['fecha_chile'] ?? '').toString();
        if (!fecha.startsWith(mes)) continue;
        final referencia = (pago['comprobante_id'] ?? '').toString();
        final identidad = referencia.isNotEmpty ? 'comprobante:$referencia' : '${cuentaFicha['id']}/${pago['id']}';
        if (!pagosContados.add(identidad)) continue;
        final destino = _normalizarCuenta(pago['cuenta_destino'],
            (pago['cargo_id'] ?? '').toString().startsWith('tesoreria_evento_cargos/') ? 'evento' : pago['tipo']);
        if (destino == 'CUENTA VISTA') {
          cuentaVista += _toInt(pago['monto']);
        } else {
          cuentaCorriente += _toInt(pago['monto']);
        }
      }
    }

    final ingresos = await FirebaseFirestore.instance
        .collection('tesoreria_ingresos_institucionales')
        .get();

    for (final doc in ingresos.docs) {
      final d = doc.data();
      if (!_esMesActual(d['fecha'])) continue;
      final cuenta = _normalizarCuenta(d['cuenta_destino'], d['concepto']);
      final monto = _toInt(d['monto']);
      if (cuenta == 'CUENTA VISTA') {
        cuentaVista += monto;
      } else {
        cuentaCorriente += monto;
      }
    }

    return {
      'cuenta_corriente': cuentaCorriente,
      'cuenta_vista': cuentaVista,
    };
  }

  Widget _card({
    required String titulo,
    required String valor,
    required IconData icono,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(.10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(.12)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: color.withOpacity(.14),
              foregroundColor: color,
              child: Icon(icono, size: 27),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      valor,
                      maxLines: 1,
                      style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF263238), fontSize: 12.5, height: 1.12, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance.collection('tesoreria_apoderados').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('No se pudieron consultar las cuentas: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return FutureBuilder<Map<String, ResumenFinancieroTesoreria>>(
          future: _saldosCuentasTesoreria(snap.data!.docs),
          builder: (context, saldosSnap) {
        if (saldosSnap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No se pudo verificar el saldo en Firebase: ${saldosSnap.error}')));
        if (saldosSnap.connectionState != ConnectionState.done || !saldosSnap.hasData) return const Center(child: CircularProgressIndicator());
        int totalDeuda = 0;
        int morosos = 0;
        int suspendidos = 0;
        int alDia = 0;
        int conciliaciones = 0;

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final resumen = saldosSnap.data![doc.id]!;
            final deuda = resumen.deuda;
            totalDeuda += deuda;
            if (resumen.advertencias.isNotEmpty) {
              conciliaciones++;
            } else if (resumen.saldoVencido > 0) {
              morosos++;
            } else {
              alDia++;
            }
            if ((data['estado_terapias'] ?? '') == 'suspendido_por_morosidad') {
              suspendidos++;
            }
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text(
                'Los cobros del mes siguiente se generan el día 20 desde Firebase, con horario de Chile.\n'
                'Fecha oficial de pago: último día del mes.\n'
                'El pago corresponde al mes siguiente.\n'
                'El día 1 solo se avisan saldos vencidos pendientes. La suspensión y reactivación siempre son confirmadas manualmente por Tesorería.',
                style: TextStyle(
                  color: Color(0xFF063E83),
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (conciliaciones > 0) Card(color: const Color(0xFFFFF0D6), child: Padding(padding: const EdgeInsets.all(14), child: Text('$conciliaciones cuenta(s) requieren conciliación. Sus datos históricos no permiten confirmar el saldo; no se clasifican como al día ni morosas. Revisa el detalle antes de gestionar cobros.'))),
            FutureBuilder<Map<String, int>>(
              future: _resumenRecaudacionMes(),
              builder: (context, recSnap) {
                if (recSnap.hasError) return Padding(padding: const EdgeInsets.all(12), child: Text('No se pudo consultar la recaudación: ${recSnap.error}'));
                final recaudadoCorriente = recSnap.data?['cuenta_corriente'] ?? 0;
                final recaudadoVista = recSnap.data?['cuenta_vista'] ?? 0;

                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.70,
                  children: [
                    _card(
                      titulo: 'Saldo con cargos registrados',
                      valor: onMoney(totalDeuda),
                      icono: Icons.account_balance_wallet,
                      color: const Color(0xFF1559A6),
                      onTap: () => cambiarVista('reportes'),
                    ),
                    _card(
                      titulo: 'Morosos',
                      valor: '$morosos',
                      icono: Icons.warning_amber,
                      color: const Color(0xFFF39C12),
                      onTap: () => verApoderadosFiltrados('morosos'),
                    ),
                    _card(
                      titulo: 'Suspendidos',
                      valor: '$suspendidos',
                      icono: Icons.block,
                      color: const Color(0xFFD9534F),
                      onTap: () => verApoderadosFiltrados('suspendidos'),
                    ),
                    _card(
                      titulo: 'Al día',
                      valor: '$alDia',
                      icono: Icons.verified,
                      color: const Color(0xFF3A9D5D),
                      onTap: () => verApoderadosFiltrados('al_dia'),
                    ),
                    _card(
                      titulo: 'Recaudado mes\nCuenta Corriente',
                      valor: recSnap.connectionState == ConnectionState.waiting
                          ? '...'
                          : onMoney(recaudadoCorriente),
                      icono: Icons.account_balance,
                      color: const Color(0xFF3978C5),
                      onTap: () => cambiarVista('cuentas'),
                    ),
                    _card(
                      titulo: 'Recaudado mes\nCuenta Vista',
                      valor: recSnap.connectionState == ConnectionState.waiting
                          ? '...'
                          : onMoney(recaudadoVista),
                      icono: Icons.event_available,
                      color: const Color(0xFF36A6A1),
                      onTap: () => cambiarVista('eventos'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.autorenew, color: Color(0xFF004193)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Firebase genera cargos reales el día 20 y recordatorios hasta fin de mes. Los pagos aprobados se aplican una sola vez al cargo seleccionado, incluyendo abonos parciales.',
                      style: TextStyle(
                        color: Color(0xFF063E83),
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          ],
        );
          },
        );
      },
    );
  }
}

class _ApoderadosTesoreria extends StatefulWidget {
  final String Function(dynamic) onMoney;
  final String? filtroInicial;
  final VoidCallback onLimpiarFiltro;

  const _ApoderadosTesoreria({
    required this.onMoney,
    required this.filtroInicial,
    required this.onLimpiarFiltro,
  });

  @override
  State<_ApoderadosTesoreria> createState() => _ApoderadosTesoreriaState();
}

class _ApoderadosTesoreriaState extends State<_ApoderadosTesoreria> {
  final buscarCtrl = TextEditingController();
  String q = '';

  String _nombreFiltro() {
    switch (widget.filtroInicial) {
      case 'morosos':
        return 'Mostrando solo morosos';
      case 'al_dia':
        return 'Mostrando solo apoderados al día';
      case 'suspendidos':
        return 'Mostrando solo suspendidos';
      default:
        return '';
    }
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }



  void _verFoto(String url, {String titulo = 'Foto'}) {
    if (url.trim().isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No se pudo cargar la foto.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  String _telefonoWhatsApp(String raw) {
    var n = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.startsWith('56')) return n;
    if (n.startsWith('9') && n.length == 9) return '56$n';
    return n;
  }

  Future<void> _abrirWhatsApp(DocumentSnapshot doc, Map<String,dynamic> d, int deuda) async {
    final tel=_telefonoWhatsApp((d['telefono']??'').toString());
    if (tel.isEmpty) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este apoderado no tiene teléfono registrado.'))); return; }
    final nombre=(d['nombre']??d['nombre_apoderado']??'').toString();
    final fechaLimite=DateTime.now().add(const Duration(days:3));
    final fechaTxt=DateFormat('dd/MM/yyyy').format(fechaLimite);
    final monto=widget.onMoney(deuda);
    final msg='Hola, $nombre. Le contactamos desde Autismo Rancagua para informarle que registra un saldo pendiente de $monto. Solicitamos regularizar su situación o comunicarse con Tesorería antes del $fechaTxt. Si no regulariza o informa su situación dentro de dicho plazo, las atenciones del beneficiario podrían ser suspendidas temporalmente. Si ya realizó el pago, por favor informe a Tesorería. Autismo Rancagua.';
    final uri=Uri.parse('https://wa.me/$tel?text=${Uri.encodeComponent(msg)}');
    final ok=await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir WhatsApp.'))); return; }
    await FirebaseFirestore.instance.collection('tesoreria_gestiones_cobranza').add({'apoderado_id':doc.id,'apoderado_nombre':nombre,'tipo':'whatsapp_abierto','monto_deuda':deuda,'plazo_hasta':Timestamp.fromDate(fechaLimite),'fecha':FieldValue.serverTimestamp(),'usuario_uid':FirebaseAuth.instance.currentUser?.uid,'usuario_email':FirebaseAuth.instance.currentUser?.email});
    await doc.reference.set({'estado_cobranza':'contacto_abierto','plazo_cobranza_hasta':Timestamp.fromDate(fechaLimite),'actualizado':FieldValue.serverTimestamp()},SetOptions(merge:true));
  }

  Future<void> _confirmarAviso(DocumentSnapshot doc, Map<String,dynamic> d) async {
    final limite=(d['plazo_cobranza_hasta'] is Timestamp)?(d['plazo_cobranza_hasta'] as Timestamp).toDate():DateTime.now().add(const Duration(days:3));
    await doc.reference.set({'estado_cobranza':'avisado','aviso_cobranza_confirmado':true,'plazo_cobranza_hasta':Timestamp.fromDate(limite),'actualizado':FieldValue.serverTimestamp()},SetOptions(merge:true));
    await FirebaseFirestore.instance.collection('tesoreria_gestiones_cobranza').add({'apoderado_id':doc.id,'tipo':'aviso_confirmado','plazo_hasta':Timestamp.fromDate(limite),'fecha':FieldValue.serverTimestamp(),'usuario_uid':FirebaseAuth.instance.currentUser?.uid,'usuario_email':FirebaseAuth.instance.currentUser?.email});
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aviso de cobranza confirmado.')));
  }

  Future<void> _atrasoInformado(DocumentSnapshot doc, Map<String,dynamic> d) async {
    DateTime fecha=DateTime.now().add(const Duration(days:3));
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setLocal)=>AlertDialog(title:const Text('Atraso informado'),content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Registra la fecha comprometida por el apoderado.'),const SizedBox(height:10),OutlinedButton.icon(onPressed:() async { final f=await showDatePicker(context:c,initialDate:fecha,firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:90))); if(f!=null)setLocal(()=>fecha=f); },icon:const Icon(Icons.calendar_month),label:Text(DateFormat('dd/MM/yyyy').format(fecha)))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),ElevatedButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Guardar'))])));
    if(ok!=true)return;
    await doc.reference.set({'estado_cobranza':'atraso_informado','fecha_compromiso_pago':Timestamp.fromDate(fecha),'actualizado':FieldValue.serverTimestamp()},SetOptions(merge:true));
    await FirebaseFirestore.instance.collection('tesoreria_gestiones_cobranza').add({'apoderado_id':doc.id,'tipo':'atraso_informado','fecha_compromiso_pago':Timestamp.fromDate(fecha),'fecha':FieldValue.serverTimestamp(),'usuario_uid':FirebaseAuth.instance.currentUser?.uid,'usuario_email':FirebaseAuth.instance.currentUser?.email});
    if(mounted)setState((){});
  }

  Future<void> _suspender(DocumentSnapshot doc, Map<String,dynamic> d, int deuda) async {
    final nombre=(d['nombre']??d['nombre_apoderado']??'').toString();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Confirmar suspensión'),content:Text('Se suspenderán manualmente las atenciones de $nombre.\n\nDeuda actual: ${widget.onMoney(deuda)}\n\nEl historial y las asignaciones no se eliminarán.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),ElevatedButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Suspender'))]));
    if(ok!=true)return;
    await doc.reference.set({'estado_terapias':'suspendido_por_morosidad','fecha_suspension':FieldValue.serverTimestamp(),'suspendido_por_uid':FirebaseAuth.instance.currentUser?.uid,'suspendido_por_email':FirebaseAuth.instance.currentUser?.email,'actualizado':FieldValue.serverTimestamp()},SetOptions(merge:true));
    final asig=await FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').where('apoderado_uid',isEqualTo:doc.id).get();
    for(final a in asig.docs){
      final x=a.data();
      final estadoAnterior=(x['estado']??'activa').toString();
      if(estadoAnterior!='eliminada' && estadoAnterior!='inactiva' && estadoAnterior!='suspendida_tesoreria'){
        await a.reference.set({'estado_antes_suspension_tesoreria':estadoAnterior,'estado':'suspendida_tesoreria','suspendida_por_tesoreria':true,'fecha_suspension_tesoreria':FieldValue.serverTimestamp()},SetOptions(merge:true));
      }
      final puid=(x['profesional_uid']??'').toString();
      if(puid.isNotEmpty) await FirebaseFirestore.instance.collection('notificaciones_profesionales').add({'profesional_uid':puid,'tipo':'suspension_tesoreria','titulo':'Atención suspendida','mensaje':'${x['beneficiario_nombre']??'Beneficiario'} se encuentra suspendido temporalmente. No realizar atención hasta nueva notificación.','apoderado_id':doc.id,'beneficiario_id':x['beneficiario_id'],'resuelta':false,'fecha':FieldValue.serverTimestamp()});
    }
    await FirebaseFirestore.instance.collection('tesoreria_gestiones_cobranza').add({'apoderado_id':doc.id,'tipo':'suspension_manual','monto_deuda':deuda,'fecha':FieldValue.serverTimestamp(),'usuario_uid':FirebaseAuth.instance.currentUser?.uid,'usuario_email':FirebaseAuth.instance.currentUser?.email});
    if(mounted) setState((){});
  }

  Future<void> _reactivar(DocumentSnapshot doc, Map<String,dynamic> d) async {
    final nombre=(d['nombre']??d['nombre_apoderado']??'').toString();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Confirmar reactivación'),content:Text('¿Reactivar las atenciones de $nombre?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),ElevatedButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Reactivar'))]));
    if(ok!=true)return;
    await doc.reference.set({'estado_terapias':'activo','fecha_reactivacion':FieldValue.serverTimestamp(),'reactivado_por_uid':FirebaseAuth.instance.currentUser?.uid,'reactivado_por_email':FirebaseAuth.instance.currentUser?.email,'actualizado':FieldValue.serverTimestamp()},SetOptions(merge:true));
    final asig=await FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').where('apoderado_uid',isEqualTo:doc.id).get();
    for(final a in asig.docs){
      final x=a.data();
      if((x['estado']??'').toString()=='suspendida_tesoreria'){
        final restaurar=(x['estado_antes_suspension_tesoreria']??'activa').toString();
        await a.reference.set({'estado':restaurar,'suspendida_por_tesoreria':false,'fecha_reactivacion_tesoreria':FieldValue.serverTimestamp()},SetOptions(merge:true));
      }
      final puid=(x['profesional_uid']??'').toString();
      if(puid.isNotEmpty) await FirebaseFirestore.instance.collection('notificaciones_profesionales').add({'profesional_uid':puid,'tipo':'reactivacion_tesoreria','titulo':'Atención reactivada','mensaje':'${x['beneficiario_nombre']??'Beneficiario'} fue reactivado por Tesorería.','apoderado_id':doc.id,'beneficiario_id':x['beneficiario_id'],'resuelta':false,'fecha':FieldValue.serverTimestamp()});
    }
    final avisos=await FirebaseFirestore.instance.collection('notificaciones_profesionales').where('apoderado_id',isEqualTo:doc.id).get();
    for(final n in avisos.docs){ final nd=n.data(); if((nd['tipo']??'').toString()=='suspension_tesoreria' && nd['resuelta']!=true) await n.reference.set({'resuelta':true,'fecha_resuelta':FieldValue.serverTimestamp()},SetOptions(merge:true)); }
    await FirebaseFirestore.instance.collection('tesoreria_gestiones_cobranza').add({'apoderado_id':doc.id,'tipo':'reactivacion_manual','fecha':FieldValue.serverTimestamp(),'usuario_uid':FirebaseAuth.instance.currentUser?.uid,'usuario_email':FirebaseAuth.instance.currentUser?.email});
    if(mounted) setState((){});
  }

  @override
  void dispose() {
    buscarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: buscarCtrl,
            onChanged: (v) => setState(() => q = v.toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Buscar por nombre, teléfono o correo',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
        if (widget.filtroInicial != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, color: Color(0xFF004193)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nombreFiltro(),
                      style: const TextStyle(
                        color: Color(0xFF063E83),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onLimpiarFiltro,
                    child: const Text('Ver todos'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tesoreria_apoderados')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('No se pudieron consultar las cuentas: ${snap.error}'));
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              return FutureBuilder<Map<String, ResumenFinancieroTesoreria>>(
                future: _saldosCuentasTesoreria(snap.data!.docs),
                builder: (context, saldosSnap) {
                  if (saldosSnap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No se pudo verificar el saldo en Firebase: ${saldosSnap.error}')));
                  if (saldosSnap.connectionState != ConnectionState.done || !saldosSnap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final texto =
                    '${d['nombre'] ?? ''} ${d['nombre_apoderado'] ?? ''} ${d['telefono'] ?? ''} ${d['email'] ?? ''}'
                        .toLowerCase();
                final coincideBusqueda = texto.contains(q);
                if (!coincideBusqueda) return false;

                final deuda = saldosSnap.data![doc.id]!.saldoVencido;
                final estadoTerapias = (d['estado_terapias'] ?? '').toString();

                switch (widget.filtroInicial) {
                  case 'morosos':
                    return saldosSnap.data![doc.id]!.advertencias.isEmpty && deuda > 0;
                  case 'al_dia':
                    return saldosSnap.data![doc.id]!.advertencias.isEmpty && deuda <= 0;
                  case 'suspendidos':
                    return estadoTerapias == 'suspendido_por_morosidad';
                  default:
                    return true;
                }
              }).toList();

              docs.sort((a, b) {
                final da = saldosSnap.data![a.id]!.saldoVencido;
                final db = saldosSnap.data![b.id]!.saldoVencido;
                return db.compareTo(da);
              });

              if (docs.isEmpty) {
                return const Center(child: Text('No hay apoderados para este filtro.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final doc = docs[i];
                  final d = doc.data() as Map<String, dynamic>;
                  final nombre =
                      (d['nombre'] ?? d['nombre_apoderado'] ?? 'Sin nombre')
                          .toString();
                  final telefono = (d['telefono'] ?? '').toString();
                  final email = (d['email'] ?? '').toString();
                  final resumen = saldosSnap.data![doc.id]!;
                  final requiereConciliacion = resumen.advertencias.isNotEmpty;
                  final deuda = requiereConciliacion ? 0 : resumen.saldoVencido;
                  final meses = resumen.cuotasMorosas;
                  final estadoTerapias = (d['estado_terapias'] ?? '').toString();

                  final estadoCobranza=(d['estado_cobranza']??'sin_contactar').toString();
                  final suspendido=estadoTerapias=='suspendido_por_morosidad';
                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      InkWell(onTap:(){ Navigator.of(context).push(MaterialPageRoute(builder:(_)=>DetalleFinancieroApoderadoPage(apoderadoId:doc.id,nombreApoderado:nombre,emailApoderado:email,telefonoApoderado:telefono))); },child:Row(children:[CircleAvatar(backgroundColor:requiereConciliacion?const Color(0xFFF39C12):deuda>0?const Color(0xFFC62828):const Color(0xFF2E7D32),child:Icon(requiereConciliacion||deuda>0?Icons.warning:Icons.check,color:Colors.white)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(nombre,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),Text('Tel: $telefono · $email'),Text(requiereConciliacion ? 'Saldo pendiente de conciliación' : 'Saldo total: ${widget.onMoney(resumen.deuda)} · Vencido: ${widget.onMoney(deuda)} · Cuotas vencidas: $meses',style:const TextStyle(fontWeight:FontWeight.w800)),Text('Cobranza: $estadoCobranza · Terapias: $estadoTerapias')]))])),
                      if(requiereConciliacion) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Requiere conciliación: ${resumen.advertencias.join(' · ')}', style: const TextStyle(color: Color(0xFF8A5600)))),
                      if(deuda>0||suspendido)...[const SizedBox(height:10),Wrap(spacing:8,runSpacing:8,children:[
                        if(deuda>0) OutlinedButton.icon(onPressed:()=>_abrirWhatsApp(doc,d,deuda),icon:const Icon(Icons.chat),label:const Text('WhatsApp')),
                        if(deuda>0 && estadoCobranza=='contacto_abierto') OutlinedButton.icon(onPressed:()=>_confirmarAviso(doc,d),icon:const Icon(Icons.done_all),label:const Text('Confirmar aviso')),
                        if(deuda>0 && !suspendido) OutlinedButton.icon(onPressed:()=>_atrasoInformado(doc,d),icon:const Icon(Icons.event_available),label:const Text('Atraso informado')),
                        if(deuda>0 && !suspendido) ElevatedButton.icon(style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFFC62828),foregroundColor:Colors.white),onPressed:()=>_suspender(doc,d,deuda),icon:const Icon(Icons.block),label:const Text('Suspender')),
                        if(suspendido) ElevatedButton.icon(style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFF2E7D32),foregroundColor:Colors.white),onPressed:()=>_reactivar(doc,d),icon:const Icon(Icons.play_circle),label:const Text('Reactivar')),
                      ])]
                    ])),
                  );
                },
              );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EventosTesoreria extends StatelessWidget {
  final String Function(dynamic) onMoney;
  final Future<void> Function({
    required String accion,
    required String detalle,
    Map<String, dynamic>? extra,
  }) auditar;

  const _EventosTesoreria({
    required this.onMoney,
    required this.auditar,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Eventos enviados a Tesorería',
                style: TextStyle(
                  color: Color(0xFF063E83),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Tesorería no crea ni asigna eventos. La encargada de eventos crea la actividad, define el valor y asigna usuarios. Luego el cobro llega automáticamente aquí para controlar pagos, abonos y reportes.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 10),
              Text(
                'Cuenta destino: CUENTA VISTA',
                style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF004193)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Eventos registrados',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tesoreria_eventos')
              .orderBy('fecha_creacion', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());

            if (snap.data!.docs.isEmpty) {
              return const Text('No hay eventos enviados desde el módulo de eventos.');
            }

            return Column(
              children: snap.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final fecha = d['fecha_limite'] is Timestamp
                    ? DateFormat('dd-MM-yyyy').format((d['fecha_limite'] as Timestamp).toDate())
                    : '';

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_available, color: Color(0xFF004193)),
                    title: Text(d['titulo'] ?? 'Evento'),
                    subtitle: Text(
                      'Monto: ${onMoney(d['monto'])}\nFecha límite: $fecha\nCuenta: CUENTA VISTA',
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _ReportesTesoreria extends StatefulWidget {
  final String Function(dynamic) onMoney;

  const _ReportesTesoreria({required this.onMoney});

  @override
  State<_ReportesTesoreria> createState() => _ReportesTesoreriaState();
}

class _ReportesTesoreriaState extends State<_ReportesTesoreria> {
  bool campoTelefono = true;
  bool campoCorreo = false;
  bool campoCuotasMorosas = true;
  bool campoMonto = true;
  bool campoEstadoTerapias = true;
  String? eventoSeleccionadoId;
  String? eventoSeleccionadoTitulo;

  bool incluirEventoPagados = true;
  bool incluirEventoAbonados = true;
  bool incluirEventoPendientes = true;

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }

  pw.Widget _tabla(List<Map<String, dynamic>> filas) {
    final headers = <String>['Nombre'];

    if (campoTelefono) headers.add('Teléfono');
    if (campoCorreo) headers.add('Correo');
    if (campoCuotasMorosas) headers.add('Cuotas');
    if (campoMonto) headers.add('Monto');
    if (campoEstadoTerapias) headers.add('Terapias');

    final data = filas.map((f) {
      final row = <String>[(f['nombre'] ?? '').toString()];
      if (campoTelefono) row.add((f['telefono'] ?? '').toString());
      if (campoCorreo) row.add((f['email'] ?? '').toString());
      if (campoCuotasMorosas) row.add((f['meses_morosos'] ?? '').toString());
      if (campoMonto) row.add(widget.onMoney(f['monto'] ?? f['monto_deuda'] ?? 0));
      if (campoEstadoTerapias) row.add((f['estado_terapias'] ?? '').toString());
      return row;
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      border: pw.TableBorder.all(),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  Future<void> _pdfAlDia() async {
    final snap=await FirebaseFirestore.instance.collection('tesoreria_apoderados').get();
    final filas=<Map<String,dynamic>>[];
    for(final doc in snap.docs){ final d=doc.data(); final r=await TesoreriaFinanzasService.calcular(doc.id,ficha:d); if(r.advertencias.isEmpty && r.saldoVencido<=0) filas.add({'nombre':d['nombre']??d['nombre_apoderado']??'','telefono':d['telefono']??'','email':d['email']??'','meses_morosos':0,'monto_deuda':0,'estado_terapias':d['estado_terapias']??'activo'}); }
    filas.sort((a,b)=>a['nombre'].toString().compareTo(b['nombre'].toString()));
    await _generarPdf(titulo:'Listado de apoderados al día',subtitulo:'Generado el ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}. Incluye solo cuentas sin advertencias de conciliación.',filas:filas);
  }

  Future<void> _pdfMorosos() async {
    final snap=await FirebaseFirestore.instance.collection('tesoreria_apoderados').get();
    final filas=<Map<String,dynamic>>[];
    for(final doc in snap.docs){ final d=doc.data(); final r=await TesoreriaFinanzasService.calcular(doc.id,ficha:d); if(r.advertencias.isEmpty && r.saldoVencido>0) filas.add({'nombre':d['nombre']??d['nombre_apoderado']??'','telefono':d['telefono']??'','email':d['email']??'','meses_morosos':r.cuotasMorosas,'monto_deuda':r.saldoVencido,'estado_terapias':d['estado_terapias']??''}); }
    filas.sort((a,b)=>_toInt(b['monto_deuda']).compareTo(_toInt(a['monto_deuda'])));
    await _generarPdf(titulo:'Listado de apoderados morosos',subtitulo:'Generado el ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}. Incluye solo cuentas sin advertencias de conciliación.',filas:filas);
  }

  String _normalizarEstadoEvento(dynamic estado) {
    final e = (estado ?? '').toString().trim().toLowerCase();
    if (e.contains('abon') || e == 'parcial') return 'abono';
    if (e.contains('pag')) return 'pagado';
    return 'sin_pago';
  }

  String _labelEstadoEvento(String estado) {
    switch (estado) {
      case 'pagado':
        return 'PAGADO';
      case 'abono':
        return 'ABONO';
      default:
        return 'SIN PAGO';
    }
  }

  Future<void> _pdfEventoSeleccionado() async {
    if (eventoSeleccionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un evento.')),
      );
      return;
    }

    final estadosIncluidos = <String>{};
    if (incluirEventoPagados) estadosIncluidos.add('pagado');
    if (incluirEventoAbonados) estadosIncluidos.add('abono');
    if (incluirEventoPendientes) estadosIncluidos.add('sin_pago');

    if (estadosIncluidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una opción para el reporte.')),
      );
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('tesoreria_evento_cargos')
        .where('evento_id', isEqualTo: eventoSeleccionadoId)
        .get();

    final filas = snap.docs.map((doc) {
      final d = doc.data();
      final estadoNormalizado = _normalizarEstadoEvento(d['estado']);
      return {
        'apoderado': d['apoderado_nombre'] ?? d['nombre_apoderado'] ?? d['nombre'] ?? '',
        'usuario': d['usuario_nombre'] ?? d['beneficiario_nombre'] ?? d['nombre_usuario'] ?? d['usuario'] ?? '',
        'estado': estadoNormalizado,
        'estado_label': _labelEstadoEvento(estadoNormalizado),
        'monto': d['monto_abonado'] ?? d['monto_pagado'] ?? d['monto'] ?? d['saldo_pendiente'] ?? 0,
      };
    }).where((f) => estadosIncluidos.contains(f['estado'])).toList();

    filas.sort((a, b) {
      final orden = {'pagado': 0, 'abono': 1, 'sin_pago': 2};
      final oa = orden[a['estado']] ?? 9;
      final ob = orden[b['estado']] ?? 9;
      if (oa != ob) return oa.compareTo(ob);
      return (a['apoderado'] ?? '').toString().compareTo((b['apoderado'] ?? '').toString());
    });

    await _generarPdfEvento(
      titulo: 'Reporte evento: ${eventoSeleccionadoTitulo ?? 'Evento'}',
      subtitulo: 'Generado el ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
      filas: filas,
    );
  }

  Future<void> _generarPdfEvento({
    required String titulo,
    required String subtitulo,
    required List<Map<String, dynamic>> filas,
  }) async {
    final pdf = pw.Document();

    final totalPagados = filas.where((f) => f['estado'] == 'pagado').length;
    final totalAbonos = filas.where((f) => f['estado'] == 'abono').length;
    final totalSinPago = filas.where((f) => f['estado'] == 'sin_pago').length;

    pdf.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('Autismo Rancagua', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(titulo, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(subtitulo),
          pw.SizedBox(height: 10),
          pw.Text('Total registros: ${filas.length}'),
          pw.Text('Pagados: $totalPagados   |   Abonos: $totalAbonos   |   Sin pago: $totalSinPago'),
          pw.SizedBox(height: 12),
          if (filas.isEmpty)
            pw.Text('No hay registros para las opciones seleccionadas.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Apoderado', 'Usuario', 'Estado', 'Monto'],
              data: filas.map((f) => [
                (f['apoderado'] ?? '').toString(),
                (f['usuario'] ?? '').toString(),
                (f['estado_label'] ?? '').toString(),
                widget.onMoney(f['monto'] ?? 0),
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              border: pw.TableBorder.all(),
              cellAlignment: pw.Alignment.centerLeft,
            ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'reporte_evento_${(eventoSeleccionadoTitulo ?? 'evento').toLowerCase().replaceAll(' ', '_')}.pdf',
    );
  }

  Future<void> _generarPdf({
    required String titulo,
    required String subtitulo,
    required List<Map<String, dynamic>> filas,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            'Autismo Rancagua',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(titulo, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(subtitulo),
          pw.SizedBox(height: 12),
          pw.Text('Total registros: ${filas.length}'),
          pw.SizedBox(height: 12),
          if (filas.isEmpty)
            pw.Text('No hay registros para este reporte.')
          else
            _tabla(filas),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${titulo.toLowerCase().replaceAll(' ', '_')}.pdf',
    );
  }

  Widget _check(String texto, bool valor, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: valor,
      onChanged: onChanged,
      title: Text(texto),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Campos para incluir en PDF',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              _check('Teléfono', campoTelefono, (v) => setState(() => campoTelefono = v ?? false)),
              _check('Correo', campoCorreo, (v) => setState(() => campoCorreo = v ?? false)),
              _check('Cantidad de cuotas morosas', campoCuotasMorosas,
                  (v) => setState(() => campoCuotasMorosas = v ?? false)),
              _check('Monto deuda', campoMonto, (v) => setState(() => campoMonto = v ?? false)),
              _check('Estado terapias', campoEstadoTerapias,
                  (v) => setState(() => campoEstadoTerapias = v ?? false)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _pdfMorosos,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('PDF lista de morosos'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC62828),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _pdfAlDia,
          icon: const Icon(Icons.verified),
          label: const Text('PDF lista de apoderados al día'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 18),
        const Text(
          'Reportes por evento',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tesoreria_eventos')
              .orderBy('fecha_creacion', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const LinearProgressIndicator();

            return DropdownButtonFormField<String>(
              value: eventoSeleccionadoId,
              decoration: const InputDecoration(
                labelText: 'Seleccionar evento',
                filled: true,
                fillColor: Colors.white,
              ),
              items: snap.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return DropdownMenuItem(
                  value: doc.id,
                  child: Text(d['titulo'] ?? 'Evento'),
                  onTap: () => eventoSeleccionadoTitulo = d['titulo'] ?? 'Evento',
                );
              }).toList(),
              onChanged: (v) => setState(() => eventoSeleccionadoId = v),
            );
          },
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Opciones del informe',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              _check('Pagado y monto', incluirEventoPagados,
                  (v) => setState(() => incluirEventoPagados = v ?? false)),
              _check('Abono y monto', incluirEventoAbonados,
                  (v) => setState(() => incluirEventoAbonados = v ?? false)),
              _check('Sin pago / no pagado y monto', incluirEventoPendientes,
                  (v) => setState(() => incluirEventoPendientes = v ?? false)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _pdfEventoSeleccionado,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Generar PDF del evento'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 90),
      ],
    );
  }
}



class _CuentasTesoreria extends StatelessWidget {
  final String Function(dynamic) onMoney;

  const _CuentasTesoreria({required this.onMoney});

  Widget _card({
    required String titulo,
    required IconData icono,
    required String descripcion,
    required List<String> items,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF004193),
                child: Icon(icono, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF063E83)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(descripcion, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...items.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
      children: [
        _card(
          titulo: 'CUENTA CORRIENTE',
          icono: Icons.account_balance,
          descripcion: 'Aquí llegan los cobros permanentes generados por Coordinación. Tesorería solo controla pagos, abonos, comprobantes y reportes.',
          items: [
            'Mensualidad base: ${onMoney(cuotaMensualDefault)} mensual',
            'Terapia/profesional asignado: ${onMoney(valorTerapiaProfesionalDefault)} mensual',
            'Taller asignado: ${onMoney(valorTallerDefault)} mensual',
            'Multa por inasistencia/no confirmación: ${onMoney(multaInasistenciaDefault)}',
          ],
        ),
        _card(
          titulo: 'CUENTA VISTA',
          icono: Icons.savings,
          descripcion: 'Aquí llegan los cobros extraordinarios creados por la encargada de eventos.',
          items: const [
            'Completadas',
            'Bingos',
            'Plato único',
            'Rifas o actividades especiales',
            'Reportes por evento: pagados, abonados y sin pago',
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Responsabilidades separadas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              SizedBox(height: 10),
              Text('• Coordinadora: asigna usuarios a profesionales, terapias y talleres.'),
              Text('• Encargada de eventos: crea eventos y asigna valor.'),
              Text('• Tesorería: recibe cobros generados, aprueba/rechaza pagos, registra abonos y genera reportes.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _IngresosInstitucionalesTesoreria extends StatefulWidget {
  final String Function(dynamic) onMoney;
  final Future<void> Function({
    required String accion,
    required String detalle,
    Map<String, dynamic>? extra,
  }) auditar;

  const _IngresosInstitucionalesTesoreria({
    required this.onMoney,
    required this.auditar,
  });

  @override
  State<_IngresosInstitucionalesTesoreria> createState() => _IngresosInstitucionalesTesoreriaState();
}

class _IngresosInstitucionalesTesoreriaState extends State<_IngresosInstitucionalesTesoreria> {
  final montoCtrl = TextEditingController();
  final detalleCtrl = TextEditingController();
  String concepto = 'reciclaje';
  String cuentaDestino = 'CUENTA CORRIENTE';

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }



  void _verFoto(String url, {String titulo = 'Foto'}) {
    if (url.trim().isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No se pudo cargar la foto.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    montoCtrl.dispose();
    detalleCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarIngreso() async {
    final monto = _toInt(montoCtrl.text);
    final detalle = detalleCtrl.text.trim();
    if (monto <= 0) return;

    await FirebaseFirestore.instance.collection('tesoreria_ingresos_institucionales').add({
      'concepto': concepto,
      'monto': monto,
      'detalle': detalle,
      'fecha': FieldValue.serverTimestamp(),
      'cuenta_destino': cuentaDestino,
      'registrado_por': FirebaseAuth.instance.currentUser?.email,
    });

    await widget.auditar(
      accion: 'registrar_ingreso_institucional',
      detalle: 'Ingreso por $concepto: ${widget.onMoney(monto)}',
      extra: {'concepto': concepto, 'monto': monto, 'detalle': detalle, 'cuenta_destino': cuentaDestino},
    );

    montoCtrl.clear();
    detalleCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingreso registrado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ingreso de dineros institucionales', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('Registra ingresos institucionales manuales separados de los cobros automáticos de usuarios y eventos.', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: concepto,
                decoration: const InputDecoration(labelText: 'Concepto'),
                items: const [
                  DropdownMenuItem(value: 'reciclaje', child: Text('Reciclaje')),
                  DropdownMenuItem(value: 'proyecto', child: Text('Proyecto')),
                  DropdownMenuItem(value: 'donacion', child: Text('Donación')),
                  DropdownMenuItem(value: 'evento', child: Text('Evento / actividad')),
                  DropdownMenuItem(value: 'otro', child: Text('Otro ingreso')),
                ],
                onChanged: (v) => setState(() => concepto = v ?? 'reciclaje'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: cuentaDestino,
                decoration: const InputDecoration(labelText: 'Cuenta destino'),
                items: const [
                  DropdownMenuItem(value: 'CUENTA CORRIENTE', child: Text('CUENTA CORRIENTE')),
                  DropdownMenuItem(value: 'CUENTA VISTA', child: Text('CUENTA VISTA')),
                ],
                onChanged: (v) => setState(() => cuentaDestino = v ?? 'CUENTA CORRIENTE'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: montoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monto'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detalleCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Detalle / observación'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _guardarIngreso,
                icon: const Icon(Icons.add_card),
                label: const Text('Registrar ingreso'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Últimos ingresos registrados', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('tesoreria_ingresos_institucionales').orderBy('fecha', descending: true).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const LinearProgressIndicator();
            if (snap.data!.docs.isEmpty) return const Text('Aún no hay ingresos registrados.');
            return Column(
              children: snap.data!.docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.savings, color: Color(0xFF004193)),
                    title: Text('${d['concepto'] ?? 'Ingreso'} - ${widget.onMoney(d['monto'])}'),
                    subtitle: Text("${d['detalle'] ?? ''}\nCuenta: ${d['cuenta_destino'] ?? ''}"),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}


class _ReemplazosAseoTesoreria extends StatelessWidget {
  final String Function(dynamic) onMoney;

  const _ReemplazosAseoTesoreria({required this.onMoney});

  String _fecha(dynamic valor) {
    if (valor is Timestamp) {
      final d = valor.toDate();
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    }
    return '';
  }

  String _nombreRegistro(Map<String, dynamic> d) {
    final nombre = (d['nombre_apoderado'] ?? d['apoderadoNombre'] ?? d['nombre'] ?? '').toString().trim();
    if (nombre.isNotEmpty) return nombre;
    return (d['email'] ?? 'Apoderado no informado').toString();
  }



  void _verFoto(BuildContext context, String url, {String titulo = 'Foto'}) {
    if (url.trim().isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No se pudo cargar la foto.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _beneficiarioRegistro(Map<String, dynamic> d) {
    final nombre = (d['beneficiario'] ?? d['beneficiario_nombre'] ?? d['nombre_beneficiario'] ?? '').toString().trim();
    return nombre.isEmpty ? 'No informado' : nombre;
  }

  Future<void> _generarPdf(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('Tesorería - Reemplazos de aseo', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Registros visibles solo para control, estadísticas y cobranza. No son ingreso institucional.'),
          pw.SizedBox(height: 14),
          pw.Table.fromTextArray(
            headers: ['Apoderado', 'Beneficiario', 'Viernes', 'Monto', 'Estado'],
            data: docs.map((doc) {
              final d = doc.data();
              return [
                _nombreRegistro(d),
                _beneficiarioRegistro(d),
                _fecha(d['fecha_viernes'] ?? d['fecha_limite_pago']),
                onMoney(d['monto'] ?? 0),
                _estadoTesoreria(d),
              ];
            }).toList(),
          ),
        ],
      ),
    );
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'tesoreria_reemplazos_aseo.pdf');
  }

  String _estadoTesoreria(Map<String, dynamic> d) {
    final estado = (d['estado_tesoreria'] ?? d['estado'] ?? 'pendiente_revision').toString();
    final fechaLimite = d['fecha_limite_pago'];
    if ((estado == 'pendiente_pago' || estado == 'pendiente_revision') && fechaLimite is Timestamp) {
      final limite = fechaLimite.toDate();
      final hoy = DateTime.now();
      final limiteDia = DateTime(limite.year, limite.month, limite.day, 23, 59);
      if (hoy.isAfter(limiteDia)) return 'vencido';
    }
    if (estado == 'aprobado') return 'pagado';
    return estado;
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'pagado':
      case 'aprobado':
        return const Color(0xFF00A878);
      case 'rechazado':
        return Colors.red;
      case 'vencido':
        return const Color(0xFFD35400);
      default:
        return const Color(0xFFE67E22);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // v8.1: se elimina orderBy('fecha_envio') para evitar índice compuesto en Firestore.
      // El orden se aplica abajo en memoria, suficiente para la etapa de pruebas.
      stream: FirebaseFirestore.instance
          .collection('aseo_reemplazos')
          .where('visible_tesoreria', isEqualTo: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _infoBox(
                'No se pudieron cargar los reemplazos de aseo. Revisa conexión, permisos o reglas de Firestore para aseo_reemplazos.',
              ),
              Text('${snap.error}'),
            ],
          );
        }
        if (!snap.hasData) return const LinearProgressIndicator();

        final docs = snap.data!.docs.toList()
          ..sort((a, b) {
            final fa = a.data()['fecha_envio'];
            final fb = b.data()['fecha_envio'];
            final da = fa is Timestamp ? fa.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final db = fb is Timestamp ? fb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });
        final pagados = docs.where((e) => _estadoTesoreria(e.data()) == 'pagado').length;
        final pendientes = docs.where((e) {
          final estado = _estadoTesoreria(e.data());
          return estado == 'pendiente_pago' || estado == 'pendiente_revision';
        }).length;
        final vencidos = docs.where((e) => _estadoTesoreria(e.data()) == 'vencido').length;
        final montoPendiente = docs.where((e) {
          final estado = _estadoTesoreria(e.data());
          return estado == 'pendiente_pago' || estado == 'pendiente_revision' || estado == 'vencido';
        }).fold<int>(0, (sum, e) => sum + ((e.data()['monto'] is num) ? (e.data()['monto'] as num).toInt() : 0));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _infoBox(
              'Tesorería solo recibe estos registros para estadísticas, control y cobro. No se suman a caja general ni a ingresos institucionales.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _stat('Pendientes', '$pendientes', Icons.pending_actions, const Color(0xFFE67E22))),
                const SizedBox(width: 8),
                Expanded(child: _stat('Pagados', '$pagados', Icons.verified, const Color(0xFF00A878))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _stat('Vencidos', '$vencidos', Icons.warning_amber, const Color(0xFFD35400))),
                const SizedBox(width: 8),
                Expanded(child: _stat('Por cobrar', onMoney(montoPendiente), Icons.payments, const Color(0xFF004193))),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: docs.isEmpty ? null : () => _generarPdf(docs),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF reemplazos'),
              ),
            ),
            const SizedBox(height: 16),
            if (docs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aún no hay reemplazos de aseo recibidos.'),
                ),
              ),
            ...docs.map((doc) {
              final d = doc.data();
              final estado = _estadoTesoreria(d);
              final color = _colorEstado(estado);
              final monto = d['monto'] is num ? d['monto'] as num : 0;
              final foto = (d['foto_url'] ?? '').toString();
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.12),
                          child: Icon(Icons.cleaning_services, color: color),
                        ),
                        title: Text(
                          _nombreRegistro(d),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          'Categoría: Reemplazo de aseo\n'
                          'Beneficiario: ${_beneficiarioRegistro(d)}\n'
                          'Viernes solicitado: ${_fecha(d['fecha_viernes'] ?? d['fecha_limite_pago'])}\n'
                          'Monto: ${onMoney(monto)}\n'
                          'Estado: $estado\n'
                          'Ingreso institucional: No',
                        ),
                        isThreeLine: true,
                      ),
                      if (foto.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _verFoto(context, foto, titulo: 'Comprobante de reemplazo'),
                          icon: const Icon(Icons.image),
                          label: const Text('Ver foto'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Nota: este movimiento queda separado de mensualidades, terapias, talleres, eventos y donaciones.',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _infoBox(String texto) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF35506B))),
    );
  }

  Widget _stat(String titulo, String valor, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icono, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF35506B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
