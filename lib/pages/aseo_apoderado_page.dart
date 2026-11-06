import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'utiles_aseo_page.dart';
import 'reemplazo_aseo_page.dart';

class AseoApoderadoPage extends StatefulWidget {
  const AseoApoderadoPage({super.key});
  @override State<AseoApoderadoPage> createState()=>_AseoApoderadoPageState();
}

class _AseoApoderadoPageState extends State<AseoApoderadoPage>{
  final db=FirebaseFirestore.instance;
  String rutClave='';
  String email='';
  bool principal=false;
  bool cargando=true;

  String _limpioRut(dynamic v)=>(v??'').toString().toUpperCase().replaceAll(RegExp(r'[^0-9K]'),'');
  String _mesId(DateTime d)=>DateFormat('yyyy-MM').format(d);
  String _estado(String e){switch(e){case'realizado':return'Turno realizado';case'ausente':return'No realizado';case'reemplazo_pendiente':return'Reemplazo · pago pendiente';case'reemplazo_comprobante':return'Reemplazo · comprobante enviado';case'reemplazo_pagado':return'Reemplazo pagado';default:return'Turno asignado';}}
  Color _color(String e)=>e=='realizado'||e=='reemplazo_pagado'?const Color(0xFF159B72):e=='ausente'?Colors.red.shade700:const Color(0xFFE67E22);

  @override void initState(){super.initState();_resolverPrincipal();}
  Future<void> _resolverPrincipal() async{
    final u=FirebaseAuth.instance.currentUser;if(u==null){if(mounted)setState(()=>cargando=false);return;}
    email=(u.email??'').toLowerCase().trim();
    final ud=await db.collection('usuarios').doc(u.uid).get();final x=ud.data()??{};
    rutClave=_limpioRut(x['rut']??x['rut_apoderado']??x['rut_normalizado']);
    // La fuente de verdad para Aseo es el apoderado_principal de cada beneficiario.
    // Los apoyos autorizados se excluyen expresamente de este módulo.
    final beneficiarios=await db.collection('ar_beneficiarios').get();
    for(final b in beneficiarios.docs){
      final d=b.data();
      final ap=d['apoderado_principal'] is Map ? Map<String,dynamic>.from(d['apoderado_principal'] as Map) : <String,dynamic>{};
      final ar=_limpioRut(ap['rut']??d['rut_apoderado']);
      final ae=(ap['email']??d['email_apoderado']??'').toString().toLowerCase().trim();
      if((rutClave.isNotEmpty&&ar==rutClave)||(email.isNotEmpty&&ae==email)){
        principal=true;if(rutClave.isEmpty)rutClave=ar;break;
      }
    }
    if(mounted)setState(()=>cargando=false);
  }

  bool _esMio(Map<String,dynamic>x,String uid){
    if((x['uid']??'').toString()==uid)return true;
    if(email.isNotEmpty&&(x['email']??'').toString().toLowerCase().trim()==email)return true;
    final r=_limpioRut(x['rut_clave']??x['rut_apoderado']);return rutClave.isNotEmpty&&r==rutClave;
  }

