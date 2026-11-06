import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'estadisticas_beneficiario_page.dart';

class ReportesGeneralesPage extends StatefulWidget {
  const ReportesGeneralesPage({super.key});
  @override
  State<ReportesGeneralesPage> createState() => _ReportesGeneralesPageState();
}

class _ReportesGeneralesPageState extends State<ReportesGeneralesPage> {
  late Future<_ResumenGeneral> _future;
  @override
  void initState() { super.initState(); _future = _cargarResumen(); }

  Future<int> _count(String c) async => (await FirebaseFirestore.instance.collection(c).get()).docs.length;
  Future<int> _countWhere(String c, String f, dynamic v) async => (await FirebaseFirestore.instance.collection(c).where(f, isEqualTo: v).get()).docs.length;
  Future<num> _sum(String c, List<String> fields) async {
    final snap = await FirebaseFirestore.instance.collection(c).get(); num total = 0;
    for (final d in snap.docs) { final m=d.data(); for (final f in fields) { final v=m[f]; if(v is num){total+=v;break;} if(v is String){final n=num.tryParse(v.replaceAll('.','').replaceAll(',','.'));if(n!=null){total+=n;break;}} } }
    return total;
  }
  Future<_ResumenGeneral> _cargarResumen() async {
    final r=_ResumenGeneral();
    r.beneficiarios=await _count('ar_beneficiarios'); r.apoderados=await _count('ar_apoderados'); r.profesionales=await _count('ar_profesionales');
    r.asignaciones=await _count('ar_asignaciones_mensuales'); r.servicios=await _count('ar_servicios_mensuales');
    r.cobrosPendientes=await _countWhere('tesoreria_apoderados','estado','pendiente'); r.comprobantesPendientes=await _countWhere('tesoreria_comprobantes','estado','pendiente_revision');
    r.reemplazosPendientes=await _countWhere('aseo_reemplazos','estado','pendiente_revision'); r.reciclajePendiente=await _countWhere('reciclaje_envios','estado','pendiente'); r.utilesPendientes=await _countWhere('utiles_aseo','estado','pendiente_revision');
    r.trabajoCasa=await _count('ar_trabajo_casa'); r.bitacoras=await _count('ar_bitacora_casa'); r.atenciones=await _count('atenciones_profesionales'); r.eventos=await _count('tesoreria_eventos'); r.noticias=await _count('noticias_comunicaciones');
    r.totalPagos=await _sum('tesoreria_pagos',['monto','monto_pagado','total']); r.ingresosInstitucionales=await _sum('tesoreria_ingresos_institucionales',['monto','total']); r.eventosPorCobrar=await _sum('tesoreria_evento_cargos',['saldo_pendiente','monto_pendiente','monto']); return r;
  }
  String _dinero(num v){final s=v.round().toString();final b=StringBuffer();for(int i=0;i<s.length;i++){final p=s.length-i;b.write(s[i]);if(p>1&&p%3==1)b.write('.');}return '\$${b.toString()}';}

  String _texto(dynamic v){ if(v==null)return '—'; if(v is Timestamp){final d=v.toDate();return '${d.day.toString().padLeft(2,'0')}-${d.month.toString().padLeft(2,'0')}-${d.year}';} return v.toString(); }
  String _principal(Map<String,dynamic> m){for(final k in ['nombre','nombreCompleto','apoderadoNombre','beneficiarioNombre','profesionalNombre','titulo','descripcion','concepto','email']){final v=m[k];if(v!=null&&v.toString().trim().isNotEmpty)return v.toString();}return 'Registro';}
  String _secundario(Map<String,dynamic> m){final partes=<String>[];for(final k in ['beneficiario','beneficiarioNombre','fecha','estado','tipo','servicio','monto','monto_pagado','total','correo','email']){final v=m[k];if(v!=null&&v.toString().trim().isNotEmpty){final t='${k.replaceAll('_',' ')}: ${_texto(v)}';if(!partes.contains(t))partes.add(t);if(partes.length==3)break;}}return partes.join(' · ');}

