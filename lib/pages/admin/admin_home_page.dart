import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../public_home.dart';
import '../tesoreria/tesorero_home_page.dart';
import '../coordinacion/coordinacion_home_page.dart';
import '../aseo/aseo_home_page.dart';
import '../reciclaje/reciclaje_home_page.dart';
import '../coordinacion/beneficiarios_contactos_page.dart';
import '../profesionales/profesional_individual_home_page.dart';
import '../comunicaciones/noticias_comunicaciones_page.dart';
import '../reportes/reportes_generales_page.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  Future<void> _cerrarSesion(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const PublicHomePage()),
        (route) => false,
      );
    }
  }

  void _abrir(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _acceso({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.94),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(.12)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF075B98).withOpacity(.055),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icono, color: color, size: 27),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 3,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF174F79),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      maxLines: 3,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF78909C),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withOpacity(.65), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccion(String titulo, String subtitulo, IconData icono) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: const Color(0xFFDFF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, size: 20, color: const Color(0xFF075B98)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF174F79))),
                Text(subtitulo, style: const TextStyle(fontSize: 12.5, color: Color(0xFF78909C), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = c.maxWidth >= 760 ? 3 : 2;
        return GridView.count(
          crossAxisCount: columnas,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: columnas == 3 ? 2.05 : 1.38,
          children: children,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Administrador';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF0066CC),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Panel Administrador', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
        actions: [
          // Se deja preparada visualmente la ubicación del futuro centro de alertas.
          IconButton(
            tooltip: 'Avisos',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => _abrir(context, const NoticiasComunicacionesPage()),
          ),
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: () => _cerrarSesion(context)),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2FAFF), Color(0xFFFFF8F2), Color(0xFFF8F4FF)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE1F4FF), Color(0xFFFFF1C9)]),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [BoxShadow(color: Colors.blue.withOpacity(.08), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('¡Hola, Administración! 👋', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF075B98))),
                          const SizedBox(height: 5),
                          const Text('Centro de gestión', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF174F79))),
                          const SizedBox(height: 5),
                          const Text('Accede rápidamente a las áreas de Autismo Rancagua.', style: TextStyle(fontSize: 13.5, height: 1.25, color: Color(0xFF567185))),
                          const SizedBox(height: 8),
                          Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF78909C), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Image.asset('assets/images/ayudante_autismo_rancagua.png', width: 94, height: 108, fit: BoxFit.contain),
                  ],
                ),
              ),

              _seccion('Gestión principal', 'Resumen, coordinación y finanzas', Icons.dashboard_customize_rounded),
              _grid([
                _acceso(context: context, titulo: 'Dashboard general', subtitulo: 'Resumen y reportes', icono: Icons.analytics_rounded, color: const Color(0xFF1697E5), onTap: () => _abrir(context, const ReportesGeneralesPage())),
                _acceso(context: context, titulo: 'Coordinación', subtitulo: 'Usuarios y asignaciones', icono: Icons.manage_accounts_rounded, color: const Color(0xFF00A99D), onTap: () => _abrir(context, const CoordinacionHomePage())),
                _acceso(context: context, titulo: 'Tesorería', subtitulo: 'Pagos y contabilidad', icono: Icons.account_balance_wallet_rounded, color: const Color(0xFF0066CC), onTap: () => _abrir(context, const TesoreroHomePage())),
                _acceso(context: context, titulo: 'Panel profesional', subtitulo: 'Atenciones y seguimiento', icono: Icons.psychology_alt_rounded, color: const Color(0xFFF2A900), onTap: () => _abrir(context, const ProfesionalIndividualHomePage())),
              ]),

              _seccion('Personas', 'Beneficiarios, contactos y red de apoyo', Icons.groups_rounded),
              _grid([
                _acceso(context: context, titulo: 'Beneficiarios y apoyos', subtitulo: 'Contactos y red de apoyo', icono: Icons.family_restroom_rounded, color: const Color(0xFF8E44AD), onTap: () => _abrir(context, const BeneficiariosContactosPage())),
              ]),

              _seccion('Organización y comunidad', 'Funcionamiento cotidiano de la sede', Icons.volunteer_activism_rounded),
              _grid([
                _acceso(context: context, titulo: 'Aseo', subtitulo: 'Turnos y organización', icono: Icons.cleaning_services_rounded, color: const Color(0xFF20B98E), onTap: () => _abrir(context, const AseoHomePage())),
                _acceso(context: context, titulo: 'Reciclaje', subtitulo: 'Aportes y puntos', icono: Icons.recycling_rounded, color: const Color(0xFF55A630), onTap: () => _abrir(context, const ReciclajeHomePage())),
                _acceso(context: context, titulo: 'Noticias y avisos', subtitulo: 'Comunicaciones generales', icono: Icons.campaign_rounded, color: const Color(0xFF075B98), onTap: () => _abrir(context, const NoticiasComunicacionesPage())),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
