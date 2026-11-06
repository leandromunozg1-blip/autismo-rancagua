import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/auditoria_service.dart';

class ReciclajeHomePage extends StatefulWidget {
  const ReciclajeHomePage({super.key});
  @override State<ReciclajeHomePage> createState()=>_ReciclajeHomePageState();
}

class _ReciclajeHomePageState extends State<ReciclajeHomePage>{
  final _db=FirebaseFirestore.instance;
  DateTime _mes=DateTime(DateTime.now().year,DateTime.now().month);

  DateTime get _inicio=>DateTime(_mes.year,_mes.month,1);
  DateTime get _fin=>DateTime(_mes.year,_mes.month+1,1);
  static const _meses=['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  String get _mesNombre=>'${_meses[_mes.month-1]} ${_mes.year}';

  Future<List<QueryDocumentSnapshot<Map<String,dynamic>>>> _enviosMes() async{
    final q=await _db.collection('reciclaje_envios').where('fecha',isGreaterThanOrEqualTo:Timestamp.fromDate(_inicio)).where('fecha',isLessThan:Timestamp.fromDate(_fin)).get();
    final l=q.docs.toList(); l.sort((a,b)=>_fecha(b.data()).compareTo(_fecha(a.data()))); return l;
  }
  DateTime _fecha(Map<String,dynamic>d){final v=d['fecha'];return v is Timestamp?v.toDate():DateTime(2000);}
  String _nombre(Map<String,dynamic>d){final x=(d['apoderadoNombre']??d['nombre_apoderado']??d['nombre']??d['email']??'Apoderado no informado').toString().trim();return x.isEmpty?'Apoderado no informado':x;}
  String _benef(Map<String,dynamic>d){final x=(d['beneficiario']??d['beneficiario_nombre']??d['nombre_beneficiario']??'').toString().trim();return x.isEmpty?'No informado':x;}
  String _estado(Map<String,dynamic>d)=>(d['estado']??'pendiente').toString().toLowerCase();
  bool _esPet(Map<String,dynamic>d)=>(d['material']??'').toString().toLowerCase().contains('pet');

  Future<List<Map<String,dynamic>>> _familiasPrincipales() async{
    final snap=await _db.collection('ar_beneficiarios').get(); final out=<String,Map<String,dynamic>>{};
    String clean(dynamic v)=>(v??'').toString().toLowerCase().trim();
    for(final doc in snap.docs){final b=doc.data();if((b['estado']??'activo').toString().toLowerCase()=='inactivo')continue;final ap=b['apoderado_principal'] is Map?Map<String,dynamic>.from(b['apoderado_principal']):<String,dynamic>{};final email=clean(ap['email']??b['email_apoderado']);final rut=clean(ap['rut']??b['rut_apoderado']).replaceAll('.','');final nombre=(ap['nombre']??b['nombre_apoderado']??'').toString().trim();if(email.isEmpty&&rut.isEmpty)continue;final key=email.isNotEmpty?'e:$email':'r:$rut';final ben=(b['nombre']??b['nombre_beneficiario']??'').toString().trim();out.putIfAbsent(key,()=>{'key':key,'nombre':nombre.isEmpty?'Apoderado principal':nombre,'email':email,'rut':rut,'beneficiarios':<String>[]});if(ben.isNotEmpty)(out[key]!['beneficiarios'] as List<String>).add(ben);}
    final l=out.values.toList();l.sort((a,b)=>a['nombre'].toString().compareTo(b['nombre'].toString()));return l;
  }

  Future<void> _elegirMes() async{final d=await showDatePicker(context:context,initialDate:_mes,firstDate:DateTime(2025),lastDate:DateTime(2035),helpText:'Selecciona un día del mes');if(d!=null)setState(()=>_mes=DateTime(d.year,d.month));}

  Future<void> _verFoto(Map<String,dynamic>d) async{String url=(d['imagen']??'').toString();final path=(d['imagenPath']??'').toString();if(url.isEmpty&&path.isNotEmpty){try{url=await FirebaseStorage.instance.ref().child(path).getDownloadURL();}catch(_){}}if(!mounted)return;if(url.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Este registro no tiene foto disponible.')));return;}showDialog(context:context,builder:(_)=>Dialog(child:InteractiveViewer(child:Image.network(url,webHtmlElementStrategy:WebHtmlElementStrategy.fallback,fit:BoxFit.contain))));}

  Future<void> _cambiarEstado(String id,String estado) async{await _db.collection('reciclaje_envios').doc(id).update({'estado':estado,'fecha_revision':FieldValue.serverTimestamp()});await AuditoriaService.registrar(modulo:'Reciclaje',accion:'Revisar entrega',coleccion:'reciclaje_envios',documentoId:id,detalle:'Estado: $estado');if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Entrega marcada como $estado')));}

  Future<void> _abrirAportes({String inicial='pendiente'}) async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>_AportesPage(inicial:inicial,onEstado:_cambiarEstado,onFoto:_verFoto,nombre:_nombre,benef:_benef)));if(mounted)setState((){});}

  Future<void> _abrirEstadisticas() async{final docs=await _enviosMes();final familias=await _familiasPrincipales();if(!mounted)return;Navigator.push(context,MaterialPageRoute(builder:(_)=>_EstadisticasReciclajePage(mes:_mes,docs:docs,familias:familias,onFoto:_verFoto,nombre:_nombre,benef:_benef)));}

  Future<void> _generarPdfMensual() async{
    final docs=await _enviosMes();final familias=await _familiasPrincipales();
    final aprob=docs.where((x)=>_estado(x.data())=='aprobado').toList();
    Map<String,List<QueryDocumentSnapshot<Map<String,dynamic>>>> por={};
    for(final d in aprob){final x=d.data();final email=(x['email']??'').toString().toLowerCase().trim();final nom=_nombre(x).toLowerCase();final key=email.isNotEmpty?'e:$email':'n:$nom';por.putIfAbsent(key,()=>[]).add(d);}
    final rows=<List<String>>[];
    for(final f in familias){final key=f['key'].toString();var l=por[key]??<QueryDocumentSnapshot<Map<String,dynamic>>>[];if(l.isEmpty){l=aprob.where((d)=>_nombre(d.data()).toLowerCase()==f['nombre'].toString().toLowerCase()).toList();}final lat=l.where((d)=>!_esPet(d.data())).length;final pet=l.where((d)=>_esPet(d.data())).length;rows.add([f['nombre'].toString(),(f['beneficiarios'] as List).join(', '),l.length.toString(),lat.toString(),pet.toString()]);}
    final pdf=pw.Document();final pendientes=docs.where((d)=>_estado(d.data())=='pendiente').length;final rechazados=docs.where((d)=>_estado(d.data())=='rechazado').length;final participantes=rows.where((r)=>int.parse(r[2])>0).length;
    pdf.addPage(pw.MultiPage(build:(_)=>[pw.Text('Autismo Rancagua - Reporte mensual de reciclaje',style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:4),pw.Text(_mesNombre.toUpperCase()),pw.SizedBox(height:10),pw.Text('Aportes aprobados: ${aprob.length}   Familias participantes: $participantes   Sin aporte: ${familias.length-participantes}'),pw.Text('Pendientes: $pendientes   Rechazados: $rechazados'),pw.SizedBox(height:12),pw.Table.fromTextArray(headers:['Apoderado','Beneficiario','Aportes','Latas','PET'],data:rows),pw.SizedBox(height:10),pw.Text('Solo latas de bebidas y botellas plásticas PET. No registra dinero, peso ni deuda.',style:const pw.TextStyle(fontSize:9))]));
    await Printing.sharePdf(bytes:await pdf.save(),filename:'reciclaje_${_mes.year}_${_mes.month.toString().padLeft(2,'0')}_autismo_rancagua.pdf');
  }

  Future<void> _abrirPuntoDialog({DocumentSnapshot? doc}) async{final data=(doc?.data() as Map<String,dynamic>?)??{};final n=TextEditingController(text:data['nombre']?.toString()??'');final dir=TextEditingController(text:data['direccion']?.toString()??'');final comuna=TextEditingController(text:data['comuna']?.toString()??'');final enc=TextEditingController(text:data['encargadoNombre']?.toString()??'');final lat=TextEditingController(text:data['latitud']?.toString()??'');final lng=TextEditingController(text:data['longitud']?.toString()??'');await showDialog(context:context,builder:(_)=>AlertDialog(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(26)),title:Text(doc==null?'Crear punto de reciclaje':'Editar punto de reciclaje'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_campo(n,'Nombre del punto',Icons.home_rounded),_campo(dir,'Dirección / referencia',Icons.location_on_outlined),_campo(comuna,'Comuna',Icons.map_outlined),_campo(enc,'Encargado del punto',Icons.person_outline),_campo(lat,'Latitud (opcional)',Icons.my_location),_campo(lng,'Longitud (opcional)',Icons.my_location),const Text('Las coordenadas pueden quedar vacías ahora. Servirán para ubicar el punto en el mapa.',style:TextStyle(fontSize:12,color:Colors.black54))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:()async{final p={'nombre':n.text.trim(),'direccion':dir.text.trim(),'comuna':comuna.text.trim(),'encargadoNombre':enc.text.trim(),'latitud':double.tryParse(lat.text.replaceAll(',','.')),'longitud':double.tryParse(lng.text.replaceAll(',','.')),'activo':true,'fecha_actualizacion':FieldValue.serverTimestamp()};if(doc==null){final r=await _db.collection('reciclaje_puntos').add({...p,'fecha_creacion':FieldValue.serverTimestamp()});await AuditoriaService.registrar(modulo:'Reciclaje',accion:'Crear punto de reciclaje',coleccion:'reciclaje_puntos',documentoId:r.id,detalle:n.text.trim());}else{await _db.collection('reciclaje_puntos').doc(doc.id).update(p);}if(mounted)Navigator.pop(context);},child:const Text('Guardar'))]));}
  Widget _campo(TextEditingController c,String l,IconData i)=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,decoration:InputDecoration(labelText:l,prefixIcon:Icon(i),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16)))));

  void _abrirPuntos()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>_PuntosPage(onEdit:_abrirPuntoDialog,onAdd:()=>_abrirPuntoDialog())));

  @override Widget build(BuildContext context){return Scaffold(backgroundColor:const Color(0xFFF4FBF5),appBar:AppBar(title:const Text('Reciclaje'),backgroundColor:const Color(0xFF238636),foregroundColor:Colors.white),body:SafeArea(child:FutureBuilder<List<QueryDocumentSnapshot<Map<String,dynamic>>>>(future:_enviosMes(),builder:(context,s){final docs=s.data??[];final pendientes=docs.where((d)=>_estado(d.data())=='pendiente').length;return ListView(padding:const EdgeInsets.fromLTRB(18,18,18,30),children:[ClipRRect(borderRadius:BorderRadius.circular(28),child:Stack(children:[Image.asset('assets/images/reciclaje_ninos_banner.png',height:190,width:double.infinity,fit:BoxFit.cover),Container(height:190,padding:const EdgeInsets.all(22),alignment:Alignment.centerLeft,decoration:BoxDecoration(gradient:LinearGradient(colors:[Colors.white.withOpacity(.94),Colors.white.withOpacity(.55),Colors.transparent])),child:const SizedBox(width:210,child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Juntos por un\nmundo más limpio',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900,color:Color(0xFF176B2C))),SizedBox(height:8),Text('Latas de bebidas y botellas plásticas PET.',style:TextStyle(fontWeight:FontWeight.w700,color:Color(0xFF315B3A)))])))])),const SizedBox(height:16),InkWell(onTap:_elegirMes,borderRadius:BorderRadius.circular(18),child:Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFD8E8DC))),child:Row(children:[const Icon(Icons.calendar_month_rounded,color:Color(0xFF238636)),const SizedBox(width:10),Text(_mesNombre.toUpperCase(),style:const TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF185B2B))),const Spacer(),const Icon(Icons.expand_more)]))),const SizedBox(height:16),GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:14,crossAxisSpacing:14,childAspectRatio:1.22,children:[_menu('Aportes','Este mes',docs.length,Icons.recycling_rounded,const Color(0xFFE5F7E8),const Color(0xFF31B44B),()=>_abrirAportes()),_menu('Pendientes','Por revisar',pendientes,Icons.schedule_rounded,const Color(0xFFFFF3D6),const Color(0xFFF2A313),()=>_abrirAportes(inicial:'pendiente')),_menu('Estadísticas','Resumen mensual',null,Icons.bar_chart_rounded,const Color(0xFFE4F2FF),const Color(0xFF1976D2),_abrirEstadisticas),_menu('Puntos','Puntos de reciclaje',null,Icons.location_on_rounded,const Color(0xFFF1E7FF),const Color(0xFF8E44D8),_abrirPuntos)]),const SizedBox(height:16),InkWell(onTap:_generarPdfMensual,borderRadius:BorderRadius.circular(22),child:Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFFE8F3FF),borderRadius:BorderRadius.circular(22),border:Border.all(color:const Color(0xFF9AC7F2))),child:const Row(children:[CircleAvatar(radius:27,backgroundColor:Colors.white,child:Icon(Icons.picture_as_pdf_rounded,color:Colors.red,size:30)),SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Reporte mensual',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900,color:Color(0xFF145A9C))),SizedBox(height:3),Text('Resumen por familia del mes seleccionado',style:TextStyle(color:Color(0xFF45657E),fontWeight:FontWeight.w600))])),Icon(Icons.chevron_right_rounded,color:Color(0xFF145A9C),size:30)]))),const SizedBox(height:14),const Text('Este módulo no registra dinero, peso ni deuda.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF55745D),fontWeight:FontWeight.w700))]);})));}
  Widget _menu(String t,String sub,int? n,IconData i,Color bg,Color c,VoidCallback tap)=>Material(color:Colors.transparent,child:InkWell(onTap:tap,borderRadius:BorderRadius.circular(24),child:Ink(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(24),border:Border.all(color:c.withOpacity(.25))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Row(children:[CircleAvatar(backgroundColor:Colors.white.withOpacity(.8),child:Icon(i,color:c)),const Spacer(),if(n!=null)Text('$n',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,color:c)),const Icon(Icons.chevron_right_rounded)]),const SizedBox(height:8),Text(t,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),Text(sub,style:const TextStyle(fontSize:12,color:Colors.black54,fontWeight:FontWeight.w600))]))));
}

