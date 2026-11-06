import 'package:flutter/material.dart';

import 'configuracion_credencial_page.dart';
import 'aseo_apoderado_page.dart';

class InicioPage extends StatelessWidget {
  final VoidCallback? onInicio;
  final VoidCallback? onCredencial;
  final VoidCallback? onTareas;
  final VoidCallback? onComprobante;
  final VoidCallback? onDocumentos;
  final VoidCallback? onReciclaje;
  final VoidCallback? onEventos;
  final VoidCallback? onAvisos;
  final VoidCallback? onSettings;
  final VoidCallback? onLogout;
  final bool mostrarPanelTesoreria;
  final VoidCallback? onTesoreria;
  final bool mostrarMateriales;
  final VoidCallback? onMateriales;
  final String tareasPendientes;
  final String avisosPendientes;

  const InicioPage({
    super.key,
    this.onInicio,
    this.onCredencial,
    this.onTareas,
    this.onComprobante,
    this.onDocumentos,
    this.onReciclaje,
    this.onEventos,
    this.onAvisos,
    this.onSettings,
    this.onLogout,
    this.mostrarPanelTesoreria = false,
    this.onTesoreria,
    this.mostrarMateriales = false,
    this.onMateriales,
    this.tareasPendientes = '0',
    this.avisosPendientes = '0',
  });

