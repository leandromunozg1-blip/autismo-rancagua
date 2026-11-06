import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../modelo_datos_autismo.dart';

class BeneficiariosContactosPage extends StatefulWidget {
  const BeneficiariosContactosPage({super.key});

  @override
  State<BeneficiariosContactosPage> createState() => _BeneficiariosContactosPageState();
}

class _BeneficiariosContactosPageState extends State<BeneficiariosContactosPage> {
  final buscarCtrl = TextEditingController();

  @override
  void dispose() {
    buscarCtrl.dispose();
    super.dispose();
  }


  bool _docCorrespondeBeneficiario(Map<String, dynamic> data, Set<String> ids) {
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
      if (v.isNotEmpty && ids.contains(v)) return true;
    }
    return false;
  }

  Future<void> _propagarUidsAutorizados({
    required DocumentSnapshot beneficiarioDoc,
    required Map<String, dynamic> beneficiarioData,
    required List<String> uidsAutorizados,
  }) async {
    final ids = <String>{beneficiarioDoc.id};
    for (final key in [
      'beneficiario_id',
      'rut',
      'rut_beneficiario',
      'rut_usuario',
      'beneficiario_rut',
      'nombre',
      'nombre_beneficiario',
      'beneficiario_nombre',
    ]) {
      final v = (beneficiarioData[key] ?? '').toString().trim();
      if (v.isNotEmpty) ids.add(v);
    }

    final colecciones = [
      'ar_bitacora_casa',
      'atenciones_profesionales',
      'ar_asignaciones_mensuales',
      'ar_asignaciones',
    ];

    for (final col in colecciones) {
      try {
        final snap = await FirebaseFirestore.instance.collection(col).get();
        for (final d in snap.docs) {
          final m = d.data();
          if (!_docCorrespondeBeneficiario(m, ids)) continue;
          await d.reference.set({
            'apoderados_uids_autorizados': FieldValue.arrayUnion(uidsAutorizados),
            'actualizado_apoyos': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {
        // No se detiene el guardado si alguna colección antigua no existe o no tiene permisos.
      }
    }
  }

  InputDecoration _campoDec(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF52606D)),
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFD8E7F2))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFD8E7F2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF0B73C9), width: 1.6)),
      );

  Future<void> _editarApoyos(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final existentes = List<Map<String, dynamic>>.from((data['apoyos_autorizados'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final apoyos = [...existentes];
    while (apoyos.length < 3) {
      apoyos.add({'rut': '', 'nombre': '', 'telefono': '', 'email': '', 'uid': '', 'parentesco': '', 'autorizado': true});
    }

    final rutCtrls = List.generate(3, (i) => TextEditingController(text: apoyos[i]['rut']?.toString() ?? ''));
    final nombreCtrls = List.generate(3, (i) => TextEditingController(text: apoyos[i]['nombre']?.toString() ?? ''));
    final telCtrls = List.generate(3, (i) => TextEditingController(text: apoyos[i]['telefono']?.toString() ?? ''));
    final emailCtrls = List.generate(3, (i) => TextEditingController(text: (apoyos[i]['email'] ?? apoyos[i]['correo'])?.toString() ?? ''));
    final uidCtrls = List.generate(3, (i) => TextEditingController(text: (apoyos[i]['uid'] ?? apoyos[i]['apoyo_uid'])?.toString() ?? ''));
    final parCtrls = List.generate(3, (i) => TextEditingController(text: apoyos[i]['parentesco']?.toString() ?? ''));
    final abiertos = <bool>[true, existentes.length > 1, existentes.length > 2];

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setModalState) {
        Widget bloqueApoyo(int i) {
          final color = [const Color(0xFF1976D2), const Color(0xFF7B2CBF), const Color(0xFF00A889)][i];
          final tieneDatos = nombreCtrls[i].text.trim().isNotEmpty || rutCtrls[i].text.trim().isNotEmpty || emailCtrls[i].text.trim().isNotEmpty || uidCtrls[i].text.trim().isNotEmpty;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: color.withOpacity(.18)), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 4))]),
            child: Column(children: [
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => setModalState(() => abiertos[i] = !abiertos[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(21)),
                  child: Row(children: [Icon(Icons.groups_rounded, color: color), const SizedBox(width: 10), Expanded(child: Text('Apoyo ${i + 1}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))), if (tieneDatos) Icon(Icons.check_circle_rounded, color: color, size: 20), const SizedBox(width: 6), Icon(abiertos[i] ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: color)]),
                ),
              ),
              if (abiertos[i]) Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Column(children: [
                  TextField(controller: nombreCtrls[i], decoration: _campoDec('Nombre completo', Icons.person_rounded)), const SizedBox(height: 10),
                  TextField(controller: rutCtrls[i], decoration: _campoDec('RUT', Icons.badge_rounded, hint: 'RUT de la persona')), const SizedBox(height: 10),
                  TextField(controller: telCtrls[i], keyboardType: TextInputType.phone, decoration: _campoDec('Teléfono', Icons.phone_rounded)), const SizedBox(height: 10),
                  TextField(controller: emailCtrls[i], keyboardType: TextInputType.emailAddress, decoration: _campoDec('Correo electrónico', Icons.email_rounded)), const SizedBox(height: 10),
                  TextField(controller: uidCtrls[i], decoration: _campoDec('UID de acceso', Icons.key_rounded, hint: 'UID de Firebase (opcional)')), const SizedBox(height: 10),
                  TextField(controller: parCtrls[i], decoration: _campoDec('Parentesco', Icons.family_restroom_rounded)),
                  if (tieneDatos) ...[const SizedBox(height: 10), Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () { nombreCtrls[i].clear(); rutCtrls[i].clear(); telCtrls[i].clear(); emailCtrls[i].clear(); uidCtrls[i].clear(); parCtrls[i].clear(); setModalState(() {}); }, icon: const Icon(Icons.delete_outline_rounded), label: const Text('Eliminar apoyo'), style: TextButton.styleFrom(foregroundColor: Colors.red)))],
                ]),
              ),
            ]),
          );
        }

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFE5F3FF), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.favorite_rounded, color: Color(0xFFEC407A))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Apoyos autorizados', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF073B78))), const SizedBox(height: 4), Text((data['nombre'] ?? '').toString().toUpperCase(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))])),
                  IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 12),
                Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFEAF6FF), borderRadius: BorderRadius.circular(16)), child: const Text('Aquí puedes registrar hasta 3 apoyos autorizados para este beneficiario. Puedes agregarlos, editarlos o eliminarlos cuando sea necesario.', style: TextStyle(color: Color(0xFF35546F), height: 1.35))),
                const SizedBox(height: 12),
                Flexible(child: SingleChildScrollView(child: Column(children: List.generate(3, bloqueApoyo)))),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(dialogContext), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Cancelar'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(
                    onPressed: () async {
                      final nuevos = <Map<String, dynamic>>[];
                      final uidsAutorizados = <String>{};
                      final apoderadoUid = (data['apoderado_uid'] ?? data['uid_apoderado'] ?? '').toString().trim();
                      if (apoderadoUid.isNotEmpty) uidsAutorizados.add(apoderadoUid);
                      for (int i = 0; i < 3; i++) {
                        final nombre = nombreCtrls[i].text.trim();
                        final rut = normalizarRutAr(rutCtrls[i].text);
                        final email = emailCtrls[i].text.trim().toLowerCase();
                        final uid = uidCtrls[i].text.trim();
                        if (nombre.isEmpty && rut.isEmpty && email.isEmpty && uid.isEmpty) continue;
                        if (uid.isNotEmpty) uidsAutorizados.add(uid);
                        nuevos.add({'nombre': nombre, 'rut': rut, 'telefono': telCtrls[i].text.trim(), 'email': email, 'correo': email, 'uid': uid, 'apoyo_uid': uid, 'parentesco': parCtrls[i].text.trim(), 'autorizado': true});
                      }
                      final listaUidsAutorizados = uidsAutorizados.toList();
                      await doc.reference.set({'apoyos_autorizados': nuevos, 'apoderados_uids_autorizados': listaUidsAutorizados, 'actualizado': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                      await _propagarUidsAutorizados(beneficiarioDoc: doc, beneficiarioData: data, uidsAutorizados: listaUidsAutorizados);
                      for (final apoyo in nuevos) {
                        final uid = (apoyo['uid'] ?? '').toString().trim();
                        if (uid.isEmpty) continue;
                        await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({'uid': uid, 'rol': 'apoderado', 'tipo_perfil': 'apoyo_autorizado', 'nombre': apoyo['nombre'] ?? '', 'rut': apoyo['rut'] ?? '', 'rut_normalizado': apoyo['rut'] ?? '', 'email': apoyo['email'] ?? '', 'email_normalizado': apoyo['email'] ?? '', 'telefono': apoyo['telefono'] ?? '', 'activo': true, 'actualizado': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    icon: const Icon(Icons.save_rounded), label: const Text('Guardar apoyos'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0756B5), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  )),
                ]),
              ]),
            ),
          ),
        );
      }),
    );

    for (final c in [...rutCtrls, ...nombreCtrls, ...telCtrls, ...emailCtrls, ...uidCtrls, ...parCtrls]) { c.dispose(); }
  }

  @override
  Widget build(BuildContext context) {
    final q = buscarCtrl.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F9FE),
      appBar: AppBar(
        title: const Text('Beneficiarios y apoyos', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF07509D),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: const [Padding(padding: EdgeInsets.only(right: 18), child: Icon(Icons.favorite_rounded, color: Color(0xFFFF8EB4)))],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection(ArColecciones.beneficiarios).orderBy('nombre').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final todos = snap.data!.docs;
          final totalApoyos = todos.fold<int>(0, (sum, d) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            return sum + ((m['apoyos_autorizados'] as List?)?.length ?? 0);
          });
          final docs = todos.where((d) {
            final data = d.data() as Map<String, dynamic>? ?? {};
            final t = '${data['nombre']} ${data['rut']} ${data['nombre_apoderado']}'.toLowerCase();
            return q.isEmpty || t.contains(q);
          }).toList();

          Widget resumen(String valor, String label, IconData icon, Color color) => Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(22), border: Border.all(color: color.withOpacity(.12))),
            child: Row(children: [Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.white.withOpacity(.8), shape: BoxShape.circle), child: Icon(icon, color: color, size: 28)), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(valor, style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: color)), Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF163D69)))])]),
          ));

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Column(children: [
                TextField(
                  controller: buscarCtrl,
                  decoration: InputDecoration(hintText: 'Buscar por nombre o RUT...', prefixIcon: const Icon(Icons.search_rounded, size: 29), suffixIcon: q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { buscarCtrl.clear(); setState(() {}); }), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFFD7E6F0))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Color(0xFFD7E6F0)))),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(children: [resumen('${todos.length}', 'Beneficiarios', Icons.child_care_rounded, const Color(0xFF1976D2)), const SizedBox(width: 10), resumen('$totalApoyos', 'Apoyos', Icons.groups_rounded, const Color(0xFFE91E63))]),
              ]),
            ),
            Expanded(child: docs.isEmpty ? const Center(child: Text('Sin beneficiarios.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))) : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data() as Map<String, dynamic>? ?? {};
                final apoyos = data['apoyos_autorizados'] as List? ?? [];
                final tonos = [const Color(0xFF1976D2), const Color(0xFF7B2CBF), const Color(0xFF00A889), const Color(0xFFE91E63), const Color(0xFFF2A900)];
                final color = tonos[i % tonos.length];
                final nombre = (data['nombre']?.toString() ?? 'Sin nombre').toUpperCase();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE3EDF4)), boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))]),
                  child: Row(children: [
                    CircleAvatar(radius: 31, backgroundColor: color.withOpacity(.13), child: Icon(Icons.child_care_rounded, color: color, size: 35)),
                    const SizedBox(width: 13),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nombre, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF1C2530))),
                      const SizedBox(height: 4),
                      Text('RUT: ${data['rut'] ?? d.id}', style: const TextStyle(color: Color(0xFF53616E), fontSize: 14.5)),
                      Text('Apoderado: ${data['nombre_apoderado'] ?? ''}', style: const TextStyle(color: Color(0xFF53616E), fontSize: 14.5)),
                      const SizedBox(height: 7),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(12)), child: Text('Apoyos: ${apoyos.length}', style: TextStyle(fontWeight: FontWeight.w800, color: color))),
                    ])),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _editarApoyos(d),
                      child: Container(width: 70, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(16)), child: Column(children: [Icon(Icons.person_add_alt_1_rounded, color: color), const SizedBox(height: 4), Text(apoyos.isEmpty ? 'Agregar\napoyo' : 'Ver\napoyos', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color))])),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: color),
                  ]),
                );
              },
            )),
          ]);
        },
      ),
    );
  }
}