class _AportesPage extends StatefulWidget{final String inicial;final Future<void>Function(String,String) onEstado;final Future<void>Function(Map<String,dynamic>) onFoto;final String Function(Map<String,dynamic>) nombre,benef;const _AportesPage({required this.inicial,required this.onEstado,required this.onFoto,required this.nombre,required this.benef});@override State<_AportesPage>createState()=>_AportesPageState();}
class _AportesPageState extends State<_AportesPage>{late String filtro;@override void initState(){super.initState();filtro=widget.inicial;}Color c(String e)=>e=='aprobado'?Colors.green:e=='rechazado'?Colors.red:Colors.orange;@override Widget build(BuildContext context){final q=FirebaseFirestore.instance.collection('reciclaje_envios').where('estado',isEqualTo:filtro);return Scaffold(backgroundColor:const Color(0xFFF5FAF6),appBar:AppBar(title:const Text('Aportes'),backgroundColor:const Color(0xFF238636),foregroundColor:Colors.white),body:Column(children:[Padding(padding:const EdgeInsets.all(14),child:SegmentedButton<String>(segments:const [ButtonSegment(value:'pendiente',label:Text('Pendientes')),ButtonSegment(value:'aprobado',label:Text('Aprobadas')),ButtonSegment(value:'rechazado',label:Text('Rechazadas'))],selected:{filtro},onSelectionChanged:(v)=>setState(()=>filtro=v.first))),Expanded(child:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:q.snapshots(),builder:(context,s){final docs=s.data?.docs.toList()??[];docs.sort((a,b){final fa=a.data()['fecha'];final fb=b.data()['fecha'];return (fb is Timestamp?fb.millisecondsSinceEpoch:0).compareTo(fa is Timestamp?fa.millisecondsSinceEpoch:0);});if(docs.isEmpty)return const Center(child:Text('No hay registros para este estado.'));return ListView.builder(padding:const EdgeInsets.fromLTRB(14,0,14,30),itemCount:docs.length,itemBuilder:(_,i){final d=docs[i],x=d.data(),e=(x['estado']??'pendiente').toString(),f=x['fecha'];final fecha=f is Timestamp?DateFormat('dd/MM/yyyy').format(f.toDate()):'';return Card(margin:const EdgeInsets.only(bottom:12),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[CircleAvatar(backgroundColor:c(e).withOpacity(.15),child:Icon(Icons.recycling,color:c(e))),const SizedBox(width:10),Expanded(child:Text(widget.nombre(x),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w900))),Chip(label:Text(e.toUpperCase()),backgroundColor:c(e).withOpacity(.12))]),const SizedBox(height:8),Text('Beneficiario: ${widget.benef(x)}'),Text('Material: ${x['material']??''}'),if(fecha.isNotEmpty)Text('Fecha: $fecha'),if((x['detalle']??'').toString().trim().isNotEmpty)Text('Observación: ${x['detalle']}'),const SizedBox(height:8),Row(children:[OutlinedButton.icon(onPressed:()=>widget.onFoto(x),icon:const Icon(Icons.photo),label:const Text('Ver foto')),const Spacer(),if(e=='pendiente')...[TextButton(onPressed:()async{await widget.onEstado(d.id,'rechazado');},child:const Text('Rechazar')),FilledButton(onPressed:()async{await widget.onEstado(d.id,'aprobado');},child:const Text('Aprobar'))]])])));});}))]));}}

