import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';

class SecurityManagementView extends StatefulWidget {
  const SecurityManagementView({super.key});

  @override
  State<SecurityManagementView> createState() => _SecurityManagementViewState();
}

class _SecurityManagementViewState extends State<SecurityManagementView> {
  final _supabase = Supabase.instance.client;

  Stream<List<Map<String, dynamic>>> get _usersStream => _supabase
      .from('admin_users')
      .stream(primaryKey: ['id'])
      .order('created_at');

  Future<void> _showAddUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'admin';
    String? selectedBranch;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final username = usernameController.text.trim();
            final password = passwordController.text.trim();
            if (username.isEmpty || password.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Usuario y contraseña son obligatorios')),
              );
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              await _supabase.from('admin_users').insert({
                'username': username,
                'password': password,
                'role': selectedRole,
                'branch_name': selectedBranch,
              });
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al crear usuario: $e')),
                );
              }
            } finally {
              if (context.mounted) setDialogState(() => isSaving = false);
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Nuevo Usuario Admin',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDialogField(
                    controller: usernameController,
                    label: 'Usuario',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  _buildDialogField(
                    controller: passwordController,
                    label: 'Contraseña',
                    icon: Icons.lock,
                    obscure: true,
                  ),
                  const SizedBox(height: 16),
                  const Text('Rol', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedRole,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'superadmin', child: Text('Superadmin')),
                        ],
                        onChanged: (v) {
                          if (v != null) setDialogState(() => selectedRole = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Sucursal', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: selectedBranch,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todas las sucursales'),
                          ),
                          ...Globals.branches.map((b) => DropdownMenuItem<String?>(
                                value: b,
                                child: Text(b),
                              )),
                        ],
                        onChanged: (v) => setDialogState(() => selectedBranch = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Crear', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteUser(Map<String, dynamic> user, List<Map<String, dynamic>> allUsers) async {
    // Count superadmins
    final superadminCount = allUsers.where((u) => u['role'] == 'superadmin').length;
    if (user['role'] == 'superadmin' && superadminCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No puedes eliminar el único superadmin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar eliminación', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Eliminar al usuario "${user['username']}"? Esta acción no se puede deshacer.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.from('admin_users').delete().eq('id', user['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario eliminado'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF6D00)),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    final isSuperAdmin = role == 'superadmin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSuperAdmin
            ? const Color(0xFFFF6D00).withOpacity(0.15)
            : const Color(0xFF334155),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSuperAdmin ? const Color(0xFFFF6D00) : const Color(0xFF475569),
        ),
      ),
      child: Text(
        isSuperAdmin ? 'Superadmin' : 'Admin',
        style: TextStyle(
          color: isSuperAdmin ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        title: const Text(
          'Usuarios Administradores',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF334155)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        backgroundColor: const Color(0xFFFF6D00),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo Usuario', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _usersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6D00)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Error al cargar usuarios:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            );
          }

          final users = snapshot.data ?? [];

          if (users.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, color: Color(0xFF475569), size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No hay usuarios registrados',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final superadminCount = users.where((u) => u['role'] == 'superadmin').length;

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final isSuperAdmin = user['role'] == 'superadmin';
              final isLastSuperAdmin = isSuperAdmin && superadminCount <= 1;
              final branch = user['branch_name'] as String?;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isSuperAdmin ? Icons.admin_panel_settings : Icons.person,
                      color: isSuperAdmin ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8),
                      size: 24,
                    ),
                  ),
                  title: Text(
                    user['username'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        _buildRoleBadge(user['role'] as String),
                        const SizedBox(width: 8),
                        Icon(
                          branch == null ? Icons.store : Icons.storefront,
                          color: const Color(0xFF475569),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            branch ?? 'Todas las sucursales',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: isLastSuperAdmin
                      ? Tooltip(
                          message: 'No se puede eliminar el único superadmin',
                          child: Icon(Icons.lock, color: const Color(0xFF475569), size: 20),
                        )
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: 'Eliminar usuario',
                          onPressed: () => _deleteUser(user, users),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
