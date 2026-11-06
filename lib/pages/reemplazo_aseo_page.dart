import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ReemplazoAseoPage extends StatefulWidget {
  final DateTime? fechaInicial;
  final String? agendaAseoId;
  final int? montoInicial;
  const ReemplazoAseoPage({super.key, this.fechaInicial, this.agendaAseoId, this.montoInicial});

  @override
  State<ReemplazoAseoPage> createState() => _ReemplazoAseoPageState();
}

class _ReemplazoAseoPageState extends State<ReemplazoAseoPage> {
  final TextEditingController montoCtrl = TextEditingController();
  final TextEditingController observacionCtrl = TextEditingController();
  final ImagePicker picker = ImagePicker();
  final DateFormat _fecha = DateFormat('dd-MM-yyyy');

  XFile? imagen;
  Uint8List? imagenBytes;
  DateTime? viernesSeleccionado;
  bool enviando = false;

  @override
  void initState() {
    super.initState();
    viernesSeleccionado = widget.fechaInicial;
    montoCtrl.text = (widget.montoInicial ?? 10000).toString();
  }

  @override
  void dispose() {
    montoCtrl.dispose();
    observacionCtrl.dispose();
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

  int _montoLimpio(String valor) {
    return int.tryParse(valor.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  List<DateTime> _viernesDisponibles() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final fin = DateTime(now.year, now.month + 2, 0);
    final dias = <DateTime>[];
    for (var d = base; !d.isAfter(fin); d = d.add(const Duration(days: 1))) {
      if (d.weekday == DateTime.friday) {
        dias.add(DateTime(d.year, d.month, d.day));
      }
    }
    return dias;
  }

  String _idDia(DateTime fecha) => '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

  Future<void> enviarComprobante() async {
    if (imagen == null) {
      _mensaje('Debes tomar o seleccionar una foto del comprobante.');
      return;
    }
    if (viernesSeleccionado == null) {
      _mensaje('Debes seleccionar el viernes de pago/reemplazo desde el calendario principal.');
      return;
    }
    if (_montoLimpio(montoCtrl.text) <= 0) {
      _mensaje('Debes ingresar el monto pagado por reemplazo.');
      return;
    }

    setState(() => enviando = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final fecha = DateTime.now();
      final id = FirebaseFirestore.instance.collection('aseo_reemplazos').doc().id;

      final uid = user?.uid ?? 'sin_uid';
      final nombreArchivo = 'aseo/reemplazos/$uid/$id.jpg';
      final ref = FirebaseStorage.instance.ref().child(nombreArchivo);
      final bytes = await imagen!.readAsBytes();

      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      ).timeout(const Duration(seconds: 45));

      String urlFoto = '';
      for (int intento = 0; intento < 3; intento++) {
        try {
          urlFoto = await uploadTask.ref.getDownloadURL().timeout(const Duration(seconds: 15));
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }

      String nombreApoderado = user?.displayName ?? '';
      String beneficiarioNombre = '';
      try {
        if (user != null) {
          final usuarioDoc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
          final usuarioData = usuarioDoc.data() ?? {};
          nombreApoderado = (usuarioData['nombre'] ?? usuarioData['nombre_apoderado'] ?? usuarioData['apoderadoNombre'] ?? nombreApoderado).toString();
          beneficiarioNombre = (usuarioData['beneficiario'] ?? usuarioData['beneficiario_nombre'] ?? usuarioData['nombre_beneficiario'] ?? '').toString();
        }
      } catch (_) {}
      if (nombreApoderado.trim().isEmpty) nombreApoderado = user?.email ?? 'Apoderado no informado';
      if (beneficiarioNombre.trim().isEmpty) beneficiarioNombre = 'No informado';

      final diaId = _idDia(viernesSeleccionado!);
      await FirebaseFirestore.instance.collection('aseo_reemplazos').doc(id).set({
        'id': id,
        'uid': user?.uid,
        'email': user?.email,
        'nombre_apoderado': nombreApoderado,
        'apoderadoNombre': nombreApoderado,
        'beneficiario': beneficiarioNombre,
        'beneficiario_nombre': beneficiarioNombre,
        'monto': _montoLimpio(montoCtrl.text),
        'observacion': observacionCtrl.text.trim(),
        'fecha_viernes': Timestamp.fromDate(viernesSeleccionado!),
        'dia_id': diaId,
        'fecha_limite_pago': Timestamp.fromDate(viernesSeleccionado!),
        'foto_url': urlFoto,
        'foto_path': nombreArchivo,
        'estado': 'pendiente_revision',
        'estado_tesoreria': 'pendiente_revision',
        'fecha_envio': Timestamp.fromDate(fecha),
        'es_pago_reemplazo_aseo': true,
        'visible_tesoreria': true,
        'afecta_tesoreria': true,
        'tipo_tesoreria': 'reemplazo_aseo',
        'categoria_tesoreria': 'Cobro operativo de aseo',
        'es_ingreso_institucional': false,
        'nota_contable': 'Reemplazo de aseo: Tesorería solo recibe el registro para estadísticas, control y cobro. No suma a caja general ni a ingresos institucionales.',
        'revisado_por': null,
        'fecha_revision': null,
        'agenda_aseo_id': widget.agendaAseoId,
        'cupo_maximo_viernes': 5,
        'agendado_reemplazo_aseo': true,
        'monto_reemplazo_oficial': 10000,
        'aviso_desde_lunes_anterior': true,
        'fecha_inicio_aviso_pago': Timestamp.fromDate(viernesSeleccionado!.subtract(const Duration(days: 4))),
        'mensaje_aviso_pago': 'Recuerda cancelar \$10.000 por el reemplazo de aseo antes del viernes.',
      });
      if ((widget.agendaAseoId ?? '').isNotEmpty) {
        await FirebaseFirestore.instance.collection('agenda_aseo').doc(widget.agendaAseoId).update({
          'modalidad':'reemplazo','estado':'reemplazo_comprobante','estado_pago_reemplazo':'comprobante_enviado','reemplazo_comprobante_id':id,'reemplazo_comprobante_url':urlFoto,'fecha_comprobante_reemplazo':FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      _mensaje('Comprobante de reemplazo enviado correctamente.');
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('ERROR REEMPLAZO ASEO: $e');
      _mensaje('Error al enviar comprobante de reemplazo: $e');
    } finally {
      if (mounted) setState(() => enviando = false);
    }
  }

  void _mensaje(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        title: const Text('Pago y reemplazo aseo', style: TextStyle(fontWeight: FontWeight.w800)),
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
              'Enviar comprobante de reemplazo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF063E83), fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'El viernes de pago/reemplazo se selecciona en el calendario principal. Aquí solo debes subir el comprobante. El monto de reemplazo es de \$10.000.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF31506D), fontSize: 15),
            ),
            const SizedBox(height: 24),
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFB9DEFF), width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.blue.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 8)),
                ],
              ),
              child: imagen == null
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 70, color: Color(0xFF075FC0)),
                          SizedBox(height: 10),
                          Text('Sin comprobante seleccionado', style: TextStyle(color: Color(0xFF31506D), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.memory(imagenBytes!, fit: BoxFit.cover, width: double.infinity),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFCC80), width: 2),
              ),
              child: Text(
                viernesSeleccionado == null
                    ? 'Viernes no seleccionado. Vuelve al calendario principal y selecciona un viernes.'
                    : 'Viernes de pago/reemplazo: ${_fecha.format(viernesSeleccionado!)}\nAviso desde el lunes anterior para cancelar \$10.000.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF063E83), fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 14),
            _campo(montoCtrl, 'Monto pagado por reemplazo', Icons.payments_outlined, teclado: TextInputType.number),
            const SizedBox(height: 14),
            TextField(
              controller: observacionCtrl,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Observación opcional',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: enviando ? null : enviarComprobante,
              icon: enviando
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(enviando ? 'Enviando...' : 'Enviar comprobante'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004193),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(TextEditingController controller, String label, IconData icono, {TextInputType? teclado}) {
    return TextField(
      controller: controller,
      keyboardType: teclado,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
