import 'package:flutter/material.dart';
import '../../core/widgets/modulo_simple_page.dart';

class PanelAseoPage extends StatelessWidget {
  const PanelAseoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuloSimplePage(
      titulo: 'Panel Útiles de Aseo',
      subtitulo: 'Acceso administrativo separado para útiles de aseo.',
      icono: Icons.cleaning_services,
    );
  }
}