class _EstadisticasReciclajePage extends StatelessWidget {
  final DateTime mes;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final List<Map<String, dynamic>> familias;
  final Future<void> Function(Map<String, dynamic>) onFoto;
  final String Function(Map<String, dynamic>) nombre, benef;

  const _EstadisticasReciclajePage({
    required this.mes,
    required this.docs,
    required this.familias,
    required this.onFoto,
    required this.nombre,
    required this.benef,
  });

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsFamilia(Map<String, dynamic> f) {
    final fe = (f['email'] ?? '').toString().toLowerCase().trim();
    final fn = (f['nombre'] ?? '').toString().toLowerCase().trim();
    return docs.where((d) {
      final x = d.data();
      final em = (x['email'] ?? '').toString().toLowerCase().trim();
      return (fe.isNotEmpty && em == fe) || nombre(x).toLowerCase().trim() == fn;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final aprob = docs.where((d) => (d.data()['estado'] ?? '').toString() == 'aprobado').toList();
    final pend = docs.where((d) => (d.data()['estado'] ?? '').toString() == 'pendiente').length;
    final rech = docs.where((d) => (d.data()['estado'] ?? '').toString() == 'rechazado').length;
    final part = familias.where((f) => _docsFamilia(f).any((d) => (d.data()['estado'] ?? '') == 'aprobado')).length;
    final pet = aprob.where((d) => (d.data()['material'] ?? '').toString().toLowerCase().contains('pet')).length;
    final lat = aprob.length - pet;

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF6),
      appBar: AppBar(title: const Text('Estadísticas'), backgroundColor: const Color(0xFF238636), foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('${_ReciclajeHomePageState._meses[mes.month - 1]} ${mes.year}'.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF176B2C))),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.45,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              _stat('Aportes aprobados', aprob.length, Icons.recycling, Colors.green),
              _stat('Familias participaron', part, Icons.groups, Colors.blue),
              _stat('Latas', lat, Icons.local_drink, Colors.green),
              _stat('Botellas PET', pet, Icons.water_drop, Colors.blue),
              _stat('Pendientes', pend, Icons.schedule, Colors.deepPurple),
              _stat('Rechazados', rech, Icons.cancel, Colors.red),
              _stat('Sin aporte', familias.length - part, Icons.person_off, Colors.grey),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF238636), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ResumenApoderadoReciclajePage(familias: familias, docs: docs, onFoto: onFoto, nombre: nombre))),
              icon: const Icon(Icons.people_alt_rounded),
              label: const Text('Resumen por apoderado', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String t, int n, IconData i, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withOpacity(.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: c.withOpacity(.18))),
        child: Row(children: [CircleAvatar(backgroundColor: c.withOpacity(.14), child: Icon(i, color: c)), const SizedBox(width: 8), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$n', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: c)), Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]))]),
      );
}

