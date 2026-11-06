import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// V23: cierre visual completo Panel Profesional: color en formularios, fichas pastel y marca de agua.


void _abrirArchivoProfesional(BuildContext context, String url, String tipo) {
  if (url.trim().isEmpty) return;
  if (tipo.toLowerCase().contains('video')) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }
  _verFotoProfesional(context, url);
}

void _verFotoProfesional(BuildContext context, String url, {String titulo = 'Foto'}) {
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
              minScale: 0.5,
              maxScale: 4,
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

class ProfesionalIndividualHomePage extends StatefulWidget {
  const ProfesionalIndividualHomePage({super.key});

  @override
  State<ProfesionalIndividualHomePage> createState() => _ProfesionalIndividualHomePageState();
}

class _ProfesionalIndividualHomePageState extends State<ProfesionalIndividualHomePage> {
  int index = 0;

  void _irA(int destino) => setState(() => index = destino);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = _normalizarEmail(user?.email ?? '');
    final uid = _normalizarUid(user?.uid ?? '');
    final pages = [
      _ResumenProfesionalTab(email: email, uid: uid, onNavigate: _irA),
      _MisBeneficiariosTab(email: email, uid: uid),
      _RegistrarAtencionTab(email: email, uid: uid),
      _TareasTerapeuticasTab(email: email, uid: uid),
      _SeguimientoTrabajoCasaTab(email: email, uid: uid),
      _MensajesProfesionalTab(uid: uid),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: index == 0
            ? const BackButton()
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => index = 0)),
        title: const Text('Panel Profesional'),
      ),
      body: pages[index],
    );
  }
}


class _ResumenProfesionalTab extends StatelessWidget {
  final String email;
  final String uid;
  final ValueChanged<int> onNavigate;
  const _ResumenProfesionalTab({required this.email, required this.uid, required this.onNavigate});

  Future<int> _count(Query query) async => (await query.get()).docs.length;

  Future<Map<String, dynamic>> _resumen() async {
    final db = FirebaseFirestore.instance;
    final bitacorasSnap = await db.collection('ar_bitacora_casa').where('profesional_uid', isEqualTo: uid).get();
    int planes = 0;
    int seguimientos = 0;
    for (final d in bitacorasSnap.docs) {
      final tipo = (d.data()['tipo_doc'] ?? '').toString();
      if (tipo == 'plan_trabajo_casa') {
        planes++;
      } else {
        seguimientos++;
      }
    }

    // Beneficiarios debe representar personas únicas, no cantidad de horarios/asignaciones.
    final asignacionesSnap = await db.collection('ar_asignaciones_mensuales').where('profesional_uid', isEqualTo: uid).get();
    final beneficiariosUnicos = <String>{};
    for (final d in asignacionesSnap.docs) {
      final m = d.data();
      final estado = (m['estado'] ?? 'activa').toString().toLowerCase();
      if (estado == 'eliminada' || estado == 'inactiva' || estado == 'suspendida_tesoreria') continue;
      final id = (m['beneficiario_id'] ?? m['rut_beneficiario'] ?? m['rut_usuario'] ?? m['beneficiario_nombre'] ?? '').toString().trim();
      if (id.isNotEmpty) beneficiariosUnicos.add(id.toLowerCase());
    }

    String nombre = '';
    if (email.isNotEmpty) {
      final prof = await db.collection('profesionales').where('email', isEqualTo: email).limit(1).get();
      if (prof.docs.isNotEmpty) nombre = (prof.docs.first.data()['nombre'] ?? '').toString().trim();
    }
    if (nombre.isEmpty) {
      for (final d in bitacorasSnap.docs) {
        final n = (d.data()['profesional_nombre'] ?? '').toString().trim();
        if (n.isNotEmpty) { nombre = n; break; }
      }
    }
    final primerNombre = nombre.isEmpty ? '' : nombre.split(RegExp(r'\s+')).first;

    return {
      'nombre': primerNombre,
      'asignaciones': beneficiariosUnicos.length,
      'atenciones': await _count(db.collection('atenciones_profesionales').where('profesional_uid', isEqualTo: uid)),
      'trabajoCasa': planes,
      'bitacoras': seguimientos,
    };
  }

  Widget _miniStat(String titulo, String valor, IconData icono, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(.10)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: color.withOpacity(.14),
          foregroundColor: color,
          child: Icon(icono, size: 23),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, height: 1.12, fontWeight: FontWeight.w800, color: Color(0xFF263238))),
        ),
        const SizedBox(width: 6),
        Text(valor, style: TextStyle(fontSize: 28, height: 1, fontWeight: FontWeight.w900, color: color)),
      ]),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _resumen(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        final nombre = (r['nombre'] ?? '').toString();
        final saludo = nombre.isEmpty ? '¡Hola! 👋' : '¡Hola, $nombre! 👋';
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF2FAFF), Color(0xFFFFF8F2), Color(0xFFF8F4FF)]),
            image: DecorationImage(image: AssetImage('assets/images/fondo_home.png'), fit: BoxFit.cover, opacity: .055),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: ListView(
            padding: EdgeInsets.fromLTRB(MediaQuery.of(context).size.width >= 800 ? 24 : 16, 16, MediaQuery.of(context).size.width >= 800 ? 24 : 16, 30),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 15, 8, 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFDDF4FF), Color(0xFFFFF0C5), Color(0xFFF8E8FF)]),
                  image: const DecorationImage(image: AssetImage('assets/images/banner_familia.png'), fit: BoxFit.cover, alignment: Alignment.centerRight, opacity: .30),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: Colors.blue.withOpacity(.08), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(saludo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
                    const SizedBox(height: 4),
                    const Text('Tu jornada de hoy', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF174F79))),
                    const SizedBox(height: 4),
                    const Text('Revisa tus atenciones y el seguimiento de tus beneficiarios.', style: TextStyle(fontSize: 14, height: 1.25, color: Color(0xFF567185))),
                  ])),
                  Container(
                    width: 150, height: 108,
                    alignment: Alignment.bottomRight,
                    child: Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 112, height: 108, fit: BoxFit.contain),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('notificaciones_profesionales').where('profesional_uid', isEqualTo: uid).where('resuelta', isEqualTo: false).snapshots(),
                builder: (context, alertSnap) {
                  if (!alertSnap.hasData || alertSnap.data!.docs.isEmpty) return const SizedBox.shrink();
                  final docs=alertSnap.data!.docs;
                  return Column(children: docs.map((doc){ final d=doc.data() as Map<String,dynamic>; final suspension=(d['tipo']??'').toString()=='suspension_tesoreria'; return Container(width:double.infinity,margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:suspension?const Color(0xFFFFEBEE):const Color(0xFFE8F5E9),borderRadius:BorderRadius.circular(18),border:Border.all(color:suspension?const Color(0xFFC62828):const Color(0xFF2E7D32))),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(suspension?Icons.block:Icons.check_circle,color:suspension?const Color(0xFFC62828):const Color(0xFF2E7D32)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((d['titulo']??'Aviso Tesorería').toString(),style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:3),Text((d['mensaje']??'').toString(),style:const TextStyle(fontWeight:FontWeight.w700))]))])); }).toList());
                },
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width >= 1000 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.05,
                children: [
                  _miniStat('Beneficiarios', '${r['asignaciones']}', Icons.child_care_rounded, const Color(0xFF1697E5), () => onNavigate(1)),
                  _miniStat('Atenciones', '${r['atenciones']}', Icons.fact_check_rounded, const Color(0xFF27AE60), () => onNavigate(2)),
                  _miniStat('Seguimientos', '${r['bitacoras']}', Icons.assignment_turned_in_rounded, const Color(0xFF9C27B0), () => onNavigate(4)),
                ],
              ),
              const SizedBox(height: 14),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('notificaciones_profesionales').where('profesional_uid', isEqualTo: uid).where('resuelta', isEqualTo: false).snapshots(),
                builder: (context, msgSnap) {
                  final mensajes = msgSnap.hasData ? msgSnap.data!.docs.where((d) => ((d.data() as Map<String,dynamic>)['tipo'] ?? '').toString().startsWith('apoderado_')).length : 0;
                  return InkWell(
                    borderRadius: BorderRadius.circular(25),
                    onTap: () => onNavigate(5),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFEAF4FF), borderRadius: BorderRadius.circular(25)),
                      child: Row(children: [
                        const Icon(Icons.mark_chat_unread_rounded, color: Color(0xFF0877C9), size: 29),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Mensajes', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
                          SizedBox(height: 3),
                          Text('Novedades enviadas por los apoderados.', style: TextStyle(color: Color(0xFF6D6D6D), fontWeight: FontWeight.w600)),
                        ])),

                        if (mensajes > 0) CircleAvatar(radius: 17, backgroundColor: Colors.red, child: Text('$mensajes', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right_rounded, color: Color(0xFF075B98), size: 30),
                      ]),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ParaHoyProfesionalPage(email: email, uid: uid))),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFFFF5D8), borderRadius: BorderRadius.circular(25)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded, color: Color(0xFF075B98), size: 29),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Para hoy', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
                      SizedBox(height: 3),
                      Text('Ver próximas atenciones pendientes de hoy.', style: TextStyle(color: Color(0xFF6D6D6D), fontWeight: FontWeight.w600)),
                    ])),

                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF075B98), size: 30),
                  ]),
                ),
              ),
            ],
          ),
            ),
          ),
        );
      },
    );
  }
}


class _ParaHoyProfesionalPage extends StatelessWidget {
  final String email;
  final String uid;
  const _ParaHoyProfesionalPage({required this.email, required this.uid});

  String _diaSemana(DateTime d) {
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    return dias[d.weekday - 1];
  }

  bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _esDeHoy(Map<String, dynamic> m, DateTime hoy) {
    final f = m['fecha'];
    if (f is Timestamp) return _mismoDia(f.toDate(), hoy);
    return (m['dia'] ?? '').toString().trim().toLowerCase() == _diaSemana(hoy);
  }

