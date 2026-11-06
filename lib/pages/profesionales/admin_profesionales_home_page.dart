import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminProfesionalesHomePage extends StatefulWidget {
  const AdminProfesionalesHomePage({super.key});

  @override
  State<AdminProfesionalesHomePage> createState() => _AdminProfesionalesHomePageState();
}

class _AdminProfesionalesHomePageState extends State<AdminProfesionalesHomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _GestionProfesionalesTab(),
      const _AsignacionesTab(),
      const _AgendaGeneralTab(),
      const _TalleresTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0047B3),
        foregroundColor: Colors.white,
        title: const Text('Administración de Profesionales'),
        centerTitle: true,
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.badge), label: 'Profesionales'),
          NavigationDestination(icon: Icon(Icons.link), label: 'Asignar'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Agenda'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Talleres'),
        ],
      ),
    );
  }
}

InputDecoration _deco(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );

class _GestionProfesionalesTab extends StatefulWidget {
  const _GestionProfesionalesTab();

  @override
  State<_GestionProfesionalesTab> createState() => _GestionProfesionalesTabState();
}

class _GestionProfesionalesTabState extends State<_GestionProfesionalesTab> {
  final nombreCtrl = TextEditingController();
  final rutCtrl = TextEditingController();
  final correoCtrl = TextEditingController();
  final telefonoCtrl = TextEditingController();
  final especialidadCtrl = TextEditingController();
  bool guardando = false;

  @override
  void dispose() {
    nombreCtrl.dispose();
    rutCtrl.dispose();
    correoCtrl.dispose();
    telefonoCtrl.dispose();
    especialidadCtrl.dispose();
    super.dispose();
  }

