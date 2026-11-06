import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auditoria_service.dart';

class SecretariaHomePage extends StatefulWidget {
  const SecretariaHomePage({super.key});

  @override
  State<SecretariaHomePage> createState() => _SecretariaHomePageState();
}

class _SecretariaHomePageState extends State<SecretariaHomePage> {
  final tituloCtrl = TextEditingController();
  final destinatarioCtrl = TextEditingController();
  final linkCtrl = TextEditingController();
  final descripcionCtrl = TextEditingController();

  String tipoGestion = 'Acta para firma';
  String filtroEstado = 'todos';
  bool guardando = false;

  final List<String> tipos = const [
    'Acta para firma',
    'Link de reunión',
    'Documento solicitado',
    'Comunicado interno',
    'Solicitud a directiva',
    'Otro',
  ];

  @override
  void dispose() {
    tituloCtrl.dispose();
    destinatarioCtrl.dispose();
    linkCtrl.dispose();
    descripcionCtrl.dispose();
    super.dispose();
  }

  String _normalizarLink(String value) {
    final link = value.trim();
    if (link.isEmpty) return '';
    if (link.startsWith('http://') || link.startsWith('https://')) return link;
    return 'https://$link';
  }

  Future<void> _guardarGestion() async {
    final titulo = tituloCtrl.text.trim();
    final destinatario = destinatarioCtrl.text.trim();
    final link = _normalizarLink(linkCtrl.text);
    final descripcion = descripcionCtrl.text.trim();

    if (titulo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe ingresar un título.')),
      );
      return;
    }

