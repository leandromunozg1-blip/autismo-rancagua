import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// El identificador y los puertos DEMO son fijos: no toma opciones productivas.
class FirebasePruebasV58 {
  static const projectId = 'demo-autismo-rancagua-v58';
  static const host = String.fromEnvironment(
    'V58_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  static Future<void> inicializar() async {
    if (!const ['127.0.0.1', 'localhost', '10.0.2.2'].contains(host)) {
      throw StateError('V58 de pruebas solo admite emuladores locales. '
          'Usa 127.0.0.1 en web o 10.0.2.2 en Android Emulator.');
    }
    for (final app in Firebase.apps) {
      if (app.name == '[DEFAULT]' && app.options.projectId != projectId) {
        throw StateError('Se detectó Firebase de producción. Se abortó el inicio. '
            'Usa una copia DEMO sin google-services.json ni plist reales.');
      }
    }
    final platform = kIsWeb ? 'web' : switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
      _ => 'web',
    };
    final options = FirebaseOptions(
      apiKey: 'demo-api-key-autismo-rancagua-v58',
      appId: '1:123456789012:$platform:58a058a058a058a0',
      messagingSenderId: '123456789012',
      projectId: projectId,
      authDomain: '$projectId.firebaseapp.com',
      storageBucket: '$projectId.appspot.com',
      iosBundleId: platform == 'ios' ? 'cl.autismorancagua.demo.v58' : null,
    );
    final app = await Firebase.initializeApp(options: options);
    if (app.options.projectId != projectId) {
      throw StateError('La aplicación activa no es el proyecto DEMO.');
    }
    // Configurar TODOS los SDK antes del primer login/lectura/subida/callable.
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
    FirebaseFunctions.instanceFor(region: 'southamerica-west1')
        .useFunctionsEmulator(host, 5001);
  }
}
