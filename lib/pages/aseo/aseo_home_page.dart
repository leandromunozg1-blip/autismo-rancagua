import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AseoHomePage extends StatefulWidget {
  const AseoHomePage({super.key});
  @override
  State<AseoHomePage> createState() => _AseoHomePageState();
}

class _AseoHomePageState extends State<AseoHomePage> {
  final _db = FirebaseFirestore.instance;
  final _speech = stt.SpeechToText();
  final _indicaciones = TextEditingController();
  final _solicitudMensaje = TextEditingController();
  final _solicitudUtiles = TextEditingController();
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _fecha = DateTime.now();
  bool _escuchando = false;
  String _dictado = '';
  final Map<String, Map<String, dynamic>> _seleccionados = {};

  String _diaId(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _mesId(DateTime d) => DateFormat('yyyy-MM').format(d);
  String _fechaBonita(DateTime d) => DateFormat("EEEE d 'de' MMMM", 'es').format(d);
  String _normal(String s) => s.toLowerCase().replaceAll(RegExp(r'[áàä]'), 'a').replaceAll(RegExp(r'[éèë]'), 'e').replaceAll(RegExp(r'[íìï]'), 'i').replaceAll(RegExp(r'[óòö]'), 'o').replaceAll(RegExp(r'[úùü]'), 'u').replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  String _nombre(Map<String,dynamic> d) => (d['nombre_apoderado'] ?? d['nombre'] ?? d['nombre_completo'] ?? 'Sin nombre').toString();
  String _rut(Map<String,dynamic> d) => (d['rut_apoderado'] ?? d['rut'] ?? d['rut_normalizado'] ?? 'RUT no informado').toString();

  @override
  void dispose(){ _indicaciones.dispose(); _solicitudMensaje.dispose(); _solicitudUtiles.dispose(); _speech.stop(); super.dispose(); }

  Future<void> _dictarAsignacion() async {
    if (_escuchando) { await _speech.stop(); setState(() => _escuchando=false); return; }
    final ok = await _speech.initialize();
    if (!ok) { _msg('No se pudo activar el reconocimiento de voz. Puedes asignar manualmente.'); return; }
    setState(() { _escuchando=true; _dictado=''; });
    await _speech.listen(localeId: 'es_CL', listenMode: stt.ListenMode.dictation, onResult: (r){
      if(!mounted) return;
      setState(() => _dictado=r.recognizedWords);
      if(r.finalResult){ setState(()=>_escuchando=false); _interpretarDictado(r.recognizedWords); }
    });
  }

  bool _esApoderado(Map<String,dynamic> x) {
    final rol=(x['rol']??x['role']??'').toString().toLowerCase();
    return rol.contains('apoderado') || rol=='padre' || rol=='madre';
  }

  Future<List<Map<String,dynamic>>> _cargarApoderados() async {
    // Aseo se construye desde los beneficiarios: allí está definido de forma
    // explícita el APODERADO PRINCIPAL. Los apoyos_autorizados nunca se leen.
    String limpioRut(dynamic v) => (v ?? '').toString().toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
    String limpioEmail(dynamic v) => (v ?? '').toString().toLowerCase().trim();

    final resultados = <String, Map<String, dynamic>>{};
    final beneficiarios = await _db.collection('ar_beneficiarios').get();

    // Mapa opcional de perfiles para recuperar UID sin hacer consultas dentro
    // del bucle. Si por reglas no puede leerse usuarios, la asignación sigue
    // funcionando por RUT/correo.
    final usuariosPorRut = <String, Map<String, dynamic>>{};
    final usuariosPorEmail = <String, Map<String, dynamic>>{};
    try {
      final usuarios = await _db.collection('usuarios').get();
      for (final ud in usuarios.docs) {
        final u = ud.data();
        final rut = limpioRut(u['rut'] ?? u['rut_apoderado'] ?? u['rut_normalizado']);
        final email = limpioEmail(u['email'] ?? u['correo']);
        final perfil = <String, dynamic>{...u, '_doc_uid': ud.id};
        if (rut.isNotEmpty) usuariosPorRut[rut] = perfil;
        if (email.isNotEmpty) usuariosPorEmail[email] = perfil;
      }
    } catch (_) {}

    for (final bd in beneficiarios.docs) {
      final b = bd.data();
      if ((b['estado'] ?? 'activo').toString().toLowerCase() == 'inactivo') continue;
      final ap = b['apoderado_principal'] is Map
          ? Map<String, dynamic>.from(b['apoderado_principal'] as Map)
          : <String, dynamic>{};
      final rut = limpioRut(ap['rut'] ?? b['rut_apoderado']);
      final email = limpioEmail(ap['email'] ?? b['email_apoderado']);
      final nombre = (ap['nombre'] ?? b['nombre_apoderado'] ?? '').toString().trim();
      if (rut.isEmpty && email.isEmpty) continue;

      final perfil = (rut.isNotEmpty ? usuariosPorRut[rut] : null) ??
          (email.isNotEmpty ? usuariosPorEmail[email] : null);
      final uid = (b['apoderado_uid'] ?? perfil?['uid'] ?? perfil?['auth_uid'] ?? perfil?['_doc_uid'] ?? '').toString().trim();
      final key = rut.isNotEmpty ? 'rut:$rut' : 'email:$email';
      final beneficiario = (b['nombre'] ?? b['nombre_beneficiario'] ?? '').toString().trim();

      if (resultados.containsKey(key)) {
        final anterior = resultados[key]!;
        final nombres = <String>{
          ...(anterior['beneficiarios'] is List ? List<String>.from(anterior['beneficiarios']) : <String>[]),
          if (beneficiario.isNotEmpty) beneficiario,
        }.toList();
        anterior['beneficiarios'] = nombres;
        anterior['beneficiario_nombre'] = nombres.join(', ');
        if ((anterior['uid'] ?? '').toString().isEmpty && uid.isNotEmpty) anterior['uid'] = uid;
        continue;
      }

      resultados[key] = {
        '_id': key,
        'uid': uid,
        'nombre_apoderado': nombre.isEmpty ? 'Apoderado principal' : nombre,
        'rut_apoderado': rut,
        'email': email,
        'beneficiarios': [if (beneficiario.isNotEmpty) beneficiario],
        'beneficiario_nombre': beneficiario,
        'es_apoderado_principal': true,
      };
    }

    final lista = resultados.values.toList();
    lista.sort((a, b) => _nombre(a).compareTo(_nombre(b)));
    return lista;
  }

  Future<void> _interpretarDictado(String texto) async {
    final t=_normal(texto);
    const meses={'enero':1,'febrero':2,'marzo':3,'abril':4,'mayo':5,'junio':6,'julio':7,'agosto':8,'septiembre':9,'octubre':10,'noviembre':11,'diciembre':12};
    final m=RegExp(r'\b([0-3]?\d)\s+de\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)(?:\s+de\s+(20\d\d))?').firstMatch(t);
    if(m!=null){
      final dia=int.tryParse(m.group(1)!)??_fecha.day; final mm=meses[m.group(2)!]??_fecha.month; final anio=int.tryParse(m.group(3)??'')??DateTime.now().year;
      final f=DateTime(anio,mm,dia); if(f.year==anio&&f.month==mm&&f.day==dia) _fecha=f;
    }
    final candidatos=await _cargarApoderados();
    final encontrados=<String,Map<String,dynamic>>{};
    for(final data in candidatos){
      final n=_normal(_nombre(data)); final partes=n.split(' ').where((x)=>x.length>=3).toList();
      final coincidencias=partes.where((x)=>t.contains(x)).length;
      if((partes.length==1&&coincidencias==1)||(partes.length>=2&&coincidencias>=2)){
        final key=(data['uid']??data['_id']??_rut(data)).toString(); encontrados[key]=data;
      }
    }
    if(mounted) setState(() { _seleccionados.addAll(encontrados); });
    if(encontrados.isEmpty) _msg('No pude identificar apoderados con seguridad. Usa “Agregar / corregir apoderados” para seleccionarlos por nombre o RUT.');
    else _msg('Reconocí ${encontrados.length} apoderado(s). Revisa nombre y RUT antes de confirmar.');
  }

  Future<void> _agregarManual() async {
    List<Map<String,dynamic>> listaCompleta;
    try {
      listaCompleta = await _cargarApoderados();
    } catch (e) {
      if (mounted) _msg('No se pudo cargar la lista de apoderados: $e');
      return;
    }
    if (!mounted) return;
    // En el selector mostramos solamente quienes aún NO tienen turno en el mes
    // elegido. Si se elimina una asignación, la persona vuelve automáticamente
    // a quedar disponible. Quienes ya están seleccionados en esta edición se
    // conservan visibles.
    try {
      final ocupadosSnap = await _db.collection('agenda_aseo').where('mes_id', isEqualTo: _mesId(_fecha)).get();
      final rutsOcupados = <String>{};
      final uidsOcupados = <String>{};
      for (final doc in ocupadosSnap.docs) {
        final d = doc.data();
        final rut = (d['rut_clave'] ?? d['rut_apoderado'] ?? '').toString().toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
        final uid = (d['uid'] ?? '').toString().trim();
        if (rut.isNotEmpty) rutsOcupados.add(rut);
        if (uid.isNotEmpty) uidsOcupados.add(uid);
      }
      listaCompleta = listaCompleta.where((d) {
        final rut = _rut(d).toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');
        final uid = (d['uid'] ?? '').toString().trim();
        final key = (d['uid'] ?? d['_id'] ?? _rut(d)).toString();
        if (_seleccionados.containsKey(key)) return true;
        return !(rut.isNotEmpty && rutsOcupados.contains(rut)) && !(uid.isNotEmpty && uidsOcupados.contains(uid));
      }).toList();
    } catch (_) {}
    if (listaCompleta.isEmpty && _seleccionados.isEmpty) {
      _msg('Todos los apoderados ya tienen turno asignado en ${DateFormat('MMMM', 'es').format(_fecha)}.');
      return;
    }

    // El modal trabaja con una copia local. El estado de la pantalla principal
    // se actualiza solo después de cerrar el bottom sheet; así evitamos
    // reconstruir/desmontar dependencias heredadas mientras el modal está vivo.
    final seleccionLocal = Map<String, Map<String,dynamic>>.from(_seleccionados);
    final resultado = await showModalBottomSheet<Map<String, Map<String,dynamic>>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _SelectorApoderadosAseo(
        listaCompleta: listaCompleta,
        seleccionInicial: seleccionLocal,
        nombre: _nombre,
        rut: _rut,
        normal: _normal,
      ),
    );
    if (!mounted || resultado == null) return;
    setState(() {
      _seleccionados
        ..clear()
        ..addAll(resultado);
    });
  }