  int _minutos(String hora) {
    final match = RegExp(r'(\d{1,2})[:.]?(\d{2})').firstMatch(hora.trim());
    if (match == null) return 9999;
    return (int.tryParse(match.group(1)!) ?? 99) * 60 + (int.tryParse(match.group(2)!) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC), foregroundColor: Colors.white,
        title: const Text('Para hoy'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').where('profesional_uid', isEqualTo: uid).snapshots(),
        builder: (context, asignSnap) {
          if (!asignSnap.hasData) return const Center(child: CircularProgressIndicator());
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('atenciones_profesionales').where('profesional_uid', isEqualTo: uid).snapshots(),
            builder: (context, atenSnap) {
              if (!atenSnap.hasData) return const Center(child: CircularProgressIndicator());
              final completadasHoy = <String>{};
              for (final d in atenSnap.data!.docs) {
                final m = d.data() as Map<String, dynamic>;
                final f = m['fecha'];
                if (f is Timestamp && _mismoDia(f.toDate(), hoy)) {
                  final id = (m['asignacion_id'] ?? '').toString();
                  if (id.isNotEmpty) completadasHoy.add(id);
                }
              }
              final pendientes = asignSnap.data!.docs.where((d) {
                final m = d.data() as Map<String, dynamic>;
                final estado=(m['estado']??'activa').toString().toLowerCase();
                if(estado=='eliminada'||estado=='inactiva'||estado=='suspendida_tesoreria') return false;
                return _esDeHoy(m, hoy) && !completadasHoy.contains(d.id);
              }).toList();
              pendientes.sort((a, b) {
                final ma = a.data() as Map<String, dynamic>;
                final mb = b.data() as Map<String, dynamic>;
                return _minutos((ma['hora'] ?? ma['horario'] ?? '').toString()).compareTo(_minutos((mb['hora'] ?? mb['horario'] ?? '').toString()));
              });

              if (pendientes.isEmpty) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded, size: 72, color: Color(0xFF27AE60)),
                    SizedBox(height: 14),
                    Text('¡Jornada completada!', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF174F79))),
                    SizedBox(height: 6),
                    Text('No quedan atenciones pendientes para hoy.', textAlign: TextAlign.center),
                  ]),
                ));
              }

              final ahoraMin = hoy.hour * 60 + hoy.minute;
              pendientes.sort((a, b) {
                final ma = a.data() as Map<String, dynamic>;
                final mb = b.data() as Map<String, dynamic>;
                final aa = _minutos((ma['hora'] ?? ma['horario'] ?? '').toString());
                final bb = _minutos((mb['hora'] ?? mb['horario'] ?? '').toString());
                final ka = (aa - ahoraMin).abs();
                final kb = (bb - ahoraMin).abs();
                if (ka != kb) return ka.compareTo(kb);
                return aa.compareTo(bb);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: pendientes.length,
                itemBuilder: (context, i) {
                  final d = pendientes[i];
                  final m = d.data() as Map<String, dynamic>;
                  final hora = (m['hora'] ?? m['horario'] ?? 'Sin hora').toString();
                  final nombre = _texto(m, ['beneficiario_nombre', 'nombre_beneficiario', 'nombre_usuario'], 'Beneficiario');
                  final terapia = _texto(m, ['servicio_nombre', 'terapia'], 'Atención');
                  final esSiguiente = i == 0;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _BeneficiarioAtencionesHistorialPage(email: email, uid: uid, asignacionId: d.id, asignacion: m))),
                    child: Card(
                    elevation: esSiguiente ? 3 : 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    color: esSiguiente ? const Color(0xFFEAF6FF) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: esSiguiente ? const Color(0xFF1697E5) : Colors.grey.shade200)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        CircleAvatar(radius: 28, backgroundColor: const Color(0xFFDDF2FF), child: Text(hora, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF075B98), fontSize: 13))),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (esSiguiente) const Text('PRÓXIMA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF1697E5))),
                          Text(nombre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          Text(terapia, style: const TextStyle(color: Color(0xFF607D8B))),
                        ])),
                      ]),
                    ),
                  ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}


class _BeneficiarioAtencionesHistorialPage extends StatefulWidget {
  final String email;
  final String uid;
  final String asignacionId;
  final Map<String, dynamic> asignacion;
  const _BeneficiarioAtencionesHistorialPage({required this.email, required this.uid, required this.asignacionId, required this.asignacion});
  @override State<_BeneficiarioAtencionesHistorialPage> createState() => _BeneficiarioAtencionesHistorialPageState();
}

class _BeneficiarioAtencionesHistorialPageState extends State<_BeneficiarioAtencionesHistorialPage> {
  int vista = 0;
  @override Widget build(BuildContext context) {
    final m=widget.asignacion;
    final nombre=_texto(m,['beneficiario_nombre','nombre_beneficiario','nombre_usuario'],'Beneficiario');
    final rut=_texto(m,['rut_beneficiario','beneficiario_id','rut_usuario']);
    final apoderado=_texto(m,['nombre_apoderado','apoderado_nombre'],'No informado');
    return Scaffold(
      appBar: AppBar(backgroundColor: const Color(0xFF0066CC), foregroundColor: Colors.white, title: Text(nombre, overflow: TextOverflow.ellipsis)),
      body: Column(children:[
        Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(16,12,16,10), color: const Color(0xFFF2F9FF), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Text(nombre.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF075B98))),
          if(rut.isNotEmpty) Text('RUT: $rut'), Text('Apoderado: $apoderado'),
          const SizedBox(height:10), Row(children:[
            Expanded(child: ElevatedButton.icon(onPressed:()=>setState(()=>vista=0), icon:const Icon(Icons.fact_check), label:const Text('Atenciones'), style:ElevatedButton.styleFrom(backgroundColor:vista==0?const Color(0xFF0877C9):Colors.white, foregroundColor:vista==0?Colors.white:const Color(0xFF0877C9)))),
            const SizedBox(width:8),
            Expanded(child: ElevatedButton.icon(onPressed:()=>setState(()=>vista=1), icon:const Icon(Icons.history), label:const Text('Historial'), style:ElevatedButton.styleFrom(backgroundColor:vista==1?const Color(0xFF0877C9):Colors.white, foregroundColor:vista==1?Colors.white:const Color(0xFF0877C9)))),
          ])
        ])),
        Expanded(child: vista==0 ? _RegistrarAtencionTab(email:widget.email, uid:widget.uid, initialAsignacionId:widget.asignacionId) : _HistorialIntegralBeneficiarioView(asignacion:m)),
      ]),
    );
  }
}

class _HistorialIntegralBeneficiarioView extends StatelessWidget {
  final Map<String,dynamic> asignacion;
  const _HistorialIntegralBeneficiarioView({required this.asignacion});
  String get id => _texto(asignacion,['beneficiario_id','rut_beneficiario','rut_usuario']);
  bool corresponde(Map<String,dynamic> m) {
    final mid=_texto(m,['beneficiario_id','rut_beneficiario','rut_usuario']);
    final nom=_texto(m,['beneficiario_nombre','nombre_beneficiario']).toLowerCase();
    final objetivo=_texto(asignacion,['beneficiario_nombre','nombre_beneficiario']).toLowerCase();
    return (id.isNotEmpty && mid==id) || (objetivo.isNotEmpty && nom==objetivo);
  }
  DateTime fecha(Map<String,dynamic> m) { for(final k in ['fecha','fecha_creacion','fecha_inicio']) { final v=m[k]; if(v is Timestamp) return v.toDate(); } return DateTime.fromMillisecondsSinceEpoch(0); }
  @override Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(stream:FirebaseFirestore.instance.collection('atenciones_profesionales').snapshots(), builder:(context,aSnap){
      return StreamBuilder<QuerySnapshot>(stream:FirebaseFirestore.instance.collection('ar_bitacora_casa').snapshots(), builder:(context,cSnap){
        if(!aSnap.hasData || !cSnap.hasData) return const Center(child:CircularProgressIndicator());
        final items=<Map<String,dynamic>>[];
        for(final d in aSnap.data!.docs){ final m=Map<String,dynamic>.from(d.data() as Map); if(corresponde(m)) items.add({...m,'_tipo':'atencion','_id':d.id}); }
        for(final d in cSnap.data!.docs){ final m=Map<String,dynamic>.from(d.data() as Map); if(corresponde(m)) items.add({...m,'_tipo':m['tipo_doc']=='plan_trabajo_casa'?'plan':'bitacora','_id':d.id}); }
        items.sort((a,b)=>fecha(b).compareTo(fecha(a)));
        if(items.isEmpty) return const Center(child:Text('Aún no hay historial registrado para este beneficiario.'));
        return ListView.builder(padding:const EdgeInsets.all(12), itemCount:items.length, itemBuilder:(context,i){ final m=items[i]; final tipo=m['_tipo'];
          IconData icon=Icons.fact_check; String titulo='Atención profesional'; Color color=const Color(0xFF0877C9);
          if(tipo=='plan'){icon=Icons.home_work; titulo='Trabajo enviado a casa'; color=const Color(0xFFE56A9D);} else if(tipo=='bitacora'){icon=Icons.assignment_turned_in; titulo='Bitácora del apoderado'; color=const Color(0xFF7B61B2);}
          final prof=_texto(m,['profesional_nombre']); final terapia=_texto(m,['terapia','servicio_nombre']); final f=fecha(m); final fs=f.year>1970?'${f.day.toString().padLeft(2,'0')}-${f.month.toString().padLeft(2,'0')}-${f.year}':'';
          return Card(margin:const EdgeInsets.only(bottom:10), child:ExpansionTile(leading:Icon(icon,color:color), title:Text('$titulo${fs.isNotEmpty?' · $fs':''}',style:const TextStyle(fontWeight:FontWeight.w900)), subtitle:Text([if(prof.isNotEmpty) prof,if(terapia.isNotEmpty) terapia].join(' · ')), childrenPadding:const EdgeInsets.fromLTRB(16,0,16,14), children:[
            if(tipo=='atencion') ...[if(_texto(m,['objetivos_trabajados']).isNotEmpty) Align(alignment:Alignment.centerLeft,child:SelectableText('Objetivos: ${_texto(m,['objetivos_trabajados'])}')),if(_texto(m,['observaciones']).isNotEmpty) Align(alignment:Alignment.centerLeft,child:SelectableText('Observaciones: ${_texto(m,['observaciones'])}')),if(_texto(m,['recomendaciones_casa']).isNotEmpty) Align(alignment:Alignment.centerLeft,child:SelectableText('Casa: ${_texto(m,['recomendaciones_casa'])}'))],
            if(tipo=='plan') ...[Align(alignment:Alignment.centerLeft,child:Text('Objetivo: ${_texto(m,['objetivo'])}')),Align(alignment:Alignment.centerLeft,child:Text('Indicaciones: ${_texto(m,['indicaciones'])}')),if(m['sugerencias_aprobadas'] is List) ...List<String>.from((m['sugerencias_aprobadas'] as List).map((e)=>e.toString())).map((x)=>Align(alignment:Alignment.centerLeft,child:Text('• $x')))],
            if(tipo=='bitacora') Align(alignment:Alignment.centerLeft,child:Text('${m['realizado']==true?'Realizado':'No realizado'} · ${m['tiempo_minutos']??0} min\n${_texto(m,['observacion','estado_emocional'])}')),
          ]));
        });
      });
    });
  }
}


class _MensajesProfesionalTab extends StatelessWidget {
  final String uid;
  const _MensajesProfesionalTab({required this.uid});

