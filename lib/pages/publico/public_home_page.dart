import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

  Future<void> abrirUrlExterna(String url) async {
    final limpio = url.trim();

    if (limpio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay enlace registrado')),
      );
      return;
    }

    final link = limpio.startsWith('http://') || limpio.startsWith('https://')
        ? limpio
        : 'https://$limpio';

    final uri = Uri.parse(link);

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
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
    final double altoPantalla = MediaQuery.of(context).size.height;
    final bool sesionIniciada = user != null;
    final double logoSize = sesionIniciada
        ? (altoPantalla < 720 ? 155 : 175)
        : (altoPantalla < 720 ? 175 : 215);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xfff9fbff),
            Color(0xfff1f5fb),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _encabezado(),
              if (user != null) ...[
                const SizedBox(height: 14),
                _sesionActiva(user),
              ],
              SizedBox(height: sesionIniciada ? 16 : 22),
              Center(
                child: Image.asset(
                  'assets/images/inicio.jpg',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(height: sesionIniciada ? 16 : 22),
              const Text(
                'Noticias y\npublicaciones',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff003f88),
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  height: 1.10,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'Información, actividades, comunicados y novedades para nuestra comunidad.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xff4a4f58),
                    fontSize: 18,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _beneficiosPublicos(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 66,
          height: 66,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/inicio.jpg',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Autismo Rancagua',
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: Color(0xff003f88),
              fontSize: 29,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: abrirSocios,
          icon: const Icon(Icons.lock, size: 17),
          label: const Text(
            'SOCIOS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xff003f88),
            elevation: 4,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _beneficio(Icons.campaign, 'Noticias'),
          _separadorBeneficio(),
          _beneficio(Icons.event_available, 'Actividades'),
          _separadorBeneficio(),
          _beneficio(Icons.groups, 'Comunidad'),
        ],
      ),
    );
  }

  Widget _separadorBeneficio() {
    return Container(
      width: 1,
      height: 62,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.black.withOpacity(0.10),
    );
  }

  Widget _beneficio(IconData icono, String texto) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, color: const Color(0xff1e88e5), size: 30),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              texto,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xff4a4f58),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenidoPrincipal() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 0),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 34),
      decoration: const BoxDecoration(
        color: Colors.white,
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
          .collection('publicaciones')
          .where('activo', isEqualTo: true)
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

  Widget _tarjetaPublicacion(Map<String, dynamic> data) {
    final titulo = (data['titulo'] ?? 'Publicación sin título').toString();
    final detalle = (data['detalle'] ?? '').toString();
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
          if (fecha.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.calendar_month, size: 16, color: Colors.black45),
                const SizedBox(width: 5),
                Text(
                  fecha,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ],
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
              onPressed: link.isEmpty ? null : () => abrirUrlExterna(link),
              icon: const Icon(Icons.open_in_new),
              label: const Text('VER PUBLICACIÓN'),
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
