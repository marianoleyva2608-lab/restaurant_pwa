import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';

class AccessManagementView extends StatefulWidget {
  const AccessManagementView({super.key});

  @override
  State<AccessManagementView> createState() => _AccessManagementViewState();
}

class _AccessManagementViewState extends State<AccessManagementView> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _kitchenPinController = TextEditingController();
  final _barPinController = TextEditingController();
  bool _isLoading = false;
  bool _pinsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final data = await _supabase.from('admin_settings').select()
      .or('setting_key.eq.kitchen_pin,setting_key.eq.bar_pin');
    for (final row in data) {
      final key = row['setting_key'] as String;
      final val = row['setting_value'] as String? ?? '';
      if (key == 'kitchen_pin') _kitchenPinController.text = val;
      if (key == 'bar_pin') _barPinController.text = val;
    }
  }

  Future<void> _savePin(String settingKey, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await _supabase.from('admin_settings').upsert({
      'setting_key': settingKey,
      'setting_value': trimmed,
    }, onConflict: 'setting_key');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN actualizado'), backgroundColor: Colors.green));
  }

  Future<void> _addCashier() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();
    if (name.isEmpty || pin.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // We'll use the waiters table for simplicity but with a special branch_name or just separate table if it exists
      // If we don't have a role column, we might use a special branch_name "ADMIN:BRANCHNAME"
      await _supabase.from('waiters').insert({
        'name': 'CAJERO: $name',
        'pin': pin,
        'branch_name': Globals.currentBranch,
      });
      _nameController.clear();
      _pinController.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acceso de Cajero agregado'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAccess(String id) async {
    try {
      await _supabase.from('waiters').delete().eq('id', id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gestión de Accesos (Cajeros y Admin)',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text('Administra quién puede entrar al panel de administración de ${Globals.currentBranch}', style: const TextStyle(color: Color(0xFF94A3B8))),
        const SizedBox(height: 32),
        
        // ADD CASHIER FORM
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF334155))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Agregar Nuevo Acceso a Caja', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Nombre del Cajero', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'PIN de Acceso', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _addCashier,
                    icon: const Icon(Icons.add),
                    label: const Text('DAR ACCESO'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6D00), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        
        // ACCESS LIST
        const Text('Accesos de Caja Registrados', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white70)),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('waiters').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch).order('name'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final allAccess = snapshot.data!.where((w) => w['name'].toString().startsWith('CAJERO:')).toList();
              
              if (allAccess.isEmpty) return const Center(child: Text('No hay cajeros individuales registrados.'));
              
              return ListView.builder(
                itemCount: allAccess.length,
                itemBuilder: (context, index) {
                  final access = allAccess[index];
                  final name = access['name'].toString().replaceAll('CAJERO: ', '');
                  return Card(
                    color: const Color(0xFF0F172A),
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFF334155))),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0xFFFF6D00), child: Icon(Icons.point_of_sale, color: Colors.white)),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text('PIN: ${access['pin']}', style: const TextStyle(color: Color(0xFF94A3B8))),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _deleteAccess(access['id']),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        
        // KITCHEN/BAR PIN SECTION
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.lock_outline, color: Color(0xFFFF6D00)),
                SizedBox(width: 10),
                Text('Claves de Acceso por Rol', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ]),
              const SizedBox(height: 6),
              const Text('Cambia el PIN de cada vista de trabajo', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              const SizedBox(height: 20),
              // Línea de Producción + Cocina
              _pinRow(
                icon: Icons.soup_kitchen,
                label: 'Línea de Producción / Cocina Para Llevar',
                controller: _kitchenPinController,
                onSave: () => _savePin('kitchen_pin', _kitchenPinController.text),
              ),
              const SizedBox(height: 16),
              // Bar / Bebidas
              _pinRow(
                icon: Icons.local_bar,
                label: 'Bar / Bebidas',
                controller: _barPinController,
                onSave: () => _savePin('bar_pin', _barPinController.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // RENAME BRANCH SECTION
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF334155))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Personalizar Nombre de Sucursal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Cambia el nombre de esta sucursal (ej: Sucursal 1 -> Matriz Central)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: Globals.currentBranch),
                      onChanged: (v) => _newBranchName = v,
                      decoration: const InputDecoration(labelText: 'Nombre Actual / Nuevo', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _renameBranch,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24)),
                    child: const Text('ACTUALIZAR NOMBRE'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _newBranchName = '';

  Widget _pinRow({required IconData icon, required String label, required TextEditingController controller, required VoidCallback onSave}) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFF0F172A),
          child: Icon(icon, color: const Color(0xFFFF6D00), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: false,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              border: const OutlineInputBorder(),
              counterText: '',
              prefixIcon: const Icon(Icons.pin, color: Color(0xFF94A3B8)),
            ),
            style: const TextStyle(color: Colors.white, letterSpacing: 4, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: onSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6D00),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _renameBranch() async {
    if (_newBranchName.isEmpty) return;
    final oldName = Globals.currentBranch;
    final newName = _newBranchName;

    if (oldName == newName) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Cambio de Nombre'),
        content: Text('Esto renombrará la sucursal "$oldName" a "$newName" en todos los pedidos, mesas y platillos. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, Renombrar')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await Globals.renameBranch(oldName, newName);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sucursal renombrada correctamente'), backgroundColor: Colors.green));
        setState(() {});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al renombrar: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