  @override Widget build(BuildContext context){
    final user=FirebaseAuth.instance.currentUser;
    if(cargando)return Scaffold(appBar:_appBar(),body:const Center(child:CircularProgressIndicator()));
    if(user==null)return Scaffold(appBar:_appBar(),body:const Center(child:Text('Debes iniciar sesión.')));
    return Scaffold(backgroundColor:const Color(0xFFF3FAFD),appBar:_appBar(),body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:db.collection('agenda_aseo').snapshots(),builder:(context,snap){
        final docs=(snap.data?.docs??[]).where((d)=>_esMio(d.data(),user.uid)).toList();
        docs.sort((a,b){final aa=(a.data()['fecha_aseo'] as Timestamp?)?.millisecondsSinceEpoch??0,bb=(b.data()['fecha_aseo'] as Timestamp?)?.millisecondsSinceEpoch??0;return aa.compareTo(bb);});
        final hoy=DateTime.now();QueryDocumentSnapshot<Map<String,dynamic>>? proximo;
        for(final d in docs){final f=(d.data()['fecha_aseo'] as Timestamp?)?.toDate();if(f!=null&&!DateTime(f.year,f.month,f.day).isBefore(DateTime(hoy.year,hoy.month,hoy.day))&&d.data()['estado']!='realizado'){proximo=d;break;}}
        return ListView(padding:const EdgeInsets.all(16),children:[
          ClipRRect(borderRadius:BorderRadius.circular(26),child:Stack(children:[Image.asset('assets/images/aseo_casa_autismo.png',height:190,width:double.infinity,fit:BoxFit.cover),Positioned.fill(child:DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,Colors.black.withOpacity(.65)])))),const Positioned(left:18,right:18,bottom:18,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Tu turno de aseo',style:TextStyle(color:Colors.white,fontSize:27,fontWeight:FontWeight.w900)),Text('Aquí verás solamente tu fecha e indicaciones.',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w600))]))])),
          const SizedBox(height:16),if(proximo==null)_sinTurno()else _turnoCard({...proximo.data(),'_doc_id':proximo.id}),
          const SizedBox(height:14),if(principal)_solicitudCard(),
          if(principal)...[const SizedBox(height:14),Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),child:ListTile(contentPadding:const EdgeInsets.all(14),leading:const CircleAvatar(radius:25,backgroundColor:Color(0xFFE8F6FF),child:Icon(Icons.inventory_2,color:Color(0xFF087BB5))),title:const Text('Aporte de útiles de aseo',style:TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF075C91))),subtitle:const Text('Envía la foto y el detalle de los materiales que entregaste.'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const UtilesAseoPage()))))],
          const SizedBox(height:14),
          Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),child:ListTile(contentPadding:const EdgeInsets.all(14),leading:const CircleAvatar(radius:25,backgroundColor:Color(0xFFEAF7F2),child:Icon(Icons.history,color:Color(0xFF159B72))),title:const Text('Mis registros / Historial',style:TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF075C91))),subtitle:const Text('Abre tus turnos y aportes de útiles cuando quieras revisarlos.'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>AseoHistorialPage(uid:user.uid,email:email,rutClave:rutClave))))),
        ]);
      }));
  }
  AppBar _appBar()=>AppBar(backgroundColor:const Color(0xFF087BB5),foregroundColor:Colors.white,title:const Text('Mi Aseo',style:TextStyle(fontWeight:FontWeight.w900)));
  Widget _sinTurno()=>Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),child:const Padding(padding:EdgeInsets.all(22),child:Column(children:[Icon(Icons.event_available,size:46,color:Color(0xFF159B72)),SizedBox(height:10),Text('No tienes un turno de aseo pendiente',textAlign:TextAlign.center,style:TextStyle(fontSize:19,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),SizedBox(height:6),Text('Cuando la encargada te asigne una fecha, aparecerá aquí automáticamente.',textAlign:TextAlign.center)])));
  Widget _turnoCard(Map<String,dynamic>d){
    final f=(d['fecha_aseo'] as Timestamp?)?.toDate(); final e=(d['estado']??'asignado').toString();
    final ind=(d['indicaciones']??'').toString().trim(); final reemplazo=(d['modalidad']??'').toString()=='reemplazo'||e.startsWith('reemplazo_');
    final pagado=(d['estado_pago_reemplazo']??'').toString()=='pagado'||e=='reemplazo_pagado';
    final comprobante=(d['estado_pago_reemplazo']??'').toString()=='comprobante_enviado'||e=='reemplazo_comprobante';
    final hoy=DateTime.now(); final manana=DateTime(hoy.year,hoy.month,hoy.day).add(const Duration(days:1)); final esManana=f!=null&&DateTime(f.year,f.month,f.day)==manana;
    return Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(esManana&&!reemplazo)Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFFFFF0D9),borderRadius:BorderRadius.circular(14)),child:const Row(children:[Icon(Icons.notifications_active,color:Color(0xFFE67E22)),SizedBox(width:8),Expanded(child:Text('Recuerda: mañana te corresponde el turno de aseo.',style:TextStyle(fontWeight:FontWeight.w900)))])),
      if(esManana&&!reemplazo)const SizedBox(height:14),
      Text(f==null?'Fecha por confirmar':DateFormat("EEEE d 'de' MMMM",'es').format(f),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),const SizedBox(height:8),
      Chip(label:Text(_estado(e)),avatar:Icon(reemplazo?Icons.autorenew:Icons.circle,size:16,color:_color(e))),
      if(reemplazo)...[const Divider(height:28),Text(pagado?'REEMPLAZO PAGADO':comprobante?'COMPROBANTE ENVIADO':'TU TURNO SERÁ CUBIERTO POR REEMPLAZO',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:pagado?const Color(0xFF159B72):const Color(0xFFE67E22))),const SizedBox(height:8),
        if(!pagado&&!comprobante)_datosPagoReemplazo(d,f),
        if(comprobante)const Text('La encargada debe revisar y confirmar tu transferencia.'),
        if(pagado)Text('Pago registrado${(d['medio_pago_reemplazo']??'').toString().isEmpty?'':' · ${d['medio_pago_reemplazo']}'}.'),
      ],
      if(ind.isNotEmpty)...[const Divider(height:28),const Text('INDICACIONES DEL TURNO',style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:Color(0xFF075C91))),const SizedBox(height:8),Text(ind,style:const TextStyle(fontSize:16,height:1.45))]
    ])));
  }

  Widget _datosPagoReemplazo(Map<String,dynamic>d,DateTime? f){
    return FutureBuilder<DocumentSnapshot<Map<String,dynamic>>>(future:db.collection('configuracion').doc('aseo_reemplazos').get(),builder:(context,snap){
      final c=snap.data?.data()??{}; final monto=(d['monto_reemplazo']??c['monto']??10000).toString();
      final banco=(c['banco']??'').toString(),tipo=(c['tipo_cuenta']??'').toString(),numero=(c['numero_cuenta']??'').toString(),titular=(c['titular']??'').toString(),rut=(c['rut']??'').toString();
      return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Valor: \$$monto',style:const TextStyle(fontWeight:FontWeight.w900,fontSize:16)),if(banco.isNotEmpty)Text('Banco: $banco'),if(tipo.isNotEmpty)Text('Cuenta: $tipo'),if(numero.isNotEmpty)Text('N°: $numero'),if(titular.isNotEmpty)Text('Titular: $titular'),if(rut.isNotEmpty)Text('RUT: $rut'),const SizedBox(height:12),
        SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ReemplazoAseoPage(fechaInicial:f,agendaAseoId:(d['_doc_id']??'').toString(),montoInicial:int.tryParse(monto)??10000))),icon:const Icon(Icons.upload_file),label:const Text('ENVIAR COMPROBANTE')))
      ]);
    });
  }

  Widget _solicitudCard(){
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:db.collection('aseo_avisos').where('visible_apoderados',isEqualTo:true).snapshots(),
      builder:(context,snap){
        final docs=(snap.data?.docs??[]).where((d){final x=d.data();final tipo=(x['tipo']??'').toString();return (tipo=='solicitud_utiles'||tipo=='solicitud_utiles_mensual')&&(x['activo']??true)==true&&(x['estado']??'pendiente')!='completada';}).toList();
        docs.sort((a,b){final au=(a.data()['urgente']??false)==true,bu=(b.data()['urgente']??false)==true;if(au!=bu)return au?-1:1;final at=a.data()['creado_en'],bt=b.data()['creado_en'];return (bt is Timestamp?bt.millisecondsSinceEpoch:0).compareTo(at is Timestamp?at.millisecondsSinceEpoch:0);});
        if(docs.isEmpty)return const SizedBox.shrink();
        return Column(children:docs.map((d){final x=d.data();final urgente=(x['urgente']??false)==true;final utiles=(x['utiles_sugeridos'] is List)?List.from(x['utiles_sugeridos']):<dynamic>[];final msg=(x['mensaje']??'').toString().trim();return Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24),side:BorderSide(color:urgente?Colors.red.shade200:const Color(0xFFFFD6A0))),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Icon(urgente?Icons.priority_high:Icons.campaign,color:urgente?Colors.red:const Color(0xFFE67E22)),const SizedBox(width:8),Expanded(child:Text(urgente?'SOLICITUD URGENTE DE ÚTILES':'SOLICITUD DE ÚTILES DE ASEO',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:urgente?Colors.red.shade700:const Color(0xFF075C91))))]),if(msg.isNotEmpty)...[const SizedBox(height:10),Text(msg,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700))],if(utiles.isNotEmpty)...[const SizedBox(height:8),...utiles.map((u)=>Padding(padding:const EdgeInsets.only(bottom:5),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('• ',style:TextStyle(fontWeight:FontWeight.w900)),Expanded(child:Text(u.toString(),style:const TextStyle(fontSize:16)))])))]])));}).toList());
      });
  }

}


