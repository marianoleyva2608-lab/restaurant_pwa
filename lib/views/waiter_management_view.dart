import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';

class WaiterManagementView extends StatefulWidget {
  const WaiterManagementView({super.key});

  @override
  State<WaiterManagementView> createState() => _WaiterManagementViewState();
}

class _WaiterManagementViewState extends State<WaiterManagementView> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _waiters = [];

  // Removed manual _fetchWaiters as it will be handled by StreamBuilder

  Future<void> _showWaiterDialog([Map<String, dynamic>? waiter]) async {
    final nameController = TextEditingController(text: waiter?['name'] ?? '');
    final pinController = TextEditingController(text: waiter?['pin']?.toString() ?? '');
    final isEditing = waiter != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(isEditing ? 'Editar Mesero' : 'Nuevo Mesero', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nombre Completo',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Contraseña / PIN (Ej. 1234)',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                try {
                  if (isEditing) {
                    await _supabase.from('waiters').update({
                      'name': nameController.text.trim(),
                      'pin': pinController.text.trim(), 'branch_name': Globals.currentBranch,
                    }).eq('id', waiter['id']);
                  } else {
                    await _supabase.from('waiters').insert({
                      'name': nameController.text.trim(),
                      'pin': pinController.text.trim(), 'branch_name': Globals.currentBranch,
                    });
                  }
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)),
              child: const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result == true) {
      // Stream will handle the update
    }
  }

  Future<void> _deleteWaiter(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Eliminar Mesero?', style: TextStyle(color: Colors.white)),
        content: const Text('Esta acción no se puede deshacer.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              try {
                await _supabase.from('waiters').delete().eq('id', id);
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se puede eliminar porque tiene órdenes registradas. $e')));
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Stream will handle the update
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final crossAxisCount = width < 600 ? 1 : width < 1000 ? 2 : width < 1400 ? 3 : 4;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase.from('waiters')
          .stream(primaryKey: ['id'])
          .eq('branch_name', Globals.currentBranch)
          .order('name'),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        _waiters = snapshot.data!;

        return Padding(
      padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flex(
            direction: isMobile ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Gestión de Meseros', style: TextStyle(fontSize: isMobile ? 24 : 28, fontWeight: FontWeight.bold, color: Colors.white)),
              if (isMobile) const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showWaiterDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo Mesero'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: isMobile ? 3.0 : 2.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _waiters.length,
              itemBuilder: (context, index) {
                final waiter = _waiters[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFFF6D00).withValues(alpha: 0.2),
                        child: Text(
                          waiter['name'].toString().substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          waiter['name'],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showWaiterDialog(waiter),
                        tooltip: 'Editar',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteWaiter(waiter['id']),
                        tooltip: 'Eliminar',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
