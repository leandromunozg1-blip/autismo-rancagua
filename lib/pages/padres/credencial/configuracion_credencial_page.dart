import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ConfiguracionCredencialPage extends StatefulWidget {
  const ConfiguracionCredencialPage({super.key});

  @override
  State<ConfiguracionCredencialPage> createState() =>
      _ConfiguracionCredencialPageState();
}

class _ConfiguracionCredencialPageState extends State<ConfiguracionCredencialPage> {
  final ImagePicker _picker = ImagePicker();
  String? _credencialBase64;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarCredencialActual();
  }

  Future<void> _cargarCredencialActual() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _cargando = false);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .get();

    final data = doc.data();
    if (!mounted) return;

    setState(() {
      _credencialBase64 = data?['credencial_digital'] as String?;
      _cargando = false;
    });
  }

  Future<void> _tomarFotoCredencial() async {
    final XFile? foto = await _picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1400,
    );

    if (foto == null) return;

    final bytes = await foto.readAsBytes();
    if (!mounted) return;

    setState(() {
      _credencialBase64 = base64Encode(bytes);
    });
  }

  Future<void> _seleccionarDesdeGaleria() async {
    final XFile? imagen = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1400,
    );

    if (imagen == null) return;

    final bytes = await imagen.readAsBytes();
    if (!mounted) return;

    setState(() {
      _credencialBase64 = base64Encode(bytes);
    });
  }

  Future<void> _guardarCredencial() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay usuario activo.')),
      );
      return;
    }

    if (_credencialBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe cargar una foto de la credencial.')),
      );
      return;
    }

    setState(() => _guardando = true);

    await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
      'credencial_digital': _credencialBase64,
      'fecha_actualizacion_credencial': FieldValue.serverTimestamp(),
      'email': user.email,
    }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() => _guardando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Credencial guardada correctamente.')),
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        title: const Text('Configuración'),
        centerTitle: true,
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.badge_outlined,
                          size: 52,
                          color: Color(0xFF004193),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Credencial de discapacidad',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF063E83),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Desde aquí el apoderado puede cargar o actualizar la foto de la credencial. El botón principal será solo para visualizarla.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            color: Color(0xFF31506D),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          height: 260,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F8FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFB6D8FF)),
                          ),
                          child: _credencialBase64 == null
                              ? const Center(
                                  child: Text(
                                    'Sin credencial cargada',
                                    style: TextStyle(
                                      color: Color(0xFF52708E),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.memory(
                                    base64Decode(_credencialBase64!),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _tomarFotoCredencial,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Tomar foto de la credencial'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0878D7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _seleccionarDesdeGaleria,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Seleccionar desde galería'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF004193),
                      side: const BorderSide(color: Color(0xFF004193), width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _guardando ? null : _guardarCredencial,
                    icon: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_guardando ? 'Guardando...' : 'Guardar credencial'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004193),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
