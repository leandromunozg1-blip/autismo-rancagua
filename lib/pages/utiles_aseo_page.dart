import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class UtilesAseoPage extends StatefulWidget {
  final DateTime? fechaInicial;
  const UtilesAseoPage({super.key, this.fechaInicial});

  @override
  State<UtilesAseoPage> createState() => _UtilesAseoPageState();
}

class _UtilesAseoPageState extends State<UtilesAseoPage> {
  final TextEditingController detalleCtrl = TextEditingController();
  final ImagePicker picker = ImagePicker();
  final DateFormat _fechaFmt = DateFormat('dd-MM-yyyy');

  XFile? imagen;
  Uint8List? imagenBytes;
  bool enviando = false;
  DateTime? fechaSeleccionada;
  bool? esApoderadoPrincipal;

  @override
  void initState() {
    super.initState();
    fechaSeleccionada = widget.fechaInicial;
    _verificarPrincipal();
  }

  Future<void> _verificarPrincipal() async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null){if(mounted)setState(()=>esApoderadoPrincipal=false);return;}
    String rut='';
    final ud=await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
    if(ud.exists){final x=ud.data()??{};rut=(x['rut']??x['rut_apoderado']??'').toString().replaceAll('.','').replaceAll('-','').toLowerCase();}
    final email=(user.email??'').toLowerCase().trim();
    final bs=await FirebaseFirestore.instance.collection('ar_beneficiarios').get();
    bool ok=false;
    for(final b in bs.docs){
      final x=b.data();final ap=x['apoderado_principal'] is Map?Map<String,dynamic>.from(x['apoderado_principal']):<String,dynamic>{};
      final ae=(ap['email']??x['email_apoderado']??'').toString().toLowerCase().trim();
      final ar=(ap['rut']??x['rut_apoderado']??'').toString().replaceAll('.','').replaceAll('-','').toLowerCase();
      if((email.isNotEmpty&&email==ae)||(rut.isNotEmpty&&rut==ar)){ok=true;break;}
    }
    if(mounted)setState(()=>esApoderadoPrincipal=ok);
  }

  String _idDia(DateTime fecha) => '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    detalleCtrl.dispose();
    super.dispose();
  }

  Future<void> tomarFoto() async {
    final XFile? foto = await picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1600,
    );

    if (foto == null) return;

    final bytes = await foto.readAsBytes();
    setState(() {
      imagen = foto;
      imagenBytes = bytes;
    });
  }

  Future<void> elegirGaleria() async {
    final XFile? foto = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );

    if (foto == null) return;

    final bytes = await foto.readAsBytes();
    setState(() {
      imagen = foto;
      imagenBytes = bytes;
    });
  }

  Future<void> enviarUtiles() async {
    if (imagen == null) {
      _mensaje('Debes tomar o seleccionar una foto.');
      return;
    }

    if (detalleCtrl.text.trim().isEmpty) {
      _mensaje('Debes ingresar el detalle de los útiles de aseo.');
      return;
    }


    setState(() => enviando = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final fecha = DateTime.now();
      final id = FirebaseFirestore.instance.collection('utiles_aseo').doc().id;

      final uid = user?.uid ?? 'sin_uid';
      final nombreArchivo = 'aseo/utiles/$uid/$id.jpg';
      final ref = FirebaseStorage.instance.ref().child(nombreArchivo);
      final bytes = await imagen!.readAsBytes();

      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      ).timeout(const Duration(seconds: 45));

      String urlFoto = '';
      for (int intento = 0; intento < 3; intento++) {
        try {
          urlFoto = await uploadTask.ref.getDownloadURL().timeout(const Duration(seconds: 15));
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }

      Map<String, dynamic> perfil = {};
      if (user != null) {
        final ud = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
        if (ud.exists) perfil = ud.data() ?? {};
        if (perfil.isEmpty && (user.email ?? '').isNotEmpty) {
          final q = await FirebaseFirestore.instance.collection('usuarios').where('email', isEqualTo: user.email).limit(1).get();
          if (q.docs.isNotEmpty) perfil = q.docs.first.data();
        }
      }
      final nombreApoderado = (perfil['nombre_apoderado'] ?? perfil['nombre'] ?? perfil['nombre_completo'] ?? user?.displayName ?? user?.email ?? 'Apoderado').toString();
      final rutApoderado = (perfil['rut_apoderado'] ?? perfil['rut'] ?? perfil['rut_normalizado'] ?? '').toString();
      final beneficiario = (perfil['nombre_beneficiario'] ?? perfil['beneficiario_nombre'] ?? perfil['usuario_nombre'] ?? '').toString();

      await FirebaseFirestore.instance.collection('utiles_aseo').doc(id).set({
        'id': id,
        'uid': user?.uid,
        'email': user?.email,
        'nombre_apoderado': nombreApoderado,
        'rut_apoderado': rutApoderado,
        'beneficiario_nombre': beneficiario,
        'mes_id': DateFormat('yyyy-MM').format(fecha),
        'detalle': detalleCtrl.text.trim(),
        'foto_url': urlFoto,
        'foto_path': nombreArchivo,
        'estado': 'pendiente_revision',
        'fecha_envio': Timestamp.fromDate(fecha),
        'coordinadora_aseo_revisado': false,
        'tipo_registro': 'aporte_utiles_aseo',
        'observacion_sistema': 'Este registro solo informa útiles/materiales enviados. No agenda fecha de aseo.',
      });

      if (!mounted) return;

      _mensaje('Útiles de aseo enviados correctamente.');
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('ERROR UTILES ASEO: $e');
      _mensaje('Error al enviar útiles de aseo: $e');
    } finally {
      if (mounted) {
        setState(() => enviando = false);
      }
    }
  }


  Widget _solicitudActiva() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('aseo_avisos')
          .where('activo', isEqualTo: true)
          .where('visible_apoderados', isEqualTo: true)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }
        docs.sort((a, b) {
          final at = a.data()['creado_en'];
          final bt = b.data()['creado_en'];
          final ad = at is Timestamp ? at.toDate() : DateTime(2000);
          final bd = bt is Timestamp ? bt.toDate() : DateTime(2000);
          return bd.compareTo(ad);
        });
        final data = docs.first.data();
        final utiles = (data['utiles_sugeridos'] is List) ? List.from(data['utiles_sugeridos']) : const [];
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFFFC77A), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.campaign, color: Color(0xFFE67E22)),
                SizedBox(width: 8),
                Expanded(child: Text('Solicitud actual de la encargada de aseo', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF063E83), fontSize: 16))),
              ]),
              const SizedBox(height: 8),
              Text((data['titulo'] ?? 'Solicitud de útiles de aseo').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
              if ((data['mensaje'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(data['mensaje'].toString()),
              ],
              if (utiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Útiles solicitados:', style: TextStyle(fontWeight: FontWeight.w900)),
                ...utiles.map((u) => Text('• ${u.toString()}')),
              ],
            ],
          ),
        );
      },
    );
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if(esApoderadoPrincipal==null){return const Scaffold(body:Center(child:CircularProgressIndicator()));}
    if(esApoderadoPrincipal==false){return Scaffold(appBar:AppBar(title:const Text('Útiles de Aseo')),body:const Center(child:Padding(padding:EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.family_restroom,size:56,color:Color(0xFF087BB5)),SizedBox(height:14),Text('Los útiles mensuales corresponden al apoderado principal',textAlign:TextAlign.center,style:TextStyle(fontSize:20,fontWeight:FontWeight.w900,color:Color(0xFF063E83))),SizedBox(height:8),Text('Las cuentas de apoyo se utilizan solamente para el módulo de terapias.',textAlign:TextAlign.center)]))));}
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        title: const Text(
          'Útiles de Aseo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF075FC0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _solicitudActiva(),
            const Text(
              'Enviar aporte de útiles de aseo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF063E83),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aquí solo debes subir la foto y el detalle de los útiles/materiales solicitados por la encargada de aseo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF31506D),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFB9DEFF), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: imagen == null
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 70,
                            color: Color(0xFF075FC0),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Sin foto seleccionada',
                            style: TextStyle(
                              color: Color(0xFF31506D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.memory(
                        imagenBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: enviando ? null : tomarFoto,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Cámara'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF075FC0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enviando ? null : elegirGaleria,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF075FC0),
                      side: const BorderSide(color: Color(0xFF075FC0), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            TextField(
              controller: detalleCtrl,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Detalle de útiles entregados',
                hintText: 'Ejemplo: 2 cloros, 1 paquete de papel higiénico, 1 desinfectante...',
                alignLabelWithHint: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: enviando ? null : enviarUtiles,
              icon: enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(enviando ? 'Enviando...' : 'Enviar a coordinadora de aseo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004193),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
