import 'package:flutter/material.dart';

import '../../tesoreria.dart';

/// Pantalla de compatibilidad.
///
/// Antes existía un menú intermedio de Tesorería y luego se abría
/// TesoreriaPage. Para evitar duplicar funciones, ahora este archivo
/// mantiene el nombre/clase que ya usan las rutas, pero abre directamente
/// el módulo real de Tesorería.
class TesoreroHomePage extends StatelessWidget {
  const TesoreroHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TesoreriaPage();
  }
}
