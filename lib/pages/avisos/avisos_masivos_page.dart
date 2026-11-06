import 'package:flutter/material.dart';
import '../../core/widgets/modulo_simple_page.dart';

class AvisosMasivosPage extends StatelessWidget {
  const AvisosMasivosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuloSimplePage(
      titulo: 'Avisos Masivos',
      subtitulo: 'Módulo preparado para publicar avisos obligatorios y registrar confirmación de lectura.',
      icono: Icons.campaign,
    );
  }
}
