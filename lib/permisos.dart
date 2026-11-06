import 'app_roles.dart';

Future<String> obtenerRolUsuario() async {
  return obtenerRolActual();
}

Future<bool> esAdmin() async {
  final rol = await obtenerRolActual();
  return esAdminGlobalPorRol(rol);
}

Future<bool> esTesorero() async {
  final rol = await obtenerRolActual();
  return rol == AppRoles.tesoreria || esAdminGlobalPorRol(rol);
}

Future<bool> esPresidente() async {
  final rol = await obtenerRolActual();
  return rol == AppRoles.adminAsociacion || rol == AppRoles.adminGeneral;
}


Future<bool> puedeVerSecretaria() async {
  final rol = await obtenerRolActual();
  return rol == AppRoles.secretaria || esAdminGlobalPorRol(rol);
}

Future<bool> puedeVerTesoreria() async {
  final rol = await obtenerRolActual();
  return rol == AppRoles.tesoreria || esAdminGlobalPorRol(rol);
}

Future<bool> puedeAdministrarUsuarios() async {
  final rol = await obtenerRolActual();
  return esAdminGlobalPorRol(rol);
}

Future<bool> puedeVerModulo(String modulo) async {
  final rol = await obtenerRolActual();
  if (esAdminGlobalPorRol(rol)) return true;
  return rol == normalizarRol(modulo);
}
