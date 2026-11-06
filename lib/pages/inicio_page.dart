import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'aseo_apoderado_page.dart';

class InicioPage extends StatelessWidget {
  final VoidCallback? onInicio,onAgenda,onCredencial,onTareas,onComprobante,onDocumentos,onReciclaje,onEventos,onAvisos,onSettings,onLogout,onTesoreria,onMateriales;
  final bool mostrarPanelTesoreria, mostrarMateriales;
  final String tareasPendientes, avisosPendientes;
  const InicioPage({super.key,this.onInicio,this.onAgenda,this.onCredencial,this.onTareas,this.onComprobante,this.onDocumentos,this.onReciclaje,this.onEventos,this.onAvisos,this.onSettings,this.onLogout,this.mostrarPanelTesoreria=false,this.onTesoreria,this.mostrarMateriales=false,this.onMateriales,this.tareasPendientes='0',this.avisosPendientes='0'});

  void _sinFuncion(BuildContext c,String m)=>ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('$m quedará operativo al conectar su módulo.')));
  void _aseo(BuildContext c)=>Navigator.of(c).push(MaterialPageRoute(builder:(_)=>const AseoApoderadoPage()));

  @override Widget build(BuildContext context){
    final email=FirebaseAuth.instance.currentUser?.email??'';
    final raw=email.isEmpty?'Familia':email.split('@').first;
    final nombre=_nombreCorto(raw);
    final modules=<Widget>[
      _Module('Credencial','Credencial discapacidad',Icons.badge_rounded,const Color(0xFF188FE5),const Color(0xFFDCEFFF),onCredencial??()=>_sinFuncion(context,'Credencial')),
      _Module('Apoyo terapéutico','Trabajo y seguimiento',Icons.favorite_rounded,const Color(0xFF00A98F),const Color(0xFFD8F7F0),onTareas??()=>_sinFuncion(context,'Apoyo terapéutico')),
      _Module('Comprobantes','Enviar pagos',Icons.receipt_long_rounded,const Color(0xFFFF557D),const Color(0xFFFFE1E9),onComprobante??()=>_sinFuncion(context,'Comprobantes')),
      _Module('Documentos','Archivos familiares',Icons.folder_rounded,const Color(0xFFFFA800),const Color(0xFFFFE9A9),onDocumentos??()=>_sinFuncion(context,'Documentos')),
      _Module('Reciclaje','Latas y botellas PET',Icons.recycling_rounded,const Color(0xFF13A866),const Color(0xFFD9F5E5),onReciclaje??()=>_sinFuncion(context,'Reciclaje')),
      _Module('Aseo','Turnos y reemplazos',Icons.cleaning_services_rounded,const Color(0xFFFF812D),const Color(0xFFFFE3CC),()=>_aseo(context)),
      _Module('Eventos','Actividades de la Casa',Icons.celebration_rounded,const Color(0xFF7658E8),const Color(0xFFE8E0FF),onEventos??()=>_sinFuncion(context,'Eventos')),
    ];
    return Scaffold(
      backgroundColor:const Color(0xFFF8FCFF),
      body:SafeArea(child:Stack(children:[
        Positioned.fill(child:Image.asset('assets/images/fondo_home.png',fit:BoxFit.cover,alignment:Alignment.topCenter,errorBuilder:(_,__,___)=>const SizedBox.shrink())),
        Positioned.fill(child:Container(color:Colors.white.withOpacity(.34))),
        CustomScrollView(slivers:[
          SliverToBoxAdapter(child:_LogoutOnly(onLogout:onLogout)),
          SliverPadding(padding:const EdgeInsets.fromLTRB(16,0,16,26),sliver:SliverList(delegate:SliverChildListDelegate([
            _Hero(nombre:nombre),
            const SizedBox(height:14),
            _NextActivity(onTap:onAgenda),
            const SizedBox(height:20),
            const Text('Tu espacio',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF073D78))),
            const SizedBox(height:10),
            GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:11,crossAxisSpacing:11,childAspectRatio:1.12,children:modules),
            if(mostrarPanelTesoreria)...[const SizedBox(height:12),_WideAccess('Panel Tesorería',Icons.account_balance_wallet_outlined,onTesoreria)],
            if(mostrarMateriales)...[const SizedBox(height:10),_WideAccess('Materiales terapéuticos',Icons.menu_book_outlined,onMateriales)],
          ])))
        ])
      ])),
    );
  }
  static String _nombreCorto(String s){var n=s.replaceAll(RegExp(r'[._-]+'),' ').trim();if(n.isEmpty)return 'Familia';n=n.split(' ').first;if(n.toLowerCase().startsWith('leandro'))n='Leandro';return '${n[0].toUpperCase()}${n.substring(1)}';}
}

