import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'visor_material_page.dart';

class MaterialesApoderadoPage extends StatelessWidget {
  const MaterialesApoderadoPage({super.key});

  String _fecha(dynamic fecha) {
    if (fecha is! Timestamp) return '';
    final d = fecha.toDate();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0047B3),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Materiales',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('materiales_terapeuticos')
            .where('activo', isEqualTo: true)
            .where('destinatarios', arrayContains: email)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Error al cargar materiales.'));
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs.toList()
            ..sort((a, b) {
              final da = (a.data() as Map<String, dynamic>)['fecha_creacion'];
              final db = (b.data() as Map<String, dynamic>)['fecha_creacion'];
              if (da is Timestamp && db is Timestamp) return db.compareTo(da);
              return 0;
            });

          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aún no tienes materiales asignados.',
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
              final titulo = (data['titulo'] ?? 'Material').toString();
              final descripcion = (data['descripcion'] ?? '').toString();
              final link = (data['link'] ?? '').toString();
              final profesional = (data['profesional_email'] ?? '').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFF063E83),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (descripcion.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(descripcion, style: const TextStyle(fontSize: 15, height: 1.3)),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Profesional: $profesional\nFecha: ${_fecha(data['fecha_creacion'])}',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: link.isEmpty
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VisorMaterialPage(
                                      titulo: titulo,
                                      url: link,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.visibility),
                        label: const Text('VER EN LA APP'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0047B3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
