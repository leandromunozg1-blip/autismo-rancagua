import 'package:flutter/material.dart';
import '../../core/widgets/modulo_simple_page.dart';

class PanelCoordinacionPage extends StatelessWidget {
  const PanelCoordinacionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuloSimplePage(
      titulo: 'Panel Coordinación',
      subtitulo: 'Acceso exclusivo para coordinación y seguimiento general.',
      icono: Icons.handshake,
    );
  }
}
