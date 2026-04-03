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
  bool _isLoading = false;

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
