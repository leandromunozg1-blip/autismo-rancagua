import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VerCredencialPage extends StatefulWidget {
  const VerCredencialPage({super.key});

  @override
  State<VerCredencialPage> createState() => _VerCredencialPageState();
}

class _VerCredencialPageState extends State<VerCredencialPage> {
  String? _credencialBase64;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarCredencial();
  }

  Future<void> _cargarCredencial() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => _cargando = false);
      return;
    }

    try {
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FF),
      appBar: AppBar(
        title: const Text('Credencial discapacidad'),
        centerTitle: true,
        backgroundColor: const Color(0xFF004193),
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
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
                      child: _credencialBase64 == null
                          ? const Center(
                              child: Text(
                                'No hay credencial cargada.\n\nPara cargarla, vuelve al inicio y entra al engranaje.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF31506D),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  height: 1.35,
                                ),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: InteractiveViewer(
                                minScale: 0.8,
                                maxScale: 4,
                                child: Image.memory(
                                  base64Decode(_credencialBase64!),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) {
                                    return const Center(
                                      child: Text(
                                        'No se pudo mostrar la credencial.',
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Esta pantalla es solo para visualizar la credencial. '
                    'La carga o actualización se realiza desde el engranaje.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF31506D),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
