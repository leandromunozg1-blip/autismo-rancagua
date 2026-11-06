import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PublicHomePage extends StatefulWidget {
  const PublicHomePage({super.key});

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage> {
  void abrirSocios() {
    Navigator.pushNamed(context, '/login');
  }

  void entrarMiPanel() {
    Navigator.pushNamed(context, '/panel');
  }

  String _normalizarLink(String url) {
    final limpio = url.trim();
    if (limpio.startsWith('http://') || limpio.startsWith('https://')) {
      return limpio;
    }
    return 'https://$limpio';
  }

  bool _debeAbrirExterno(String plataforma, String url) {
    final valor = '${plataforma.toLowerCase()} ${url.toLowerCase()}';
    return valor.contains('instagram') ||
        valor.contains('facebook') ||
        valor.contains('fb.watch');
  }

  Future<void> abrirPublicacion(String titulo, String url, String plataforma) async {
    final limpio = url.trim();

    if (limpio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay enlace registrado')),
      );
      return;
    }

    final link = _normalizarLink(limpio);

    if (_debeAbrirExterno(plataforma, link)) {
      final uri = Uri.parse(link);
      final abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abierto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la publicación.')),
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisorPublicacionPublicaPage(
          titulo: titulo,
          url: link,
        ),
      ),
    );
  }

  String formatearFecha(dynamic fecha) {
    if (fecha is! Timestamp) return '';

    final date = fecha.toDate();
    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    final anio = date.year.toString();

    return '$dia-$mes-$anio';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xfff4f6f9),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _portada(context, user),
          _contenidoPrincipal(),
        ],
      ),
    );
  }

  Widget _portada(BuildContext context, User? user) {
    final bool sesionIniciada = user != null;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/fondo_home.png'),
          fit: BoxFit.cover,
          opacity: 0.20,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffeffaff), Color(0xfffff6fb), Color(0xfffff8df)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Column(
            children: [
              _encabezado(),
              if (sesionIniciada) ...[
                const SizedBox(height: 12),
                _sesionActiva(user),
              ],
              const SizedBox(height: 18),
              _heroPublico(),
              const SizedBox(height: 20),
              const Text(
                'Conoce lo que estamos viviendo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff07538d),
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Noticias, actividades y comunidad en un mismo lugar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff597083),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _beneficiosPublicos(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'AUTISMO RANCAGUA',
                  maxLines: 1,
                  style: TextStyle(
                    color: Color(0xff07538d),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .15,
                  ),
                ),
              ),
              SizedBox(height: 5),
              Text(
                'POR EL MÍO, POR EL TUYO Y POR LOS QUE VENDRÁN.',
                style: TextStyle(
                  color: Color(0xff2c6f9f),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 10),
        Material(
          color: Colors.white,
          elevation: 3,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: abrirSocios,
            borderRadius: BorderRadius.circular(17),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 18, color: Color(0xff07538d)),
                  SizedBox(width: 6),
                  Text('ACCESO', style: TextStyle(color: Color(0xff07538d), fontWeight: FontWeight.w900, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroPublico() {
    return Container(
      width: double.infinity,
      height: 330,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff07538d).withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/inicio_casa_autismo.png',
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _sesionActiva(User user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xff003f88),
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sesión iniciada\n${user.email ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff002b5c),
                fontWeight: FontWeight.bold,
                height: 1.18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: entrarMiPanel,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff1e88e5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'MI PANEL',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _beneficiosPublicos() {
    return Row(
      children: [
        Expanded(child: _beneficioColor(Icons.campaign_rounded, 'Noticias', 'Novedades', const Color(0xffffe5ef), const Color(0xffff4f86))),
        const SizedBox(width: 9),
        Expanded(child: _beneficioColor(Icons.event_available_rounded, 'Actividades', 'Participa', const Color(0xfffff0cf), const Color(0xffffa000))),
        const SizedBox(width: 9),
        Expanded(child: _beneficioColor(Icons.groups_rounded, 'Comunidad', 'Juntos', const Color(0xffdff8ef), const Color(0xff0caf82))),
      ],
    );
  }

  Widget _beneficioColor(IconData icono, String titulo, String subtitulo, Color fondo, Color acento) {
    return Container(
      height: 118,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [BoxShadow(color: acento.withOpacity(.10), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: acento, borderRadius: BorderRadius.circular(14)),
            child: Icon(icono, color: Colors.white, size: 23),
          ),
          const SizedBox(height: 8),
          FittedBox(child: Text(titulo, style: const TextStyle(color: Color(0xff074d82), fontWeight: FontWeight.w900, fontSize: 13.5))),
          const SizedBox(height: 2),
          Text(subtitulo, style: TextStyle(color: acento, fontWeight: FontWeight.w800, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _contenidoPrincipal() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 0),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
      decoration: const BoxDecoration(
        color: Color(0xfffffefe),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Últimas publicaciones',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xff003f88),
              fontSize: 27,
              fontWeight: FontWeight.bold,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Revisa aquí las novedades y enlaces importantes.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 24),
          _listaPublicaciones(),
        ],
      ),
    );
  }

  Widget _listaPublicaciones() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('noticias_comunicaciones')
          .where('visible', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _mensajeVacio(
            icono: Icons.error_outline,
            texto: 'Error al cargar publicaciones',
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 35),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final da = (a.data() as Map<String, dynamic>)['fecha'];
            final db = (b.data() as Map<String, dynamic>)['fecha'];

            if (da is Timestamp && db is Timestamp) {
              return db.compareTo(da);
            }
            return 0;
          });

        if (docs.isEmpty) {
          return _mensajeVacio(
            icono: Icons.campaign,
            texto: 'Aquí aparecerán las noticias y publicaciones activas.',
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _tarjetaPublicacion(data);
          }).toList(),
        );
      },
    );
  }

  Widget _mensajeVacio({required IconData icono, required String texto}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xfff4f6f9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(
            icono,
            color: const Color(0xff1e88e5),
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(String texto, IconData icono) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xffe3f2fd),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: const Color(0xff003f88)),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(
              color: Color(0xff003f88),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPublicacion(Map<String, dynamic> data) {
    final titulo = (data['titulo'] ?? 'Publicación sin título').toString();
    final detalle = (data['descripcion'] ?? data['detalle'] ?? '').toString();
    final tipo = (data['tipo'] ?? 'Noticia').toString();
    final plataforma = (data['plataforma'] ?? 'Link web').toString();
    final link = (data['link'] ?? '').toString();
    final fecha = formatearFecha(data['fecha']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xffe3f2fd),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.campaign,
                  color: Color(0xff003f88),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    height: 1.16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chipInfo(tipo, Icons.label_outline),
              _chipInfo(plataforma, Icons.public),
              if (fecha.isNotEmpty) _chipInfo(fecha, Icons.calendar_month),
            ],
          ),
          if (detalle.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              detalle,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
                height: 1.32,
              ),
            ),
          ],
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: link.isEmpty ? null : () => abrirPublicacion(titulo, link, plataforma),
              icon: Icon(
                _debeAbrirExterno(plataforma, link)
                    ? Icons.open_in_new
                    : Icons.play_circle_fill,
              ),
              label: Text(
                _debeAbrirExterno(plataforma, link)
                    ? 'ABRIR PUBLICACIÓN'
                    : 'VER EN LA APP',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff1e88e5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class VisorPublicacionPublicaPage extends StatefulWidget {
  final String titulo;
  final String url;

  const VisorPublicacionPublicaPage({
    super.key,
    required this.titulo,
    required this.url,
  });

  @override
  State<VisorPublicacionPublicaPage> createState() => _VisorPublicacionPublicaPageState();
}

class _VisorPublicacionPublicaPageState extends State<VisorPublicacionPublicaPage> {
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
          onPageStarted: (_) => setState(() => cargando = true),
          onPageFinished: (_) => setState(() => cargando = false),
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
