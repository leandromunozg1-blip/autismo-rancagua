# Respaldo V58 recuperada en GitHub

Esta rama conserva los archivos fuente recuperados, las modificaciones de integración de Tesorería/Apoderados, las pruebas, las reglas propuestas y la documentación Windows. Es un respaldo de trabajo en curso, no una versión de producción validada ni un despliegue Firebase. No se habilitó la automatización.

## Exclusiones y configuración local

Se excluyen cachés, dependencias instaladas, resultados de compilación, logs, ZIP, bases/exportaciones, claves privadas y configuración local. También se excluye `assets/images/tesoreria_v25/referencia_diseno_v25e.png`, referencia de diseño con datos personales que no es necesaria para ejecutar la app.

Los correos de acceso heredados y la configuración Firebase se externalizaron a variables de compilación: no se suben valores reales. Los archivos originales y el archivo `local_config/firebase.define.json` se conservan localmente, fuera del respaldo Git. Los roles de Firestore siguen funcionando según sus documentos; los fallbacks por correo solo se habilitan si se configura un valor no vacío.

Para preparar otra máquina, copiar `docs/firebase.define.example.json` a `local_config/firebase.define.json` y completar los valores de manera privada, o recuperar la copia local existente. Después ejecutar:

```sh
flutter run --dart-define-from-file=local_config/firebase.define.json
```

No compartir ese JSON ni agregarlo a Git. El punto de entrada `lib/main_v58_pruebas.dart` usa exclusivamente datos ficticios/emuladores y no requiere la configuración de producción.

La semilla DEMO requiere `V58_DEMO_PASSWORD` definido únicamente en el proceso local (al menos 12 caracteres); no hay contraseñas hardcodeadas ni se imprime su valor. Las direcciones `example.test` de los fixtures son ficticias. Las pruebas conservan sus fixtures y lockfiles; no incluyen registros de personas reales ni credenciales administrativas.

## Estado de las comprobaciones

La sintaxis y las suites del backend se comprueban localmente. Flutter y las pruebas con emuladores requieren las herramientas descritas en la guía Windows; no se deben presentar como aprobadas mientras no se ejecuten. Los informes anteriores describen sus respectivas revisiones; el presente respaldo incluye también modificaciones posteriores y la sanitización de datos/configuración solicitada para GitHub.

Las reglas de producción V57 no venían en el archivo original. Los fragmentos entregados deben integrarse y probarse contra las reglas reales antes de cualquier publicación. No se ejecutaron despliegues ni operaciones con datos reales.

En la revisión final de este respaldo pasaron 50 pruebas del backend y la comprobación sintáctica de 65 archivos Dart. Se completó además la comprobación de imágenes para excluir la referencia con datos personales. Una prueba recuperada detectó que el estado legado `pendiente_revision` omitía la verificación de imagen: el guard se corrigió para exigirla en ambos estados pendientes y la prueba pasó. Esto no constituye una validación Flutter ni de reglas en emuladores, que continúan pendientes.