  Future<void> _confirmar() async {
    if(_seleccionados.isEmpty){_msg('Agrega al menos un apoderado.');return;}
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Confirmar asignación'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(_fechaBonita(_fecha),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:17)),const SizedBox(height:12),
      ..._seleccionados.values.map((d)=>ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.verified_user,color:Color(0xFF159B72)),title:Text(_nombre(d),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('RUT ${_rut(d)}'))),
      if(_indicaciones.text.trim().isNotEmpty)...[const Divider(),const Text('Indicaciones / cosas solicitadas',style:TextStyle(fontWeight:FontWeight.w900)),Text(_indicaciones.text.trim())]
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Volver')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmar'))]));
    if(ok!=true)return;
    final batch=_db.batch(); final ahora=FieldValue.serverTimestamp();
    for(final e in _seleccionados.entries){ final d=e.value; final uid=(d['uid']??d['auth_uid']??'').toString(); final rut=_rut(d); final email=(d['email']??d['correo']??'').toString().toLowerCase().trim(); final base=uid.isNotEmpty?uid:(rut.isNotEmpty?rut.replaceAll(RegExp(r'[^0-9Kk]'),''):email.replaceAll(RegExp(r'[^a-zA-Z0-9]'),'_')); final id='${base}_${_diaId(_fecha)}'; final ref=_db.collection('agenda_aseo').doc(id); batch.set(ref,{
      'id':id,'uid':uid,'usuario_doc_id':e.key,'email':email,'rut_clave':rut.replaceAll(RegExp(r'[^0-9Kk]'),'').toUpperCase(),'nombre_apoderado':_nombre(d),'rut_apoderado':_rut(d),'fecha_aseo':Timestamp.fromDate(DateTime(_fecha.year,_fecha.month,_fecha.day)),'dia_id':_diaId(_fecha),'mes_id':_mesId(_fecha),'estado':'asignado','modalidad':'asiste','indicaciones':_indicaciones.text.trim(),'asignado_por':FirebaseAuth.instance.currentUser?.email,'fecha_asignacion':ahora,'recordatorio_dia_anterior':true,'fecha_recordatorio':Timestamp.fromDate(DateTime(_fecha.year,_fecha.month,_fecha.day).subtract(const Duration(days:1)))
    },SetOptions(merge:true));
      final aviso=_db.collection('avisos_apoderados').doc('aseo_$id'); batch.set(aviso,{'uid':uid,'email':d['email']??d['correo'],'titulo':'Turno de aseo asignado','mensaje':'Tu turno de aseo fue asignado para ${DateFormat('dd/MM/yyyy').format(_fecha)}. Revisa las indicaciones en Aseo.','tipo':'aseo_turno','agenda_aseo_id':id,'fecha_turno':Timestamp.fromDate(_fecha),'activo':true,'leido':false,'creado_en':ahora},SetOptions(merge:true));
    }
    try {
      await batch.commit();
    } catch (e) {
      if (mounted) _msg('No se pudo guardar la asignación: $e');
      return;
    }
    if(!mounted)return; setState(()=>_seleccionados.clear()); _indicaciones.clear(); _msg('Turno asignado. Los avisos quedaron creados para los apoderados.');
  }


  Future<void> _configurarReemplazos() async {
    final ref=_db.collection('configuracion').doc('aseo_reemplazos');
    final snap=await ref.get(); final d=snap.data()??{};
    final monto=TextEditingController(text:(d['monto']??10000).toString());
    final banco=TextEditingController(text:(d['banco']??'').toString());
    final tipo=TextEditingController(text:(d['tipo_cuenta']??'').toString());
    final numero=TextEditingController(text:(d['numero_cuenta']??'').toString());
    final titular=TextEditingController(text:(d['titular']??'').toString());
    final rut=TextEditingController(text:(d['rut']??'').toString());
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Cuenta para reemplazos'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(children:[
      TextField(controller:monto,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Valor del reemplazo')),const SizedBox(height:8),
      TextField(controller:banco,decoration:const InputDecoration(labelText:'Banco')),const SizedBox(height:8),
      TextField(controller:tipo,decoration:const InputDecoration(labelText:'Tipo de cuenta')),const SizedBox(height:8),
      TextField(controller:numero,decoration:const InputDecoration(labelText:'Número de cuenta')),const SizedBox(height:8),
      TextField(controller:titular,decoration:const InputDecoration(labelText:'Titular')),const SizedBox(height:8),
      TextField(controller:rut,decoration:const InputDecoration(labelText:'RUT titular')),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Guardar'))]));
    if(ok==true){await ref.set({'monto':int.tryParse(monto.text.replaceAll(RegExp(r'[^0-9]'),''))??10000,'banco':banco.text.trim(),'tipo_cuenta':tipo.text.trim(),'numero_cuenta':numero.text.trim(),'titular':titular.text.trim(),'rut':rut.text.trim(),'actualizado_en':FieldValue.serverTimestamp()},SetOptions(merge:true));if(mounted)_msg('Datos de reemplazo guardados.');}
    monto.dispose();banco.dispose();tipo.dispose();numero.dispose();titular.dispose();rut.dispose();
  }

  Future<void> _cambiarModalidad(DocumentSnapshot<Map<String,dynamic>> doc,String accion) async {
    final ref=doc.reference; final d=doc.data()??{};
    if(accion=='reemplazo'){
      final cfg=(await _db.collection('configuracion').doc('aseo_reemplazos').get()).data()??{};
      final monto=(cfg['monto']??10000) as num;
      await ref.update({'modalidad':'reemplazo','estado':'reemplazo_pendiente','estado_pago_reemplazo':'pendiente','monto_reemplazo':monto.toInt(),'actualizado_en':FieldValue.serverTimestamp()});
      await _db.collection('avisos_apoderados').doc('reemplazo_${doc.id}').set({'uid':d['uid'],'email':d['email'],'titulo':'Reemplazo de aseo','mensaje':'Tu turno fue cambiado a reemplazo. Revisa los datos de transferencia y envía tu comprobante.','tipo':'aseo_reemplazo','agenda_aseo_id':doc.id,'activo':true,'leido':false,'creado_en':FieldValue.serverTimestamp()},SetOptions(merge:true));
      if(mounted)_msg('Turno cambiado a reemplazo. Al apoderado le aparecerá la opción de pago.');
    }else if(accion=='efectivo'){
      await ref.update({'modalidad':'reemplazo','estado':'reemplazo_pagado','estado_pago_reemplazo':'pagado','medio_pago_reemplazo':'efectivo','pago_registrado_por':FirebaseAuth.instance.currentUser?.email,'fecha_pago_reemplazo':FieldValue.serverTimestamp(),'actualizado_en':FieldValue.serverTimestamp()});
      if(mounted)_msg('Pago en efectivo registrado.');
    }else if(accion=='transferencia_ok'){
      await ref.update({'modalidad':'reemplazo','estado':'reemplazo_pagado','estado_pago_reemplazo':'pagado','medio_pago_reemplazo':'transferencia','pago_registrado_por':FirebaseAuth.instance.currentUser?.email,'fecha_pago_reemplazo':FieldValue.serverTimestamp(),'actualizado_en':FieldValue.serverTimestamp()});
      if(mounted)_msg('Transferencia confirmada.');
    }else if(accion=='eliminar'){
      final confirmar=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Quitar del turno'),content:Text('¿Quitar a ${_nombre(d)} de este turno? Volverá a aparecer entre los pendientes del mes.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Quitar'))]));
      if(confirmar==true){
        await ref.delete();
        await _db.collection('avisos_apoderados').doc('aseo_${doc.id}').delete().catchError((_){ });
        await _db.collection('avisos_apoderados').doc('reemplazo_${doc.id}').delete().catchError((_){ });
        if(mounted)_msg('${_nombre(d)} quedó nuevamente disponible para asignar este mes.');
      }
    }else{
      await ref.update({'modalidad':'asiste','estado':accion,'estado_pago_reemplazo':FieldValue.delete(),'medio_pago_reemplazo':FieldValue.delete(),'actualizado_en':FieldValue.serverTimestamp()});
    }
  }
  Future<void> _cargarTurnoEnFormulario(DateTime fecha) async {
    final snap = await _db.collection('agenda_aseo').where('dia_id', isEqualTo: _diaId(fecha)).get();
    final cargados = <String, Map<String,dynamic>>{};
    String indicaciones = '';
    for (final doc in snap.docs) {
      final d = <String,dynamic>{...doc.data(), '_agenda_doc_id': doc.id};
      final key = (d['uid'] ?? d['usuario_doc_id'] ?? d['rut_clave'] ?? doc.id).toString();
      cargados[key] = d;
      if (indicaciones.isEmpty && (d['indicaciones'] ?? '').toString().trim().isNotEmpty) {
        indicaciones = d['indicaciones'].toString();
      }
    }
    if (!mounted) return;
    setState(() {
      _fecha = fecha;
      _seleccionados
        ..clear()
        ..addAll(cargados);
      _dictado = '';
    });
    _indicaciones.text = indicaciones;
  }

  Future<void> _seleccionarFecha() async {
    DateTime mesDialogo = DateTime(_fecha.year, _fecha.month);
    final f = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final primero = DateTime(mesDialogo.year, mesDialogo.month, 1);
        final cantidadDias = DateTime(mesDialogo.year, mesDialogo.month + 1, 0).day;
        final espaciosIniciales = primero.weekday - 1;
        final totalCeldas = ((espaciosIniciales + cantidadDias + 6) ~/ 7) * 7;
        const diasSemana = ['L','M','X','J','V','S','D'];
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
                stream: _db.collection('agenda_aseo').where('mes_id', isEqualTo: _mesId(mesDialogo)).snapshots(),
                builder: (context, snap) {
                  final diasConTurno = <int>{};
                  for (final doc in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String,dynamic>>>[]) {
                    final fecha = (doc.data()['fecha_aseo'] as Timestamp?)?.toDate();
                    if (fecha != null && fecha.year == mesDialogo.year && fecha.month == mesDialogo.month) diasConTurno.add(fecha.day);
                  }
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children:[
                      IconButton(onPressed:()=>setLocal(()=>mesDialogo=DateTime(mesDialogo.year,mesDialogo.month-1)),icon:const Icon(Icons.chevron_left)),
                      Expanded(child:Text(DateFormat('MMMM yyyy','es').format(mesDialogo),textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:Color(0xFF075C91)))),
                      IconButton(onPressed:()=>setLocal(()=>mesDialogo=DateTime(mesDialogo.year,mesDialogo.month+1)),icon:const Icon(Icons.chevron_right)),
                    ]),
                    const SizedBox(height:8),
                    Row(children:diasSemana.map((d)=>Expanded(child:Center(child:Text(d,style:const TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF526F87)))))).toList()),
                    const SizedBox(height:6),
                    GridView.builder(
                      shrinkWrap:true, physics:const NeverScrollableScrollPhysics(), itemCount:totalCeldas,
                      gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,childAspectRatio:.88),
                      itemBuilder:(context,i){
                        final dia=i-espaciosIniciales+1;
                        if(dia<1||dia>cantidadDias)return const SizedBox.shrink();
                        final tieneTurno=diasConTurno.contains(dia);
                        final seleccionado=_fecha.year==mesDialogo.year&&_fecha.month==mesDialogo.month&&_fecha.day==dia;
                        return InkWell(borderRadius:BorderRadius.circular(14),onTap:()=>Navigator.pop(ctx,DateTime(mesDialogo.year,mesDialogo.month,dia)),child:Container(
                          margin:const EdgeInsets.all(3),
                          decoration:BoxDecoration(color:seleccionado?const Color(0xFFE8F6FF):Colors.transparent,borderRadius:BorderRadius.circular(14),border:seleccionado?Border.all(color:const Color(0xFF087BB5),width:1.5):null),
                          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('$dia',style:TextStyle(fontSize:16,fontWeight:tieneTurno?FontWeight.w900:FontWeight.w600,color:tieneTurno?const Color(0xFF075C91):const Color(0xFF263238))),const SizedBox(height:4),if(tieneTurno)Container(width:8,height:8,decoration:const BoxDecoration(color:Color(0xFF159B72),shape:BoxShape.circle))]),
                        ));
                      },
                    ),
                    const SizedBox(height:8),
                    const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.circle,size:9,color:Color(0xFF159B72)),SizedBox(width:6),Text('Día con turno asignado',style:TextStyle(color:Color(0xFF526F87)))]),
                    Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar'))),
                  ]);
                },
              ),
            ),
          ),
        );
      }),
    );
    if(f!=null){
      setState(()=>_mes=DateTime(f.year,f.month));
      await _cargarTurnoEnFormulario(f);
    }
  }
  void _msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));

  Widget _agenda() {
    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Image.asset('assets/images/aseo_casa_autismo.png', height: 170, width: double.infinity, fit: BoxFit.cover),
              Positioned.fill(child: Container(color: Colors.black.withOpacity(.38))),
              const Positioned(left: 18, right: 18, bottom: 16, child: Text('Organización de Aseo', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: _configurarReemplazos, icon: const Icon(Icons.account_balance), label: const Text('Cuenta y valor de reemplazos'))),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Nueva asignación', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF075C91))),
              const SizedBox(height: 12),
              const Text('1. Fecha del turno', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SizedBox(height: 52, child: OutlinedButton.icon(onPressed: _seleccionarFecha, icon: const Icon(Icons.calendar_month), label: Text(_fechaBonita(_fecha)))),
              const SizedBox(height: 10),
              SizedBox(height: 52, child: FilledButton.icon(onPressed: _dictarAsignacion, icon: Icon(_escuchando ? Icons.stop_circle : Icons.mic), label: Text(_escuchando ? 'ESCUCHANDO… TOCA PARA DETENER' : (_seleccionados.isEmpty ? 'ASIGNAR POR VOZ' : '+ AGREGAR POR VOZ')))),
              if (_dictado.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Escuché: “$_dictado”', style: const TextStyle(color: Color(0xFF526F87)))),
              const SizedBox(height: 14),
              const Text('2. Apoderados principales', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SizedBox(height: 52, child: FilledButton.icon(onPressed: _agregarManual, icon: const Icon(Icons.person_add_alt_1), label: Text(_seleccionados.isEmpty ? 'SELECCIONAR APODERADOS' : 'MODIFICAR APODERADOS (${_seleccionados.length})'))),
              if (_seleccionados.isNotEmpty) ...[
                const SizedBox(height: 10),
                ..._seleccionados.entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(color: const Color(0xFFEAF7FD), borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: const Icon(Icons.check_circle, color: Color(0xFF159B72)),
                    title: Text(_nombre(e.value), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('RUT ${_rut(e.value)}'),
                    trailing: Icon((e.value['_agenda_doc_id'] ?? '').toString().isNotEmpty ? Icons.edit : Icons.close, color: const Color(0xFF075C91)),
                    onTap: () async {
                      final docId = (e.value['_agenda_doc_id'] ?? '').toString();
                      if (docId.isEmpty) {
                        setState(() => _seleccionados.remove(e.key));
                        return;
                      }
                      final doc = await _db.collection('agenda_aseo').doc(docId).get();
                      if (doc.exists && mounted) {
                        await _editarPersonaTurno(doc);
                        await _cargarTurnoEnFormulario(_fecha);
                      }
                    },
                  ),
                )),
              ],
              const SizedBox(height: 14),
              const Text('3. Indicaciones especiales (opcional)', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(controller: _indicaciones, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'Ej.: sector a limpiar, horario o instrucción especial', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(height: 54, child: FilledButton.icon(onPressed: _confirmar, icon: const Icon(Icons.notifications_active), label: const Text('CONFIRMAR ASIGNACIÓN Y AVISAR'))),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        _comprobantesReemplazoPendientes(),
      ],
    );
  }

  Widget _listaTurnosMes() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('agenda_aseo').where('mes_id', isEqualTo: _mesId(_mes)).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('No se pudieron cargar los turnos: ${snap.error}')));
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));

        final porDia = <int, List<QueryDocumentSnapshot<Map<String,dynamic>>>>{};
        for (final doc in snap.data!.docs) {
          final d = doc.data();
          final f = (d['fecha_aseo'] as Timestamp?)?.toDate();
          if (f != null && f.year == _mes.year && f.month == _mes.month) {
            porDia.putIfAbsent(f.day, () => []).add(doc);
          }
        }

        final primero = DateTime(_mes.year, _mes.month, 1);
        final cantidadDias = DateTime(_mes.year, _mes.month + 1, 0).day;
        final espaciosIniciales = primero.weekday - 1; // lunes = 0
        final totalCeldas = ((espaciosIniciales + cantidadDias + 6) ~/ 7) * 7;
        const diasSemana = ['L','M','X','J','V','S','D'];

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
            child: Column(children: [
              Row(children: diasSemana.map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF526F87)))))).toList()),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: .88),
                itemCount: totalCeldas,
                itemBuilder: (context, i) {
                  final dia = i - espaciosIniciales + 1;
                  if (dia < 1 || dia > cantidadDias) return const SizedBox.shrink();
                  final grupo = porDia[dia] ?? const <QueryDocumentSnapshot<Map<String,dynamic>>>[];
                  final tieneTurno = grupo.isNotEmpty;
                  final seleccionado = _fecha.year == _mes.year && _fecha.month == _mes.month && _fecha.day == dia;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final fecha = DateTime(_mes.year, _mes.month, dia);
                      await _cargarTurnoEnFormulario(fecha);
                    },
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: seleccionado ? const Color(0xFFE8F6FF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: seleccionado ? Border.all(color: const Color(0xFF087BB5), width: 1.5) : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('$dia', style: TextStyle(fontSize: 16, fontWeight: tieneTurno ? FontWeight.w900 : FontWeight.w600, color: tieneTurno ? const Color(0xFF075C91) : const Color(0xFF263238))),
                        const SizedBox(height: 4),
                        if (tieneTurno)
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF159B72), shape: BoxShape.circle)),
                      ]),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.circle, size: 9, color: Color(0xFF159B72)),
                SizedBox(width: 6),
                Text('Día con turno asignado', style: TextStyle(color: Color(0xFF526F87))),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _mostrarAsignadosDia(DateTime fecha, List<QueryDocumentSnapshot<Map<String,dynamic>>> grupo) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .58,
        minChildSize: .35,
        maxChildSize: .88,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: ListView(controller: controller, children: [
            Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 14),
            Text(_fechaBonita(fecha), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF075C91))),
            const SizedBox(height: 4),
            Text('${grupo.length} ${grupo.length == 1 ? 'apoderado asignado' : 'apoderados asignados'}', style: const TextStyle(color: Color(0xFF526F87))),
            const SizedBox(height: 14),
            ...grupo.map((doc) {
              final d = doc.data();
              final estado = (d['estado'] ?? 'asignado').toString().replaceAll('_', ' ');
              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(color: const Color(0xFFEAF7FD), borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const Icon(Icons.person, color: Color(0xFF159B72)),
                  title: Text(_nombre(d), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('RUT ${_rut(d)}\n$estado'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.edit, color: Color(0xFF075C91)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _editarPersonaTurno(doc);
                  },
                ),
              );
            }),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() { _fecha = fecha; _seleccionados.clear(); });
                await _agregarManual();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('AGREGAR OTRA PERSONA'),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editarPersonaTurno(DocumentSnapshot<Map<String,dynamic>> doc) async {
    final d=doc.data()??{};
    final modalidad=(d['modalidad']??'asiste').toString();
    final estado=(d['estado']??'asignado').toString();
    final pago=(d['estado_pago_reemplazo']??'').toString();
    final esReemplazo=modalidad=='reemplazo' || estado.startsWith('reemplazo_');
    final pagado=pago=='pagado' || estado=='reemplazo_pagado';
    final accion=await showModalBottomSheet<String>(
      context:context,
      useSafeArea:true,
      isScrollControlled:true,
      builder:(ctx)=>SafeArea(child:SingleChildScrollView(child:Padding(
        padding:EdgeInsets.fromLTRB(16,16,16,16+MediaQuery.of(ctx).viewInsets.bottom),
        child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(_nombre(d),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),
          Text('RUT ${_rut(d)}',style:const TextStyle(color:Color(0xFF526F87))),
          const SizedBox(height:14),
          if(!esReemplazo) ...[
            const ListTile(leading:Icon(Icons.cleaning_services,color:Color(0xFF159B72)),title:Text('Asiste al turno'),subtitle:Text('Asignación actual')),
            ListTile(leading:const Icon(Icons.swap_horiz,color:Color(0xFFE67E22)),title:const Text('Usará reemplazo'),subtitle:const Text('Activa el pago de reemplazo para el apoderado'),onTap:()=>Navigator.pop(ctx,'reemplazo')),
          ] else ...[
            ListTile(leading:const Icon(Icons.swap_horiz,color:Color(0xFFE67E22)),title:Text(pagado?'Reemplazo pagado':'Usará reemplazo'),subtitle:Text(pagado?'Pago ya registrado':'Pago pendiente del apoderado')),
            if(!pagado) ListTile(leading:const Icon(Icons.payments,color:Color(0xFF159B72)),title:const Text('Registrar pago en efectivo'),onTap:()=>Navigator.pop(ctx,'efectivo')),
            if(!pagado) ListTile(leading:const Icon(Icons.account_balance,color:Color(0xFF075C91)),title:const Text('Confirmar transferencia recibida'),onTap:()=>Navigator.pop(ctx,'transferencia_ok')),
            ListTile(leading:const Icon(Icons.cleaning_services,color:Color(0xFF159B72)),title:const Text('Volver a: asiste al turno'),onTap:()=>Navigator.pop(ctx,'asignado')),
          ],
          if(estado!='realizado') ListTile(leading:const Icon(Icons.check_circle,color:Color(0xFF159B72)),title:const Text('Marcar que asistió'),onTap:()=>Navigator.pop(ctx,'realizado')),
          if(estado!='ausente') ListTile(leading:Icon(Icons.person_off,color:Colors.red.shade700),title:const Text('Marcar que no asistió'),onTap:()=>Navigator.pop(ctx,'ausente')),
          const Divider(),
          ListTile(leading:Icon(Icons.delete_outline,color:Colors.red.shade700),title:Text('Quitar de este turno',style:TextStyle(color:Colors.red.shade700,fontWeight:FontWeight.w800)),subtitle:const Text('Volverá al listado de pendientes del mes'),onTap:()=>Navigator.pop(ctx,'eliminar')),
        ]),
      ))),
    );
    if(accion!=null && mounted) await _cambiarModalidad(doc,accion);
  }

  String _estadoUtil(String e){switch(e){case'aprobado':return'Aceptado';case'rechazado':return'Rechazado';default:return'Pendiente';}}
  Color _colorUtil(String e)=>e=='aprobado'?const Color(0xFF159B72):e=='rechazado'?Colors.red.shade700:const Color(0xFFE67E22);

  Future<Map<String,dynamic>> _perfilEnvio(Map<String,dynamic>d) async {
    final r=Map<String,dynamic>.from(d);
    final uid=(d['uid']??'').toString();
    if(uid.isNotEmpty){final u=await _db.collection('usuarios').doc(uid).get();if(u.exists){final x=u.data()??{};r['nombre_apoderado']=x['nombre_apoderado']??x['nombre']??x['nombre_completo']??r['nombre_apoderado'];r['rut_apoderado']=x['rut_apoderado']??x['rut']??x['rut_normalizado']??r['rut_apoderado'];r['beneficiario_nombre']=x['nombre_beneficiario']??x['beneficiario_nombre']??r['beneficiario_nombre'];}}
    return r;
  }

  Future<void> _revisarUtil(DocumentReference<Map<String,dynamic>> ref,String estado) async {
    String motivo='';
    if(estado=='rechazado'){
      final c=TextEditingController();
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Motivo del rechazo'),content:TextField(controller:c,maxLines:3,decoration:const InputDecoration(hintText:'Indica por qué se rechaza este aporte',border:OutlineInputBorder())),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Rechazar'))]));
      if(ok!=true)return; motivo=c.text.trim(); c.dispose(); if(motivo.isEmpty){_msg('Escribe el motivo del rechazo.');return;}
    }
    await ref.update({'estado':estado,'motivo_rechazo':motivo,'coordinadora_aseo_revisado':true,'fecha_revision':FieldValue.serverTimestamp(),'revisado_por':FirebaseAuth.instance.currentUser?.email});
  }

  Future<void> _detalleUtil(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    final d=await _perfilEnvio(doc.data()); if(!mounted)return;
    final f=(d['fecha_envio'] as Timestamp?)?.toDate(); final estado=(d['estado']??'pendiente_revision').toString(); final foto=(d['foto_url']??'').toString();
    await showDialog(context:context,builder:(ctx)=>Dialog(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      const Text('Detalle del aporte de útiles',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),const SizedBox(height:14),
      Text(_nombre(d),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),Text('RUT ${_rut(d)}'),if((d['beneficiario_nombre']??'').toString().trim().isNotEmpty)Text('Beneficiario: ${d['beneficiario_nombre']}'),if(f!=null)Text('Enviado: ${DateFormat('dd/MM/yyyy HH:mm').format(f)}'),const SizedBox(height:12),
      if(foto.isNotEmpty)ClipRRect(borderRadius:BorderRadius.circular(18),child:Image.network(foto,width:double.infinity,height:260,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox(height:120,child:Center(child:Text('No se pudo cargar la fotografía.'))))),
      const SizedBox(height:14),const Text('Materiales entregados',style:TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF075C91))),Text((d['detalle']??d['descripcion']??'Sin detalle').toString(),style:const TextStyle(fontSize:16)),const SizedBox(height:12),
      Chip(label:Text(_estadoUtil(estado)),avatar:Icon(Icons.circle,size:12,color:_colorUtil(estado))),if((d['motivo_rechazo']??'').toString().isNotEmpty)Text('Motivo: ${d['motivo_rechazo']}'),const SizedBox(height:12),
      if(estado!='aprobado')SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()async{Navigator.pop(ctx);await _revisarUtil(doc.reference,'aprobado');},icon:const Icon(Icons.check_circle),label:const Text('ACEPTAR'))),
      if(estado!='rechazado')SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()async{Navigator.pop(ctx);await _revisarUtil(doc.reference,'rechazado');},icon:const Icon(Icons.cancel),label:const Text('RECHAZAR'))),
      Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cerrar')))
    ])))));
  }

  Widget _utiles(){return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:_db.collection('utiles_aseo').orderBy('fecha_envio',descending:true).limit(150).snapshots(),builder:(context,snap){final docs=(snap.data?.docs??[]).where((d)=>(d.data()['estado']??'pendiente_revision').toString()!='aprobado').toList();return ListView(padding:const EdgeInsets.all(16),children:[
    Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF087BB5),Color(0xFF25A7D9)]),borderRadius:BorderRadius.circular(24)),child:const Row(children:[CircleAvatar(radius:27,backgroundColor:Colors.white,child:Icon(Icons.inventory_2,color:Color(0xFF087BB5),size:30)),SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Útiles de aseo enviados',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w900)),SizedBox(height:3),Text('Toca una tarjeta para ver foto, materiales y revisar.',style:TextStyle(color:Colors.white))]))])),
    const SizedBox(height:14),if(docs.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('No hay envíos todavía.'))),
    ...docs.map((doc){final d=doc.data(),e=(d['estado']??'pendiente_revision').toString(),f=(d['fecha_envio'] as Timestamp?)?.toDate(),foto=(d['foto_url']??'').toString();return Container(margin:const EdgeInsets.only(bottom:12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22),border:Border.all(color:_colorUtil(e).withOpacity(.28),width:1.5),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.05),blurRadius:10,offset:const Offset(0,4))]),child:InkWell(borderRadius:BorderRadius.circular(22),onTap:()=>_detalleUtil(doc),child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      ClipRRect(borderRadius:BorderRadius.circular(15),child:foto.isNotEmpty?Image.network(foto,width:72,height:72,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(width:72,height:72,color:_colorUtil(e).withOpacity(.12),child:Icon(Icons.inventory_2,color:_colorUtil(e)))):Container(width:72,height:72,color:_colorUtil(e).withOpacity(.12),child:Icon(Icons.inventory_2,color:_colorUtil(e),size:30))),const SizedBox(width:13),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(_nombre(d),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:Color(0xFF063E83))),const SizedBox(height:4),Text((d['detalle']??d['descripcion']??'Sin detalle').toString(),maxLines:2,overflow:TextOverflow.ellipsis),if(f!=null)Text(DateFormat('dd/MM/yyyy HH:mm').format(f),style:const TextStyle(color:Color(0xFF607D8B),fontSize:12))])),const SizedBox(width:8),
      Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),decoration:BoxDecoration(color:_colorUtil(e).withOpacity(.12),borderRadius:BorderRadius.circular(14)),child:Column(children:[Icon(Icons.circle,size:10,color:_colorUtil(e)),const SizedBox(height:3),Text(_estadoUtil(e),style:TextStyle(fontSize:11,fontWeight:FontWeight.w900,color:_colorUtil(e)))]) )
    ]))));})]);});}

  Widget _comprobantesReemplazoPendientes(){
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:_db.collection('agenda_aseo').where('estado',isEqualTo:'reemplazo_comprobante').snapshots(),
      builder:(context,snap){
        final docs=snap.data?.docs??[];
        if(docs.isEmpty)return const SizedBox.shrink();
        return Container(
          padding:const EdgeInsets.all(14),
          decoration:BoxDecoration(color:const Color(0xFFFFF4E6),borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFF0A13A))),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[const Icon(Icons.notifications_active,color:Color(0xFFE67E22)),const SizedBox(width:8),Expanded(child:Text('Comprobantes de reemplazo por revisar (${docs.length})',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16,color:Color(0xFF8A4A00))))]),
            const SizedBox(height:8),
            ...docs.map((doc){final d=doc.data();return ListTile(contentPadding:EdgeInsets.zero,leading:const CircleAvatar(child:Icon(Icons.receipt_long)),title:Text(_nombre(d),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('RUT ${_rut(d)} · Toca para revisar'),trailing:const Icon(Icons.chevron_right),onTap:()=>_revisarComprobanteReemplazo(doc));}),
          ]),
        );
      },
    );
  }

  Future<void> _revisarComprobanteReemplazo(DocumentSnapshot<Map<String,dynamic>> agendaDoc) async {
    final d=agendaDoc.data()??{};
    final comprobanteId=(d['reemplazo_comprobante_id']??'').toString();
    Map<String,dynamic> comp={};
    if(comprobanteId.isNotEmpty){final c=await _db.collection('aseo_reemplazos').doc(comprobanteId).get();comp=c.data()??{};}
    if(!mounted)return;
    final foto=(d['reemplazo_comprobante_url']??comp['foto_url']??'').toString();
    final monto=(comp['monto']??d['monto_reemplazo']??10000).toString();
    final accion=await showDialog<String>(context:context,builder:(ctx)=>Dialog(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      const Text('Comprobante de reemplazo',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),const SizedBox(height:10),
      Text(_nombre(d),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),Text('RUT ${_rut(d)}'),Text('Monto informado: \$$monto'),const SizedBox(height:12),
      if(foto.isNotEmpty)ClipRRect(borderRadius:BorderRadius.circular(16),child:Image.network(foto,width:double.infinity,height:280,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const SizedBox(height:100,child:Center(child:Text('No se pudo cargar el comprobante.'))))),
      const SizedBox(height:14),
      SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>Navigator.pop(ctx,'aprobar'),icon:const Icon(Icons.check_circle),label:const Text('APROBAR TRANSFERENCIA'))),
      SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>Navigator.pop(ctx,'rechazar'),icon:const Icon(Icons.cancel),label:const Text('RECHAZAR COMPROBANTE'))),
      Align(alignment:Alignment.centerRight,child:TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cerrar'))),
    ])))));
    if(accion==null)return;
    if(accion=='aprobar'){
      await agendaDoc.reference.update({'modalidad':'reemplazo','estado':'reemplazo_pagado','estado_pago_reemplazo':'pagado','medio_pago_reemplazo':'transferencia','pago_registrado_por':FirebaseAuth.instance.currentUser?.email,'fecha_pago_reemplazo':FieldValue.serverTimestamp(),'actualizado_en':FieldValue.serverTimestamp()});
      if(comprobanteId.isNotEmpty)await _db.collection('aseo_reemplazos').doc(comprobanteId).set({'estado':'aprobado','estado_tesoreria':'aprobado','revisado_por':FirebaseAuth.instance.currentUser?.email,'fecha_revision':FieldValue.serverTimestamp()},SetOptions(merge:true));
      await _db.collection('avisos_apoderados').doc('reemplazo_${agendaDoc.id}').set({'uid':d['uid'],'email':d['email'],'titulo':'Pago de reemplazo confirmado','mensaje':'Tu transferencia por reemplazo de aseo fue confirmada.','tipo':'aseo_reemplazo_pago','agenda_aseo_id':agendaDoc.id,'activo':true,'leido':false,'creado_en':FieldValue.serverTimestamp()},SetOptions(merge:true));
      if(mounted)_msg('Transferencia aprobada. El pago pasó a estadísticas.');
    }else{
      await agendaDoc.reference.update({'estado':'reemplazo_pendiente','estado_pago_reemplazo':'pendiente','reemplazo_comprobante_id':FieldValue.delete(),'reemplazo_comprobante_url':FieldValue.delete(),'actualizado_en':FieldValue.serverTimestamp()});
      if(comprobanteId.isNotEmpty)await _db.collection('aseo_reemplazos').doc(comprobanteId).set({'estado':'rechazado','estado_tesoreria':'rechazado','revisado_por':FirebaseAuth.instance.currentUser?.email,'fecha_revision':FieldValue.serverTimestamp()},SetOptions(merge:true));
      await _db.collection('avisos_apoderados').doc('reemplazo_${agendaDoc.id}').set({'uid':d['uid'],'email':d['email'],'titulo':'Comprobante de reemplazo rechazado','mensaje':'Tu comprobante fue rechazado. Debes enviar uno nuevo.','tipo':'aseo_reemplazo','agenda_aseo_id':agendaDoc.id,'activo':true,'leido':false,'creado_en':FieldValue.serverTimestamp()},SetOptions(merge:true));
      if(mounted)_msg('Comprobante rechazado. El apoderado puede enviarlo nuevamente.');
    }
  }

  Future<void> _guardarSolicitud({DocumentSnapshot<Map<String,dynamic>>? existente}) async {
    final utilesCtrl=TextEditingController();
    final mensajeCtrl=TextEditingController();
    bool urgente=false;
    String estado='pendiente';
    if(existente!=null){
      final x=existente.data()??{};
      utilesCtrl.text=((x['utiles_sugeridos'] as List?)??[]).join('\n');
      mensajeCtrl.text=(x['mensaje']??'').toString();
      urgente=(x['urgente']??false)==true;
      estado=(x['estado']??'pendiente').toString();
    }
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setLocal)=>AlertDialog(
      title:Text(existente==null?'Nueva solicitud de útiles':'Editar solicitud de útiles'),
      content:SizedBox(width:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(controller:utilesCtrl,minLines:3,maxLines:7,decoration:const InputDecoration(labelText:'Útiles necesarios',hintText:'Ej.: Limpia piso\nCloro\nPaños',border:OutlineInputBorder())),const SizedBox(height:10),
        TextField(controller:mensajeCtrl,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'Mensaje adicional (opcional)',border:OutlineInputBorder())),const SizedBox(height:8),
        SwitchListTile(contentPadding:EdgeInsets.zero,value:urgente,onChanged:(v)=>setLocal(()=>urgente=v),title:const Text('Marcar como URGENTE',style:TextStyle(fontWeight:FontWeight.w800)),secondary:Icon(Icons.priority_high,color:urgente?Colors.red:Colors.grey)),
        if(existente!=null)DropdownButtonFormField<String>(value:['pendiente','parcial','completada'].contains(estado)?estado:'pendiente',decoration:const InputDecoration(labelText:'Estado',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:'pendiente',child:Text('Pendiente')),DropdownMenuItem(value:'parcial',child:Text('Parcial')),DropdownMenuItem(value:'completada',child:Text('Completada'))],onChanged:(v){if(v!=null)setLocal(()=>estado=v);}),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(existente==null?'Publicar':'Guardar cambios'))],
    )));
    if(ok!=true){utilesCtrl.dispose();mensajeCtrl.dispose();return;}
    final utiles=utilesCtrl.text.split(RegExp(r'[,\n;]')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
    if(utiles.isEmpty){utilesCtrl.dispose();mensajeCtrl.dispose();_msg('Escribe al menos un útil o material.');return;}
    final ref=existente?.reference??_db.collection('aseo_avisos').doc();
    await ref.set({'tipo':'solicitud_utiles','titulo':urgente?'Solicitud URGENTE de útiles':'Solicitud de útiles de aseo','mensaje':mensajeCtrl.text.trim(),'utiles_sugeridos':utiles,'urgente':urgente,'estado':estado,'activo':estado!='completada','visible_apoderados':true,'solo_apoderado_principal':true,'actualizado_en':FieldValue.serverTimestamp(),if(existente==null)'creado_en':FieldValue.serverTimestamp(),'creado_por':FirebaseAuth.instance.currentUser?.email},SetOptions(merge:true));
    utilesCtrl.dispose();mensajeCtrl.dispose();if(mounted)_msg(existente==null?'Solicitud publicada.':'Solicitud actualizada.');
  }

  Widget _solicitudesUtiles(){
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:_db.collection('aseo_avisos').where('tipo',whereIn:['solicitud_utiles','solicitud_utiles_mensual']).snapshots(),builder:(context,snap){
      final docs=[...(snap.data?.docs??[])];
      docs.sort((a,b){final at=a.data()['creado_en'];final bt=b.data()['creado_en'];return (bt is Timestamp?bt.millisecondsSinceEpoch:0).compareTo(at is Timestamp?at.millisecondsSinceEpoch:0);});
      return ListView(padding:const EdgeInsets.all(16),children:[
        Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF087BB5),Color(0xFF25A7D9)]),borderRadius:BorderRadius.circular(24)),child:const Row(children:[CircleAvatar(radius:27,backgroundColor:Colors.white,child:Icon(Icons.campaign,color:Color(0xFF087BB5),size:30)),SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Solicitudes de útiles',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w900)),SizedBox(height:3),Text('Crea una solicitud cuando haga falta. Puede ser normal o urgente.',style:TextStyle(color:Colors.white))]))])),
        const SizedBox(height:12),SizedBox(height:52,child:FilledButton.icon(onPressed:()=>_guardarSolicitud(),icon:const Icon(Icons.add),label:const Text('NUEVA SOLICITUD'))),const SizedBox(height:14),
        if(docs.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('No hay solicitudes creadas.'))),
        ...docs.map((doc){final x=doc.data();final urgente=(x['urgente']??false)==true;final estado=(x['estado']??((x['activo']??true)?'pendiente':'completada')).toString();final utiles=((x['utiles_sugeridos'] as List?)??[]);return Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20),side:BorderSide(color:urgente?Colors.red.shade200:const Color(0xFFD4EAF6))),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Icon(urgente?Icons.priority_high:Icons.campaign,color:urgente?Colors.red:const Color(0xFF087BB5)),const SizedBox(width:8),Expanded(child:Text(urgente?'URGENTE':'Solicitud de útiles',style:TextStyle(fontWeight:FontWeight.w900,fontSize:17,color:urgente?Colors.red.shade700:const Color(0xFF063E83)))),Chip(label:Text(estado.toUpperCase()))]),const SizedBox(height:6),...utiles.map((u)=>Text('• $u')),if((x['mensaje']??'').toString().trim().isNotEmpty)...[const SizedBox(height:6),Text(x['mensaje'].toString())],const SizedBox(height:8),Align(alignment:Alignment.centerRight,child:OutlinedButton.icon(onPressed:()=>_guardarSolicitud(existente:doc),icon:const Icon(Icons.edit),label:const Text('Editar')))])));})
      ]);
    });
  }

  Widget _utilesPanel(){
    return DefaultTabController(length:2,child:Column(children:[Container(color:Colors.white,child:const TabBar(labelColor:Color(0xFF075C91),unselectedLabelColor:Color(0xFF607D8B),indicatorColor:Color(0xFF087BB5),tabs:[Tab(icon:Icon(Icons.inventory_2),text:'Aportes recibidos'),Tab(icon:Icon(Icons.campaign),text:'Solicitudes')])),Expanded(child:TabBarView(children:[_utiles(),_solicitudesUtiles()]))]));
  }

  Future<Map<String,dynamic>> _datosEstadisticas() async {
    final aps=await _cargarApoderados();
    final env=await _db.collection('utiles_aseo').get();
    final mes=_mesId(_mes); final delMes=env.docs.where((d){final x=d.data();if((x['mes_id']??'').toString()==mes)return true;final f=(x['fecha_envio'] as Timestamp?)?.toDate();return f!=null&&f.year==_mes.year&&f.month==_mes.month;}).toList();
    String clave(Map<String,dynamic>x){final rut=_rut(x).replaceAll('.','').replaceAll('-','').toLowerCase();if(rut.isNotEmpty&&rut!='rut no informado')return 'r:$rut';final em=(x['email']??x['correo']??'').toString().toLowerCase().trim();return 'e:$em';}
    final porClave=<String,Map<String,dynamic>>{}; for(final d in delMes){final x=d.data();porClave[clave(x)]=x;}
    final filas=<Map<String,dynamic>>[];
    for(final a in aps){final k=clave(a);Map<String,dynamic>? aporte=porClave[k];if(aporte==null){final email=(a['email']??a['correo']??'').toString().toLowerCase().trim();for(final d in delMes){if((d.data()['email']??'').toString().toLowerCase().trim()==email&&email.isNotEmpty){aporte=d.data();break;}}}filas.add({'nombre':_nombre(a),'rut':_rut(a),'estado':aporte==null?'no_enviado':(aporte['estado']??'pendiente_revision').toString(),'fecha':aporte?['fecha_envio'],'detalle':aporte?['detalle']??''});}
    final enviados=filas.where((x)=>x['estado']!='no_enviado').length;final pendientes=filas.where((x)=>x['estado']=='pendiente_revision').length;final rechazados=filas.where((x)=>x['estado']=='rechazado').length;final aceptados=filas.where((x)=>x['estado']=='aprobado').length;
    final turnosSnap=await _db.collection('agenda_aseo').where('mes_id',isEqualTo:mes).get();
    final turnos=turnosSnap.docs.map((x){final d=Map<String,dynamic>.from(x.data());d['_doc_id']=x.id;return d;}).toList();
    final asistieron=turnos.where((x)=>(x['estado']??'').toString()=='realizado').length;
    final reemplazosPagados=turnos.where((x)=>(x['estado']??'').toString()=='reemplazo_pagado').length;
    final reemplazosPendientes=turnos.where((x){final e=(x['estado']??'').toString();return e=='reemplazo_pendiente'||e=='reemplazo_comprobante';}).length;
    final noAsistieron=turnos.where((x)=>(x['estado']??'').toString()=='ausente').length;
    return {'filas':filas,'total':filas.length,'enviados':enviados,'no_enviados':filas.length-enviados,'pendientes':pendientes,'rechazados':rechazados,'aceptados':aceptados,'turnos_total':turnos.length,'asistieron':asistieron,'reemplazos_pagados':reemplazosPagados,'reemplazos_pendientes':reemplazosPendientes,'no_asistieron':noAsistieron,'turnos_filas':turnos};
  }

  Future<void> _imprimirEstadisticas(Map<String,dynamic> data) async {
    final doc=pw.Document(); final filas=(data['filas'] as List).cast<Map<String,dynamic>>();
    doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(28),build:(_)=>[
      pw.Text('AUTISMO RANCAGUA',style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)),pw.Text('Informe mensual de útiles de aseo',style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold)),pw.Text(DateFormat('MMMM yyyy','es').format(_mes)),pw.SizedBox(height:12),
      pw.Text('Total: ${data['total']}   Enviaron: ${data['enviados']}   No enviaron: ${data['no_enviados']}   Aceptados: ${data['aceptados']}   Pendientes: ${data['pendientes']}   Rechazados: ${data['rechazados']}'),pw.SizedBox(height:14),
      pw.Table.fromTextArray(headers:['Apoderado','RUT','Estado','Fecha'],data:filas.map((x){final f=x['fecha'] is Timestamp?(x['fecha'] as Timestamp).toDate():null;return [x['nombre'],x['rut'],x['estado']=='no_enviado'?'NO ENVIÓ':_estadoUtil(x['estado'].toString()).toUpperCase(),f==null?'—':DateFormat('dd/MM/yyyy').format(f)];}).toList(),headerStyle:pw.TextStyle(fontWeight:pw.FontWeight.bold),cellStyle:const pw.TextStyle(fontSize:8))
    ]));
    await Printing.layoutPdf(onLayout:(_)=>doc.save(),name:'utiles_aseo_${_mesId(_mes)}.pdf');
  }

  Future<void> _mostrarListaEstadistica(List<Map<String,dynamic>> filas,String titulo) async {
    await showDialog(context:context,builder:(ctx)=>Dialog(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:600,maxHeight:650),child:Column(mainAxisSize:MainAxisSize.min,children:[Padding(padding:const EdgeInsets.fromLTRB(20,20,12,10),child:Row(children:[Expanded(child:Text(titulo,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:Color(0xFF075C91)))),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))])),const Divider(height:1),Flexible(child:filas.isEmpty?const Center(child:Padding(padding:EdgeInsets.all(30),child:Text('No hay registros en esta categoría.'))):ListView.builder(padding:const EdgeInsets.all(12),itemCount:filas.length,itemBuilder:(_,i){final x=filas[i];final e=x['estado'].toString();final c=e=='no_enviado'?Colors.red.shade700:_colorUtil(e);return Card(elevation:0,child:ListTile(leading:Icon(e=='no_enviado'?Icons.close:Icons.inventory_2,color:c),title:Text(x['nombre'].toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('RUT ${x['rut']}'),trailing:Text(e=='no_enviado'?'NO ENVIÓ':_estadoUtil(e),style:TextStyle(color:c,fontWeight:FontWeight.w900))));}))]))));
  }

  Future<void> _mostrarDetalleTurnos(List<Map<String,dynamic>> filas,String titulo) async {
    await showDialog(context:context,builder:(ctx)=>Dialog(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:600,maxHeight:650),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Padding(padding:const EdgeInsets.fromLTRB(20,20,12,10),child:Row(children:[Expanded(child:Text(titulo,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:Color(0xFF075C91)))),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))])),
      const Divider(height:1),
      Flexible(child:filas.isEmpty?const Center(child:Padding(padding:EdgeInsets.all(30),child:Text('No hay registros en esta categoría.'))):ListView.builder(padding:const EdgeInsets.all(12),itemCount:filas.length,itemBuilder:(_,i){
        final x=filas[i];
        final f=x['fecha_aseo'] is Timestamp?(x['fecha_aseo'] as Timestamp).toDate():null;
        final estado=(x['estado']??'asignado').toString();
        String etiqueta;
        IconData icono;
        Color color;
        switch(estado){
          case 'realizado': etiqueta='ASISTIÓ';icono=Icons.cleaning_services;color=const Color(0xFF159B72);break;
          case 'reemplazo_pagado': etiqueta='REEMPLAZO PAGADO';icono=Icons.paid;color=const Color(0xFF159B72);break;
          case 'reemplazo_pendiente': case 'reemplazo_comprobante': etiqueta='REEMPLAZO PENDIENTE';icono=Icons.schedule;color=const Color(0xFFE67E22);break;
          case 'ausente': etiqueta='NO ASISTIÓ';icono=Icons.person_off;color=Colors.red.shade700;break;
          default: etiqueta='ASIGNADO';icono=Icons.calendar_month;color=const Color(0xFF087BB5);
        }
        return Card(elevation:0,child:ListTile(leading:Icon(icono,color:color),title:Text((x['nombre_apoderado']??'Apoderado').toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${f==null?'Fecha no informada':DateFormat('dd/MM/yyyy').format(f)} · RUT ${(x['rut_apoderado']??'no informado')}'),trailing:Text(etiqueta,textAlign:TextAlign.right,style:TextStyle(color:color,fontWeight:FontWeight.w900,fontSize:11))));
      }))
    ]))));
  }

  Widget _estadisticas(){return FutureBuilder<Map<String,dynamic>>(future:_datosEstadisticas(),builder:(context,snap){
    if(!snap.hasData)return const Center(child:CircularProgressIndicator());
    final d=snap.data!,filas=(d['filas'] as List).cast<Map<String,dynamic>>(),turnos=(d['turnos_filas'] as List).cast<Map<String,dynamic>>();
    Widget dato(String t,int n,IconData i,VoidCallback onTap)=>Expanded(child:Card(elevation:0,clipBehavior:Clip.antiAlias,child:InkWell(onTap:onTap,child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[Icon(i,color:const Color(0xFF087BB5)),Text('$n',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),Text(t,textAlign:TextAlign.center,style:const TextStyle(fontSize:12))])))));
    final enviados=filas.where((x)=>x['estado']!='no_enviado').toList();
    final noEnviados=filas.where((x)=>x['estado']=='no_enviado').toList();
    final aceptados=filas.where((x)=>x['estado']=='aprobado').toList();
    final pendientes=filas.where((x)=>x['estado']=='pendiente_revision').toList();
    final rechazados=filas.where((x)=>x['estado']=='rechazado').toList();
    List<Map<String,dynamic>> porEstado(List<String> estados)=>turnos.where((x)=>estados.contains((x['estado']??'').toString())).toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Estadísticas mensuales',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),const SizedBox(height:10),Row(children:[IconButton(onPressed:()=>setState(()=>_mes=DateTime(_mes.year,_mes.month-1)),icon:const Icon(Icons.chevron_left)),Expanded(child:Text(DateFormat('MMMM yyyy','es').format(_mes),textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18))),IconButton(onPressed:()=>setState(()=>_mes=DateTime(_mes.year,_mes.month+1)),icon:const Icon(Icons.chevron_right))]),
      const Text('Cumplimiento de turnos',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),
      Row(children:[dato('Turnos',d['turnos_total'],Icons.calendar_month,()=>_mostrarDetalleTurnos(turnos,'Todos los turnos')),dato('Asistieron',d['asistieron'],Icons.cleaning_services,()=>_mostrarDetalleTurnos(porEstado(['realizado']),'Apoderados que asistieron')),dato('Reemplazos pagados',d['reemplazos_pagados'],Icons.paid,()=>_mostrarDetalleTurnos(porEstado(['reemplazo_pagado']),'Reemplazos pagados'))]),
      Row(children:[dato('Reemplazo pendiente',d['reemplazos_pendientes'],Icons.schedule,()=>_mostrarDetalleTurnos(porEstado(['reemplazo_pendiente','reemplazo_comprobante']),'Reemplazos pendientes')),dato('No asistieron',d['no_asistieron'],Icons.person_off,()=>_mostrarDetalleTurnos(porEstado(['ausente']),'Apoderados que no asistieron')),const Spacer()]),
      const Divider(height:28),const Text('Útiles de aseo',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),
      Row(children:[dato('Total',d['total'],Icons.groups,()=>_mostrarListaEstadistica(filas,'Todos los apoderados')),dato('Enviaron',d['enviados'],Icons.check_circle,()=>_mostrarListaEstadistica(enviados,'Apoderados que enviaron')),dato('No enviaron',d['no_enviados'],Icons.warning_amber,()=>_mostrarListaEstadistica(noEnviados,'Apoderados que no enviaron'))]),
      Row(children:[dato('Aceptados',d['aceptados'],Icons.verified,()=>_mostrarListaEstadistica(aceptados,'Aportes aceptados')),dato('Pendientes',d['pendientes'],Icons.schedule,()=>_mostrarListaEstadistica(pendientes,'Aportes pendientes')),dato('Rechazados',d['rechazados'],Icons.cancel,()=>_mostrarListaEstadistica(rechazados,'Aportes rechazados'))]),
      const SizedBox(height:8),FilledButton.icon(onPressed:()=>_imprimirEstadisticas(d),icon:const Icon(Icons.picture_as_pdf),label:const Text('Imprimir / generar PDF')),const SizedBox(height:12),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>_mostrarListaEstadistica(enviados,'Apoderados que enviaron'),icon:const Icon(Icons.check_circle),label:const Text('Ver quién envió'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>_mostrarListaEstadistica(noEnviados,'Apoderados que no enviaron'),icon:const Icon(Icons.cancel),label:const Text('Ver quién no envió')))])
    ]);
  });}


  @override Widget build(BuildContext context)=>DefaultTabController(length:3,child:Scaffold(backgroundColor:const Color(0xFFF2F9FD),appBar:AppBar(backgroundColor:const Color(0xFF087BB5),foregroundColor:Colors.white,title:const Text('Aseo · Administración',style:TextStyle(fontWeight:FontWeight.w900)),bottom:const TabBar(labelColor:Colors.white,unselectedLabelColor:Colors.white70,indicatorColor:Colors.white,tabs:[Tab(icon:Icon(Icons.calendar_month),text:'Turnos'),Tab(icon:Icon(Icons.inventory_2),text:'Útiles'),Tab(icon:Icon(Icons.bar_chart),text:'Estadísticas')])),body:TabBarView(children:[_agenda(),_utilesPanel(),_estadisticas()])));
}


