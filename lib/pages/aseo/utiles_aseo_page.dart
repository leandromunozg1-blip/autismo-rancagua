import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class UtilesAseoPage extends StatefulWidget {
  const UtilesAseoPage({super.key});

  @override
  State<UtilesAseoPage> createState() => _UtilesAseoPageState();
}

class _UtilesAseoPageState extends State<UtilesAseoPage> {
  final TextEditingController detalleCtrl = TextEditingController();
  final TextEditingController nombreCtrl = TextEditingController();
  final ImagePicker picker = ImagePicker();

  XFile? imagen;
  Uint8List? imagenBytes;
  bool enviando = false;

  @override
  void dispose() {
    detalleCtrl.dispose();
    nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> tomarFoto() async {
    final XFile? foto = await picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1600,
    );

    if (foto == null) return;

    final bytes = await foto.readAsBytes();
    setState(() {
      imagen = foto;
      imagenBytes = bytes;
    });
  }

  Future<void> elegirGaleria() async {
    final XFile? foto = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );

    if (foto == null) return;

    final bytes = await foto.readAsBytes();
    setState(() {
      imagen = foto;
      imagenBytes = bytes;
    });
  }

  Future<void> enviarUtiles() async {
    if (imagen == null) {
      _mensaje('Debes tomar o seleccionar una foto.');
      return;
    }

    if (detalleCtrl.text.trim().isEmpty) {
      _mensaje('Debes ingresar el detalle de los útiles de aseo.');
      return;
    }

    setState(() => enviando = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final fecha = DateTime.now();
      final id = FirebaseFirestore.instance.collection('utiles_aseo').doc().id;

      final ref = FirebaseStorage.instance
          .ref()
          .child('utiles_aseo')
          .child('$id.jpg');

      final bytes = await imagen!.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final urlFoto = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('utiles_aseo').doc(id).set({
        'id': id,
        'uid': user?.uid,
        'email': user?.email,
        'nombre_apoderado': nombreCtrl.text.trim(),
        'detalle': detalleCtrl.text.trim(),
        'foto_url': urlFoto,
        'estado': 'pendiente_revision',
        'fecha_envio': Timestamp.fromDate(fecha),
        'coordinadora_aseo_revisado': false,
      });

      if (!mounted) return;

      _mensaje('Útiles de aseo enviados correctamente.');
      Navigator.of(context).pop();
    } catch (e) {
      _mensaje('Error al enviar: $e');
    } finally {
      if (mounted) {
        setState(() => enviando = false);
      }
    }
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        title: const Text(
          'Útiles de Aseo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF075FC0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enviar aporte de útiles de aseo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF063E83),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Toma una foto de los materiales donados y agrega un detalle para que la coordinadora de aseo pueda revisarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF31506D),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),

            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFB9DEFF), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: imagen == null
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 70,
                            color: Color(0xFF075FC0),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Sin foto seleccionada',
                            style: TextStyle(
                              color: Color(0xFF31506D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.memory(
                        imagenBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: enviando ? null : tomarFoto,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Cámara'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF075FC0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enviando ? null : elegirGaleria,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF075FC0),
                      side: const BorderSide(color: Color(0xFF075FC0), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            TextField(
              controller: nombreCtrl,
              decoration: InputDecoration(
                labelText: 'Nombre del apoderado',
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller: detalleCtrl,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Detalle de útiles entregados',
                hintText: 'Ejemplo: 2 cloros, 1 paquete de papel higiénico, 1 desinfectante...',
                alignLabelWithHint: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: enviando ? null : enviarUtiles,
              icon: enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(enviando ? 'Enviando...' : 'Enviar a coordinadora de aseo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004193),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