    setState(() => guardando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final data = {
        'titulo': titulo,
        'tipo': tipoGestion,
        'destinatario': destinatario,
        'link': link,
        'descripcion': descripcion,
        'estado': 'pendiente',
        'fecha': FieldValue.serverTimestamp(),
        'creadoPorUid': user?.uid ?? '',
        'creadoPorCorreo': user?.email ?? '',
      };
      final doc = await FirebaseFirestore.instance.collection('secretaria_gestiones').add(data);
      await AuditoriaService.registrar(
        modulo: 'Secretaría',
        accion: 'Crear gestión',
        coleccion: 'secretaria_gestiones',
        documentoId: doc.id,
        detalle: '$tipoGestion: $titulo',
        despues: {...data, 'fecha': 'serverTimestamp'},
      );

      tituloCtrl.clear();
      destinatarioCtrl.clear();
      linkCtrl.clear();
      descripcionCtrl.clear();
      setState(() => tipoGestion = 'Acta para firma');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gestión guardada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> _cambiarEstado(String id, Map<String, dynamic> actual, String nuevoEstado) async {
    final user = FirebaseAuth.instance.currentUser;
    final cambios = {
      'estado': nuevoEstado,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'actualizadoPorCorreo': user?.email ?? '',
    };
    await FirebaseFirestore.instance.collection('secretaria_gestiones').doc(id).update(cambios);
    await AuditoriaService.registrar(
      modulo: 'Secretaría',
      accion: 'Cambiar estado',
      coleccion: 'secretaria_gestiones',
      documentoId: id,
      detalle: '${actual['titulo'] ?? ''}: ${actual['estado'] ?? ''} → $nuevoEstado',
      antes: actual,
      despues: {'estado': nuevoEstado},
    );
  }

  Future<void> _eliminar(String id, Map<String, dynamic> actual) async {
    await FirebaseFirestore.instance.collection('secretaria_gestiones').doc(id).delete();
    await AuditoriaService.registrar(
      modulo: 'Secretaría',
      accion: 'Eliminar gestión',
      coleccion: 'secretaria_gestiones',
      documentoId: id,
      detalle: actual['titulo']?.toString() ?? '',
      antes: actual,
    );
  }

  Future<void> _abrirLink(String link) async {
    final limpio = _normalizarLink(link);
    if (limpio.isEmpty) return;
    final uri = Uri.tryParse(limpio);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el link.')),
      );
    }
  }

  String _fechaTexto(dynamic fecha) {
    if (fecha is Timestamp) {
      final d = fecha.toDate();
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return 'Fecha pendiente';
  }

  Stream<QuerySnapshot> _streamGestiones() {
    Query query = FirebaseFirestore.instance
        .collection('secretaria_gestiones')
        .orderBy('fecha', descending: true);
    if (filtroEstado != 'todos') {
      query = FirebaseFirestore.instance
          .collection('secretaria_gestiones')
          .where('estado', isEqualTo: filtroEstado)
          .orderBy('fecha', descending: true);
    }
    return query.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Panel Secretaría', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _encabezado(),
          const SizedBox(height: 14),
          _formulario(),
          const SizedBox(height: 18),
          _filtros(),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: _streamGestiones(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('Error: ${snapshot.error}');
              if (!snapshot.hasData) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ));
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) return _emptyCard();
              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _gestionCard(doc.id, data);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _encabezado() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: Color(0xFF004193),
            child: Icon(Icons.assignment_ind, color: Colors.white, size: 34),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Secretaría', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
                SizedBox(height: 5),
                Text('Actas, documentos, links de reunión, solicitudes y gestiones internas.', style: TextStyle(fontSize: 14.5, color: Color(0xFF50647A), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formulario() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nueva gestión', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
          const SizedBox(height: 12),
          TextField(controller: tituloCtrl, decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: tipoGestion,
            decoration: const InputDecoration(labelText: 'Tipo de gestión', border: OutlineInputBorder()),
            items: tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => tipoGestion = v ?? tipoGestion),
          ),
          const SizedBox(height: 10),
          TextField(controller: destinatarioCtrl, decoration: const InputDecoration(labelText: 'Destinatario / responsable', hintText: 'Ej: Presidenta, Directiva, Apoderados, Profesional', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: linkCtrl, decoration: const InputDecoration(labelText: 'Link opcional', hintText: 'Drive, Meet, Zoom, documento, carpeta, etc.', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: descripcionCtrl, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Detalle / observación', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: guardando ? null : _guardarGestion,
              icon: guardando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(guardando ? 'Guardando...' : 'Guardar gestión'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004193),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    final estados = const [
      ['todos', 'Todos'],
      ['pendiente', 'Pendientes'],
      ['enviado', 'Enviados'],
      ['firmado', 'Firmados'],
      ['cerrado', 'Cerrados'],
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: estados.map((e) {
        final selected = filtroEstado == e[0];
        return ChoiceChip(
          selected: selected,
          label: Text(e[1]!),
          onSelected: (_) => setState(() => filtroEstado = e[0]!),
          selectedColor: const Color(0xFF004193),
          labelStyle: TextStyle(color: selected ? Colors.white : const Color(0xFF063E83), fontWeight: FontWeight.w800),
        );
      }).toList(),
    );
  }

  Widget _gestionCard(String id, Map<String, dynamic> data) {
    final titulo = data['titulo']?.toString() ?? 'Sin título';
    final tipo = data['tipo']?.toString() ?? 'Gestión';
    final destinatario = data['destinatario']?.toString() ?? '';
    final link = data['link']?.toString() ?? '';
    final descripcion = data['descripcion']?.toString() ?? '';
    final estado = data['estado']?.toString() ?? 'pendiente';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _colorEstado(estado),
                child: const Icon(Icons.description, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text('$tipo · ${_fechaTexto(data['fecha'])}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF50647A))),
                  ],
                ),
              ),
            ],
          ),
          if (destinatario.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Destinatario: $destinatario', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          ],
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(descripcion, style: const TextStyle(fontSize: 15.5)),
          ],
          if (link.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(link, style: const TextStyle(color: Color(0xFF004193), fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (link.isNotEmpty)
                _accion(Icons.open_in_new, 'Abrir', () => _abrirLink(link)),
              if (link.isNotEmpty)
                _accion(Icons.copy, 'Copiar', () async {
                  if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La copia de texto está habilitada solo para profesionales y administración.'))); }
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copiado.')));
                }),
              _accion(Icons.send, 'Enviado', () => _cambiarEstado(id, data, 'enviado')),
              _accion(Icons.draw, 'Firmado', () => _cambiarEstado(id, data, 'firmado')),
              _accion(Icons.check_circle, 'Cerrar', () => _cambiarEstado(id, data, 'cerrado')),
              IconButton(
                onPressed: () => _eliminar(id, data),
                icon: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accion(IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'enviado':
        return Colors.orange;
      case 'firmado':
        return Colors.green;
      case 'cerrado':
        return Colors.blueGrey;
      default:
        return const Color(0xFF004193);
    }
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: const Center(
        child: Text('Aún no hay gestiones registradas.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
