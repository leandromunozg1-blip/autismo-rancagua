import 'package:flutter/material.dart';

import 'config/firebase_pruebas_v58.dart';
import 'main.dart' as app;

/// Ejecutar SOLO desde una copia de pruebas. Nunca inicializa opciones reales.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FirebasePruebasV58.inicializar();
    await app.iniciarAplicacion(firebaseYaInicializado: true, modoPruebas: true);
  } catch (error) {
    runApp(MaterialApp(home: Scaffold(
      appBar: AppBar(title: const Text('V58 de pruebas: inicio detenido')),
      body: Padding(padding: const EdgeInsets.all(24), child: SelectableText(
        'No se abrió la aplicación ni se conectaron sus pantallas a Firebase.\n\n'
        '$error\n\n'
        'Inicia los emuladores demo-autismo-rancagua-v58 y utiliza las '
        'instrucciones de docs/INSTALAR_Y_PROBAR_EN_WINDOWS.md.',
      )),
    )));
  }
}
