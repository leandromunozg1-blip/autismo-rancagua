import '../ayudante_autismo_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfesionalHomePage extends StatefulWidget {
  const ProfesionalHomePage({super.key});

  @override
  State<ProfesionalHomePage> createState() => _ProfesionalHomePageState();
}

class _ProfesionalHomePageState extends State<ProfesionalHomePage> {
  final tituloCtrl = TextEditingController();
  final descripcionCtrl = TextEditingController();
  final linkCtrl = TextEditingController();
  final buscarCtrl = TextEditingController();

  bool guardando = false;

  DocumentSnapshot? apoderadoSeleccionado;
  List<DocumentSnapshot> usuarios = [];
  List<DocumentSnapshot> filtrados = [];

  @override
  void initState() {
    super.initState();
    cargarUsuarios();
  }

  @override
  void dispose() {
    tituloCtrl.dispose();
    descripcionCtrl.dispose();
    linkCtrl.dispose();
    buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> cargarUsuarios() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .get();

      final lista = snap.docs.where((doc) {
        final data = doc.data();
        final email = (data['email'] ?? '').toString().trim();
        return email.isNotEmpty;
      }).toList();

      lista.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;

        final ea = (da['email'] ?? '').toString().toLowerCase();
        final eb = (db['email'] ?? '').toString().toLowerCase();

        return ea.compareTo(eb);
      });

      if (!mounted) return;

      setState(() {
        usuarios = lista;
        filtrados = lista;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar usuarios: $e'),
        ),
      );
    }
  }

  void filtrarUsuarios(String texto) {
    final q = texto.trim().toLowerCase();

    setState(() {
      if (q.isEmpty) {
        filtrados = usuarios;
      } else {
        filtrados = usuarios.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final email = (data['email'] ?? '').toString().toLowerCase();
          final nombre = (data['nombre'] ??
                  data['nombre_apoderado'] ??
                  data['nombre_empresa'] ??
                  data['rut_empresa'] ??
                  '')
              .toString()
              .toLowerCase();

          return email.contains(q) || nombre.contains(q);
        }).toList();
      }
    });
  }

  String _nombreVisible(Map<String, dynamic> data) {
    final nombre = (data['nombre'] ??
            data['nombre_apoderado'] ??
            data['nombre_empresa'] ??
            '')
        .toString()
        .trim();

    final email = (data['email'] ?? '').toString().trim();

    if (nombre.isNotEmpty) {
      return '$nombre\n$email';
    }

    return email;
  }

  Future<void> guardarMaterial() async {
    final titulo = tituloCtrl.text.trim();
    final descripcion = descripcionCtrl.text.trim();
    final link = linkCtrl.text.trim();

    if (titulo.isEmpty || link.isEmpty || apoderadoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes ingresar título, link y seleccionar un apoderado.',
          ),
        ),
      );
      return;
    }

    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El link debe comenzar con http:// o https://'),
        ),
      );
      return;
    }

    final dataApoderado =
        apoderadoSeleccionado!.data() as Map<String, dynamic>;

    final emailApoderado =
        (dataApoderado['email'] ?? '').toString().trim().toLowerCase();

    if (emailApoderado.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El apoderado seleccionado no tiene correo.'),
        ),
      );
      return;
    }

    setState(() => guardando = true);

    try {
      await FirebaseFirestore.instance
          .collection('materiales_terapeuticos')
          .add({
        'titulo': titulo,
        'descripcion': descripcion,
        'link': link,
        'destinatarios': [emailApoderado],
        'destinatario_email': emailApoderado,
        'destinatario_uid': apoderadoSeleccionado!.id,
        'destinatario_nombre':
            (dataApoderado['nombre'] ??
                    dataApoderado['nombre_apoderado'] ??
                    dataApoderado['nombre_empresa'] ??
                    '')
                .toString(),
        'activo': true,
        'profesional_email': FirebaseAuth.instance.currentUser?.email,
        'profesional_uid': FirebaseAuth.instance.currentUser?.uid,
        'fecha_creacion': FieldValue.serverTimestamp(),
        'tipo': 'link_webview',
      });

      tituloCtrl.clear();
      descripcionCtrl.clear();
      linkCtrl.clear();
      buscarCtrl.clear();

      if (!mounted) return;

      setState(() {
        apoderadoSeleccionado = null;
        filtrados = usuarios;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material enviado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar material: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => guardando = false);
      }
    }
  }

  InputDecoration deco(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }

  Widget _selectorApoderado() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black54),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seleccionar apoderado desde Firebase',
            style: TextStyle(
              color: Color(0xFF063E83),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: buscarCtrl,
            onChanged: filtrarUsuarios,
            decoration: InputDecoration(
              hintText: 'Buscar por correo o nombre',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF3F8FF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (usuarios.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (filtrados.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No se encontraron usuarios.',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 230),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtrados.length,
                itemBuilder: (context, index) {
                  final doc = filtrados[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final email = (data['email'] ?? '').toString();
                  final seleccionado =
                      apoderadoSeleccionado?.id == doc.id;

                  return Card(
                    color: seleccionado
                        ? const Color(0xFFE3F2FD)
                        : Colors.white,
                    elevation: seleccionado ? 3 : 1,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: seleccionado
                            ? const Color(0xFF0047B3)
                            : const Color(0xFF90CAF9),
                        child: Icon(
                          seleccionado
                              ? Icons.check
                              : Icons.person,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        _nombreVisible(data),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text('UID: ${doc.id}'),
                      onTap: () {
                        setState(() {
                          apoderadoSeleccionado = doc;
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Apoderado seleccionado: $email',
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seleccionadoData =
        apoderadoSeleccionado?.data() as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0047B3),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [IconButton(tooltip: 'Ayudante', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AyudanteAutismoPage(contexto: AyudanteContexto.profesional))), icon: const Icon(Icons.auto_awesome_rounded))],
        title: const Text(
          'Panel Profesional',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Text(
              'Enviar material terapéutico al apoderado',
              style: TextStyle(
                color: Color(0xFF063E83),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TextField(
            controller: tituloCtrl,
            decoration: deco(
              'Título del material',
              Icons.title,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descripcionCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: deco(
              'Descripción o indicaciones',
              Icons.notes,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: linkCtrl,
            keyboardType: TextInputType.url,
            decoration: deco(
              'Link Google Docs / Drive',
              Icons.link,
            ),
          ),
          const SizedBox(height: 12),
          _selectorApoderado(),
          if (seleccionadoData != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                'Seleccionado:\n${_nombreVisible(seleccionadoData)}',
                style: const TextStyle(
                  color: Color(0xFF063E83),
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: guardando ? null : guardarMaterial,
            icon: guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(
              guardando ? 'Enviando...' : 'Enviar material',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0047B3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
