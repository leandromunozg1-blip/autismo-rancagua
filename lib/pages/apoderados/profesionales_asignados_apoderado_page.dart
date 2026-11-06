import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfesionalesAsignadosApoderadoPage extends StatelessWidget {
  const ProfesionalesAsignadosApoderadoPage({super.key});

  String _txt(Map<String, dynamic> data, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  String _fecha(dynamic value) {
    if (value is! Timestamp) return '';
    final d = value.toDate();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }


  String _proximoVencimiento() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1, 1);
    return '${next.day.toString().padLeft(2, '0')}-${next.month.toString().padLeft(2, '0')}-${next.year}';
  }

  Widget _infoPagoCard() {
    final vencimiento = _proximoVencimiento();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF004193),
                    child: Icon(Icons.attach_money, color: Colors.white, size: 22),
                  ),
                  SizedBox(width: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Valor mensual:\n', style: TextStyle(fontSize: 13)),
                        TextSpan(text: '\$20.000', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    style: TextStyle(color: Color(0xFF004193), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Container(width: 1, height: 38, color: Color(0x33004193)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month, color: Color(0xFF004193), size: 30),
                  const SizedBox(width: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Próximo vencimiento:\n', style: TextStyle(fontSize: 13)),
                        TextSpan(text: vencimiento, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    style: const TextStyle(color: Color(0xFF004193), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE4F8EA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF9BE0B2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle, color: Color(0xFF129B4F), size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Estado: Al día',
                      style: TextStyle(
                        color: Color(0xFF08743A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _listaTieneUid(dynamic value, String uid) {
    if (uid.isEmpty || value is! List) return false;
    return value.map((e) => e.toString().trim()).contains(uid);
  }

  bool _apoyoTieneUid(dynamic value, String uid) {
    if (uid.isEmpty || value is! List) return false;
    for (final item in value) {
      if (item is Map) {
        final apoyoUid = (item['uid'] ?? item['apoyo_uid'] ?? '').toString().trim();
        if (apoyoUid == uid) return true;
      }
    }
    return false;
  }

  bool _asignacionVisible(Map<String, dynamic> data, String uid, Set<String> beneficiariosAutorizados) {
    if (uid.isEmpty) return false;
    final apoderadoUid = (data['apoderado_uid'] ?? data['uid_apoderado'] ?? '').toString().trim();
    if (apoderadoUid == uid) return true;
    if (apoderadoUid.isNotEmpty && beneficiariosAutorizados.contains(apoderadoUid)) return true;
    if (_listaTieneUid(data['apoderados_uids_autorizados'], uid)) return true;

    // Compatibilidad con asignaciones antiguas: antes no existía apoderados_uids_autorizados.
    // Si el apoyo está autorizado en el beneficiario, igual puede ver la asignación de ese beneficiario.
    for (final key in [
      'beneficiario_id',
      'rut_beneficiario',
      'rut_usuario',
      'beneficiario_rut',
      'rut',
      'beneficiario_nombre',
      'nombre_beneficiario',
      'nombre',
    ]) {
      final v = (data[key] ?? '').toString().trim();
      if (v.isNotEmpty && beneficiariosAutorizados.contains(v)) return true;
    }
    return false;
  }


  Future<void> _enviarCertificadoMedico(BuildContext context, String uid, Set<String> beneficiariosAutorizados) async {
    if (uid.isEmpty) return;
    DateTime? desde = DateTime.now();
    DateTime? hasta = DateTime.now();
    XFile? archivo;
    final motivoCtrl = TextEditingController();
    bool guardando = false;

    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

    await showDialog(
      context: context,
      barrierDismissible: !guardando,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> elegirFecha(bool esDesde) async {
              final actual = esDesde ? desde : hasta;
              final picked = await showDatePicker(
                context: context,
                initialDate: actual ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2035),
              );
              if (picked != null) setState(() => esDesde ? desde = picked : hasta = picked);
            }

            Future<void> elegirImagen() async {
              final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
              if (picked != null) setState(() => archivo = picked);
            }

            Future<void> guardar() async {
              if (desde == null || hasta == null) return;
              if (hasta!.isBefore(desde!)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La fecha de término no puede ser anterior a la fecha de inicio.')));
                return;
              }
              setState(() => guardando = true);
              try {
                String url = '';
                String path = '';
                if (archivo != null) {
                  final bytes = await archivo!.readAsBytes();
                  path = 'certificados_medicos_sos/$uid/${DateTime.now().millisecondsSinceEpoch}_${archivo!.name}';
                  final ref = FirebaseStorage.instance.ref().child(path);
                  await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
                  url = await ref.getDownloadURL();
                }
                await FirebaseFirestore.instance.collection('certificados_medicos_sos').add({
                  'apoderado_uid': uid,
                  'beneficiarios_autorizados': beneficiariosAutorizados.toList(),
                  'motivo': motivoCtrl.text.trim(),
                  'fecha_inicio': Timestamp.fromDate(DateTime(desde!.year, desde!.month, desde!.day)),
                  'fecha_termino': Timestamp.fromDate(DateTime(hasta!.year, hasta!.month, hasta!.day, 23, 59, 59)),
                  'archivo_url': url,
                  'archivo_path': path,
                  'estado': 'pendiente_revision',
                  'tipo': 'certificado_medico_sos',
                  'creado_por_uid': uid,
                  'creado': FieldValue.serverTimestamp(),
                  'actualizado': FieldValue.serverTimestamp(),
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Certificado enviado. Coordinación revisará la solicitud SOS.')));
                }
              } catch (e) {
                setState(() => guardando = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo enviar el certificado: $e')));
              }
            }

            return AlertDialog(
              title: const Text('Enviar certificado médico'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Este certificado permitirá coordinar cupos SOS mientras dure la licencia médica o permiso justificado.', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton.icon(onPressed: guardando ? null : () => elegirFecha(true), icon: const Icon(Icons.date_range), label: Text('Desde: ${desde == null ? '--' : fmt(desde!)}'))),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton.icon(onPressed: guardando ? null : () => elegirFecha(false), icon: const Icon(Icons.event_available), label: Text('Hasta: ${hasta == null ? '--' : fmt(hasta!)}'))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: motivoCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Observación / motivo', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: guardando ? null : elegirImagen,
                      icon: const Icon(Icons.upload_file),
                      label: Text(archivo == null ? 'Adjuntar foto del certificado' : 'Adjunto: ${archivo!.name}'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: guardando ? null : () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
                ElevatedButton.icon(onPressed: guardando ? null : guardar, icon: guardando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: const Text('Enviar')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _aceptarSos(BuildContext context, QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    try {
      await FirebaseFirestore.instance.collection('sos_asignaciones').doc(doc.id).update({
        'estado': 'aceptado_apoderado',
        'aceptado_por_uid': FirebaseAuth.instance.currentUser?.uid ?? '',
        'aceptado_el': FieldValue.serverTimestamp(),
        'actualizado': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').add({
        ...data,
        'origen': 'sos',
        'sos_id': doc.id,
        'costo': 0,
        'sin_costo': true,
        'nota_costo': 'Reemplazo SOS sin costo para el apoderado.',
        'estado': 'activo',
        'creado': FieldValue.serverTimestamp(),
        'actualizado': FieldValue.serverTimestamp(),
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOS aceptado e ingresado a la agenda.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo aceptar el SOS: $e')));
    }
  }

  Widget _sosPendientes(String uid) {
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_asignaciones')
          .where('apoderado_uid', isEqualTo: uid)
          .where('estado', isEqualTo: 'pendiente_apoderado')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? <QueryDocumentSnapshot>[];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final beneficiario = _txt(data, ['beneficiario_nombre', 'nombre_beneficiario'], 'Beneficiario');
            final profesional = _txt(data, ['profesional_nombre'], 'Profesional');
            final terapia = _txt(data, ['servicio_nombre', 'terapia'], 'Terapia');
            final dia = _txt(data, ['dia']);
            final hora = _txt(data, ['hora', 'horario']);
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFFFF8DE), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFFCF72))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Solicitud SOS pendiente', style: TextStyle(color: Color(0xFFE65F00), fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(beneficiario, style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text('Profesional: $profesional'),
                  Text('Terapia/Taller: $terapia'),
                  Text('Horario: $dia $hora'),
                  const SizedBox(height: 6),
                  const Text('Esta asignación es un reemplazo SOS sin costo.', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(onPressed: () => _aceptarSos(context, doc), icon: const Icon(Icons.check_circle), label: const Text('Aceptar SOS')),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid.trim() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F9FF),
        foregroundColor: const Color(0xFF5D50BE),
        elevation: 0, surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: const Text(
          'Profesionales asignados',
          style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF3E357F)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('ar_beneficiarios').snapshots(),
        builder: (context, beneficiariosSnap) {
          if (beneficiariosSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final beneficiariosAutorizados = <String>{};
          for (final b in beneficiariosSnap.data?.docs ?? <QueryDocumentSnapshot>[]) {
            final data = b.data() as Map<String, dynamic>;
            final apoderadoUid = (data['apoderado_uid'] ?? data['uid_apoderado'] ?? '').toString().trim();
            if (apoderadoUid == uid || _listaTieneUid(data['apoderados_uids_autorizados'], uid) || _apoyoTieneUid(data['apoyos_autorizados'], uid)) {
              beneficiariosAutorizados.add(b.id);
              for (final key in [
                'beneficiario_id',
                'rut',
                'rut_beneficiario',
                'rut_usuario',
                'beneficiario_rut',
                'nombre',
                'nombre_beneficiario',
                'beneficiario_nombre',
                'apoderado_uid',
                'uid_apoderado',
                'email_apoderado',
                'correo_apoderado',
                'email',
                'correo',
              ]) {
                final v = (data[key] ?? '').toString().trim();
                if (v.isNotEmpty) beneficiariosAutorizados.add(v);
              }
            }
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Container(
                  height: 145, width: double.infinity, clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: const Color(0xFF6657C8).withOpacity(.12), blurRadius: 18, offset: const Offset(0, 8))]),
                  child: Image.asset('assets/images/apoyo_03_profesionales.png', fit: BoxFit.cover),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _enviarCertificadoMedico(context, uid, beneficiariosAutorizados),
                    icon: const Icon(Icons.medical_information),
                    label: const Text('Enviar certificado médico'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6657C8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFFF8DE), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFFCF72))),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber_rounded, color: Color(0xFFF28C00), size: 28), SizedBox(width: 10),
                    Expanded(child: Text('El copago es anticipado. Revise su próximo vencimiento para asegurar la continuidad de las terapias según la Carta de Compromiso.', style: TextStyle(color: Color(0xFF6B4B12), fontWeight: FontWeight.w700, height: 1.35))),
                  ]),
                ),
              ),
              _sosPendientes(uid),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
            // Se deja sin filtro para no perder asignaciones antiguas creadas solo con apoderado_uid.
            stream: FirebaseFirestore.instance.collection('ar_asignaciones_mensuales').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No se pudieron cargar las asignaciones.\n\n$snap',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
                  ),
                );
              }

              final docs = (snap.data?.docs ?? [])
                  .where((d) => _asignacionVisible(d.data() as Map<String, dynamic>, uid, beneficiariosAutorizados))
                  .toList();
              docs.sort((a, b) {
                final ma = a.data() as Map<String, dynamic>;
                final mb = b.data() as Map<String, dynamic>;
                final xa = '${ma['dia'] ?? ''} ${ma['hora'] ?? ''}';
                final xb = '${mb['dia'] ?? ''} ${mb['hora'] ?? ''}';
                return xa.compareTo(xb);
              });

              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aún no hay profesionales asignados a tus beneficiarios.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF31506D),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final beneficiario = _txt(data, ['beneficiario_nombre', 'nombre_beneficiario'], 'Beneficiario');
                  final profesional = _txt(data, ['profesional_nombre'], 'Profesional');
                  final terapia = _txt(data, ['servicio_nombre', 'terapia'], 'Terapia');
                  final dia = _txt(data, ['dia']);
                  final hora = _txt(data, ['hora', 'horario']);
                  final obs = _txt(data, ['observacion']);
                  final fecha = _fecha(data['creado']);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6657C8).withOpacity(0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          beneficiario,
                          style: const TextStyle(
                            color: Color(0xFF063E83),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Profesional: $profesional', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('Terapia/Taller: $terapia'),
                        Text('Horario: $dia $hora'),
                        if (obs.isNotEmpty) Text('Observación: $obs'),
                        if (fecha.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Asignado: $fecha', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                        const SizedBox(height: 10),
                        _infoPagoCard(),
                      ],
                    ),
                  );
                },
              );
            },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
