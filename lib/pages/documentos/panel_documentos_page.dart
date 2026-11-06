import 'package:flutter/material.dart';
import '../../core/widgets/modulo_simple_page.dart';

class PanelDocumentosPage extends StatelessWidget {
  const PanelDocumentosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuloSimplePage(
      titulo: 'Panel Documentos',
      subtitulo: 'Módulo administrativo de documentos.',
      icono: Icons.folder,
    );
  }
}
