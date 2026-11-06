import 'package:flutter/material.dart';

import '../app_roles.dart';
import '../main.dart';
import 'admin/admin_home_page.dart';
import 'modulo_simple_page.dart';
import 'profesionales/profesional_individual_home_page.dart';
import 'tesoreria/tesorero_home_page.dart';
import 'reciclaje/reciclaje_home_page.dart';
import 'coordinacion/coordinacion_home_page.dart';
import 'secretaria/secretaria_home_page.dart';
import 'aseo/aseo_home_page.dart';
import 'eventos/panel_eventos_page.dart';

class RoleRouterPage extends StatelessWidget {
  const RoleRouterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: obtenerRolActual(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final rol = snapshot.data ?? AppRoles.apoderado;

        if (esAdminGlobalPorRol(rol)) {
          return const AdminHomePage();
        }

        switch (rol) {
          case AppRoles.secretaria:
            return const SecretariaHomePage();
          case AppRoles.tesoreria:
            return const TesoreroHomePage();
          case AppRoles.aseo:
            return const AseoHomePage();
          case AppRoles.reciclaje:
            return const ReciclajeHomePage();
          case AppRoles.eventos:
            return const PanelEventosPage();
          case AppRoles.coordinacion:
            return const CoordinacionHomePage();
          case AppRoles.profesional:
            return const ProfesionalIndividualHomePage();
          default:
            return const HomePage();
        }
      },
    );
  }
}