  DateTime _fecha(Map<String,dynamic> m) {
    final v=m['fecha'];
    return v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(colors:[Color(0xFFF2FAFF),Color(0xFFFFF8F2)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('notificaciones_profesionales').where('profesional_uid',isEqualTo:uid).snapshots(),
        builder:(context,snap){
          if(!snap.hasData) return const Center(child:CircularProgressIndicator());
          final docs=snap.data!.docs.where((d)=>((d.data() as Map<String,dynamic>)['tipo']??'').toString().startsWith('apoderado_')).toList();
          docs.sort((a,b)=>_fecha(b.data() as Map<String,dynamic>).compareTo(_fecha(a.data() as Map<String,dynamic>)));
          if(docs.isEmpty) return const Center(child:Text('Aún no hay novedades enviadas por los apoderados.',style:TextStyle(fontSize:16,fontWeight:FontWeight.w700)));
          return ListView(padding:const EdgeInsets.all(18),children:[
            const Text('Mensajes y novedades',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:Color(0xFF075B98))),
            const SizedBox(height:4), const Text('Toca un aviso para revisar directamente lo que envió el apoderado.'), const SizedBox(height:14),
            ...docs.map((doc){final m=doc.data() as Map<String,dynamic>; final leido=m['resuelta']==true; final nombre=(m['beneficiario_nombre']??'Beneficiario').toString(); final titulo=(m['titulo']??'Nueva actividad del apoderado').toString(); final mensaje=(m['mensaje']??'').toString();
              return Card(color:leido?Colors.white:const Color(0xFFEAF4FF),margin:const EdgeInsets.only(bottom:10),child:ListTile(
                leading:CircleAvatar(backgroundColor:leido?const Color(0xFFECEFF1):const Color(0xFF0877C9),foregroundColor:leido?const Color(0xFF607D8B):Colors.white,child:const Icon(Icons.mark_chat_unread_rounded)),
                title:Text(titulo,style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('$nombre${mensaje.isNotEmpty?' · $mensaje':''}'),trailing:const Icon(Icons.chevron_right_rounded),
                onTap:() async {await doc.reference.update({'resuelta':true,'fecha_lectura':FieldValue.serverTimestamp()}); if(!context.mounted)return; Navigator.push(context,MaterialPageRoute(builder:(_)=>_DetalleNovedadApoderadoPage(data:m)));},
              ));
            })
          ]);
        }
      ))),
    );
  }
}

class _DetalleNovedadApoderadoPage extends StatelessWidget {
  final Map<String,dynamic> data;
  const _DetalleNovedadApoderadoPage({required this.data});
  @override Widget build(BuildContext context){
    final bid=(data['bitacora_id']??'').toString();
    return Scaffold(appBar:AppBar(backgroundColor:const Color(0xFF0066CC),foregroundColor:Colors.white,title:const Text('Envío del apoderado')),body:FutureBuilder<DocumentSnapshot>(
      future: bid.isEmpty ? null : FirebaseFirestore.instance.collection('ar_bitacora_casa').doc(bid).get(),
      builder:(context,snap){
        final m=(snap.hasData && snap.data!.exists)?snap.data!.data() as Map<String,dynamic>:data;
        final nombre=(m['beneficiario_nombre']??data['beneficiario_nombre']??'Beneficiario').toString();
        final realizado=m['realizado']==true; final minutos=m['tiempo_minutos']??0; final obs=(m['observacion']??'').toString(); final estado=(m['estado_emocional']??'').toString();
        return ListView(padding:const EdgeInsets.all(18),children:[
          Text(nombre,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900,color:Color(0xFF075B98))),const SizedBox(height:14),
          Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(realizado?'Trabajo en casa realizado':'Registro del apoderado',style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),const SizedBox(height:10),
            Text('Tiempo registrado: $minutos minutos'),if(estado.isNotEmpty) Text('Estado emocional: $estado'),if(obs.isNotEmpty)...[const SizedBox(height:8),Text('Observación: $obs')],
            if(m['respuestas_guiadas'] is Map)...[(const SizedBox(height:12)),...(m['respuestas_guiadas'] as Map).entries.where((e)=>e.value.toString().trim().isNotEmpty).map((e)=>Padding(padding:const EdgeInsets.only(bottom:6),child:Text('${e.key}: ${e.value}')))],
          ])))
        ]);
      }
    ));
  }
}

Color _fondoCampo(IconData icon) {
  if (icon == Icons.search) return const Color(0xFFF1F9FF);
  if (icon == Icons.event || icon == Icons.child_care) return const Color(0xFFF2FAF5);
  if (icon == Icons.fact_check) return const Color(0xFFFFF8E8);
  if (icon == Icons.flag) return const Color(0xFFFFF4F7);
  if (icon == Icons.note_alt) return const Color(0xFFF7F2FF);
  if (icon == Icons.home_work) return const Color(0xFFFFF8E8);
  if (icon == Icons.mic) return const Color(0xFFF1F9FF);
  if (icon == Icons.add_comment) return const Color(0xFFF2FAF5);
  return const Color(0xFFF7FBFE);
}

InputDecoration _deco(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF176FAE)),
      filled: true,
      fillColor: _fondoCampo(icon),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFC9DFEC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF1687CF), width: 1.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
    );

class _CampoTextoDictado extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  const _CampoTextoDictado({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
  });

  @override
  State<_CampoTextoDictado> createState() => _CampoTextoDictadoState();
}

class _CampoTextoDictadoState extends State<_CampoTextoDictado> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _activarDictado() {
    _focusNode.requestFocus();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Campo listo para dictar. Usa el micrófono del teclado del teléfono.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType ?? (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
      onChanged: widget.onChanged,
      decoration: _deco(widget.label, widget.icon).copyWith(
        suffixIcon: IconButton(
          tooltip: 'Dictar por voz',
          icon: const Icon(Icons.mic),
          onPressed: _activarDictado,
        ),
      ),
    );
  }
}

String _normalizarEmail(String v) => v.trim().toLowerCase();
String _normalizarUid(String v) => v.trim();