  Future<void> guardar() async {
    final nombre = nombreCtrl.text.trim();
    final correo = correoCtrl.text.trim().toLowerCase();
    if (nombre.isEmpty || correo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre y correo son obligatorios.')));
      return;
    }
    setState(() => guardando = true);
    try {
      final db = FirebaseFirestore.instance;
      final doc = await db.collection('profesionales').add({
        'nombre': nombre,
        'rut': rutCtrl.text.trim(),
        'email': correo,
        'telefono': telefonoCtrl.text.trim(),
        'especialidad': especialidadCtrl.text.trim(),
        'estado': 'activo',
        'rol': 'profesional',
        'fecha_creacion': FieldValue.serverTimestamp(),
      });
      await db.collection('usuarios_roles_pendientes').doc(correo).set({
        'email': correo,
        'rol': 'profesional',
        'profesional_id': doc.id,
        'nombre': nombre,
        'estado': 'pendiente_uid',
        'fecha_creacion': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      nombreCtrl.clear();
      rutCtrl.clear();
      correoCtrl.clear();
      telefonoCtrl.clear();
      especialidadCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profesional creado. Cuando inicie sesión, asigna su UID en usuarios.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> cambiarEstado(String id, String estado) async {
    await FirebaseFirestore.instance.collection('profesionales').doc(id).update({'estado': estado});
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Crear profesional', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
                const SizedBox(height: 12),
                TextField(controller: nombreCtrl, decoration: _deco('Nombre profesional', Icons.person)),
                const SizedBox(height: 10),
                TextField(controller: rutCtrl, decoration: _deco('RUT profesional', Icons.credit_card)),
                const SizedBox(height: 10),
                TextField(controller: correoCtrl, keyboardType: TextInputType.emailAddress, decoration: _deco('Correo de acceso', Icons.email)),
                const SizedBox(height: 10),
                TextField(controller: telefonoCtrl, keyboardType: TextInputType.phone, decoration: _deco('Teléfono', Icons.phone)),
                const SizedBox(height: 10),
                TextField(controller: especialidadCtrl, decoration: _deco('Especialidad / terapia', Icons.psychology)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: guardando ? null : guardar,
                    icon: const Icon(Icons.save),
                    label: Text(guardando ? 'Guardando...' : 'Guardar profesional'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Profesionales registrados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('profesionales').orderBy('nombre').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data!.docs.isEmpty) return const Text('Aún no hay profesionales registrados.');
            return Column(
              children: snap.data!.docs.map((d) {
                final m = d.data() as Map<String, dynamic>;
                final activo = (m['estado'] ?? 'activo') == 'activo';
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: activo ? Colors.green : Colors.grey, child: const Icon(Icons.person, color: Colors.white)),
                    title: Text((m['nombre'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${m['especialidad'] ?? ''}\n${m['email'] ?? ''}'),
                    isThreeLine: true,
                    trailing: Switch(value: activo, onChanged: (v) => cambiarEstado(d.id, v ? 'activo' : 'inactivo')),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _AsignacionesTab extends StatefulWidget {
  const _AsignacionesTab();

  @override
  State<_AsignacionesTab> createState() => _AsignacionesTabState();
}

class _AsignacionesTabState extends State<_AsignacionesTab> {
  String? profesionalId;
  String? beneficiarioId;
  String dia = 'Lunes';
  final horaCtrl = TextEditingController();
  final terapiaCtrl = TextEditingController(text: 'Terapia individual');
  final valorCtrl = TextEditingController(text: '20000');
  final obsCtrl = TextEditingController();

  @override
  void dispose() {
    horaCtrl.dispose();
    terapiaCtrl.dispose();
    valorCtrl.dispose();
    obsCtrl.dispose();
    super.dispose();
  }

  Future<void> guardarAsignacion() async {
    if (profesionalId == null || beneficiarioId == null || horaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona profesional, beneficiario y horario.')));
      return;
    }
    final db = FirebaseFirestore.instance;
    final prof = await db.collection('profesionales').doc(profesionalId).get();
    final ben = await db.collection('beneficiarios').doc(beneficiarioId).get();
    final mp = prof.data() ?? {};
    final mb = ben.data() ?? {};
    await db.collection('asignaciones_profesionales').add({
      'profesional_id': profesionalId,
      'profesional_nombre': mp['nombre'] ?? '',
      'profesional_email': mp['email'] ?? '',
      'beneficiario_id': beneficiarioId,
      'beneficiario_nombre': mb['nombre_beneficiario'] ?? mb['nombre'] ?? '',
      'rut_beneficiario': mb['rut_beneficiario'] ?? mb['rut'] ?? '',
      'terapia': terapiaCtrl.text.trim(),
      'dia': dia,
      'hora': horaCtrl.text.trim(),
      'valor_mensual': int.tryParse(valorCtrl.text.trim()) ?? 0,
      'observacion': obsCtrl.text.trim(),
      'estado': 'activa',
      'fecha_creacion': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    horaCtrl.clear();
    obsCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asignación creada correctamente.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Asignar beneficiario a profesional', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF063E83))),
        const SizedBox(height: 12),
        _ProfesionalDropdown(value: profesionalId, onChanged: (v) => setState(() => profesionalId = v)),
        const SizedBox(height: 10),
        _BeneficiarioDropdown(value: beneficiarioId, onChanged: (v) => setState(() => beneficiarioId = v)),
        const SizedBox(height: 10),
        TextField(controller: terapiaCtrl, decoration: _deco('Terapia / servicio', Icons.medical_services)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: dia,
          decoration: _deco('Día', Icons.today),
          items: const ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => dia = v ?? 'Lunes'),
        ),
        const SizedBox(height: 10),
        TextField(controller: horaCtrl, decoration: _deco('Horario. Ej: 09:00', Icons.schedule)),
        const SizedBox(height: 10),
        TextField(controller: valorCtrl, keyboardType: TextInputType.number, decoration: _deco('Valor mensual que genera cobro en tesorería', Icons.attach_money)),
        const SizedBox(height: 10),
        TextField(controller: obsCtrl, maxLines: 3, decoration: _deco('Observación interna', Icons.note_alt)),
        const SizedBox(height: 14),
        ElevatedButton.icon(onPressed: guardarAsignacion, icon: const Icon(Icons.check), label: const Text('Crear asignación')),
      ],
    );
  }
}

class _AgendaGeneralTab extends StatelessWidget {
  const _AgendaGeneralTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('asignaciones_profesionales').where('estado', isEqualTo: 'activa').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No hay asignaciones activas.'));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final m = docs[i].data() as Map<String, dynamic>;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.event_available, color: Color(0xFF0047B3)),
                title: Text('${m['dia'] ?? ''} ${m['hora'] ?? ''} - ${m['beneficiario_nombre'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${m['profesional_nombre'] ?? ''}\n${m['terapia'] ?? ''}'),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

class _TalleresTab extends StatefulWidget {
  const _TalleresTab();

  @override
  State<_TalleresTab> createState() => _TalleresTabState();
}

class _TalleresTabState extends State<_TalleresTab> {
  final nombreCtrl = TextEditingController();
  final valorCtrl = TextEditingController(text: '10000');
  final descripcionCtrl = TextEditingController();

  @override
  void dispose() {
    nombreCtrl.dispose();
    valorCtrl.dispose();
    descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> guardar() async {
    if (nombreCtrl.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('talleres').add({
      'nombre': nombreCtrl.text.trim(),
      'valor_mensual': int.tryParse(valorCtrl.text.trim()) ?? 0,
      'descripcion': descripcionCtrl.text.trim(),
      'estado': 'activo',
      'fecha_creacion': FieldValue.serverTimestamp(),
    });
    nombreCtrl.clear();
    descripcionCtrl.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Taller creado.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: nombreCtrl, decoration: _deco('Nombre del taller', Icons.groups)),
        const SizedBox(height: 10),
        TextField(controller: valorCtrl, keyboardType: TextInputType.number, decoration: _deco('Valor mensual', Icons.attach_money)),
        const SizedBox(height: 10),
        TextField(controller: descripcionCtrl, maxLines: 3, decoration: _deco('Descripción', Icons.description)),
        const SizedBox(height: 12),
        ElevatedButton.icon(onPressed: guardar, icon: const Icon(Icons.save), label: const Text('Guardar taller')),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('talleres').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return Column(children: snap.data!.docs.map((d) {
              final m = d.data() as Map<String, dynamic>;
              return Card(child: ListTile(title: Text(m['nombre']?.toString() ?? ''), subtitle: Text('Valor: ${m['valor_mensual'] ?? 0}')));
            }).toList());
          },
        ),
      ],
    );
  }
}

class _ProfesionalDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _ProfesionalDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('profesionales').where('estado', isEqualTo: 'activo').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return DropdownButtonFormField<String>(
          value: value,
          decoration: _deco('Profesional', Icons.person),
          items: docs.map((d) {
            final m = d.data() as Map<String, dynamic>;
            return DropdownMenuItem(value: d.id, child: Text((m['nombre'] ?? m['email'] ?? '').toString()));
          }).toList(),
          onChanged: onChanged,
        );
      },
    );
  }
}

class _BeneficiarioDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _BeneficiarioDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('beneficiarios').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return DropdownButtonFormField<String>(
          value: value,
          decoration: _deco('Beneficiario / usuario', Icons.child_care),
          items: docs.map((d) {
            final m = d.data() as Map<String, dynamic>;
            final nombre = (m['nombre_beneficiario'] ?? m['nombre'] ?? '').toString();
            final rut = (m['rut_beneficiario'] ?? m['rut'] ?? '').toString();
            return DropdownMenuItem(value: d.id, child: Text('$nombre $rut'));
          }).toList(),
          onChanged: onChanged,
        );
      },
    );
  }
}
