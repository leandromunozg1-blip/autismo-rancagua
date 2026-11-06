import 'package:flutter/material.dart';
import '../../core/widgets/modulo_simple_page.dart';

class PanelReciclajePage extends StatelessWidget {
  const PanelReciclajePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuloSimplePage(
      titulo: 'Panel Reciclaje',
      subtitulo: 'Acceso administrativo separado para reciclaje.',
      icono: Icons.recycling,
    );
  }
}
