import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum AyudanteContexto { apoderado, profesional }

class AyudanteAutismoPage extends StatefulWidget {
  final AyudanteContexto contexto;
  const AyudanteAutismoPage({super.key, required this.contexto});
  @override State<AyudanteAutismoPage> createState() => _AyudanteAutismoPageState();
}

class _AyudanteAutismoPageState extends State<AyudanteAutismoPage> {
  final _texto = TextEditingController();
  final _speech = stt.SpeechToText();
  bool _cargando = false, _escuchando = false;
  String _respuesta = '';

  String get _titulo => switch(widget.contexto){AyudanteContexto.apoderado=>'Tu ayudante',AyudanteContexto.profesional=>'Ayudante profesional'};
  String get _bajada => switch(widget.contexto){AyudanteContexto.apoderado=>'Te acompaño con el trabajo en casa y las indicaciones recibidas.',AyudanteContexto.profesional=>'Te ayudo a ordenar antecedentes, resumir reportes y preparar el seguimiento.'};
  String get _ejemplo => switch(widget.contexto){AyudanteContexto.apoderado=>'Ej.: ¿Cómo puedo organizar en casa la actividad que nos indicó la terapeuta?',AyudanteContexto.profesional=>'Ej.: Ayúdame a ordenar los puntos importantes para la próxima sesión.'};
  String get _instruccion => switch(widget.contexto){
    AyudanteContexto.apoderado=>'Eres el ayudante de Autismo Rancagua para apoderados. Responde en español de Chile, claro, cálido y breve. Ayuda a comprender y organizar indicaciones de profesionales y trabajo en casa. No diagnostiques, no reemplaces al equipo profesional y no inventes datos del niño. Si falta información, dilo y pide solo lo necesario. Nunca digas que realizaste cambios en la aplicación.',
    AyudanteContexto.profesional=>'Eres el ayudante de Autismo Rancagua para profesionales. Responde en español de Chile, profesional, claro y breve. Ayuda a ordenar información, resumir reportes aportados por el usuario y preparar seguimientos. No inventes antecedentes clínicos, diagnósticos ni conclusiones. Distingue hechos entregados de sugerencias. Nunca digas que realizaste cambios en la aplicación.'};

  Future<void> _preguntar() async {
    final consulta=_texto.text.trim(); if(consulta.isEmpty||_cargando)return;
    FocusScope.of(context).unfocus(); setState((){_cargando=true;_respuesta='';});
    try{
      final model=FirebaseAI.googleAI().generativeModel(model:'gemini-3.8-flash',systemInstruction:Content.system(_instruccion));
      final result=await model.generateContent([Content.text(consulta)]);
      if(!mounted)return; setState(()=>_respuesta=(result.text??'').trim().isEmpty?'No pude preparar una respuesta. Intenta nuevamente.':result.text!.trim());
    }catch(e){if(mounted)setState(()=>_respuesta='No pude comunicarme con el ayudante en este momento.\n\nDetalle: $e');}
    finally{if(mounted)setState(()=>_cargando=false);}
  }

  Future<void> _voz() async {
    if(_escuchando){await _speech.stop();if(mounted)setState(()=>_escuchando=false);return;}
    final disponible=await _speech.initialize();
    if(!disponible){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No se pudo activar el micrófono. Puedes escribir.')));return;}
    setState(()=>_escuchando=true);
    await _speech.listen(localeId:'es_CL',listenMode:stt.ListenMode.dictation,onResult:(r){if(!mounted)return;setState(()=>_texto.text=r.recognizedWords);if(r.finalResult)setState(()=>_escuchando=false);});
  }

  @override void dispose(){_texto.dispose();_speech.stop();super.dispose();}

  @override Widget build(BuildContext context){
    const azul=Color(0xFF087BB5);
    return Scaffold(backgroundColor:const Color(0xFFF1F9FE),appBar:AppBar(backgroundColor:azul,foregroundColor:Colors.white,title:Text(_titulo,style:const TextStyle(fontWeight:FontWeight.w900))),body:ListView(padding:const EdgeInsets.all(18),children:[
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF087BB5),Color(0xFF19A9C5)]),borderRadius:BorderRadius.circular(26)),child:Row(children:[Container(width:68,height:68,decoration:BoxDecoration(color:Colors.white.withOpacity(.18),shape:BoxShape.circle),child:const Icon(Icons.auto_awesome_rounded,color:Colors.white,size:36)),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(_titulo,style:const TextStyle(color:Colors.white,fontSize:23,fontWeight:FontWeight.w900)),const SizedBox(height:5),Text(_bajada,style:const TextStyle(color:Colors.white,height:1.35,fontWeight:FontWeight.w600))]))])),
      const SizedBox(height:18),
      Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(_ejemplo,style:const TextStyle(color:Color(0xFF58758B),fontWeight:FontWeight.w600)),const SizedBox(height:12),TextField(controller:_texto,minLines:3,maxLines:6,decoration:InputDecoration(hintText:'Escribe o usa el micrófono…',filled:true,fillColor:const Color(0xFFF5FAFD),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide.none),suffixIcon:IconButton(tooltip:_escuchando?'Detener':'Hablar',onPressed:_voz,icon:Icon(_escuchando?Icons.stop_circle_rounded:Icons.mic_rounded,color:_escuchando?Colors.red:azul)))),const SizedBox(height:12),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_cargando?null:_preguntar,icon:_cargando?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.auto_awesome_rounded),label:Text(_cargando?'Preparando…':'Preguntar al ayudante'),style:FilledButton.styleFrom(backgroundColor:azul,padding:const EdgeInsets.symmetric(vertical:14))))]))),
      if(_respuesta.isNotEmpty)...[const SizedBox(height:16),Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24),side:const BorderSide(color:Color(0xFFCDE9F7))),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Row(children:[Icon(Icons.favorite_rounded,color:Color(0xFF159B72)),SizedBox(width:8),Text('Respuesta del ayudante',style:TextStyle(fontWeight:FontWeight.w900,fontSize:17,color:Color(0xFF075C91)))]),const SizedBox(height:12),widget.contexto==AyudanteContexto.profesional?SelectableText(_respuesta,style:const TextStyle(fontSize:15.5,height:1.45)):Text(_respuesta,style:const TextStyle(fontSize:15.5,height:1.45))])))],
    ]));
  }
}
