import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EventosApoderadoPage extends StatelessWidget {
  const EventosApoderadoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Eventos y canales'), backgroundColor: const Color(0xFF0B69B7), foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('ar_eventos').where('estado', isEqualTo: 'activo').snapshots(),
        builder: (context, eventosSnap) {
          if (!eventosSnap.hasData) return const Center(child: CircularProgressIndicator());
          final eventos = eventosSnap.data!.docs;
          if (eventos.isEmpty) return const Center(child: Text('No hay eventos disponibles.'));
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: eventos.length,
            itemBuilder: (_, i) {
              final evento = eventos[i];
              return _EventoAutorizadoCard(evento: evento, uid: uid);
            },
          );
        },
      ),
    );
  }
}

class _EventoAutorizadoCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> evento;
  final String uid;
  const _EventoAutorizadoCard({required this.evento, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: evento.reference.collection('canales').where('activo', isEqualTo: true).snapshots(),
      builder: (context, canalesSnap) {
        if (!canalesSnap.hasData) return const SizedBox.shrink();
        final autorizados = canalesSnap.data!.docs.where((c) {
          final uids = ((c.data()['apoderados_uids'] as List?) ?? const []).map((e) => e.toString());
          return uids.contains(uid);
        }).toList();
        if (autorizados.isEmpty) return const SizedBox.shrink();
        final d = evento.data();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: const CircleAvatar(child: Icon(Icons.event)),
            title: Text((d['titulo'] ?? 'Evento').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text([d['fecha_texto'], d['lugar']].where((e) => (e ?? '').toString().trim().isNotEmpty).join(' · ')),
            children: autorizados.map((canal) => ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: Text((canal.data()['nombre'] ?? 'Canal').toString()),
              subtitle: const Text('Canal asignado por el administrador'),
              trailing: const Icon(Icons.mic),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El canal está habilitado. La transmisión PTT se conectará en la siguiente etapa.'))),
            )).toList(),
          ),
        );
      },
    );
  }
}