class _ResumenApoderadoReciclajePage extends StatefulWidget {
  final List<Map<String, dynamic>> familias;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Future<void> Function(Map<String, dynamic>) onFoto;
  final String Function(Map<String, dynamic>) nombre;

  const _ResumenApoderadoReciclajePage({required this.familias, required this.docs, required this.onFoto, required this.nombre});

  @override
  State<_ResumenApoderadoReciclajePage> createState() => _ResumenApoderadoReciclajePageState();
}

class _ResumenApoderadoReciclajePageState extends State<_ResumenApoderadoReciclajePage> {
  final TextEditingController _buscar = TextEditingController();
  String _query = '';

  @override
  void dispose() { _buscar.dispose(); super.dispose(); }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsFamilia(Map<String, dynamic> f) {
    final fe = (f['email'] ?? '').toString().toLowerCase().trim();
    final fn = (f['nombre'] ?? '').toString().toLowerCase().trim();
    return widget.docs.where((d) {
      final x = d.data();
      final em = (x['email'] ?? '').toString().toLowerCase().trim();
      return (fe.isNotEmpty && em == fe) || widget.nombre(x).toLowerCase().trim() == fn;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final resultados = q.isEmpty ? <Map<String, dynamic>>[] : widget.familias.where((f) {
      final n = (f['nombre'] ?? '').toString().toLowerCase();
      final e = (f['email'] ?? '').toString().toLowerCase();
      final b = ((f['beneficiarios'] as List?) ?? const []).join(' ').toLowerCase();
      return n.contains(q) || e.contains(q) || b.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF6),
      appBar: AppBar(title: const Text('Resumen por apoderado'), backgroundColor: const Color(0xFF238636), foregroundColor: Colors.white),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        TextField(
          controller: _buscar,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(hintText: 'Buscar apoderado o beneficiario', prefixIcon: const Icon(Icons.search), suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () { _buscar.clear(); setState(() => _query = ''); }), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 16),
        if (q.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 50), child: Center(child: Text('Escribe el nombre del apoderado para ver su resumen.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)))),
        if (q.isNotEmpty && resultados.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 50), child: Center(child: Text('No se encontraron coincidencias.'))),
        for (final f in resultados) _familia(context, f, _docsFamilia(f)),
      ])),
    );
  }