String _texto(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = (m[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return fallback;
}

String _motivoCambioLabel(Map<String, dynamic> m) {
  final raw = _texto(m, ['motivo_cambio_usuario', 'tipo_cambio_usuario', 'tipo_reemplazo']).trim().toUpperCase();
  if (raw == 'SOS') return 'SOS';
  if (raw == 'REAGENDADO') return 'Reagendado';
  return '';
}

String _fecha(dynamic value) {
  if (value is! Timestamp) return '';
  final d = value.toDate();
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}

Stream<QuerySnapshot> _misAsignaciones(String uid) {
  return FirebaseFirestore.instance
      .collection('ar_asignaciones_mensuales')
      .where('profesional_uid', isEqualTo: uid)
      .snapshots();
}


class _MiAgendaTab extends StatefulWidget {
  final String email;
  final String uid;
  const _MiAgendaTab({required this.email, required this.uid});

  @override
  State<_MiAgendaTab> createState() => _MiAgendaTabState();
}

class _MiAgendaTabState extends State<_MiAgendaTab> {
  late DateTime mesVisible;
  late DateTime diaSeleccionado;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    mesVisible = DateTime(ahora.year, ahora.month, 1);
    diaSeleccionado = DateTime(ahora.year, ahora.month, ahora.day);
  }

  String _nombreMes(int mes) {
    const meses = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return meses[mes - 1];
  }

  String _diaSemana(DateTime d) {
    const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    return dias[d.weekday - 1];
  }

  bool _esMismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _correspondeAlDia(Map<String, dynamic> m, DateTime dia) {
    final diaTexto = (m['dia'] ?? '').toString().trim().toLowerCase();
    final fecha = m['fecha'];
    if (fecha is Timestamp) {
      final f = fecha.toDate();
      return _esMismoDia(f, dia);
    }
    return diaTexto == _diaSemana(dia).toLowerCase();
  }

  List<QueryDocumentSnapshot> _docsDelDia(List<QueryDocumentSnapshot> docs, DateTime dia) {
    final filtrados = docs.where((d) => _correspondeAlDia(d.data() as Map<String, dynamic>, dia)).toList();
    filtrados.sort((a, b) {
      final ma = a.data() as Map<String, dynamic>;
      final mb = b.data() as Map<String, dynamic>;
      return (ma['hora'] ?? ma['horario'] ?? '').toString().compareTo((mb['hora'] ?? mb['horario'] ?? '').toString());
    });
    return filtrados;
  }

  Widget _calendario(List<QueryDocumentSnapshot> docs) {
    final primerDia = DateTime(mesVisible.year, mesVisible.month, 1);
    final diasMes = DateTime(mesVisible.year, mesVisible.month + 1, 0).day;
    final espaciosAntes = primerDia.weekday - 1;
    final totalCeldas = espaciosAntes + diasMes;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.blue.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: () => setState(() => mesVisible = DateTime(mesVisible.year, mesVisible.month - 1, 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_nombreMes(mesVisible.month)} ${mesVisible.year}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: () => setState(() => mesVisible = DateTime(mesVisible.year, mesVisible.month + 1, 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: const [
                _DiaHeader('Lun'), _DiaHeader('Mar'), _DiaHeader('Mié'), _DiaHeader('Jue'),
                _DiaHeader('Vie'), _DiaHeader('Sáb'), _DiaHeader('Dom'),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.35,
              ),
              itemCount: totalCeldas,
              itemBuilder: (_, i) {
                if (i < espaciosAntes) return const SizedBox.shrink();
                final numeroDia = i - espaciosAntes + 1;
                final fecha = DateTime(mesVisible.year, mesVisible.month, numeroDia);
                final seleccionado = _esMismoDia(fecha, diaSeleccionado);
                final cantidad = _docsDelDia(docs, fecha).length;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => diaSeleccionado = fecha),
                  child: Container(
                    decoration: BoxDecoration(
                      color: seleccionado ? const Color(0xFFE6F3FF) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: seleccionado ? const Color(0xFF008EE6) : Colors.grey.shade300, width: seleccionado ? 2 : 1),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            '$numeroDia',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: seleccionado ? const Color(0xFF0066CC) : Colors.black87,
                            ),
                          ),
                        ),
                        if (cantidad > 0)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: CircleAvatar(
                              radius: 10,
                              backgroundColor: const Color(0xFF008EE6),
                              child: Text('$cantidad', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _guardarCambioUsuario({
    required BuildContext pageContext,
    required BuildContext dialogContext,
    required QueryDocumentSnapshot asignacionDoc,
    required QueryDocumentSnapshot<Map<String, dynamic>> docUsuario,
    required String motivoCambio,
  }) async {
    final asignacionActual = asignacionDoc.data() as Map<String, dynamic>;
    final u = docUsuario.data();

    final nombre = _texto(u, ['nombre', 'nombre_usuario', 'beneficiario_nombre'], 'Usuario sin nombre');
    final rutCampo = _texto(u, ['rut', 'rut_usuario', 'rut_normalizado']);
    final rut = rutCampo.trim().isNotEmpty ? rutCampo.trim() : docUsuario.id;
    final apoderado = _texto(u, ['nombre_apoderado', 'apoderado_nombre'], 'Apoderado no informado');
    final telefono = _texto(u, ['telefono_apoderado', 'telefono']);
    final emailApoderado = _texto(u, ['email_apoderado', 'email']);
    final apoderadoUid = _texto(u, ['apoderado_uid', 'uid_apoderado']);
    final accesoApoderados = <String>{if (apoderadoUid.isNotEmpty) apoderadoUid};
    final apoyos = u['apoyos_autorizados'];
    if (apoyos is List) {
      for (final apoyo in apoyos) {
        if (apoyo is Map) {
          final uidApoyo = (apoyo['uid'] ?? apoyo['apoyo_uid'] ?? '').toString().trim();
          if (uidApoyo.isNotEmpty) accesoApoderados.add(uidApoyo);
        }
      }
    }
    final anteriorNombre = _texto(asignacionActual, ['beneficiario_nombre', 'nombre_beneficiario', 'nombre_usuario'], 'Beneficiario anterior');
    final anteriorRut = _texto(asignacionActual, ['beneficiario_id', 'rut_beneficiario', 'rut_usuario'], '');

    try {
      final db = FirebaseFirestore.instance;
      final ref = db.collection('ar_asignaciones_mensuales').doc(asignacionDoc.id);

      // Actualiza la hora existente. Se mantiene el mismo profesional, terapia, día y hora.
      await ref.update({
        'beneficiario_id': rut,
        'rut_beneficiario': rut,
        'rut_usuario': rut,
        'beneficiario_nombre': nombre,
        'nombre_beneficiario': nombre,
        'nombre_usuario': nombre,
        'apoderado_uid': apoderadoUid,
        'uid_apoderado': apoderadoUid,
        'apoderados_uids_autorizados': accesoApoderados.toList(),
        'nombre_apoderado': apoderado,
        'apoderado_nombre': apoderado,
        'telefono_apoderado': telefono,
        'email_apoderado': emailApoderado,
        'email_apoderado_normalizado': _normalizarEmail(emailApoderado),
        'cambio_manual_usuario': true,
        'motivo_cambio_usuario': motivoCambio,
        'tipo_cambio_usuario': motivoCambio,
        'usuario_anterior_nombre': anteriorNombre,
        'usuario_anterior_rut': anteriorRut,
        'actualizado': FieldValue.serverTimestamp(),
        'cambiado_manualmente_en': FieldValue.serverTimestamp(),
        'cambiado_manualmente_por': FirebaseAuth.instance.currentUser?.email ?? FirebaseAuth.instance.currentUser?.uid,
      });

      // Registro simple para auditoría interna. Si falla, no bloquea el cambio principal.
      try {
        await db.collection('ar_cambios_usuario_agenda').add({
          'asignacion_id': asignacionDoc.id,
          'usuario_anterior_nombre': anteriorNombre,
          'usuario_anterior_rut': anteriorRut,
          'usuario_nuevo_nombre': nombre,
          'usuario_nuevo_rut': rut,
          'motivo_cambio_usuario': motivoCambio,
          'tipo_cambio_usuario': motivoCambio,
          'profesional_uid': _texto(asignacionActual, ['profesional_uid']),
          'profesional_nombre': _texto(asignacionActual, ['profesional_nombre']),
          'dia': _texto(asignacionActual, ['dia']),
          'hora': _texto(asignacionActual, ['hora', 'horario']),
          'servicio_nombre': _texto(asignacionActual, ['servicio_nombre', 'terapia']),
          'creado': FieldValue.serverTimestamp(),
          'creado_por': FirebaseAuth.instance.currentUser?.email ?? FirebaseAuth.instance.currentUser?.uid,
        });
      } catch (_) {}

      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Hora reasignada a $nombre como $motivoCambio')),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('No se pudo reasignar: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('No se pudo reasignar: $e')),
        );
      }
    }
  }

  Future<void> _confirmarYGuardarCambioUsuario({
    required BuildContext pageContext,
    required BuildContext dialogContext,
    required QueryDocumentSnapshot asignacionDoc,
    required QueryDocumentSnapshot<Map<String, dynamic>> docUsuario,
    required String motivoCambio,
  }) async {
    final asignacionActual = asignacionDoc.data() as Map<String, dynamic>;
    final usuarioNuevo = docUsuario.data();
    final anteriorNombre = _texto(asignacionActual, ['beneficiario_nombre', 'nombre_beneficiario', 'nombre_usuario'], 'Beneficiario actual');
    final nuevoNombre = _texto(usuarioNuevo, ['nombre', 'nombre_usuario', 'beneficiario_nombre'], 'Usuario nuevo');
    final hora = _texto(asignacionActual, ['hora', 'horario'], 'hora asignada');
    final motivoLabel = motivoCambio == 'SOS' ? 'SOS' : 'Reagendado';

    final confirmar = await showDialog<bool>(
      context: pageContext,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar cambio'),
        content: Text('¿Desea reemplazar a $anteriorNombre por $nuevoNombre en la atención de las $hora?\n\nMotivo: $motivoLabel'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(pageContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(pageContext, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirmar == true) {
      await _guardarCambioUsuario(
        pageContext: pageContext,
        dialogContext: dialogContext,
        asignacionDoc: asignacionDoc,
        docUsuario: docUsuario,
        motivoCambio: motivoCambio,
      );
    }
  }

  Future<void> _cambiarUsuarioAsignado(BuildContext context, QueryDocumentSnapshot asignacionDoc) async {
    final busquedaCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        String filtro = '';
        String motivoCambio = 'SOS';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cambiar usuario asignado'),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Busca por nombre o RUT, selecciona el motivo y presiona "Asignar" para confirmar el cambio de esta hora.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: busquedaCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Buscar usuario',
                        hintText: 'Nombre o RUT',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setDialogState(() => filtro = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'SOS', label: Text('SOS'), icon: Icon(Icons.priority_high)),
                        ButtonSegment(value: 'REAGENDADO', label: Text('Reagendado'), icon: Icon(Icons.event_repeat)),
                      ],
                      selected: {motivoCambio},
                      onSelectionChanged: (v) => setDialogState(() => motivoCambio = v.first),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        future: FirebaseFirestore.instance.collection('ar_beneficiarios').get(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            return const Center(child: Text('No se pudo cargar la lista de usuarios.'));
                          }

                          final usuarios = (snap.data?.docs ?? []).where((doc) {
                            final u = doc.data();
                            final nombre = _texto(u, ['nombre', 'nombre_usuario', 'beneficiario_nombre']).toLowerCase();
                            final rut = _texto(u, ['rut', 'rut_usuario', 'rut_normalizado'], doc.id).toLowerCase();
                            if (filtro.isEmpty) return true;
                            return nombre.contains(filtro) || rut.contains(filtro);
                          }).toList()
                            ..sort((a, b) {
                              final an = _texto(a.data(), ['nombre', 'nombre_usuario', 'beneficiario_nombre']);
                              final bn = _texto(b.data(), ['nombre', 'nombre_usuario', 'beneficiario_nombre']);
                              return an.compareTo(bn);
                            });

                          if (usuarios.isEmpty) {
                            return const Center(child: Text('No se encontraron usuarios con esa búsqueda.'));
                          }

                          return ListView.separated(
                            itemCount: usuarios.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final docUsuario = usuarios[i];
                              final u = docUsuario.data();
                              final nombre = _texto(u, ['nombre', 'nombre_usuario', 'beneficiario_nombre'], 'Usuario sin nombre');
                              final rutCampo = _texto(u, ['rut', 'rut_usuario', 'rut_normalizado']);
                              final rut = rutCampo.trim().isNotEmpty ? rutCampo.trim() : docUsuario.id;
                              final apoderado = _texto(u, ['nombre_apoderado', 'apoderado_nombre'], 'Apoderado no informado');
                              final telefono = _texto(u, ['telefono_apoderado', 'telefono'], '');

                              return ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.child_care)),
                                title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text('RUT: $rut\nApoderado: $apoderado${telefono.trim().isNotEmpty ? '\nTeléfono: $telefono' : ''}'),
                                isThreeLine: telefono.trim().isNotEmpty,
                                trailing: FilledButton.icon(
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Asignar'),
                                  onPressed: () async {
                                    await _confirmarYGuardarCambioUsuario(
                                      pageContext: context,
                                      dialogContext: dialogContext,
                                      asignacionDoc: asignacionDoc,
                                      docUsuario: docUsuario,
                                      motivoCambio: motivoCambio,
                                    );
                                  },
                                ),
                                onTap: () async {
                                  await _confirmarYGuardarCambioUsuario(
                                    pageContext: context,
                                    dialogContext: dialogContext,
                                    asignacionDoc: asignacionDoc,
                                    docUsuario: docUsuario,
                                    motivoCambio: motivoCambio,
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );

    busquedaCtrl.dispose();
  }

  Widget _listaAtenciones(BuildContext context, List<QueryDocumentSnapshot> docsDelDia, List<QueryDocumentSnapshot> todas) {
    final titulo = '${_diaSemana(diaSeleccionado)} ${diaSeleccionado.day} - Atenciones del día';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.blue.shade100)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 8),
            if (docsDelDia.isEmpty)
              const Expanded(child: Center(child: Text('No hay usuarios agendados para este día.')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: docsDelDia.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = docsDelDia[i];
                    final m = d.data() as Map<String, dynamic>;
                    final beneficiario = _texto(m, ['beneficiario_nombre', 'nombre_beneficiario'], 'Beneficiario sin nombre');
                    final apoderado = _texto(m, ['nombre_apoderado', 'apoderado_nombre'], 'Apoderado no informado');
                    final terapia = _texto(m, ['servicio_nombre', 'terapia'], 'Terapia no informada');
                    final profesional = _texto(m, ['profesional_nombre'], 'Profesional no informado');
                    final hora = _texto(m, ['hora', 'horario'], 'Hora no informada');
                    final motivoCambio = _motivoCambioLabel(m);
                    final subtitulo = '$terapia\nProfesional: $profesional\nApoderado: $apoderado${motivoCambio.isNotEmpty ? '\nCambio: $motivoCambio' : ''}';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      leading: const CircleAvatar(backgroundColor: Color(0xFFEAF6FF), foregroundColor: Color(0xFF0066CC), child: Icon(Icons.schedule)),
                      title: Text('$hora · $beneficiario', style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text(subtitulo),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (motivoCambio.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Chip(
                                label: Text(motivoCambio, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                                backgroundColor: motivoCambio == 'SOS' ? const Color(0xFFFFE8E8) : const Color(0xFFFFF3D6),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          IconButton(
                            tooltip: 'Cambiar usuario de esta hora',
                            icon: const Icon(Icons.swap_horiz, color: Color(0xFF0066CC)),
                            onPressed: () => _cambiarUsuarioAsignado(context, d),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _PerfilBeneficiarioProfesionalPage(asignacion: m),
                          ),
                        );
                      },
                    );
                  },
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
      stream: _misAsignaciones(widget.uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.toList();
        if (docs.isEmpty) return const Center(child: Text('Aún no tienes agenda asignada.'));
        final docsDelDia = _docsDelDia(docs, diaSeleccionado);

        return LayoutBuilder(
          builder: (context, constraints) {
            final esAncho = constraints.maxWidth >= 520;
            if (esAncho) {
              final anchoCalendario = constraints.maxWidth * 0.48;
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: anchoCalendario.clamp(360.0, 520.0),
                      child: SingleChildScrollView(child: _calendario(docs)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _listaAtenciones(context, docsDelDia, docs)),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _calendario(docs),
                const SizedBox(height: 12),
                SizedBox(height: 430, child: _listaAtenciones(context, docsDelDia, docs)),
              ],
            );
          },
        );
      },
    );
  }
}

class _DiaHeader extends StatelessWidget {
  final String texto;
  const _DiaHeader(this.texto);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF46627A))),
      ),
    );
  }
}

