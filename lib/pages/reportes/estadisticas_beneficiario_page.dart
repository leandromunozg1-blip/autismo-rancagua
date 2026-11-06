import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class EstadisticasBeneficiarioPage extends StatefulWidget {
  final String beneficiarioDocId;
  final Map<String,dynamic> beneficiario;
  const EstadisticasBeneficiarioPage({super.key,required this.beneficiarioDocId,required this.beneficiario});
  @override State<EstadisticasBeneficiarioPage> createState()=>_EstadisticasBeneficiarioPageState();
}

class _EstadisticasBeneficiarioPageState extends State<EstadisticasBeneficiarioPage>{
  late DateTime desde,hasta; late Future<List<_Grupo>> future;
  String get nombre=>(widget.beneficiario['nombre']??widget.beneficiario['beneficiario_nombre']??widget.beneficiario['nombre_beneficiario']??'Beneficiario').toString();
  String get rut=>(widget.beneficiario['rut']??widget.beneficiario['rut_beneficiario']??widget.beneficiarioDocId).toString();
  @override void initState(){super.initState();final n=DateTime.now();desde=DateTime(n.year,n.month,1);hasta=DateTime(n.year,n.month+1,0,23,59,59);future=_cargar();}
  String norm(dynamic v)=>v?.toString().trim().toLowerCase()??'';
  DateTime? fecha(Map<String,dynamic> m){for(final k in ['fecha','fecha_envio','fecha_aseo','fecha_pago','fecha_creacion','creado_en','createdAt','fecha_asignacion']){final v=m[k];if(v is Timestamp)return v.toDate();if(v is DateTime)return v;if(v is String){final d=DateTime.tryParse(v);if(d!=null)return d;}}return null;}
  bool esBenef(Map<String,dynamic> m){final ids={norm(widget.beneficiarioDocId),norm(rut),norm(nombre)}..remove('');for(final k in ['beneficiario_id','rut_beneficiario','beneficiario_rut','beneficiario','beneficiario_nombre','nombre_beneficiario','usuario_id','rut_usuario','nombre_usuario']){if(ids.contains(norm(m[k])))return true;}return false;}
  bool periodo(Map<String,dynamic> m){final f=fecha(m);return f==null?false:!f.isBefore(desde)&&!f.isAfter(hasta);}
  Future<List<Map<String,dynamic>>> docs(String c)async{try{final s=await FirebaseFirestore.instance.collection(c).get();return s.docs.map((d)=>{'_id':d.id,...d.data()}).where((m)=>esBenef(m)&&periodo(m)).toList();}catch(_){return [];}}
  Future<List<_Grupo>> _cargar()async{
    final at=await docs('atenciones_profesionales');
    final bit=await docs('ar_bitacora_casa');
    final rec=await docs('reciclaje_envios');
    final aseo=await docs('agenda_aseo');
    final utiles=await docs('utiles_aseo');
    final pagos=await docs('tesoreria_pagos');
    final cargos=await docs('tesoreria_movimientos');
    int asist=at.where((m){final a=norm(m['asistencia']);return a.contains('asist')&&!a.contains('no ');}).length;
    int aus=at.where((m){final a=norm(m['asistencia']);return a.contains('aus')||a.contains('no asist')||a.contains('inasist');}).length;
    int just=at.where((m)=>norm(m['asistencia']).contains('just')).length;
    int aprobRec=rec.where((m)=>norm(m['estado'])=='aprobado').length;
    int cumplAseo=aseo.where((m){final e=norm(m['estado']);return e.contains('realiz')||e.contains('cumpl')||e.contains('complet');}).length;
    int aprobUtil=utiles.where((m){final e=norm(m['estado']);return e.contains('aprob')||e.contains('recibid')||e.contains('entreg');}).length;
    num totalPagos=0;for(final m in pagos){final v=m['monto'];if(v is num)totalPagos+=v;}
    return [
      _Grupo('Terapias',Icons.medical_services_rounded,Colors.indigo,at,'${at.length} registradas',at.isEmpty?null:((asist/at.length)*100),['Asistió: $asist','Ausencias: $aus','Justificadas: $just']),
      _Grupo('Reportes / bitácora',Icons.assignment_rounded,Colors.purple,bit,'${bit.length} registros',null,['Enviados por familia y profesionales']),
      _Grupo('Reciclaje / latas',Icons.recycling_rounded,Colors.green,rec,'${rec.length} entregas',rec.isEmpty?null:(aprobRec/rec.length*100),['Aprobadas: $aprobRec','Pendientes/rechazadas: ${rec.length-aprobRec}']),
      _Grupo('Aseo',Icons.cleaning_services_rounded,Colors.teal,aseo,'${aseo.length} asignaciones',aseo.isEmpty?null:(cumplAseo/aseo.length*100),['Cumplidas: $cumplAseo','Otras: ${aseo.length-cumplAseo}']),
      _Grupo('Útiles de aseo',Icons.inventory_2_rounded,Colors.orange,utiles,'${utiles.length} envíos',utiles.isEmpty?null:(aprobUtil/utiles.length*100),['Aprobados/recibidos: $aprobUtil']),
      _Grupo('Tesorería',Icons.account_balance_wallet_rounded,Colors.blue,pagos,'${pagos.length} pagos',null,['Pagado en período: ${dinero(totalPagos)}','Movimientos asociados: ${cargos.length}']),
    ];
  }
  String dinero(num v){final s=v.round().toString();return '\$${s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>'.')}';}
  String f(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  Future<void> elegir(bool inicio)async{final actual=inicio?desde:hasta;final d=await showDatePicker(context:context,initialDate:actual,firstDate:DateTime(2020),lastDate:DateTime(2035));if(d==null)return;setState((){if(inicio)desde=DateTime(d.year,d.month,d.day);else hasta=DateTime(d.year,d.month,d.day,23,59,59);future=_cargar();});}
  void mesActual(){final n=DateTime.now();setState((){desde=DateTime(n.year,n.month,1);hasta=DateTime(n.year,n.month+1,0,23,59,59);future=_cargar();});}
  void anioActual(){final n=DateTime.now();setState((){desde=DateTime(n.year,1,1);hasta=DateTime(n.year,12,31,23,59,59);future=_cargar();});}
  String detalle(Map<String,dynamic> m){final p=<String>[];for(final k in ['fecha','fecha_envio','fecha_aseo','terapia','profesional_nombre','asistencia','estado','material','detalle','objetivo','observacion','monto']){final v=m[k];if(v==null||v.toString().trim().isEmpty)continue;if(v is Timestamp){p.add('${k.replaceAll('_',' ')}: ${f(v.toDate())}');}else{p.add('${k.replaceAll('_',' ')}: $v');}if(p.length>=5)break;}return p.join('\n');}
  List<DateTime> mesesPeriodo(){
    final out=<DateTime>[];
    var m=DateTime(desde.year,desde.month,1);
    final fin=DateTime(hasta.year,hasta.month,1);
    while(!m.isAfter(fin) && out.length<24){out.add(m);m=DateTime(m.year,m.month+1,1);}
    return out;
  }
  String mesCorto(int m)=>const ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][m-1];
  Map<String,int> conteoMensual(_Grupo g){
    final r=<String,int>{};
    for(final m in mesesPeriodo())r['${m.year}-${m.month}']=0;
    for(final x in g.items){final d=fecha(x);if(d!=null){final k='${d.year}-${d.month}';if(r.containsKey(k))r[k]=r[k]!+1;}}
    return r;
  }
  Widget graficoMensual(_Grupo g){
    final meses=mesesPeriodo(); if(meses.isEmpty)return const SizedBox.shrink();
    final c=conteoMensual(g); final max=c.values.fold<int>(0,(a,b)=>b>a?b:a);
    return Padding(padding:const EdgeInsets.only(top:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Evolución mensual',style:TextStyle(fontSize:12,fontWeight:FontWeight.w800,color:Colors.black54)),
      const SizedBox(height:7),
      SizedBox(height:76,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:meses.map((m){final v=c['${m.year}-${m.month}']??0;final h=max==0?4.0:8.0+(48.0*v/max);return Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:2),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[Text('$v',style:const TextStyle(fontSize:9,fontWeight:FontWeight.bold)),Container(height:h,decoration:BoxDecoration(color:g.color.withOpacity(.72),borderRadius:BorderRadius.circular(4))),const SizedBox(height:3),Text(mesCorto(m.month),style:const TextStyle(fontSize:8))])));}).toList()))
    ]));
  }
  Future<void> imprimirEstadisticas(List<_Grupo> grupos,{required bool detallado})async{
    final pdf=pw.Document();
    final meses=mesesPeriodo();
    pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(28),build:(ctx)=>[
      pw.Text('Autismo Rancagua',style:pw.TextStyle(fontSize:12,fontWeight:pw.FontWeight.bold,color:PdfColors.blue800)),
      pw.SizedBox(height:4),pw.Text('Estadísticas del beneficiario',style:pw.TextStyle(fontSize:22,fontWeight:pw.FontWeight.bold)),
      pw.Text(nombre,style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold)),
      pw.Text('RUT: $rut'),pw.Text('Período: ${f(desde)} al ${f(hasta)}'),pw.SizedBox(height:16),
      ...grupos.expand((g){final c=conteoMensual(g);final max=c.values.fold<int>(0,(a,b)=>b>a?b:a);return <pw.Widget>[
        pw.Container(margin:const pw.EdgeInsets.only(bottom:8),padding:const pw.EdgeInsets.all(10),decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey300),borderRadius:pw.BorderRadius.circular(6)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
          pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text(g.titulo,style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),if(g.porcentaje!=null)pw.Text('${g.porcentaje!.round()}%',style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold,color:PdfColors.blue700))]),
          pw.Text(g.resumen),...g.lineas.map((x)=>pw.Text(x,style:const pw.TextStyle(fontSize:9,color:PdfColors.grey700))),pw.SizedBox(height:7),
          pw.Text('Evolución mensual',style:pw.TextStyle(fontSize:9,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:4),
          pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.end,children:meses.map((m){final v=c['${m.year}-${m.month}']??0;final h=max==0?3.0:6.0+(30.0*v/max);return pw.Expanded(child:pw.Column(mainAxisAlignment:pw.MainAxisAlignment.end,children:[pw.Text('$v',style:const pw.TextStyle(fontSize:7)),pw.Container(height:h,margin:const pw.EdgeInsets.symmetric(horizontal:2),color:PdfColors.blue300),pw.Text(mesCorto(m.month),style:const pw.TextStyle(fontSize:6))]));}).toList())
        ])),
        if(detallado && g.items.isNotEmpty)...[pw.Text('Detalle ${g.titulo}',style:pw.TextStyle(fontSize:11,fontWeight:pw.FontWeight.bold)),...g.items.map((m)=>pw.Container(margin:const pw.EdgeInsets.only(bottom:4),padding:const pw.EdgeInsets.all(5),color:PdfColors.grey100,child:pw.Text(detalle(m).isEmpty?'Registro':detalle(m),style:const pw.TextStyle(fontSize:8)))),pw.SizedBox(height:8)]
      ];}),
      pw.SizedBox(height:8),pw.Text('Informe generado desde datos registrados en la plataforma.',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey600))
    ]));
    await Printing.layoutPdf(onLayout:(_)=>pdf.save(),name:'estadisticas_${nombre.replaceAll(' ','_')}_${desde.year}.pdf');
  }
  Future<void> menuPdf()async{
    final grupos=await future;if(!mounted)return;
    showModalBottomSheet(context:context,builder:(ctx)=>SafeArea(child:Wrap(children:[
      const ListTile(title:Text('Imprimir / PDF',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('Usará el período que estás viendo en pantalla.')),
      ListTile(leading:const Icon(Icons.summarize_rounded),title:const Text('Informe resumido'),subtitle:const Text('Indicadores y gráficos mensuales'),onTap:(){Navigator.pop(ctx);imprimirEstadisticas(grupos,detallado:false);}),
      ListTile(leading:const Icon(Icons.description_rounded),title:const Text('Informe detallado'),subtitle:const Text('Indicadores, gráficos y todos los registros'),onTap:(){Navigator.pop(ctx);imprimirEstadisticas(grupos,detallado:true);}),
    ])));
  }
  void abrir(_Grupo g){showModalBottomSheet(context:context,isScrollControlled:true,builder:(ctx)=>DraggableScrollableSheet(expand:false,initialChildSize:.78,maxChildSize:.95,builder:(ctx,sc)=>Column(children:[ListTile(title:Text(g.titulo,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),subtitle:Text('${f(desde)} al ${f(hasta)}'),trailing:IconButton(icon:const Icon(Icons.close),onPressed:()=>Navigator.pop(ctx))),const Divider(height:1),Expanded(child:g.items.isEmpty?const Center(child:Text('No hay registros en este período.')):ListView.separated(controller:sc,padding:const EdgeInsets.all(14),itemCount:g.items.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final m=g.items[i];return Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(detalle(m).isEmpty?'Registro ${i+1}':detalle(m))));}))])));}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8FF),
      appBar: AppBar(
        title: const Text('Estadísticas del beneficiario'),
        backgroundColor: const Color(0xFF064DA8),
        foregroundColor: Colors.white,
        actions: [IconButton(tooltip: 'Imprimir / PDF', icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: menuPdf)],
      ),
      body: FutureBuilder<List<_Grupo>>(
        future: future,
        builder: (context, s) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      if (rut.isNotEmpty) Text('RUT: $rut'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(label: Text('Desde ${f(desde)}'), avatar: const Icon(Icons.calendar_month, size: 18), onPressed: () => elegir(true)),
                          ActionChip(label: Text('Hasta ${f(hasta)}'), avatar: const Icon(Icons.event, size: 18), onPressed: () => elegir(false)),
                          ActionChip(label: const Text('Este mes'), onPressed: mesActual),
                          ActionChip(label: const Text('Este año'), onPressed: anioActual),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Cada estadística es independiente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
              const Text('Toca una tarjeta para ver todos los registros que forman su resultado.'),
              const SizedBox(height: 12),
              if (s.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (s.hasError)
                Text('No se pudieron cargar las estadísticas: ${s.error}')
              else
                ...s.data!.map(
                  (g) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => abrir(g),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            CircleAvatar(backgroundColor: g.color.withOpacity(.12), child: Icon(g.icon, color: g.color)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(g.titulo, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                                      if (g.porcentaje != null)
                                        Text('${g.porcentaje!.round()}%', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: g.color)),
                                    ],
                                  ),
                                  Text(g.resumen),
                                  ...g.lineas.map((x) => Text(x, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                                  graficoMensual(g),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
class _Grupo{final String titulo;final IconData icon;final Color color;final List<Map<String,dynamic>> items;final String resumen;final double? porcentaje;final List<String> lineas;_Grupo(this.titulo,this.icon,this.color,this.items,this.resumen,this.porcentaje,this.lineas);}
