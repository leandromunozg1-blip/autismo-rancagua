import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../modelo_datos_autismo.dart';

const int valorMensualidadGeneral = 5000;

class CargaMasivaRealPage extends StatefulWidget {
  const CargaMasivaRealPage({super.key});

  @override
  State<CargaMasivaRealPage> createState() => _CargaMasivaRealPageState();
}

class _CargaMasivaRealPageState extends State<CargaMasivaRealPage> {
  final TextEditingController datosCtrl = TextEditingController();
  bool cargando = false;
  String tipo = 'beneficiarios';
  String resultado = '';
  bool generarInvitaciones = true;

  @override
  void dispose() {
    datosCtrl.dispose();
    super.dispose();
  }

  List<String> _splitLinea(String linea) {
    if (linea.contains('\t')) return linea.split('\t').map((e) => e.trim()).toList();
    if (linea.contains(';')) return linea.split(';').map((e) => e.trim()).toList();
    return linea.split(',').map((e) => e.trim()).toList();
  }

  Future<void> _importar() async {
    final texto = datosCtrl.text.trim();
    if (texto.isEmpty) {
      _msg('Pega datos desde Google Sheets o CSV.');
      return;
    }

    setState(() {
      cargando = true;
      resultado = '';
    });

    int ok = 0;
    int errores = 0;
    final erroresDetalle = <String>[];
    final lineas = texto.split('\n').where((e) => e.trim().isNotEmpty).toList();

    try {
      for (int i = 0; i < lineas.length; i++) {
        final linea = lineas[i].trim();
        final cols = _splitLinea(linea);

        // Permite pegar encabezados desde Google Forms/Sheets.
        if (i == 0 && linea.toLowerCase().contains('rut_beneficiario')) continue;
        if (i == 0 && linea.toLowerCase().contains('rut_profesional')) continue;
        if (i == 0 && linea.toLowerCase().contains('correo') && tipo == 'administradores') continue;

        try {
          if (tipo == 'beneficiarios') {
            await _guardarBeneficiario(cols);
          } else if (tipo == 'profesionales') {
            await _guardarProfesional(cols);
          } else {
            await _guardarAdministrador(cols);
          }
          ok++;
        } catch (e) {
          errores++;
          erroresDetalle.add('Línea ${i + 1}: $e');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          cargando = false;
          resultado = "Importados: $ok\nInvitaciones preparadas: ${tipo == 'beneficiarios' && generarInvitaciones ? 'sí' : 'no'}\nErrores: $errores${erroresDetalle.isEmpty ? '' : '\n\n${erroresDetalle.take(8).join('\n')}'}";
        });
      }
    }
  }

  Future<void> _guardarBeneficiario(List<String> c) async {
    // Orden columnas Google Form/Sheets:
    // 0 rut_beneficiario
    // 1 nombre_beneficiario
    // 2 fecha_nacimiento
    // 3 direccion
    // 4 observaciones
    // 5 rut_apoderado_principal
    // 6 nombre_apoderado_principal
    // 7 telefono_apoderado_principal
    // 8 correo_apoderado_principal
    // 9 parentesco_apoderado_principal
    // 10 rut_apoyo_1
    // 11 nombre_apoyo_1
    // 12 telefono_apoyo_1
    // 13 parentesco_apoyo_1
    // 14 rut_apoyo_2
    // 15 nombre_apoyo_2
    // 16 telefono_apoyo_2
    // 17 parentesco_apoyo_2
    // 18 rut_apoyo_3
    // 19 nombre_apoyo_3
    // 20 telefono_apoyo_3
    // 21 parentesco_apoyo_3
    final rutBeneficiario = normalizarRutAr(c.length > 0 ? c[0] : '');
    final nombreBeneficiario = limpiarTextoAr(c.length > 1 ? c[1] : '');
    final rutApoderado = normalizarRutAr(c.length > 5 ? c[5] : '');
    final nombreApoderado = limpiarTextoAr(c.length > 6 ? c[6] : '');

    if (rutBeneficiario.isEmpty || nombreBeneficiario.isEmpty) {
      throw 'Falta RUT o nombre del beneficiario';
    }
    if (rutApoderado.isEmpty || nombreApoderado.isEmpty) {
      throw 'Falta RUT o nombre del apoderado principal';
    }

    final apoyos = <Map<String, dynamic>>[];
    void addApoyo(int rutIdx, int nombreIdx, int telIdx, int parIdx) {
      final rut = normalizarRutAr(c.length > rutIdx ? c[rutIdx] : '');
      final nombre = limpiarTextoAr(c.length > nombreIdx ? c[nombreIdx] : '');
      if (rut.isEmpty && nombre.isEmpty) return;
      apoyos.add({
        'rut': rut,
        'nombre': nombre,
        'telefono': limpiarTextoAr(c.length > telIdx ? c[telIdx] : ''),
        'parentesco': limpiarTextoAr(c.length > parIdx ? c[parIdx] : ''),
        'autorizado': true,
      });
    }

    addApoyo(10, 11, 12, 13);
    addApoyo(14, 15, 16, 17);
    addApoyo(18, 19, 20, 21);

    final db = FirebaseFirestore.instance;
    final emailApoderado = limpiarTextoAr(c.length > 8 ? c[8] : '').toLowerCase();
    final telefonoApoderado = limpiarTextoAr(c.length > 7 ? c[7] : '');

    await db.collection(ArColecciones.apoderados).doc(rutApoderado).set({
      'rut': rutApoderado,
      'nombre': nombreApoderado,
      'telefono': telefonoApoderado,
      'email': emailApoderado,
      'parentesco': limpiarTextoAr(c.length > 9 ? c[9] : ''),
      'activo': true,
      'actualizado': FieldValue.serverTimestamp(),
      'creado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (generarInvitaciones && emailApoderado.isNotEmpty) {
      final invitacionId = emailApoderado.replaceAll(RegExp(r'[^a-z0-9]'), '_');
      await db.collection('ar_invitaciones_usuarios').doc(invitacionId).set({
        'email': emailApoderado,
        'nombre': nombreApoderado,
        'rut_apoderado': rutApoderado,
        'rol': 'apoderado',
        'estado': 'pendiente',
        'enviar_correo': true,
        'beneficiarios_rut': FieldValue.arrayUnion([rutBeneficiario]),
        'solicitado_por_uid': FirebaseAuth.instance.currentUser?.uid,
        'solicitado_por_email': FirebaseAuth.instance.currentUser?.email,
        'actualizado': FieldValue.serverTimestamp(),
        'creado': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await db.collection(ArColecciones.beneficiarios).doc(rutBeneficiario).set({
      'rut': rutBeneficiario,
      'nombre': nombreBeneficiario,
      'fecha_nacimiento': limpiarTextoAr(c.length > 2 ? c[2] : ''),
      'direccion': limpiarTextoAr(c.length > 3 ? c[3] : ''),
      'observaciones': limpiarTextoAr(c.length > 4 ? c[4] : ''),
      'estado': 'activo',
      'mensualidad_base': valorMensualidadGeneral,
      'cuenta_destino': 'CUENTA CORRIENTE',
      'apoderado_principal': {
        'rut': rutApoderado,
        'nombre': nombreApoderado,
        'telefono': telefonoApoderado,
        'email': emailApoderado,
        'parentesco': limpiarTextoAr(c.length > 9 ? c[9] : ''),
      },
      'rut_apoderado': rutApoderado,
      'nombre_apoderado': nombreApoderado,
      'telefono_apoderado': telefonoApoderado,
      'email_apoderado': emailApoderado,
      'apoyos_autorizados': apoyos,
      'apoderados_uids_autorizados': [],
      'creado_por': FirebaseAuth.instance.currentUser?.email,
      'actualizado': FieldValue.serverTimestamp(),
      'creado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Tesorería se centra en beneficiario: cada beneficiario tiene su cuenta financiera.
    await db.collection(ArColecciones.tesoreriaApoderados).doc(rutBeneficiario).set({
      'uid': rutBeneficiario,
      'rut_usuario': rutBeneficiario,
      'nombre_usuario': nombreBeneficiario,
      'nombre': nombreBeneficiario,
      'rut_apoderado': rutApoderado,
      'nombre_apoderado': nombreApoderado,
      'email': emailApoderado,
      'telefono': telefonoApoderado,
      'cuota_mensual': valorMensualidadGeneral,
      'monto_deuda': 0,
      'saldo_favor': 0,
      'meses_morosos': 0,
      'estado_pago': 'pendiente',
      'estado_terapias': 'activo',
      'cuenta_destino': 'CUENTA CORRIENTE',
      'actualizado': FieldValue.serverTimestamp(),
      'fecha_creacion': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _guardarProfesional(List<String> c) async {
    // 0 rut_profesional, 1 nombre, 2 especialidad, 3 telefono, 4 correo
    final rut = normalizarRutAr(c.length > 0 ? c[0] : '');
    final nombre = limpiarTextoAr(c.length > 1 ? c[1] : '');
    if (rut.isEmpty || nombre.isEmpty) throw 'Falta RUT o nombre profesional';
    await FirebaseFirestore.instance.collection(ArColecciones.profesionales).doc(rut).set({
      'rut': rut,
      'nombre': nombre,
      'especialidad': limpiarTextoAr(c.length > 2 ? c[2] : ''),
      'telefono': limpiarTextoAr(c.length > 3 ? c[3] : ''),
      'email': limpiarTextoAr(c.length > 4 ? c[4] : '').toLowerCase(),
      'activo': true,
      'creado_por': FirebaseAuth.instance.currentUser?.email,
      'creado': FieldValue.serverTimestamp(),
      'actualizado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _guardarAdministrador(List<String> c) async {
    // 0 correo, 1 rol, 2 nombre
    final correo = limpiarTextoAr(c.length > 0 ? c[0] : '').toLowerCase();
    final rol = limpiarTextoAr(c.length > 1 ? c[1] : '').toLowerCase();
    final nombre = limpiarTextoAr(c.length > 2 ? c[2] : '');
    if (correo.isEmpty || rol.isEmpty) throw 'Falta correo o rol';
    await FirebaseFirestore.instance.collection(ArColecciones.usuariosSistema).doc(correo).set({
      'email': correo,
      'rol': rol,
      'nombre': nombre,
      'activo': true,
      'creado_por': FirebaseAuth.instance.currentUser?.email,
      'creado': FieldValue.serverTimestamp(),
      'actualizado': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _msg(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  String get ejemplo {
    if (tipo == 'profesionales') {
      return 'rut_profesional\tnombre\tespecialidad\ttelefono\tcorreo\nRUT_EJEMPLO\tProfesional de ejemplo\tTerapeuta ocupacional\tTELEFONO_EJEMPLO\tprofesional@example.test';
    }
    if (tipo == 'administradores') {
      return 'correo\trol\tnombre\ntesoreria@example.test\ttesoreria\tEncargada Tesorería\nreciclaje@example.test\treciclaje\tEncargada Reciclaje';
    }
    return 'rut_beneficiario\tnombre_beneficiario\tfecha_nacimiento\tdireccion\tobservaciones\trut_apoderado_principal\tnombre_apoderado_principal\ttelefono_apoderado_principal\tcorreo_apoderado_principal\tparentesco_apoderado_principal\trut_apoyo_1\tnombre_apoyo_1\ttelefono_apoyo_1\tparentesco_apoyo_1\trut_apoyo_2\tnombre_apoyo_2\ttelefono_apoyo_2\tparentesco_apoyo_2\trut_apoyo_3\tnombre_apoyo_3\ttelefono_apoyo_3\tparentesco_apoyo_3';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carga masiva real'),
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Carga masiva desde Google Forms / Google Sheets',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text('Pega las filas copiadas desde Google Sheets. La primera fila puede ser encabezado.'),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'beneficiarios', label: Text('Beneficiarios')),
              ButtonSegment(value: 'profesionales', label: Text('Profesionales')),
              ButtonSegment(value: 'administradores', label: Text('Admins')),
            ],
            selected: {tipo},
            onSelectionChanged: (v) => setState(() => tipo = v.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: datosCtrl,
            minLines: 12,
            maxLines: 18,
            decoration: InputDecoration(
              labelText: 'Datos pegados',
              hintText: ejemplo,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          if (tipo == 'beneficiarios')
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: generarInvitaciones,
              onChanged: cargando ? null : (v) => setState(() => generarInvitaciones = v),
              title: const Text('Preparar acceso de los apoderados', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Crea una invitación pendiente para que una Cloud Function genere la cuenta y envíe el enlace de contraseña. No crea usuarios Auth desde el teléfono.'),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: cargando ? null : _importar,
            icon: cargando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file),
            label: Text(cargando ? 'Importando...' : 'Importar a Firebase'),
          ),
          const SizedBox(height: 16),
          if (resultado.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(resultado),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Roles válidos: admin_general, admin_asociacion, tesoreria, aseo, reciclaje, eventos, coordinacion, profesionales, apoderado.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