class _PerfilBeneficiarioProfesionalPage extends StatelessWidget {
  final Map<String, dynamic> asignacion;
  const _PerfilBeneficiarioProfesionalPage({required this.asignacion});

  String get beneficiarioId => _texto(asignacion, ['beneficiario_id', 'rut_beneficiario', 'rut', 'rut_usuario']);
  String get beneficiarioNombre => _texto(asignacion, ['beneficiario_nombre', 'nombre_beneficiario', 'nombre', 'nombre_usuario'], 'Beneficiario');

  Query<Map<String, dynamic>> _queryAsignaciones() {
    final db = FirebaseFirestore.instance.collection('ar_asignaciones_mensuales');
    if (beneficiarioId.trim().isNotEmpty) {
      return db.where('beneficiario_id', isEqualTo: beneficiarioId.trim());
    }
    return db.where('beneficiario_nombre', isEqualTo: beneficiarioNombre);
  }

  Widget _dato(String label, String valor, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF0066CC)),
          const SizedBox(width: 8),
          Expanded(child: Text('$label: $valor', style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sesionesOrdenadas(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = docs.where((doc) {
      final estado = _texto(doc.data(), ['estado'], 'activa').toLowerCase();
      return estado != 'eliminada' && estado != 'inactiva' && estado != 'suspendida_tesoreria';
    }).toList();
    out.sort((a, b) {
      final ma = a.data();
      final mb = b.data();
      final at = '${_texto(ma, ['servicio_nombre', 'terapia'])}|${_texto(ma, ['profesional_nombre'])}|${_texto(ma, ['dia'])}|${_texto(ma, ['hora', 'horario'])}';
      final bt = '${_texto(mb, ['servicio_nombre', 'terapia'])}|${_texto(mb, ['profesional_nombre'])}|${_texto(mb, ['dia'])}|${_texto(mb, ['hora', 'horario'])}';
      return at.compareTo(bt);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final apoderado = _texto(asignacion, ['nombre_apoderado', 'apoderado_nombre'], 'No informado');
    final telefono = _texto(asignacion, ['telefono_apoderado', 'telefono'], 'No informado');
    final rut = _texto(asignacion, ['rut_beneficiario', 'beneficiario_id', 'rut', 'rut_usuario'], 'No informado');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        title: const Text('Perfil del beneficiario'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _queryAsignaciones().snapshots(),
        builder: (context, snap) {
          final asignaciones = _sesionesOrdenadas(snap.data?.docs ?? []);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.blue.shade100)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(beneficiarioNombre.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF0047B3))),
                      const SizedBox(height: 10),
                      _dato('RUT', rut, Icons.badge),
                      _dato('Apoderado', apoderado, Icons.person),
                      _dato('Teléfono', telefono, Icons.phone),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Terapias y profesionales asignados', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 4),
              const Text('Toca una terapia para revisar todo el itinerario registrado desde que empezó el beneficiario.', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF607D8B))),
              const SizedBox(height: 8),
              if (!snap.hasData)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (asignaciones.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No se encontraron terapias asignadas para este beneficiario.')))
              else
                ...asignaciones.map((doc) {
                  final m = doc.data();
                  final terapia = _texto(m, ['servicio_nombre', 'terapia'], 'Terapia no informada');
                  final profesional = _texto(m, ['profesional_nombre'], 'Profesional no informado');
                  final dia = _texto(m, ['dia'], 'Día no informado');
                  final hora = _texto(m, ['hora', 'horario'], 'Hora no informada');
                  final estado = _texto(m, ['estado'], 'activa');
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0xFFEAF6FF), foregroundColor: Color(0xFF0066CC), child: Icon(Icons.medical_services)),
                      title: Text(terapia.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text('Profesional: $profesional\nHorario: $dia $hora\nEstado: $estado'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _HistorialTerapiaBeneficiarioPage(
                              beneficiarioId: rut == 'No informado' ? beneficiarioId : rut,
                              beneficiarioNombre: beneficiarioNombre,
                              terapia: terapia,
                              asignacion: m,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _HistorialTerapiaBeneficiarioPage extends StatelessWidget {
  final String beneficiarioId;
  final String beneficiarioNombre;
  final String terapia;
  final Map<String, dynamic> asignacion;
  const _HistorialTerapiaBeneficiarioPage({
    required this.beneficiarioId,
    required this.beneficiarioNombre,
    required this.terapia,
    required this.asignacion,
  });

  bool _mismaTerapia(Map<String, dynamic> m) {
    final t = _texto(m, ['terapia', 'servicio_nombre']).trim().toLowerCase();
    return t == terapia.trim().toLowerCase();
  }

  String _asistenciaLabel(String v) {
    switch (v) {
      case 'asistio': return 'Asistió';
      case 'no_asistio_justificado': return 'No asistió justificado';
      case 'no_asistio_injustificado': return 'No asistió injustificado';
      default: return v.trim().isEmpty ? 'Sin estado' : v;
    }
  }

  Widget _linea(String titulo, String valor, IconData icono) {
    if (valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: const Color(0xFF0066CC)),
          const SizedBox(width: 8),
          Expanded(child: SelectableText('$titulo: $valor')),
          IconButton(
            tooltip: 'Copiar',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: valor));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profesional = _texto(asignacion, ['profesional_nombre'], 'Profesional no informado');
    final dia = _texto(asignacion, ['dia'], 'Día no informado');
    final hora = _texto(asignacion, ['hora', 'horario'], 'Hora no informada');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        title: const Text('Historial de terapia'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('atenciones_profesionales')
            .where('beneficiario_id', isEqualTo: beneficiarioId)
            .snapshots(),
        builder: (context, snap) {
          final docs = (snap.data?.docs ?? []).where((d) => _mismaTerapia(d.data())).toList();
          docs.sort((a, b) {
            final fa = a.data()['fecha'];
            final fb = b.data()['fecha'];
            final da = fa is Timestamp ? fa.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final db = fb is Timestamp ? fb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.blue.shade100)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(terapia.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF0047B3))),
                      const SizedBox(height: 8),
                      Text(beneficiarioNombre, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      _linea('Profesional actual', profesional, Icons.person),
                      _linea('Horario actual', '$dia $hora', Icons.schedule),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Itinerario / historial desde el inicio', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 8),
              if (!snap.hasData)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (docs.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Aún no hay atenciones registradas para esta terapia.')))
              else
                ...docs.map((doc) {
                  final m = doc.data();
                  final fecha = _fecha(m['fecha']);
                  final asistencia = _asistenciaLabel((m['asistencia'] ?? '').toString());
                  final prof = _texto(m, ['profesional_nombre'], profesional);
                  final objetivos = _texto(m, ['objetivos_trabajados']);
                  final obs = _texto(m, ['observaciones']);
                  final rec = _texto(m, ['recomendaciones_casa']);
                  final motivo = _motivoCambioLabel(m);
                  return Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.fact_check, color: Color(0xFF0066CC)),
                      title: Text('${fecha.isEmpty ? 'Fecha no registrada' : fecha} · $asistencia', style: const TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: Text('Profesional: $prof${motivo.isNotEmpty ? '\nCambio: $motivo' : ''}'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _linea('Objetivos trabajados', objetivos, Icons.flag),
                        _linea('Observaciones', obs, Icons.note_alt),
                        _linea('Recomendaciones', rec, Icons.home_work),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _MisBeneficiariosTab extends StatefulWidget {
  final String email;
  final String uid;
  const _MisBeneficiariosTab({required this.email, required this.uid});

  @override
  State<_MisBeneficiariosTab> createState() => _MisBeneficiariosTabState();
}

class _MisBeneficiariosTabState extends State<_MisBeneficiariosTab> {
  final TextEditingController buscarCtrl = TextEditingController();
  String filtro = '';

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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: buscarCtrl,
            decoration: _deco('Buscar beneficiario del universo completo', Icons.search),
            onChanged: (v) => setState(() => filtro = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('ar_beneficiarios').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.where((d) {
                final m = d.data();
                final nombre = _texto(m, ['nombre', 'nombre_usuario', 'beneficiario_nombre']).toLowerCase();
                final rut = _texto(m, ['rut', 'rut_usuario', 'rut_normalizado'], d.id).toLowerCase();
                final apoderado = _texto(m, ['nombre_apoderado', 'apoderado_nombre']).toLowerCase();
                if (filtro.isEmpty) return true;
                return nombre.contains(filtro) || rut.contains(filtro) || apoderado.contains(filtro);
              }).toList()
                ..sort((a, b) {
                  final an = _texto(a.data(), ['nombre', 'nombre_usuario', 'beneficiario_nombre']);
                  final bn = _texto(b.data(), ['nombre', 'nombre_usuario', 'beneficiario_nombre']);
                  return an.compareTo(bn);
                });

              if (docs.isEmpty) return const Center(child: Text('No se encontraron beneficiarios.'));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final doc = docs[i];
                  final m = doc.data();
                  final nombre = _texto(m, ['nombre', 'nombre_usuario', 'beneficiario_nombre'], 'Beneficiario sin nombre');
                  final rutCampo = _texto(m, ['rut', 'rut_usuario', 'rut_normalizado']);
                  final rut = rutCampo.trim().isNotEmpty ? rutCampo : doc.id;
                  final apoderado = _texto(m, ['nombre_apoderado', 'apoderado_nombre'], 'Apoderado no informado');
                  final telefono = _texto(m, ['telefono_apoderado', 'telefono'], 'Sin teléfono');
                  final tonos = <List<Color>>[
                    [const Color(0xFFEAF7FF), const Color(0xFFF8FCFF)],
                    [const Color(0xFFFFF4D9), const Color(0xFFFFFBF1)],
                    [const Color(0xFFFFEAF3), const Color(0xFFFFF8FB)],
                    [const Color(0xFFF0EAFF), const Color(0xFFFBF9FF)],
                    [const Color(0xFFE9F8EE), const Color(0xFFF8FDF9)],
                  ];
                  final tono = tonos[i % tonos.length];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: tono),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFD7E6F0)),
                      boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(children: [
                        Positioned(right: 10, bottom: -8, child: Opacity(opacity: .07, child: Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 88, height: 88))),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                          leading: CircleAvatar(backgroundColor: Colors.white.withOpacity(.72), child: const Icon(Icons.child_care, color: Color(0xFF075B98))),
                          title: Text(nombre.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('RUT: $rut\nApoderado: $apoderado\nTeléfono: $telefono'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right, color: Color(0xFF455A64)),
                          onTap: () {
                            final perfil = Map<String, dynamic>.from(m);
                            perfil['beneficiario_id'] = rut;
                            perfil['rut_beneficiario'] = rut;
                            perfil['beneficiario_nombre'] = nombre;
                            Navigator.push(context, MaterialPageRoute(builder: (_) => _PerfilBeneficiarioProfesionalPage(asignacion: perfil)));
                          },
                        ),
                      ]),
                    ),
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


class _RegistrarAtencionTab extends StatefulWidget {
  final String email;
  final String uid;
  final String? initialAsignacionId;
  const _RegistrarAtencionTab({required this.email, required this.uid, this.initialAsignacionId});

  @override
  State<_RegistrarAtencionTab> createState() => _RegistrarAtencionTabState();
}

class _RegistrarAtencionTabState extends State<_RegistrarAtencionTab> {
  String? asignacionId;
  final sugerenciaCtrl = TextEditingController();
  List<String> sugerencias = [];

  @override
  void initState() {
    super.initState();
    asignacionId = widget.initialAsignacionId;
  }
  String filtroAsignacion = '';
  String asistencia = 'asistio';
  final objetivosCtrl = TextEditingController();
  final observacionesCtrl = TextEditingController();
  final recomendacionesCtrl = TextEditingController();
  bool guardando = false;
  bool enviarTrabajoCasa = true;
  final List<XFile> evidenciaArchivos = [];
  final List<String> evidenciaTipos = [];

  @override
  void dispose() {
    objetivosCtrl.dispose();
    observacionesCtrl.dispose();
    recomendacionesCtrl.dispose();
    sugerenciaCtrl.dispose();
    super.dispose();
  }

  List<String> _generarIdeasCasa(String texto) {
    final t = texto.toLowerCase();
    final set = <String>{};
    void add(String v) => set.add(v.trim());
    if (t.contains('espera') || t.contains('turno')) add('Practicar juegos breves de turnos y tiempos de espera en casa.');
    if (t.contains('frustr')) add('Anticipar cambios, validar la emoción y practicar pedir ayuda cuando aparezca frustración.');
    if (t.contains('motricidad fina') || t.contains('pinza') || t.contains('trazo')) add('Realizar actividades cortas de pinza, coloreado, recorte o modelado con materiales del hogar.');
    if (t.contains('lenguaje') || t.contains('palabra') || t.contains('comunicación')) add('Practicar lenguaje durante rutinas cotidianas, dando tiempo para responder y reforzando los intentos de comunicación.');
    if (t.contains('rutina') || t.contains('hábito') || t.contains('habito')) add('Usar una rutina visual simple y repetirla a la misma hora durante la semana.');
    if (t.contains('emocion') || t.contains('autorreg')) add('Nombrar emociones y practicar una estrategia breve de calma en situaciones cotidianas.');
    if (set.isEmpty && texto.trim().isNotEmpty) add('Repetir en casa una actividad breve relacionada con lo trabajado en sesión, respetando pausas y reforzando los avances.');
    return set.take(6).toList();
  }

  void _actualizarIdeasCasa() {
    if (!mounted) return;
    setState(() => sugerencias = _generarIdeasCasa('${objetivosCtrl.text} ${recomendacionesCtrl.text}'));
  }

  void _agregarIdeaManual() {
    final v = sugerenciaCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() { if (!sugerencias.contains(v)) sugerencias.add(v); sugerenciaCtrl.clear(); });
  }

  Future<void> seleccionarFotoEvidencia() async {
    if (evidenciaTipos.where((t) => t == 'foto').length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 5 fotos por atención.')));
      return;
    }
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img == null) return;
    setState(() {
      evidenciaArchivos.add(img);
      evidenciaTipos.add('foto');
    });
  }

  Future<void> seleccionarVideoEvidencia() async {
    if (evidenciaTipos.where((t) => t == 'video').length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 3 videos por atención.')));
      return;
    }
    final picker = ImagePicker();
    final vid = await picker.pickVideo(source: ImageSource.gallery);
    if (vid == null) return;
    setState(() {
      evidenciaArchivos.add(vid);
      evidenciaTipos.add('video');
    });
  }

  Future<void> guardar() async {
    if (asignacionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona una asignación.')));
      return;
    }
    setState(() => guardando = true);
    try {
      final asig = await FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').doc(asignacionId).get();
      final m = asig.data() ?? {};
      final estadoAsignacion=(m['estado']??'activa').toString().toLowerCase();
      if(estadoAsignacion=='suspendida_tesoreria'){
        if(mounted){
          setState(() => guardando = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Esta atención está suspendida por Tesorería y no puede registrarse.')));
        }
        return;
      }
      final evidencias = <Map<String, dynamic>>[];
      for (var i = 0; i < evidenciaArchivos.length; i++) {
        final archivo = evidenciaArchivos[i];
        final tipo = evidenciaTipos[i];
        final esVideo = tipo == 'video';
        final extension = esVideo ? 'mp4' : 'jpg';
        final contentType = esVideo ? 'video/mp4' : 'image/jpeg';
        final path = 'evidencias/atenciones_profesionales/${widget.uid}-${asignacionId}-${DateTime.now().millisecondsSinceEpoch}-$i.$extension';
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putData(await archivo.readAsBytes(), SettableMetadata(contentType: contentType));
        final url = await ref.getDownloadURL();
        evidencias.add({
          'url': url,
          'path': path,
          'tipo': tipo,
          'content_type': contentType,
          'nombre': archivo.name,
        });
      }
      final primera = evidencias.isNotEmpty ? evidencias.first : <String, dynamic>{};

      final objetivosTexto = objetivosCtrl.text.trim();
      final observacionesTexto = observacionesCtrl.text.trim();
      final recomendacionesTexto = recomendacionesCtrl.text.trim();

      final atencionRef = await FirebaseFirestore.instance.collection('atenciones_profesionales').add({
        'asignacion_id': asignacionId,
        'profesional_uid': widget.uid,
        'profesional_email': _normalizarEmail(widget.email),
        'profesional_id': m['profesional_id'] ?? '',
        'profesional_nombre': m['profesional_nombre'] ?? '',
        'beneficiario_id': m['beneficiario_id'] ?? '',
        'beneficiario_nombre': m['beneficiario_nombre'] ?? '',
        'rut_beneficiario': m['rut_beneficiario'] ?? '',
        'apoderado_uid': m['apoderado_uid'] ?? m['uid_apoderado'] ?? '',
        'apoderados_uids_autorizados': (m['apoderados_uids_autorizados'] is List) ? m['apoderados_uids_autorizados'] : [m['apoderado_uid'] ?? m['uid_apoderado'] ?? ''],
        'email_apoderado': m['email_apoderado'] ?? '',
        'nombre_apoderado': m['nombre_apoderado'] ?? m['apoderado_nombre'] ?? '',
        'terapia': m['servicio_nombre'] ?? m['terapia'] ?? '',
        'motivo_cambio_usuario': m['motivo_cambio_usuario'] ?? '',
        'tipo_cambio_usuario': m['tipo_cambio_usuario'] ?? '',
        'cambio_manual_usuario': m['cambio_manual_usuario'] ?? false,
        'asistencia': asistencia,
        'objetivos_trabajados': objetivosTexto,
        'observaciones': observacionesTexto,
        'recomendaciones_casa': recomendacionesTexto,
        'evidencias': evidencias,
        'evidencia_url': primera['url'] ?? '',
        'evidencia_path': primera['path'] ?? '',
        'evidencia_tipo': primera['tipo'] ?? '',
        'evidencia_content_type': primera['content_type'] ?? '',
        'evidencia_vence_el': Timestamp.fromDate(DateTime.now().add(const Duration(days: 8))),
        'visible_apoderado': true,
        'fecha': FieldValue.serverTimestamp(),
      });

      // Si el profesional lo decide, la misma bitácora genera el trabajo para casa
      // usando la arquitectura existente de ar_bitacora_casa / plan_trabajo_casa.
      if (enviarTrabajoCasa && recomendacionesTexto.isNotEmpty) {
        final now = DateTime.now();
        final fin = now.add(const Duration(days: 7));
        final emailApoderado = _normalizarEmail(_texto(m, ['email_apoderado_normalizado', 'email_apoderado']));
        final apoderadoUid = _normalizarUid(_texto(m, ['apoderado_uid', 'uid_apoderado']));
        await FirebaseFirestore.instance.collection('ar_bitacora_casa').add({
          'tipo_doc': 'plan_trabajo_casa',
          'origen': 'bitacora_atencion',
          'atencion_id': atencionRef.id,
          'asignacion_id': asignacionId,
          'objetivo': objetivosTexto.isEmpty ? 'Trabajo posterior a la sesión' : objetivosTexto,
          'indicaciones': recomendacionesTexto,
          'sugerencias_aprobadas': sugerencias,
          'estado': 'activo',
          'activa': true,
          'duracion_dias': 7,
          'fecha_inicio': Timestamp.fromDate(now),
          'fecha_fin': Timestamp.fromDate(fin),
          'fecha_creacion': FieldValue.serverTimestamp(),
          'profesional_uid': widget.uid,
          'profesional_email': _normalizarEmail(widget.email),
          'profesional_nombre': m['profesional_nombre'] ?? '',
          'beneficiario_id': m['beneficiario_id'] ?? '',
          'beneficiario_nombre': m['beneficiario_nombre'] ?? m['nombre_beneficiario'] ?? '',
          'rut_beneficiario': m['rut_beneficiario'] ?? '',
          'apoderado_uid': apoderadoUid,
          'apoderados_uids_autorizados': (m['apoderados_uids_autorizados'] is List) ? m['apoderados_uids_autorizados'] : [apoderadoUid],
          'email_apoderado': emailApoderado,
          'email_apoderado_normalizado': emailApoderado,
          'nombre_apoderado': m['nombre_apoderado'] ?? m['apoderado_nombre'] ?? '',
          'telefono_apoderado': m['telefono_apoderado'] ?? m['telefono'] ?? '',
          'terapia': m['servicio_nombre'] ?? m['terapia'] ?? '',
          'requiere_bitacora': true,
          'material_url': '',
          'material_path': '',
          'material_tipo': '',
          'material_content_type': '',
          'material_vence_el': Timestamp.fromDate(now.add(const Duration(days: 5))),
          'sin_material_privado': true,
        });
      }
      objetivosCtrl.clear();
      observacionesCtrl.clear();
      recomendacionesCtrl.clear();
      setState(() { evidenciaArchivos.clear(); evidenciaTipos.clear(); sugerencias.clear(); sugerenciaCtrl.clear(); });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enviarTrabajoCasa && recomendacionesTexto.isNotEmpty ? 'Atención registrada y trabajo para casa enviado.' : 'Atención registrada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al registrar atención: $e')));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          decoration: _deco('Buscar beneficiario / horario', Icons.search),
          onChanged: (v) => setState(() => filtroAsignacion = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: _misAsignaciones(widget.uid),
          builder: (context, snap) {
            final todos = snap.data?.docs ?? [];
            final filtro = filtroAsignacion;
            final docs = todos.where((d) {
              if (d.id == asignacionId) return true;
              final m = d.data() as Map<String, dynamic>;
              final estado=(m['estado']??'activa').toString().toLowerCase();
              if(estado=='eliminada'||estado=='inactiva'||estado=='suspendida_tesoreria') return false;
              final texto = [
                _texto(m, ['beneficiario_nombre', 'nombre_beneficiario']),
                _texto(m, ['servicio_nombre', 'terapia']),
                (m['dia'] ?? '').toString(),
                (m['hora'] ?? '').toString(),
              ].join(' ').toLowerCase();
              return filtro.isEmpty || texto.contains(filtro);
            }).toList();
            return DropdownButtonFormField<String>(
              isExpanded: true,
              value: asignacionId,
              decoration: _deco('Beneficiario / horario', Icons.event),
              items: docs.map((d) {
                final m = d.data() as Map<String, dynamic>;
                final nombre = _texto(m, ['beneficiario_nombre', 'nombre_beneficiario'], 'Beneficiario');
                final terapia = _texto(m, ['servicio_nombre', 'terapia'], 'Terapia');
                final motivo = _motivoCambioLabel(m);
                final sufijo = motivo.isNotEmpty ? ' · $motivo' : '';
                return DropdownMenuItem(value: d.id, child: Text('$nombre - $terapia - ${m['dia'] ?? ''} ${m['hora'] ?? ''}$sufijo', maxLines: 1, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (v) => setState(() => asignacionId = v),
            );
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: asistencia,
          decoration: _deco('Asistencia', Icons.fact_check),
          items: const [
            DropdownMenuItem(value: 'asistio', child: Text('Asistió')),
            DropdownMenuItem(value: 'no_asistio_justificado', child: Text('No asistió justificado')),
            DropdownMenuItem(value: 'no_asistio_injustificado', child: Text('No asistió injustificado')),
            DropdownMenuItem(value: 'reagendado', child: Text('Reagendado')),
            DropdownMenuItem(value: 'otros', child: Text('Otros')),
          ],
          onChanged: (v) => setState(() => asistencia = v ?? 'asistio'),
        ),
        const SizedBox(height: 10),
        _CampoTextoDictado(controller: objetivosCtrl, maxLines: 3, label: 'Objetivos trabajados', icon: Icons.flag, onChanged: (_) => _actualizarIdeasCasa()),
        const SizedBox(height: 10),
        _CampoTextoDictado(controller: observacionesCtrl, maxLines: 3, label: 'Observaciones', icon: Icons.note_alt),
        const SizedBox(height: 10),
        _CampoTextoDictado(controller: recomendacionesCtrl, maxLines: 3, label: 'Recomendaciones para casa', icon: Icons.home_work, onChanged: (_) => _actualizarIdeasCasa()),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFF1F9FF), Color(0xFFFFF8E7)]), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFB7D8FF))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ideas para apoyar el trabajo en casa', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            const Text('Se preparan a partir de lo trabajado y las recomendaciones. Puedes quitar, editar o agregar antes de enviar.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            if (sugerencias.isEmpty) const Text('Escribe o dicta objetivos y recomendaciones para recibir ideas de apoyo.'),
            ...sugerencias.map(
              (idea) => Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(idea),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => sugerencias.remove(idea)),
                  ),
                ),
              ),
            ),
            Row(children: [Expanded(child: _CampoTextoDictado(controller: sugerenciaCtrl, label: 'Agregar sugerencia propia', icon: Icons.add_comment)), IconButton(onPressed: _agregarIdeaManual, icon: const Icon(Icons.add_circle))]),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFFEAF7F0), borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enviarTrabajoCasa,
            onChanged: guardando ? null : (v) => setState(() => enviarTrabajoCasa = v),
            secondary: const Icon(Icons.home_work_rounded, color: Color(0xFF16865B)),
            title: const Text('Enviar también como trabajo para casa', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Se enviará al apoderado por 7 días usando el mismo seguimiento del Plan semanal.'),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF7DF), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 56, height: 60, fit: BoxFit.contain),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tu ayudante', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
              SizedBox(height: 2),
              Text('Este espacio quedará preparado para ayudarte a ordenar observaciones, objetivos e indicaciones. La conexión inteligente se habilitará más adelante.', style: TextStyle(fontSize: 12.5, color: Color(0xFF66757F))),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFB7D8FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Evidencia de la sesión', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                'Adjunta hasta 5 fotos y hasta 3 videos como respaldo de la atención realizada. Los videos profesionales no tienen límite de duración y se eliminan a los 8 días.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: guardando || evidenciaTipos.where((t) => t == 'foto').length >= 5 ? null : seleccionarFotoEvidencia,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text("Adjuntar foto (${evidenciaTipos.where((t) => t == 'foto').length}/5)"),
                  ),
                  OutlinedButton.icon(
                    onPressed: guardando || evidenciaTipos.where((t) => t == 'video').length >= 3 ? null : seleccionarVideoEvidencia,
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text("Adjuntar video (${evidenciaTipos.where((t) => t == 'video').length}/3)"),
                  ),
                  if (evidenciaArchivos.isNotEmpty)
                    TextButton.icon(
                      onPressed: guardando ? null : () => setState(() { evidenciaArchivos.clear(); evidenciaTipos.clear(); }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Quitar todos'),
                    ),
                ],
              ),
              if (evidenciaArchivos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(evidenciaArchivos.length, (i) => Text(
                      '${i + 1}. ${evidenciaTipos[i] == 'video' ? 'Video' : 'Foto'}: ${evidenciaArchivos[i].name}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(onPressed: guardando ? null : guardar, icon: const Icon(Icons.save), label: Text(guardando ? 'Guardando...' : 'Guardar registro')),
      ],
    );
  }
}


class _TareasTerapeuticasTab extends StatefulWidget {
  final String email;
  final String uid;
  const _TareasTerapeuticasTab({required this.email, required this.uid});

  @override
  State<_TareasTerapeuticasTab> createState() => _TareasTerapeuticasTabState();
}

class _TareasTerapeuticasTabState extends State<_TareasTerapeuticasTab> {
  String? asignacionId;
  String filtroAsignacion = '';
  final objetivoCtrl = TextEditingController();
  final indicacionesCtrl = TextEditingController();
  final sugerenciaCtrl = TextEditingController();
  bool guardando = false;
  List<String> sugerencias = [];

  @override
  void dispose() {
    objetivoCtrl.dispose();
    indicacionesCtrl.dispose();
    sugerenciaCtrl.dispose();
    super.dispose();
  }

  DateTime get _fechaFin => DateTime.now().add(const Duration(days: 7));

  List<String> _generarSugerencias(String texto) {
    final t = texto.toLowerCase();
    final set = <String>{};
    void add(String v) => set.add(v.trim());

    if (t.contains('espera') || t.contains('turno') || t.contains('turnos')) {
      add('Buscar en YouTube: juegos de turnos para niños en casa');
      add('Buscar en Google: actividades para trabajar tiempos de espera con niños');
      add('Buscar en Google: juegos simples para tolerancia a la espera');
    }
    if (t.contains('frustr')) {
      add('Buscar en YouTube: actividades para tolerancia a la frustración infantil');
      add('Buscar en Google: estrategias para manejar frustración en casa');
    }
    if (t.contains('auditiv') || t.contains('ruido') || t.contains('sonido')) {
      add('Buscar en YouTube: sensibilidad auditiva actividades en casa');
      add('Buscar en Google: estrategias para sensibilidad auditiva en niños');
    }
    if (t.contains('motricidad fina') || t.contains('pinza') || t.contains('pinzas') || t.contains('trazo')) {
      add('Buscar en YouTube: motricidad fina con materiales del hogar');
      add('Buscar en Google: actividades de motricidad fina para hacer en casa');
    }
    if (t.contains('lenguaje') || t.contains('palabra') || t.contains('comunicación')) {
      add('Buscar en YouTube: actividades de lenguaje para niños en casa');
      add('Buscar en Google: juegos para estimular lenguaje infantil en casa');
    }
    if (t.contains('rutina') || t.contains('hábitos') || t.contains('habitos')) {
      add('Buscar en Google: rutinas visuales para niños en casa');
      add('Buscar en YouTube: cómo trabajar rutinas con niños en casa');
    }
    if (t.contains('emocion') || t.contains('emociones') || t.contains('autorregulación') || t.contains('autorregulacion')) {
      add('Buscar en YouTube: actividades para reconocer emociones en niños');
      add('Buscar en Google: estrategias de autorregulación para niños en casa');
    }

    if (set.isEmpty && texto.trim().isNotEmpty) {
      final base = texto.trim().split(RegExp(r'\s+')).take(8).join(' ');
      add('Buscar en YouTube: $base para niños en casa');
      add('Buscar en Google: actividades de $base en casa');
    }
    return set.take(6).toList();
  }

  void _actualizarSugerencias() {
    final texto = '${objetivoCtrl.text} ${indicacionesCtrl.text}';
    setState(() => sugerencias = _generarSugerencias(texto));
  }

  void _agregarSugerenciaManual() {
    final v = sugerenciaCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      if (!sugerencias.contains(v)) sugerencias.add(v);
      sugerenciaCtrl.clear();
    });
  }

  Future<void> guardarPlan() async {
    if (asignacionId == null || objetivoCtrl.text.trim().isEmpty || indicacionesCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona beneficiario, objetivo e indicaciones.')),
      );
      return;
    }
    setState(() => guardando = true);
    try {
      final asig = await FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').doc(asignacionId).get();
      final m = asig.data() ?? {};
      final emailApoderado = _normalizarEmail(_texto(m, ['email_apoderado_normalizado', 'email_apoderado']));
      final apoderadoUid = _normalizarUid(_texto(m, ['apoderado_uid', 'uid_apoderado']));
      final now = DateTime.now();
      final fin = now.add(const Duration(days: 7));
      const materialUrl = '';
      const materialPath = '';
      const materialContentType = '';
      const materialTipo = '';

      // Se guarda en ar_bitacora_casa como documento tipo plan_trabajo_casa.
      // Esta colección ya permite crear/actualizar a usuarios logueados en las reglas actuales,
      // evitando el bloqueo de permisos que estaba ocurriendo con ar_trabajo_casa.
      await FirebaseFirestore.instance.collection('ar_bitacora_casa').add({
        'tipo_doc': 'plan_trabajo_casa',
        'asignacion_id': asignacionId,
        'objetivo': objetivoCtrl.text.trim(),
        'indicaciones': indicacionesCtrl.text.trim(),
        'sugerencias_aprobadas': sugerencias,
        'estado': 'activo',
        'activa': true,
        'duracion_dias': 7,
        'fecha_inicio': Timestamp.fromDate(now),
        'fecha_fin': Timestamp.fromDate(fin),
        'fecha_creacion': FieldValue.serverTimestamp(),
        'profesional_uid': widget.uid,
        'profesional_email': _normalizarEmail(widget.email),
        'profesional_nombre': m['profesional_nombre'] ?? '',
        'beneficiario_id': m['beneficiario_id'] ?? '',
        'beneficiario_nombre': m['beneficiario_nombre'] ?? m['nombre_beneficiario'] ?? '',
        'rut_beneficiario': m['rut_beneficiario'] ?? '',
        'apoderado_uid': apoderadoUid,
        'apoderados_uids_autorizados': (m['apoderados_uids_autorizados'] is List) ? m['apoderados_uids_autorizados'] : [apoderadoUid],
        'email_apoderado': emailApoderado,
        'email_apoderado_normalizado': emailApoderado,
        'nombre_apoderado': m['nombre_apoderado'] ?? m['apoderado_nombre'] ?? '',
        'telefono_apoderado': m['telefono_apoderado'] ?? m['telefono'] ?? '',
        'terapia': m['servicio_nombre'] ?? m['terapia'] ?? '',
        'requiere_bitacora': true,
        'material_url': materialUrl,
        'material_path': materialPath,
        'material_tipo': materialTipo,
        'material_content_type': materialContentType,
        'material_vence_el': Timestamp.fromDate(now.add(const Duration(days: 5))),
        'sin_material_privado': true,
      });

      objetivoCtrl.clear();
      indicacionesCtrl.clear();
      sugerenciaCtrl.clear();
      setState(() {
        asignacionId = null;
        sugerencias = [];
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan semanal enviado al apoderado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al crear plan: $e')));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE5F6FF), Color(0xFFFFF3D7)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 68, height: 74, fit: BoxFit.contain),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tu ayudante', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
              SizedBox(height: 3),
              Text('Te acompaño a preparar indicaciones claras para el hogar. Tú siempre revisas y decides qué enviar.', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF526D7D))),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: _deco('Buscar beneficiario', Icons.search),
          onChanged: (v) => setState(() => filtroAsignacion = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: _misAsignaciones(widget.uid),
          builder: (context, snap) {
            final todos = snap.data?.docs ?? [];
            final filtro = filtroAsignacion;
            final docs = todos.where((d) {
              if (d.id == asignacionId) return true;
              final m = d.data() as Map<String, dynamic>;
              final estado=(m['estado']??'activa').toString().toLowerCase();
              if(estado=='eliminada'||estado=='inactiva'||estado=='suspendida_tesoreria') return false;
              final texto = [
                _texto(m, ['beneficiario_nombre', 'nombre_beneficiario']),
                _texto(m, ['servicio_nombre', 'terapia']),
                (m['dia'] ?? '').toString(),
                (m['hora'] ?? '').toString(),
              ].join(' ').toLowerCase();
              return filtro.isEmpty || texto.contains(filtro);
            }).toList();
            return DropdownButtonFormField<String>(
              isExpanded: true,
              value: asignacionId,
              decoration: _deco('Beneficiario', Icons.child_care),
              items: docs.map((d) {
                final m = d.data() as Map<String, dynamic>;
                final nombre = _texto(m, ['beneficiario_nombre', 'nombre_beneficiario'], 'Beneficiario');
                final terapia = _texto(m, ['servicio_nombre', 'terapia'], 'Terapia');
                return DropdownMenuItem(value: d.id, child: Text('$nombre - $terapia', maxLines: 1, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (v) => setState(() => asignacionId = v),
            );
          },
        ),
        const SizedBox(height: 10),
        _CampoTextoDictado(
          controller: objetivoCtrl,
          label: 'Objetivo de la semana',
          icon: Icons.flag,
          onChanged: (_) => _actualizarSugerencias(),
        ),
        const SizedBox(height: 10),
        _CampoTextoDictado(
          controller: indicacionesCtrl,
          maxLines: 5,
          label: 'Indicaciones para casa',
          icon: Icons.mic,
          onChanged: (_) => _actualizarSugerencias(),
        ),
        const SizedBox(height: 10),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFF1F9FF), Color(0xFFFFF8E7)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFB7D8FF)),
            boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 7, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ideas para apoyar el trabajo en casa', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('El ayudante propone ideas a partir del objetivo y las indicaciones. Puedes quitar, editar o agregar antes de enviar.', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              if (sugerencias.isEmpty)
                const Text('Escribe o dicta el objetivo y las indicaciones para recibir ideas de apoyo.'),
              ...sugerencias.map((s) => Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(s),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => sugerencias.remove(s)),
                      ),
                    ),
                  )),
              Row(
                children: [
                  Expanded(child: _CampoTextoDictado(controller: sugerenciaCtrl, label: 'Agregar sugerencia propia', icon: Icons.add_comment)),
                  IconButton(onPressed: _agregarSugerenciaManual, icon: const Icon(Icons.add_circle)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('Duración automática: 7 días. Vence: ${_fecha(Timestamp.fromDate(_fechaFin))}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        ElevatedButton.icon(onPressed: guardando ? null : guardarPlan, icon: const Icon(Icons.send), label: Text(guardando ? 'Enviando...' : 'Enviar plan semanal')),
        const SizedBox(height: 24),
        const Text('Planes enviados recientemente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('ar_bitacora_casa').where('profesional_uid', isEqualTo: widget.uid).snapshots(),
          builder: (context, snap) {
            final docs = (snap.data?.docs ?? []).where((d) {
              final m = d.data() as Map<String, dynamic>;
              return m['tipo_doc'] == 'plan_trabajo_casa';
            }).toList();
            docs.sort((a, b) {
              final da = (a.data() as Map<String, dynamic>)['fecha_creacion'];
              final db = (b.data() as Map<String, dynamic>)['fecha_creacion'];
              if (da is Timestamp && db is Timestamp) return db.compareTo(da);
              return 0;
            });
            if (docs.isEmpty) return const Text('Aún no hay planes creados.');
            return Column(
              children: docs.take(10).map((d) {
                final m = d.data() as Map<String, dynamic>;
                final sugerenciasPlan = (m['sugerencias_aprobadas'] is List)
                    ? List<String>.from((m['sugerencias_aprobadas'] as List).map((e) => e.toString()))
                    : <String>[];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF4FAFF), Color(0xFFFFF8E7)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFCFE5F5)),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        Positioned(
                          right: 12,
                          bottom: 8,
                          child: Opacity(
                            opacity: 0.09,
                            child: Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 82, height: 82, fit: BoxFit.contain),
                          ),
                        ),
                        ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: const Color(0xFFE2F2FF), borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.home_work_rounded, color: Color(0xFF0877C9)),
                          ),
                          title: Text(_texto(m, ['objetivo'], 'Plan semanal'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('${_texto(m, ['beneficiario_nombre'], 'Beneficiario')} · vence ${_fecha(m['fecha_fin'])}'),
                          ),
                          children: [
                            const Divider(),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Objetivo de la semana', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
                                  const SizedBox(height: 4),
                                  Text(_texto(m, ['objetivo'], 'Plan semanal')),
                                  const SizedBox(height: 12),
                                  const Text('Indicaciones para casa', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
                                  const SizedBox(height: 4),
                                  Text(_texto(m, ['indicaciones'], 'Sin indicaciones registradas.')),
                                  if (sugerenciasPlan.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    const Text('Ideas enviadas al apoderado', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
                                    const SizedBox(height: 5),
                                    ...sugerenciasPlan.map((s) => Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check_circle_rounded, size: 17, color: Color(0xFF2EAD68))),
                                          const SizedBox(width: 7),
                                          Expanded(child: Text(s)),
                                        ],
                                      ),
                                    )),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text('Enviado: ${_fecha(m['fecha_creacion'])}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
                                      Text('Vence: ${_fecha(m['fecha_fin'])}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
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

class _SeguimientoTrabajoCasaTab extends StatelessWidget {
  final String email;
  final String uid;
  const _SeguimientoTrabajoCasaTab({required this.email, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('ar_bitacora_casa').where('profesional_uid', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final docs = (snap.data?.docs ?? []).where((d) {
          final m = d.data() as Map<String, dynamic>;
          return m['tipo_doc'] == 'plan_trabajo_casa';
        }).toList();
        docs.sort((a, b) {
          final da = (a.data() as Map<String, dynamic>)['fecha_creacion'];
          final db = (b.data() as Map<String, dynamic>)['fecha_creacion'];
          if (da is Timestamp && db is Timestamp) return db.compareTo(da);
          return 0;
        });
        if (docs.isEmpty) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aún no hay planes semanales enviados.', textAlign: TextAlign.center),
          ));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final m = doc.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ExpansionTile(
                leading: const Icon(Icons.fact_check, color: Color(0xFF0066CC)),
                title: Text(_texto(m, ['objetivo'], 'Plan semanal'), style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${_texto(m, ['beneficiario_nombre'], 'Beneficiario')} · vence ${_fecha(m['fecha_fin'])}'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Indicaciones: ${_texto(m, ['indicaciones'])}'),
                        if (_texto(m, ['material_url']).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _abrirArchivoProfesional(context, _texto(m, ['material_url']), _texto(m, ['material_tipo'])),
                            icon: Icon(_texto(m, ['material_tipo']) == 'video' ? Icons.play_circle_outline : Icons.photo_library_outlined),
                            label: Text(_texto(m, ['material_tipo']) == 'video' ? 'Ver video enviado' : 'Ver foto enviada'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('ar_bitacora_casa').where('trabajo_id', isEqualTo: doc.id).snapshots(),
                          builder: (context, bitSnap) {
                            final bits = (bitSnap.data?.docs ?? []).toList();
                            bits.sort((a, b) {
                              final da = (a.data() as Map<String, dynamic>)['fecha'];
                              final db = (b.data() as Map<String, dynamic>)['fecha'];
                              if (da is Timestamp && db is Timestamp) return db.compareTo(da);
                              return 0;
                            });
                            if (bits.isEmpty) return const Text('El apoderado aún no registra bitácora.');
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: bits.map((b) {
                                final bm = b.data() as Map<String, dynamic>;
                                final fotoUrl = _texto(bm, ['evidencia_url', 'foto_url', 'imagen_url', 'url_foto']);
                                final evidenciaTipo = _texto(bm, ['evidencia_tipo']);
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(bm['realizado'] == true ? Icons.check_circle : Icons.cancel, color: bm['realizado'] == true ? Colors.green : Colors.red),
                                  title: Text('${_fecha(bm['fecha'])} · ${bm['tiempo_minutos'] ?? 0} min'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${_texto(bm, ['estado_emocional'], 'Sin estado')}\n${_texto(bm, ['observacion'])}'),
                                      if (fotoUrl.trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        OutlinedButton.icon(
                                          onPressed: () => _abrirArchivoProfesional(context, fotoUrl, evidenciaTipo),
                                          icon: Icon(evidenciaTipo == 'video' ? Icons.play_circle_outline : Icons.photo_library_outlined),
                                          label: Text(evidenciaTipo == 'video' ? 'Ver video' : 'Ver foto'),
                                        ),
                                      ],
                                    ],
                                  ),
                                  isThreeLine: true,
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