class AseoHistorialPage extends StatelessWidget {
  final String uid,email,rutClave;
  const AseoHistorialPage({super.key,required this.uid,required this.email,required this.rutClave});
  String limpio(dynamic v)=>(v??'').toString().toUpperCase().replaceAll(RegExp(r'[^0-9K]'),'');
  bool mio(Map<String,dynamic>x){
    if((x['uid']??'').toString()==uid)return true;
    if(email.isNotEmpty&&(x['email']??'').toString().toLowerCase().trim()==email)return true;
    final r=limpio(x['rut_clave']??x['rut_apoderado']); return rutClave.isNotEmpty&&r==rutClave;
  }
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF3FAFD),
    appBar:AppBar(title:const Text('Mis registros de aseo'),backgroundColor:const Color(0xFF087BB5),foregroundColor:Colors.white),
    body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('agenda_aseo').snapshots(),builder:(context,turnosSnap){
      return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('utiles_aseo').where('uid',isEqualTo:uid).snapshots(),builder:(context,utilesSnap){
        if(turnosSnap.connectionState==ConnectionState.waiting||utilesSnap.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
        final turnos=(turnosSnap.data?.docs??[]).where((d)=>mio(d.data())).toList();
        final utiles=[...(utilesSnap.data?.docs??[])];
        turnos.sort((a,b){final af=a.data()['fecha_aseo'],bf=b.data()['fecha_aseo'];return (bf is Timestamp?bf.millisecondsSinceEpoch:0).compareTo(af is Timestamp?af.millisecondsSinceEpoch:0);});
        utiles.sort((a,b){final af=a.data()['fecha_envio'],bf=b.data()['fecha_envio'];return (bf is Timestamp?bf.millisecondsSinceEpoch:0).compareTo(af is Timestamp?af.millisecondsSinceEpoch:0);});
        if(turnos.isEmpty&&utiles.isEmpty)return const Center(child:Text('Aún no tienes registros de aseo.'));
        return ListView(padding:const EdgeInsets.all(16),children:[
          if(turnos.isNotEmpty)...[const Text('TURNOS DE ASEO',style:TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF075C91),fontSize:18)),const SizedBox(height:8),...turnos.map((d){final x=d.data(),f=x['fecha_aseo'] is Timestamp?(x['fecha_aseo'] as Timestamp).toDate():null;return Card(child:ListTile(leading:const Icon(Icons.cleaning_services,color:Color(0xFF087BB5)),title:Text(f==null?'Fecha no disponible':DateFormat('dd/MM/yyyy').format(f),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Estado: ${x['estado']??'asignado'}')));}),const SizedBox(height:18)],
          if(utiles.isNotEmpty)...[const Text('APORTES DE ÚTILES',style:TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF075C91),fontSize:18)),const SizedBox(height:8),...utiles.map((d){final x=d.data(),f=x['fecha_envio'] is Timestamp?(x['fecha_envio'] as Timestamp).toDate():null,url=(x['foto_url']??'').toString();return Card(child:ListTile(leading:const Icon(Icons.inventory_2,color:Color(0xFF159B72)),title:Text(f==null?'Fecha pendiente':DateFormat('dd/MM/yyyy HH:mm').format(f),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${x['detalle']??''}\nEstado: ${x['estado']??'pendiente_revision'}'),isThreeLine:true,trailing:url.isEmpty?null:const Icon(Icons.image_outlined),onTap:url.isEmpty?null:()=>showDialog(context:context,builder:(_)=>Dialog(child:InteractiveViewer(child:Image.network(url,fit:BoxFit.contain))))));})]
        ]);
      });
    })
  );
}
