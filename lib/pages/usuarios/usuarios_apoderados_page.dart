import 'package:flutter/material.dart';
import '../../core/widgets/modulo_simple_page.dart';

class UsuariosApoderadosPage extends StatelessWidget {
  const UsuariosApoderadosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuloSimplePage(
      titulo: 'Usuarios Apoderados',
      subtitulo: 'Módulo reservado para administrar apoderados y perfiles familiares.',
      icono: Icons.groups,
    );
  }
}