class _SelectorApoderadosAseo extends StatefulWidget {
  final List<Map<String,dynamic>> listaCompleta;
  final Map<String,Map<String,dynamic>> seleccionInicial;
  final String Function(Map<String,dynamic>) nombre;
  final String Function(Map<String,dynamic>) rut;
  final String Function(String) normal;
  const _SelectorApoderadosAseo({required this.listaCompleta,required this.seleccionInicial,required this.nombre,required this.rut,required this.normal});
  @override State<_SelectorApoderadosAseo> createState()=>_SelectorApoderadosAseoState();
}
class _SelectorApoderadosAseoState extends State<_SelectorApoderadosAseo> {
  final buscar=TextEditingController();
  late final Map<String,Map<String,dynamic>> seleccion;
  @override void initState(){super.initState();seleccion=Map<String,Map<String,dynamic>>.from(widget.seleccionInicial);}
  @override void dispose(){buscar.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final q=widget.normal(buscar.text);
    final lista=widget.listaCompleta.where((d)=>q.isEmpty||widget.normal('${widget.nombre(d)} ${widget.rut(d)}').contains(q)).toList();
    return Padding(padding:EdgeInsets.only(left:16,right:16,top:16,bottom:MediaQuery.viewInsetsOf(context).bottom+16),child:FractionallySizedBox(heightFactor:.76,child:Column(children:[
      const Text('Agregar apoderados',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),
      const SizedBox(height:10),
      TextField(controller:buscar,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar por nombre o RUT',border:OutlineInputBorder())),
      const SizedBox(height:8),
      Expanded(child:lista.isEmpty?const Center(child:Text('No se encontraron apoderados.')):ListView.builder(itemCount:lista.length,itemBuilder:(_,i){final data=lista[i];final key=(data['uid']??data['_id']??widget.rut(data)).toString();return CheckboxListTile(value:seleccion.containsKey(key),title:Text(widget.nombre(data),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('RUT ${widget.rut(data)}'),onChanged:(v)=>setState((){if(v==true)seleccion[key]=data;else seleccion.remove(key);}));})),
      FilledButton.icon(onPressed:()=>Navigator.of(context).pop(Map<String,Map<String,dynamic>>.from(seleccion)),icon:const Icon(Icons.check),label:const Text('Listo'))
    ])));
  }
}
