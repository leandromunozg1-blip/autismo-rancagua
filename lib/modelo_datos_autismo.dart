/// Modelo oficial de datos para Autismo Rancagua.
///
/// La base queda centrada en el BENEFICIARIO/USUARIO.
/// El apoderado principal y los apoyos autorizados son contactos asociados.
/// Esto permite que un mismo apoderado tenga 2 o más beneficiarios vinculados.
class ArColecciones {
  static const usuariosSistema = 'usuarios';
  static const beneficiarios = 'ar_beneficiarios';
  static const apoderados = 'ar_apoderados';
  static const profesionales = 'ar_profesionales';
  static const serviciosMensuales = 'ar_servicios_mensuales';
  static const asignaciones = 'ar_asignaciones';
  static const tesoreriaApoderados = 'tesoreria_apoderados';
}

class ArRoles {
  static const adminGeneral = 'admin_general';
  static const adminAsociacion = 'admin_asociacion';
  static const tesoreria = 'tesoreria';
  static const aseo = 'aseo';
  static const reciclaje = 'reciclaje';
  static const eventos = 'eventos';
  static const coordinacion = 'coordinacion';
  static const profesionales = 'profesionales';
  static const apoderado = 'apoderado';
}

String normalizarRutAr(String v) {
  final limpio = v
      .trim()
      .replaceAll('.', '')
      .replaceAll('-', '')
      .replaceAll(' ', '')
      .toUpperCase();

  if (limpio.length < 2) return limpio;

  final cuerpo = limpio.substring(0, limpio.length - 1);
  final dv = limpio.substring(limpio.length - 1);
  return '$cuerpo-$dv';
}

String limpiarTextoAr(dynamic v) => (v ?? '').toString().trim();

int montoAr(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString().replaceAll('.', '').replaceAll(r'$', '').trim()) ?? 0;
}