class _LogoutOnly extends StatelessWidget{final VoidCallback? onLogout;const _LogoutOnly({this.onLogout});@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.fromLTRB(0,4,10,0),child:Align(alignment:Alignment.centerRight,child:IconButton(tooltip:'Cerrar sesión',onPressed:onLogout,icon:const Icon(Icons.logout_rounded,color:Color(0xFF0B64A5),size:27))));}

class _Hero extends StatelessWidget{final String nombre;const _Hero({required this.nombre});@override Widget build(BuildContext context)=>Container(height:178,clipBehavior:Clip.antiAlias,decoration:BoxDecoration(borderRadius:BorderRadius.circular(30),boxShadow:[BoxShadow(color:const Color(0xFF075D9E).withOpacity(.16),blurRadius:22,offset:const Offset(0,9))]),child:Stack(fit:StackFit.expand,children:[Image.asset('assets/images/inicio_casa_autismo.png',fit:BoxFit.cover),Container(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.centerLeft,end:Alignment.centerRight,colors:[const Color(0xFF073D78).withOpacity(.72),const Color(0xFF073D78).withOpacity(.16),Colors.transparent]))),Padding(padding:const EdgeInsets.fromLTRB(18,20,130,18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Text('Hola, $nombre',style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900,color:Colors.white,shadows:[Shadow(color:Colors.black26,blurRadius:4)])),const SizedBox(height:6),const Text('Bienvenido a tu espacio familiar',style:TextStyle(fontSize:14,color:Colors.white,fontWeight:FontWeight.w800))]))]));}

class _NextActivity extends StatelessWidget{final VoidCallback? onTap;const _NextActivity({this.onTap});@override Widget build(BuildContext context)=>Material(color:Colors.transparent,child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(25),child:Ink(padding:const EdgeInsets.all(15),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFBDEBFF),Color(0xFFFFDCE9),Color(0xFFFFE9A9)]),borderRadius:BorderRadius.circular(25),border:Border.all(color:Colors.white,width:2),boxShadow:[BoxShadow(color:const Color(0xFF075D9E).withOpacity(.12),blurRadius:18,offset:const Offset(0,7))]),child:Row(children:[Container(width:55,height:55,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18)),child:const Icon(Icons.calendar_month_rounded,color:Color(0xFF7658E8),size:30)),const SizedBox(width:12),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Mis próximos pendientes',style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:Color(0xFF073D78))),SizedBox(height:4),Text('Terapias · copagos · reciclaje · aseo',style:TextStyle(fontSize:12.2,color:Color(0xFF365F7E),fontWeight:FontWeight.w800))])),const Icon(Icons.chevron_right_rounded,color:Color(0xFF7658E8),size:30)]))));}

class _Module extends StatelessWidget{final String title,subtitle;final IconData icon;final Color color,tint;final VoidCallback onTap;const _Module(this.title,this.subtitle,this.icon,this.color,this.tint,this.onTap);@override Widget build(BuildContext context)=>Material(color:Colors.transparent,child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(24),child:Ink(padding:const EdgeInsets.all(13),decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Colors.white,tint]),borderRadius:BorderRadius.circular(24),border:Border.all(color:Colors.white,width:2),boxShadow:[BoxShadow(color:color.withOpacity(.16),blurRadius:15,offset:const Offset(0,7))]),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Container(width:46,height:46,decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(15),boxShadow:[BoxShadow(color:color.withOpacity(.24),blurRadius:9,offset:const Offset(0,4))]),child:Icon(icon,color:Colors.white,size:27)),const SizedBox(height:9),Text(title,maxLines:2,style:const TextStyle(fontSize:14.5,fontWeight:FontWeight.w900,color:Color(0xFF073D78),height:1.03)),const SizedBox(height:4),Text(subtitle,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:10.5,fontWeight:FontWeight.w800,color:color))]))));}
class _WideAccess extends StatelessWidget{final String title;final IconData icon;final VoidCallback? onTap;const _WideAccess(this.title,this.icon,this.onTap);@override Widget build(BuildContext context)=>ListTile(onTap:onTap,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),tileColor:Colors.white,leading:CircleAvatar(backgroundColor:const Color(0xFFE7F4FF),child:Icon(icon,color:const Color(0xFF1687EA))),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF073D78))),trailing:const Icon(Icons.chevron_right_rounded));}
