import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class NoticiasComunicacionesPage extends StatefulWidget {
  const NoticiasComunicacionesPage({super.key});

  @override
  State<NoticiasComunicacionesPage> createState() => _NoticiasComunicacionesPageState();
}

class _NoticiasComunicacionesPageState extends State<NoticiasComunicacionesPage> {
  final TextEditingController tituloCtrl = TextEditingController();
  final TextEditingController linkCtrl = TextEditingController();
  final TextEditingController descripcionCtrl = TextEditingController();

  String tipo = 'Noticia';
  bool publicando = false;

  @override
  void dispose() {
    tituloCtrl.dispose();
    linkCtrl.dispose();
    descripcionCtrl.dispose();
    super.dispose();
  }

  String _plataforma(String url) {
    final value = url.toLowerCase();
    if (value.contains('instagram.com')) return 'Instagram';
    if (value.contains('facebook.com') || value.contains('fb.watch')) return 'Facebook';
    if (value.contains('youtube.com') || value.contains('youtu.be')) return 'YouTube';
    return 'Link web';
  }

  IconData _iconoPlataforma(String plataforma) {
    switch (plataforma) {
      case 'Instagram':
        return Icons.camera_alt;
      case 'Facebook':
        return Icons.facebook;
      case 'YouTube':
        return Icons.play_circle_fill;
      default:
        return Icons.link;
    }
  }

  bool _debeAbrirExterno(String plataforma, String url) {
    final valor = '${plataforma.toLowerCase()} ${url.toLowerCase()}';
    return valor.contains('instagram') ||
        valor.contains('facebook') ||
        valor.contains('fb.watch');
  }

  String _normalizarLink(String url) {
    final limpio = url.trim();
    if (limpio.startsWith('http://') || limpio.startsWith('https://')) {
      return limpio;
    }
    return 'https://$limpio';
  }

  Future<void> _abrirPublicacion(String titulo, String link, String plataforma) async {
    final url = _normalizarLink(link);
    if (_debeAbrirExterno(plataforma, url)) {
      final abierto = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!abierto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la publicación.')),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisorPublicacionWebPage(titulo: titulo, url: url),
      ),
    );
  }

  Future<void> _publicar() async {
    final titulo = tituloCtrl.text.trim();
    final link = linkCtrl.text.trim();
    final descripcion = descripcionCtrl.text.trim();

    if (titulo.isEmpty || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe ingresar título y link.')),
      );
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese un link válido que comience con http o https.')),
      );
      return;
    }

    setState(() => publicando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('noticias_comunicaciones').add({
        'titulo': titulo,
        'link': link,
        'descripcion': descripcion,
        'tipo': tipo,
        'plataforma': _plataforma(link),
        'visible': true,
        'fecha': FieldValue.serverTimestamp(),
        'creadoPorUid': user?.uid ?? '',
        'creadoPorCorreo': user?.email ?? '',
      });

      tituloCtrl.clear();
      linkCtrl.clear();
      descripcionCtrl.clear();
      setState(() => tipo = 'Noticia');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publicación guardada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al publicar: $e')),
      );
    } finally {
      if (mounted) setState(() => publicando = false);
    }
  }

  Future<void> _cambiarVisibilidad(String id, bool visible) async {
    await FirebaseFirestore.instance.collection('noticias_comunicaciones').doc(id).update({
      'visible': !visible,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'actualizadoPorCorreo': FirebaseAuth.instance.currentUser?.email ?? '',
    });
  }

  Future<void> _eliminar(String id) async {
    await FirebaseFirestore.instance.collection('noticias_comunicaciones').doc(id).delete();
  }

  String _fechaTexto(dynamic fecha) {
    if (fecha is Timestamp) {
      final d = fecha.toDate();
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return 'Fecha pendiente';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Noticias y Comunicaciones',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _formularioPublicacion(),
          const SizedBox(height: 18),
          const Text(
            'Feed publicado',
            style: TextStyle(
              color: Color(0xFF063E83),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('noticias_comunicaciones')
                .orderBy('fecha', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ));
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return _emptyCard();
              }
              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _publicacionCard(doc.id, data);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _formularioPublicacion() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nueva publicación',
            style: TextStyle(
              color: Color(0xFF063E83),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pega un link de Instagram, Facebook, YouTube o una noticia web. Instagram y Facebook se abrirán afuera para fortalecer las redes sociales; YouTube y enlaces web se pueden ver dentro de la app.',
            style: TextStyle(color: Color(0xFF46627A), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: tituloCtrl,
            decoration: const InputDecoration(
              labelText: 'Título',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: tipo,
            decoration: const InputDecoration(
              labelText: 'Tipo de publicación',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Noticia', child: Text('Noticia')),
              DropdownMenuItem(value: 'Aviso', child: Text('Aviso')),
              DropdownMenuItem(value: 'Comunicado', child: Text('Comunicado')),
              DropdownMenuItem(value: 'Campaña', child: Text('Campaña')),
              DropdownMenuItem(value: 'Evento', child: Text('Evento')),
            ],
            onChanged: (value) => setState(() => tipo = value ?? 'Noticia'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: linkCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Link de Instagram, Facebook, YouTube o web',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descripcionCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Descripción opcional',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: publicando ? null : _publicar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004193),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: publicando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.publish),
            label: const Text('Publicar', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'Aún no hay publicaciones cargadas.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF46627A), fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _publicacionCard(String id, Map<String, dynamic> data) {
    final titulo = (data['titulo'] ?? 'Sin título').toString();
    final link = (data['link'] ?? '').toString();
    final descripcion = (data['descripcion'] ?? '').toString();
    final plataforma = (data['plataforma'] ?? _plataforma(link)).toString();
    final tipo = (data['tipo'] ?? 'Noticia').toString();
    final visible = data['visible'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: visible ? const Color(0xFFD6E6F7) : Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF004193),
                child: Icon(_iconoPlataforma(plataforma), color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text('$tipo · $plataforma · ${_fechaTexto(data['fecha'])}', style: const TextStyle(color: Color(0xFF46627A), fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(descripcion, style: const TextStyle(fontSize: 15, height: 1.3)),
          ],
          const SizedBox(height: 10),
          Text(
            link,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF004193), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _abrirPublicacion(titulo, link, plataforma),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004193),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: Icon(_debeAbrirExterno(plataforma, link) ? Icons.open_in_new : Icons.play_circle_fill),
                  label: Text(_debeAbrirExterno(plataforma, link) ? 'Abrir publicación' : 'Ver en la app'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: visible ? 'Ocultar' : 'Mostrar',
                onPressed: () => _cambiarVisibilidad(id, visible),
                icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => _eliminar(id),
                icon: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class VisorPublicacionWebPage extends StatefulWidget {
  final String titulo;
  final String url;

  const VisorPublicacionWebPage({
    super.key,
    required this.titulo,
    required this.url,
  });

  @override
  State<VisorPublicacionWebPage> createState() => _VisorPublicacionWebPageState();
}

class _VisorPublicacionWebPageState extends State<VisorPublicacionWebPage> {
  late final WebViewController controller;
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => cargando = false),
          onPageStarted: (_) => setState(() => cargando = true),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: controller)),
              if (cargando)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(),
                ),
              Positioned(
                top: 10,
                left: 10,
                child: Material(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
              Positioned(
                top: 15,
                left: 62,
                right: 16,
                child: Text(
                  widget.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
