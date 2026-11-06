import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PanelEventosPage extends StatefulWidget {
  const PanelEventosPage({super.key});

  @override
  State<PanelEventosPage> createState() => _PanelEventosPageState();
}

class _PanelEventosPageState extends State<PanelEventosPage> {
  final _tituloCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();
  final _lugarCtrl = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _fechaCtrl.dispose();
    _lugarCtrl.dispose();
    super.dispose();
  }

  Future<void> _crearEvento() async {
    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) {
      _mensaje('Ingresa el nombre del evento.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance.collection('ar_eventos').add({
        'titulo': titulo,
        'fecha_texto': _fechaCtrl.text.trim(),
        'lugar': _lugarCtrl.text.trim(),
        'estado': 'activo',
        'creado_por_uid': FirebaseAuth.instance.currentUser?.uid,
        'creado_por_email': FirebaseAuth.instance.currentUser?.email,
        'creado': FieldValue.serverTimestamp(),
        'actualizado': FieldValue.serverTimestamp(),
      });
      _tituloCtrl.clear();
      _fechaCtrl.clear();
      _lugarCtrl.clear();
      if (mounted) Navigator.pop(context);
      _mensaje('Evento creado. Ahora agrega y nombra sus canales.');
    } catch (e) {
      _mensaje('No fue posible crear el evento: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  void _mostrarCrearEvento() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Crear evento', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextField(controller: _tituloCtrl, decoration: const InputDecoration(labelText: 'Nombre del evento')),
            const SizedBox(height: 12),
            TextField(controller: _fechaCtrl, decoration: const InputDecoration(labelText: 'Fecha y horario')),
            const SizedBox(height: 12),
            TextField(controller: _lugarCtrl, decoration: const InputDecoration(labelText: 'Lugar')),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _crearEvento,
                icon: const Icon(Icons.add_circle_outline),
                label: Text(_guardando ? 'Creando...' : 'Crear evento'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos y canales'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarCrearEvento,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo evento'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('ar_eventos').orderBy('creado', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error al cargar eventos: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Todavía no hay eventos.', textAlign: TextAlign.center)));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final d = doc.data();
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.event_available)),
                  title: Text((d['titulo'] ?? 'Evento').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text([d['fecha_texto'], d['lugar']].where((e) => (e ?? '').toString().trim().isNotEmpty).join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _CanalesEventoAdminPage(eventoId: doc.id, titulo: (d['titulo'] ?? 'Evento').toString()))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CanalesEventoAdminPage extends StatelessWidget {
  final String eventoId;
  final String titulo;
  const _CanalesEventoAdminPage({required this.eventoId, required this.titulo});

  CollectionReference<Map<String, dynamic>> get _canales =>
      FirebaseFirestore.instance.collection('ar_eventos').doc(eventoId).collection('canales');

  Future<void> _editarNombre(BuildContext context, {DocumentSnapshot<Map<String, dynamic>>? canal}) async {
    final ctrl = TextEditingController(text: canal?.data()?['nombre']?.toString() ?? '');
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(canal == null ? 'Agregar canal' : 'Renombrar canal'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre del canal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.isEmpty) return;
    if (canal == null) {
      await _canales.add({'nombre': nombre, 'activo': true, 'apoderados_uids': <String>[], 'creado': FieldValue.serverTimestamp(), 'actualizado': FieldValue.serverTimestamp()});
    } else {
      await canal.reference.set({'nombre': nombre, 'actualizado': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
  }

  Future<void> _asignarApoderados(BuildContext context, DocumentSnapshot<Map<String, dynamic>> canal) async {
    final actuales = ((canal.data()?['apoderados_uids'] as List?) ?? const []).map((e) => e.toString()).toSet();
    final usuarios = await FirebaseFirestore.instance.collection('usuarios').limit(1000).get();
    final apoderados = usuarios.docs.where((doc) {
      final d = doc.data();
      final rol = (d['rol'] ?? d['role'] ?? d['tipo_perfil'] ?? '').toString().toLowerCase();
      final roles = ((d['roles'] as List?) ?? const []).map((e) => e.toString().toLowerCase());
      return rol.contains('apoderado') || rol.contains('padre') || rol.contains('madre') || roles.any((r) => r.contains('apoderado'));
    }).toList()
      ..sort((a, b) => _nombreUsuario(a).toLowerCase().compareTo(_nombreUsuario(b).toLowerCase()));

    if (!context.mounted) return;
    final seleccion = <String>{...actuales};
    final resultado = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Apoderados con acceso'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx).size.height * .62,
            child: apoderados.isEmpty
                ? const Center(child: Text('No se encontraron apoderados registrados.'))
                : ListView.builder(
                    itemCount: apoderados.length,
                    itemBuilder: (_, i) {
                      final u = apoderados[i];
                      final marcado = seleccion.contains(u.id);
                      return CheckboxListTile(
                        value: marcado,
                        title: Text(_nombreUsuario(u)),
                        subtitle: Text((u.data()['email'] ?? u.data()['correo'] ?? '').toString()),
                        onChanged: (v) => setState(() => v == true ? seleccion.add(u.id) : seleccion.remove(u.id)),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, seleccion), child: const Text('Guardar acceso')),
          ],
        ),
      ),
    );
    if (resultado == null) return;
    await canal.reference.set({'apoderados_uids': resultado.toList(), 'actualizado': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accesos actualizados.')));
  }

  static String _nombreUsuario(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    for (final key in ['nombre_completo', 'nombre', 'nombres', 'apoderado_nombre', 'email', 'correo']) {
      final v = (d[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return doc.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _editarNombre(context), icon: const Icon(Icons.add), label: const Text('Agregar canal')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _canales.where('activo', isEqualTo: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No hay canales. Usa “Agregar canal”.'));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final canal = docs[index];
              final accesos = ((canal.data()['apoderados_uids'] as List?) ?? const []).length;
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.record_voice_over)),
                  title: Text((canal.data()['nombre'] ?? 'Canal').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('$accesos apoderado${accesos == 1 ? '' : 's'} con acceso'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (opcion) async {
                      if (opcion == 'renombrar') await _editarNombre(context, canal: canal);
                      if (opcion == 'accesos') await _asignarApoderados(context, canal);
                      if (opcion == 'eliminar') await canal.reference.set({'activo': false, 'actualizado': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'renombrar', child: Text('Renombrar canal')),
                      PopupMenuItem(value: 'accesos', child: Text('Asignar apoderados')),
                      PopupMenuItem(value: 'eliminar', child: Text('Eliminar canal')),
                    ],
                  ),
                  onTap: () => _asignarApoderados(context, canal),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