  Widget _familia(BuildContext context, Map<String, dynamic> f, List<QueryDocumentSnapshot<Map<String, dynamic>>> all) {
    final aprob = all.where((d) => (d.data()['estado'] ?? '') == 'aprobado').toList();
    final pet = aprob.where((d) => (d.data()['material'] ?? '').toString().toLowerCase().contains('pet')).length;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(backgroundColor: aprob.isEmpty ? Colors.grey.shade200 : Colors.green.shade100, child: Icon(Icons.recycling, color: aprob.isEmpty ? Colors.grey : Colors.green)),
        title: Text(f['nombre'].toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${aprob.length} aportes · Latas ${aprob.length - pet} · PET $pet'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _DetalleFamilia(nombre: f['nombre'].toString(), beneficiarios: ((f['beneficiarios'] as List?) ?? const []).join(', '), docs: all, onFoto: widget.onFoto)),
      ),
    );
  }
}

class _DetalleFamilia extends StatelessWidget {
  final String nombre, beneficiarios;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Future<void> Function(Map<String, dynamic>) onFoto;
  const _DetalleFamilia({required this.nombre, required this.beneficiarios, required this.docs, required this.onFoto});

  String _fechaLarga(DateTime d) { const dias=['lunes','martes','miércoles','jueves','viernes','sábado','domingo']; return '${dias[d.weekday-1]} ${DateFormat('dd/MM/yyyy').format(d)}'; }

