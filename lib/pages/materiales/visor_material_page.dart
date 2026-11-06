import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class VisorMaterialPage extends StatefulWidget {
  final String titulo;
  final String url;

  const VisorMaterialPage({
    super.key,
    required this.titulo,
    required this.url,
  });

  @override
  State<VisorMaterialPage> createState() => _VisorMaterialPageState();
}

class _VisorMaterialPageState extends State<VisorMaterialPage> {
  late final WebViewController controller;
  bool cargando = true;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => cargando = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Usuario autorizado';
    final marcaAgua = '$email • Autismo Rancagua';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0047B3),
        foregroundColor: Colors.white,
        title: Text(widget.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (cargando) const Center(child: CircularProgressIndicator()),
          IgnorePointer(
            ignoring: true,
            child: Center(
              child: Transform.rotate(
                angle: -0.45,
                child: Opacity(
                  opacity: 0.13,
                  child: Text(
                    marcaAgua,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