  void _volverInicioAnterior(BuildContext context) {
    if (onInicio != null) {
      onInicio!();
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _abrirConfiguracionCredencial(BuildContext context) {
    if (onSettings != null) {
      onSettings!();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ConfiguracionCredencialPage(),
      ),
    );
  }

  void _abrirAseo(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AseoApoderadoPage(),
      ),
    );
  }

  void _cerrarSesion(BuildContext context) {
    if (onLogout != null) {
      onLogout!();
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _sinFuncionAun(BuildContext context, String modulo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$modulo quedará operativo al conectar su módulo.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      body: SafeArea(
        child: Stack(
          children: [
            const _FondoSuave(),
            Column(
              children: [
                _Header(
                  onInicio: () => _volverInicioAnterior(context),
                  onSettings: () => _abrirConfiguracionCredencial(context),
                  onLogout: () => _cerrarSesion(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        const _LogoPrincipal(),
                        const SizedBox(height: 16),
                        const Text(
                          '¡Bienvenido!',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF063E83),
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Estamos aquí para apoyarte',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF31506D),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: _IndicadorOvalado(
                                numero: tareasPendientes,
                                texto: 'TAREAS\nPENDIENTES',
                                icono: Icons.assignment_outlined,
                                color: const Color(0xFF1B64B5),
                                fondo: const Color(0xFFE9F5FF),
                                onTap: onTareas ?? () => _sinFuncionAun(context, 'Tareas pendientes'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _IndicadorOvalado(
                                numero: avisosPendientes,
                                texto: 'AVISOS\nPENDIENTES',
                                icono: Icons.campaign_outlined,
                                color: const Color(0xFFE35D5D),
                                fondo: const Color(0xFFFFF1F1),
                                onTap: onAvisos ?? () => _sinFuncionAun(context, 'Avisos pendientes'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.35,
                          children: [
                            _BotonModulo(
                              titulo: 'CREDENCIAL\nDISCAPACIDAD',
                              icono: Icons.badge_outlined,
                              color1: const Color(0xFF70D4FF),
                              color2: const Color(0xFF28A9E6),
                              onTap: onCredencial ??
                                  () => _sinFuncionAun(
                                        context,
                                        'Credencial discapacidad',
                                      ),
                            ),
                            _BotonModulo(
                              titulo: 'APOYO\nTERAPÉUTICO',
                              icono: Icons.family_restroom,
                              color1: const Color(0xFF70D4FF),
                              color2: const Color(0xFF28A9E6),
                              onTap: onTareas ??
                                  () => _sinFuncionAun(
                                        context,
                                        'Apoyo terapéutico',
                                      ),
                            ),
                            _BotonModulo(
                              titulo: 'ENVIAR\nCOMPROBANTE',
                              icono: Icons.receipt_long_outlined,
                              color1: const Color(0xFF2D9BE8),
                              color2: const Color(0xFF0878D7),
                              onTap: onComprobante ??
                                  () => _sinFuncionAun(
                                        context,
                                        'Enviar comprobante',
                                      ),
                            ),
                            _BotonModulo(
                              titulo: 'DOCUMENTOS',
                              icono: Icons.folder_rounded,
                              color1: const Color(0xFF2D9BE8),
                              color2: const Color(0xFF0878D7),
                              onTap: onDocumentos ??
                                  () => _sinFuncionAun(
                                        context,
                                        'Documentos',
                                      ),
                            ),
                            _BotonModulo(
                              titulo: 'RECICLAJE',
                              icono: Icons.recycling,
                              color1: const Color(0xFF075FC0),
                              color2: const Color(0xFF004193),
                              onTap: onReciclaje ??
                                  () => _sinFuncionAun(
                                        context,
                                        'Reciclaje',
                                      ),
                            ),
                            _BotonModulo(
                              titulo: 'ASEO',
                              icono: Icons.cleaning_services_outlined,
                              color1: const Color(0xFFE67E22),
                              color2: const Color(0xFFC65D00),
                              onTap: () => _abrirAseo(context),
                            ),
                            _BotonModulo(
                              titulo: 'EVENTOS / PTT',
                              icono: Icons.record_voice_over,
                              color1: const Color(0xFF8E44AD),
                              color2: const Color(0xFF6A1B9A),
                              onTap: onEventos ??
                                  () => _sinFuncionAun(context, 'Eventos y canales'),
                            ),
                          ],
                        ),
                        if (mostrarPanelTesoreria) ...[
                          const SizedBox(height: 14),
                          _BotonAccesoTesorero(
                            onTap: onTesoreria,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onInicio;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  const _Header({
    required this.onInicio,
    required this.onSettings,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF003C99),
            Color(0xFF0A84FF),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onInicio,
            borderRadius: BorderRadius.circular(14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.home, color: Colors.white, size: 28),
                SizedBox(width: 5),
                Text(
                  'Inicio',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Autismo\nRancagua',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onSettings,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.settings, color: Colors.white, size: 28),
          ),
          IconButton(
            onPressed: onLogout,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const Icon(Icons.logout, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class _LogoPrincipal extends StatelessWidget {
  const _LogoPrincipal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      height: 145,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/inicio.jpg',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _IndicadorOvalado extends StatelessWidget {
  final String numero;
  final String texto;
  final IconData icono;
  final Color color;
  final Color fondo;
  final VoidCallback? onTap;

  const _IndicadorOvalado({
    required this.numero,
    required this.texto,
    required this.icono,
    required this.color,
    required this.fondo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(42),
      child: Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(45),
        border: Border.all(color: color, width: 1.7),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color,
            child: Icon(icono, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    numero,
                    style: TextStyle(
                      color: color,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      height: 1.03,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _BotonModulo extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Color color1;
  final Color color2;
  final VoidCallback? onTap;

  const _BotonModulo({
    required this.titulo,
    required this.icono,
    required this.color1,
    required this.color2,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color1, color2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: color2.withOpacity(0.22),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icono, color: Colors.white, size: 34),
                const SizedBox(height: 8),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class _BotonAccesoMateriales extends StatelessWidget {
  final VoidCallback? onTap;

  const _BotonAccesoMateriales({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1ED0C6),
              Color(0xFF0077FF),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0077FF).withOpacity(0.22),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.menu_book,
                color: Color(0xFF004193),
                size: 28,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'MATERIALES TERAPÉUTICOS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
}

class _BotonAccesoTesorero extends StatelessWidget {
  final VoidCallback? onTap;

  const _BotonAccesoTesorero({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF004193),
              Color(0xFF0077FF),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF004193).withOpacity(0.22),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.account_balance_wallet,
                color: Color(0xFF004193),
                size: 28,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'PANEL TESORERÍA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
}

class _FondoSuave extends StatelessWidget {
  const _FondoSuave();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FondoPainter(),
      child: Container(),
    );
  }
}

class _FondoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final arriba1 = Paint()..color = const Color(0xFFBFE2FF);
    final arriba2 = Paint()..color = const Color(0xFFDDEFFF);
    final abajo = Paint()..color = const Color(0xFFB9DEFF);

    final path1 = Path()
      ..moveTo(0, 80)
      ..quadraticBezierTo(size.width * 0.30, 35, size.width * 0.58, 62)
      ..quadraticBezierTo(size.width * 0.80, 88, size.width, 70)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path1, arriba1);

    final path2 = Path()
      ..moveTo(0, 118)
      ..quadraticBezierTo(size.width * 0.38, 65, size.width, 104)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path2, arriba2);

    final path3 = Path()
      ..moveTo(0, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.67,
        size.width,
        size.height * 0.75,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path3, abajo);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
