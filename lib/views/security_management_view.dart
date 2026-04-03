import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecurityManagementView extends StatefulWidget {
  const SecurityManagementView({super.key});

  @override
  State<SecurityManagementView> createState() => _SecurityManagementViewState();
}

class _SecurityManagementViewState extends State<SecurityManagementView> {
  final _supabase = Supabase.instance.client;
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    try {
      final resUser = await _supabase
          .from('admin_settings')
          .select('setting_value')
          .eq('setting_key', 'admin_user')
          .maybeSingle();

      final resPass = await _supabase
          .from('admin_settings')
          .select('setting_value')
          .eq('setting_key', 'admin_password')
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          if (resUser != null) _userController.text = resUser['setting_value'] as String;
          if (resPass != null) _passController.text = resPass['setting_value'] as String;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetch settings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_userController.text.trim().isEmpty || _passController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor llena usuario y contraseña')));
      return;
    }

    setState(() => _isSaving = true);
    
    try {
      await _supabase.from('admin_settings').upsert([
        {'setting_key': 'admin_user', 'setting_value': _userController.text.trim()},
        {'setting_key': 'admin_password', 'setting_value': _passController.text.trim()},
        {'setting_key': 'master_pin', 'setting_value': _passController.text.trim()}, // Mantenido para retrocompatibilidad con producción
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Credenciales de administrador actualizadas exitosamente'), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Seguridad'),
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.security, size: 64, color: Color(0xFFFF6D00)),
                    const SizedBox(height: 24),
                    const Text(
                      'Credenciales de Administrador',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Este usuario y contraseña serán solicitados para acceder a la caja o menú de administración de Gorditas Mis Hermanas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _userController,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'NUEVO USUARIO (ej. admin)',
                        labelStyle: const TextStyle(fontSize: 14, letterSpacing: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passController,
                      obscureText: true,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'NUEVA CONTRASEÑA',
                        labelStyle: const TextStyle(fontSize: 14, letterSpacing: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        prefixIcon: const Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: const Color(0xFFFF6D00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Guardar Modificaciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
