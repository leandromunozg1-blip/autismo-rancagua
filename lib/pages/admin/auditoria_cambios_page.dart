import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuditoriaCambiosPage extends StatelessWidget {
  const AuditoriaCambiosPage({super.key});

  String _fecha(dynamic v) {
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría de cambios')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('auditoria_cambios')
            .orderBy('fecha', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Aún no hay registros de auditoría.'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('${d['modulo'] ?? 'Módulo'} · ${d['accion'] ?? 'Cambio'}'),
                  subtitle: Text(
                    'Usuario: ${d['usuario_email'] ?? ''}\n'
                    'Rol: ${d['usuario_rol'] ?? ''}\n'
                    'Documento: ${d['coleccion'] ?? ''}/${d['documento_id'] ?? ''}\n'
                    'Fecha: ${_fecha(d['fecha'])}\n'
                    'Detalle: ${d['detalle'] ?? ''}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