  @override
  Widget build(BuildContext context) {
    final l = docs.toList();
    l.sort((a, b) {
      final x = a.data()['fecha'], y = b.data()['fecha'];
      return (y is Timestamp ? y.millisecondsSinceEpoch : 0).compareTo(x is Timestamp ? x.millisecondsSinceEpoch : 0);
    });
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .92,
        builder: (_, c) => ListView(
          controller: c,
          padding: const EdgeInsets.all(20),
          children: [
            Text(nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            if (beneficiarios.isNotEmpty) Text('Beneficiario: $beneficiarios'),
            const SizedBox(height: 14),
            if (l.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('Sin entregas registradas durante este mes.')),
              ),
            for (final d in l)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.recycling, color: Colors.green),
                  title: Text((d.data()['material'] ?? 'Reciclaje').toString()),
                  subtitle: Text(
                    '${d.data()['fecha'] is Timestamp ? _fechaLarga((d.data()['fecha'] as Timestamp).toDate()) : ''}\n'
                    'Estado: ${d.data()['estado'] ?? 'pendiente'}'
                    '${(d.data()['detalle'] ?? '').toString().isNotEmpty ? '\n${d.data()['detalle']}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(icon: const Icon(Icons.photo), onPressed: () => onFoto(d.data())),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PuntosPage extends StatelessWidget {
  final void Function({DocumentSnapshot? doc}) onEdit;
  final VoidCallback onAdd;
  const _PuntosPage({required this.onEdit, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF6),
      appBar: AppBar(
        title: const Text('Puntos de reciclaje'),
        backgroundColor: const Color(0xFF238636),
        foregroundColor: Colors.white,
        actions: [IconButton(onPressed: onAdd, icon: const Icon(Icons.add_location_alt_rounded))],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('reciclaje_puntos').orderBy('nombre').snapshots(),
        builder: (context, s) {
          final d = s.data?.docs ?? [];
          if (d.isEmpty) return const Center(child: Text('Aún no hay puntos registrados.'));
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: d.length,
            itemBuilder: (_, i) {
              final doc = d[i];
              final x = doc.data() as Map<String, dynamic>;
              final comuna = (x['comuna'] ?? '').toString();
              final encargado = (x['encargadoNombre'] ?? '').toString();
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F5E6),
                    child: Icon(Icons.location_on, color: Color(0xFF238636)),
                  ),
                  title: Text((x['nombre'] ?? 'Punto').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${x['direccion'] ?? ''}${comuna.isNotEmpty ? '\n$comuna' : ''}${encargado.isNotEmpty ? '\nEncargado: $encargado' : ''}'),
                  trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => onEdit(doc: doc)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
