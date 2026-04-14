import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';

class GuisadosManagementView extends StatefulWidget {
  const GuisadosManagementView({super.key});

  @override
  State<GuisadosManagementView> createState() => _GuisadosManagementViewState();
}

class _GuisadosManagementViewState extends State<GuisadosManagementView> {
  final _supabase = Supabase.instance.client;

  Stream<List<Map<String, dynamic>>> _guisadosStream() {
    return _supabase
        .from('guisados')
        .stream(primaryKey: ['id'])
        .order('name', ascending: true)
        .map((rows) => rows.where((g) {
              final branch = g['branch_name'] as String?;
              return branch == null || branch == Globals.currentBranch;
            }).toList());
  }

  Future<void> _toggleAvailable(Map<String, dynamic> guisado) async {
    try {
      await _supabase
          .from('guisados')
          .update({'available': !(guisado['available'] as bool)})
          .eq('id', guisado['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e')),
        );
      }
    }
  }

  Future<void> _deleteGuisado(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Eliminar guisado?',
            style: TextStyle(color: Colors.white)),
        content: const Text('Esta acción no se puede deshacer.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.2)),
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabase.from('guisados').delete().eq('id', id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  Future<void> _showAddGuisadoDialog() async {
    final nameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Nuevo Guisado',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nombre del guisado (ej. Picadillo)',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF6D00)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF6D00), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _supabase.from('guisados').insert({
                  'name': name,
                  'branch_name': null, // disponible para todas
                  'available': true,
                });
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al agregar: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00).withOpacity(0.15),
            ),
            child: const Text('Agregar',
                style: TextStyle(color: Color(0xFFFF6D00))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddGuisadoDialog,
        backgroundColor: const Color(0xFFFF6D00),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              'Gestión de Guisados',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              'Administra los rellenos disponibles para gorditas, tamales y más.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _guisadosStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF6D00),
                    ),
                  );
                }

                final guisados = snapshot.data!;

                if (guisados.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay guisados registrados.\nPresiona + para agregar uno.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
                  itemCount: guisados.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF334155)),
                  itemBuilder: (context, index) {
                    final g = guisados[index];
                    final available = g['available'] as bool;

                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: available
                              ? const Color(0xFFFF6D00).withOpacity(0.15)
                              : const Color(0xFF334155),
                          child: Icon(
                            Icons.lunch_dining,
                            color: available
                                ? const Color(0xFFFF6D00)
                                : Colors.white38,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          g['name'] as String,
                          style: TextStyle(
                            color: available ? Colors.white : Colors.white38,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          available ? 'Disponible' : 'No disponible',
                          style: TextStyle(
                            color: available
                                ? const Color(0xFF34D399)
                                : Colors.white30,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: available,
                              onChanged: (_) => _toggleAvailable(g),
                              activeColor: const Color(0xFFFF6D00),
                              inactiveThumbColor: Colors.white38,
                              inactiveTrackColor: const Color(0xFF334155),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () => _deleteGuisado(g['id'] as String),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
