import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class ConfiguracionCredencialPage extends StatefulWidget {
  const ConfiguracionCredencialPage({super.key});
  @override State<ConfiguracionCredencialPage> createState() => _ConfiguracionCredencialPageState();
}

class _ConfiguracionCredencialPageState extends State<ConfiguracionCredencialPage> {
  final ImagePicker _picker = ImagePicker();
  String? _credencialBase64;
  String? _pdfUrl;
  Uint8List? _pdfPendiente;
  String? _pdfNombre;
  bool _cargando = true, _guardando = false;

  @override void initState(){ super.initState(); _cargar(); }

  Future<void> _cargar() async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null){ if(mounted)setState(()=>_cargando=false); return; }
    final doc=await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
    final d=doc.data(); if(!mounted)return;
    setState((){ _credencialBase64=d?['credencial_digital'] as String?; _pdfUrl=d?['credencial_pdf_url'] as String?; _pdfNombre=d?['credencial_pdf_nombre'] as String?; _cargando=false; });
  }

  Future<void> _foto(ImageSource source) async {
    final f=await _picker.pickImage(source:kIsWeb?ImageSource.gallery:source,imageQuality:80,maxWidth:1800);
    if(f==null)return; final b=await f.readAsBytes(); if(!mounted)return;
    setState((){_credencialBase64=base64Encode(b);_pdfPendiente=null;_pdfUrl=null;_pdfNombre=null;});
  }

  Future<void> _pdf() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['pdf'],withData:true);
    if(r==null||r.files.isEmpty)return; final f=r.files.single;
    if(f.bytes==null)return;
    if(!mounted)return; setState((){_pdfPendiente=f.bytes;_pdfNombre=f.name;_credencialBase64=null;});
  }

  void _verImagenCompleta() {
    if (_credencialBase64 == null) return;
    final bytes = base64Decode(_credencialBase64!);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mi credencial', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(80),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    )));
  }

  Future<void> _verPdf() async {
    if(_pdfUrl==null)return; final u=Uri.tryParse(_pdfUrl!);
    if(u!=null && !await launchUrl(u,mode:LaunchMode.externalApplication) && mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No se pudo abrir el PDF.')));}
  }

  Future<void> _guardar() async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null)return;
    if(_credencialBase64==null && _pdfPendiente==null && _pdfUrl==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Carga la credencial en PDF, foto o imagen.')));return;}
    setState(()=>_guardando=true);
    try{
      String? url=_pdfUrl;
      if(_pdfPendiente!=null){
        final ref=FirebaseStorage.instance.ref('credenciales/${user.uid}/credencial_discapacidad.pdf');
        await ref.putData(_pdfPendiente!,SettableMetadata(contentType:'application/pdf'));
        url=await ref.getDownloadURL();
      }
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
        'credencial_digital':_credencialBase64,
        'credencial_pdf_url':url,
        'credencial_pdf_nombre':url!=null?(_pdfNombre??'credencial_discapacidad.pdf'):null,
        'fecha_actualizacion_credencial':FieldValue.serverTimestamp(),
        'email':user.email,
      },SetOptions(merge:true));
      if(!mounted)return; setState((){_pdfUrl=url;_pdfPendiente=null;_guardando=false;});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Credencial guardada correctamente.')));
    }catch(e){if(mounted){setState(()=>_guardando=false);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo guardar: $e')));}}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF6FBFF),
    appBar:AppBar(title:const Text('Mi credencial',style:TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF073D78))),backgroundColor:Colors.transparent,elevation:0,foregroundColor:const Color(0xFF0B64A5)),
    body:_cargando?const Center(child:CircularProgressIndicator()):SingleChildScrollView(padding:const EdgeInsets.fromLTRB(20,8,20,28),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFDDF2FF),Color(0xFFFFE7F0),Color(0xFFFFF0BF)]),borderRadius:BorderRadius.circular(28),border:Border.all(color:Colors.white,width:2)),child:const Column(children:[Icon(Icons.badge_rounded,size:50,color:Color(0xFF1687EA)),SizedBox(height:8),Text('Credencial de discapacidad',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Color(0xFF073D78))),SizedBox(height:6),Text('Guárdala aquí para tenerla disponible rápidamente desde la app.',textAlign:TextAlign.center,style:TextStyle(fontSize:14,height:1.35,color:Color(0xFF557086),fontWeight:FontWeight.w600))])),
      const SizedBox(height:16),
      Container(height:250,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(24),border:Border.all(color:const Color(0xFFD6E8F5)),boxShadow:[BoxShadow(color:Colors.blue.withOpacity(.08),blurRadius:16,offset:const Offset(0,7))]),child:_credencialBase64!=null?InkWell(onTap:_verImagenCompleta,borderRadius:BorderRadius.circular(24),child:Stack(fit:StackFit.expand,children:[ClipRRect(borderRadius:BorderRadius.circular(24),child:Image.memory(base64Decode(_credencialBase64!),fit:BoxFit.contain)),Positioned(right:12,bottom:12,child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),decoration:BoxDecoration(color:Colors.black.withOpacity(.58),borderRadius:BorderRadius.circular(14)),child:const Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.zoom_in_rounded,color:Colors.white,size:19),SizedBox(width:5),Text('Tocar para ampliar',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:12))])))])):_pdfPendiente!=null||_pdfUrl!=null?Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.picture_as_pdf_rounded,size:68,color:Color(0xFFE74C5B)),const SizedBox(height:12),Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Text(_pdfNombre??'Credencial de discapacidad.pdf',textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF073D78)))),if(_pdfUrl!=null)...[const SizedBox(height:12),TextButton.icon(onPressed:_verPdf,icon:const Icon(Icons.visibility_rounded),label:const Text('Ver PDF'))]]) : const Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.add_card_rounded,size:66,color:Color(0xFF7AA9CA)),SizedBox(height:12),Text('Aún no hay una credencial cargada',style:TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF557086)))])),
      const SizedBox(height:16),
      ElevatedButton.icon(onPressed:_pdf,icon:const Icon(Icons.picture_as_pdf_rounded),label:const Text('Cargar PDF'),style:_primary(const Color(0xFF1687EA))),
      const SizedBox(height:10),
      OutlinedButton.icon(onPressed:()=>_foto(ImageSource.camera),icon:const Icon(Icons.camera_alt_rounded),label:const Text('Tomar fotografía'),style:_outline()),
      const SizedBox(height:10),
      OutlinedButton.icon(onPressed:()=>_foto(ImageSource.gallery),icon:const Icon(Icons.photo_library_rounded),label:const Text('Elegir imagen'),style:_outline()),
      const SizedBox(height:18),
      ElevatedButton.icon(onPressed:_guardando?null:_guardar,icon:_guardando?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.cloud_done_rounded),label:Text(_guardando?'Guardando...':'Guardar credencial'),style:_primary(const Color(0xFF073D78))),
    ])));

  ButtonStyle _primary(Color c)=>ElevatedButton.styleFrom(backgroundColor:c,foregroundColor:Colors.white,padding:const EdgeInsets.symmetric(vertical:16),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),textStyle:const TextStyle(fontSize:15,fontWeight:FontWeight.w900));
  ButtonStyle _outline()=>OutlinedButton.styleFrom(foregroundColor:const Color(0xFF0B64A5),side:const BorderSide(color:Color(0xFF9CCCEB),width:1.4),padding:const EdgeInsets.symmetric(vertical:15),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),textStyle:const TextStyle(fontWeight:FontWeight.w800));
}