  Future<void> _verDetalle(String titulo,String collection,{String? field,dynamic value}) async {
    showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(ctx)=>DraggableScrollableSheet(initialChildSize:.72,minChildSize:.45,maxChildSize:.94,builder:(ctx,scroll)=>Container(
      decoration:const BoxDecoration(color:Color(0xFFF7FAFD),borderRadius:BorderRadius.vertical(top:Radius.circular(28))),
      child:Column(children:[Container(width:45,height:5,margin:const EdgeInsets.only(top:10,bottom:8),decoration:BoxDecoration(color:Colors.black26,borderRadius:BorderRadius.circular(10))),Padding(padding:const EdgeInsets.fromLTRB(20,6,12,12),child:Row(children:[Expanded(child:Text(titulo,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF063E83)))),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))])),Expanded(child:FutureBuilder<QuerySnapshot<Map<String,dynamic>>>(future:field==null?FirebaseFirestore.instance.collection(collection).get():FirebaseFirestore.instance.collection(collection).where(field!,isEqualTo:value).get(),builder:(ctx,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());if(s.hasError)return Padding(padding:const EdgeInsets.all(24),child:Text('No se pudo cargar el detalle: ${s.error}'));final docs=s.data?.docs??[];if(docs.isEmpty)return const Center(child:Text('No hay registros para mostrar.',style:TextStyle(fontSize:17)));return ListView.separated(controller:scroll,padding:const EdgeInsets.fromLTRB(16,4,16,30),itemCount:docs.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(_,i){final m=docs[i].data();final sub=_secundario(m);return Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.05),blurRadius:8)]),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const CircleAvatar(backgroundColor:Color(0xFFE7F2FF),child:Icon(Icons.chevron_right,color:Color(0xFF0B68B7))),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(_principal(m),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),if(sub.isNotEmpty)...[const SizedBox(height:4),Text(sub,style:const TextStyle(color:Colors.black54))]]))]));});}))]),
    )));
  }

  Future<void> _verBeneficiarios() async {
    final snap=await FirebaseFirestore.instance.collection('ar_beneficiarios').get();
    if(!mounted)return;
    showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(ctx)=>DraggableScrollableSheet(initialChildSize:.82,minChildSize:.5,maxChildSize:.95,builder:(ctx,scroll)=>Container(decoration:const BoxDecoration(color:Color(0xFFF7FAFD),borderRadius:BorderRadius.vertical(top:Radius.circular(28))),child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(18,14,8,8),child:Row(children:[const Expanded(child:Text('Beneficiarios',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF063E83)))),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))])),
      const Padding(padding:EdgeInsets.symmetric(horizontal:18),child:Align(alignment:Alignment.centerLeft,child:Text('Selecciona un beneficiario para ver sus estadísticas separadas.'))),const SizedBox(height:8),
      Expanded(child:ListView.separated(controller:scroll,padding:const EdgeInsets.all(14),itemCount:snap.docs.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final d=snap.docs[i],m=d.data();final n=(m['nombre']??m['beneficiario_nombre']??m['nombre_beneficiario']??'Beneficiario').toString();final r=(m['rut']??m['rut_beneficiario']??d.id).toString();return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.child_care)),title:Text(n,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('RUT: $r'),trailing:const Icon(Icons.analytics_rounded),onTap:(){Navigator.pop(ctx);Navigator.push(context,MaterialPageRoute(builder:(_)=>EstadisticasBeneficiarioPage(beneficiarioDocId:d.id,beneficiario:m)));}));}))
    ]))));
  }

  Widget _card(String titulo,String valor,IconData icono,Color color,String collection,{String? field,dynamic value,String? detalle}) => InkWell(
    borderRadius:BorderRadius.circular(22),
    onTap:()=>collection=='ar_beneficiarios'?_verBeneficiarios():_verDetalle(titulo,collection,field:field,value:value),
    child:Container(
      padding:const EdgeInsets.fromLTRB(14,13,14,13),
      decoration:BoxDecoration(
        color:Colors.white,
        borderRadius:BorderRadius.circular(22),
        border:Border.all(color:color.withOpacity(.07)),
        boxShadow:[BoxShadow(color:color.withOpacity(.11),blurRadius:12,offset:const Offset(0,4))],
      ),
      child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Row(children:[
            CircleAvatar(radius:19,backgroundColor:color.withOpacity(.12),foregroundColor:color,child:Icon(icono,size:21)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,color:color,size:26),
          ]),
          const Spacer(),
          FittedBox(
            fit:BoxFit.scaleDown,
            alignment:Alignment.centerLeft,
            child:Text(valor,style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,color:color)),
          ),
          const SizedBox(height:3),
          Text(titulo,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13.5,height:1.12)),
          if(detalle!=null)...[
            const SizedBox(height:2),
            Text(detalle,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Colors.black45)),
          ],
        ],
      ),
    ),
  );

  Widget _seccion(String titulo,List<Widget> cards)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,
    children:[
      const SizedBox(height:22),
      Text(titulo,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:Color(0xFF063E83))),
      const SizedBox(height:10),
      GridView.count(
        crossAxisCount:2,
        shrinkWrap:true,
        physics:const NeverScrollableScrollPhysics(),
        crossAxisSpacing:12,
        mainAxisSpacing:12,
        childAspectRatio:1.05,
        children:cards,
      ),
    ],
  );

  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(backgroundColor:const Color(0xFF0047B3),foregroundColor:Colors.white,centerTitle:true,title:const Text('Dashboard General',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:()=>setState(()=>_future=_cargarResumen()),icon:const Icon(Icons.refresh))]),backgroundColor:const Color(0xFFEAF6FF),body:FutureBuilder<_ResumenGeneral>(future:_future,builder:(context,snap){if(snap.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());if(snap.hasError)return Center(child:Text('No se pudo cargar el resumen: ${snap.error}'));final r=snap.data!;return ListView(padding:const EdgeInsets.all(16),children:[Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(22)),child:const Row(children:[Icon(Icons.touch_app,color:Color(0xFF0B68B7)),SizedBox(width:10),Expanded(child:Text('Toca cualquier tarjeta para ver quiénes y qué registros forman ese número.',style:TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF46627A))))])),
    _seccion('Personas y atención',[_card('Beneficiarios','${r.beneficiarios}',Icons.child_care,Colors.blue,'ar_beneficiarios'),_card('Apoderados','${r.apoderados}',Icons.groups,Colors.teal,'ar_apoderados'),_card('Profesionales','${r.profesionales}',Icons.psychology_alt,Colors.deepPurple,'ar_profesionales'),_card('Asignaciones activas','${r.asignaciones}',Icons.link,Colors.indigo,'ar_asignaciones_mensuales'),_card('Servicios / talleres','${r.servicios}',Icons.medical_services,Colors.cyan,'ar_servicios_mensuales'),_card('Atenciones registradas','${r.atenciones}',Icons.fact_check,Colors.green,'atenciones_profesionales')]),
    _seccion('Pendientes operativos',[_card('Cobros pendientes','${r.cobrosPendientes}',Icons.account_balance_wallet,Colors.orange,'tesoreria_apoderados',field:'estado',value:'pendiente'),_card('Comprobantes pendientes','${r.comprobantesPendientes}',Icons.receipt_long,Colors.red,'tesoreria_comprobantes',field:'estado',value:'pendiente_revision'),_card('Reemplazos aseo','${r.reemplazosPendientes}',Icons.cleaning_services,Colors.brown,'aseo_reemplazos',field:'estado',value:'pendiente_revision'),_card('Reciclaje pendiente','${r.reciclajePendiente}',Icons.recycling,Colors.green,'reciclaje_envios',field:'estado',value:'pendiente'),_card('Útiles aseo','${r.utilesPendientes}',Icons.inventory_2,Colors.blueGrey,'utiles_aseo',field:'estado',value:'pendiente_revision')]),
    _seccion('Trabajo terapéutico',[_card('Trabajo en casa','${r.trabajoCasa}',Icons.home_work,Colors.pink,'ar_trabajo_casa'),_card('Bitácoras','${r.bitacoras}',Icons.fact_check,Colors.purple,'ar_bitacora_casa')]),
    _seccion('Finanzas',[_card('Pagos registrados',_dinero(r.totalPagos),Icons.payments,Colors.green,'tesoreria_pagos'),_card('Ingresos institucionales',_dinero(r.ingresosInstitucionales),Icons.account_balance,Colors.blue,'tesoreria_ingresos_institucionales'),_card('Eventos por cobrar',_dinero(r.eventosPorCobrar),Icons.event_available,Colors.deepOrange,'tesoreria_evento_cargos'),_card('Eventos creados','${r.eventos}',Icons.event,Colors.deepPurple,'tesoreria_eventos')]),
    _seccion('Comunicaciones',[_card('Noticias / avisos','${r.noticias}',Icons.campaign,Colors.indigo,'noticias_comunicaciones')]),const SizedBox(height:30)]); }));
}

class _ResumenGeneral {int beneficiarios=0,apoderados=0,profesionales=0,asignaciones=0,servicios=0,cobrosPendientes=0,comprobantesPendientes=0,reemplazosPendientes=0,reciclajePendiente=0,utilesPendientes=0,trabajoCasa=0,bitacoras=0,atenciones=0,eventos=0,noticias=0;num totalPagos=0,ingresosInstitucionales=0,eventosPorCobrar=0;}
