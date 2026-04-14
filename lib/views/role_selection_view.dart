import 'package:flutter/material.dart';
import 'client_home_view.dart';
import 'comandas_view.dart';
import 'kitchen_view.dart';
import 'admin_view.dart';
import '../globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoleSelectionView extends StatefulWidget {
  const RoleSelectionView({super.key});

  @override
  State<RoleSelectionView> createState() => _RoleSelectionViewState();
}

class _RoleSelectionViewState extends State<RoleSelectionView> {
  // --- Valores por defecto para credenciales de seguridad ---
  // Cambiar aquí si se necesita un fallback distinto al valor en DB.
  static const String _defaultMasterPin = '0000';
  static const String _defaultAdminUser = 'admin';
  static const String _defaultAdminPass = '1234';
  // ---------------------------------------------------------

  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _hasSelectedBranch = false;
  bool _entered = false;

  String _masterPin = _defaultMasterPin;
  String _kitchenPin = _defaultMasterPin;
  String _barPin = _defaultMasterPin;
  String _adminUser = _defaultAdminUser;
  String _adminPass = _defaultAdminPass;

  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final settings = await _supabase
          .from('admin_settings')
          .select('setting_key, setting_value')
          .or('setting_key.eq.master_pin,setting_key.eq.admin_user,setting_key.eq.admin_pass,setting_key.eq.kitchen_pin,setting_key.eq.bar_pin');
      for (final row in settings) {
        final key = row['setting_key'] as String;
        final value = row['setting_value'] as String? ?? '';
        if (value.isEmpty) continue;
        if (key == 'master_pin') _masterPin = value;
        if (key == 'admin_user') _adminUser = value;
        if (key == 'admin_pass') _adminPass = value;
        if (key == 'kitchen_pin') _kitchenPin = value;
        if (key == 'bar_pin') _barPin = value;
      }
    } catch (e) {
      // Si falla la carga, se usan los defaults definidos arriba.
      debugPrint('Error loading security settings: $e');
    }
  }

  Future<void> _requirePin(BuildContext context, VoidCallback onAuthenticated, {String? pinToCheck}) async {
    String pin = '';
    final effectivePin = pinToCheck ?? _masterPin;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ingrese PIN de Acceso'),
        content: TextField(
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          onChanged: (v) => pin = v,
          onSubmitted: (_) {
            if (pin == effectivePin) {
              Navigator.pop(context);
              onAuthenticated();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN Incorrecto')));
            }
          },
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '####'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (pin == effectivePin) {
                Navigator.pop(context);
                onAuthenticated();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN Incorrecto')));
              }
            },
            child: const Text('Ingresar'),
          ),
        ],
      ),
    );
  }

  Future<void> _requireWaiterPin(BuildContext context, Function(String) onAuthenticated) async {
    String pin = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ingrese PIN de Mesero'),
        content: TextField(
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          onChanged: (v) => pin = v,
          onSubmitted: (_) async {
            try {
              final response = await _supabase.from('waiters').select().eq('pin', pin).eq('branch_name', Globals.currentBranch).maybeSingle();
              if (response != null) {
                Navigator.pop(context);
                onAuthenticated(response['id'].toString());
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN de mesero no válido para esta sucursal')));
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          },
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '####'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              try {
                final response = await _supabase.from('waiters').select().eq('pin', pin).eq('branch_name', Globals.currentBranch).maybeSingle();
                if (response != null) {
                  Navigator.pop(context);
                  onAuthenticated(response['id'].toString());
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN de mesero no válido para esta sucursal')));
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _requireAdminLogin(BuildContext context, VoidCallback onAuthenticated) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> attemptLogin() async {
              if (_isLoading) return;
              final email = emailController.text.trim();
              final password = passwordController.text.trim();

              setState(() => _isLoading = true);
              try {
                // 1. CREDENCIALES ADMIN CARGADAS DESDE DB (via _loadSecuritySettings)
                if (email == _adminUser && password == _adminPass) {
                  Navigator.pop(context);
                  onAuthenticated();
                  return;
                }

                // 2. CHECK AGAINST admin_users TABLE (multi-admin support)
                final adminUserResult = await _supabase
                    .from('admin_users')
                    .select()
                    .eq('username', email)
                    .eq('password', password)
                    .maybeSingle();

                if (adminUserResult != null) {
                  Navigator.pop(context);
                  onAuthenticated();
                  return;
                }

                // 3. CHECK IF IT IS A REGISTERED CASHIER PIN
                final cashierResponse = await _supabase
                    .from('waiters')
                    .select()
                    .eq('pin', password)
                    .eq('branch_name', Globals.currentBranch)
                    .maybeSingle();

                if (cashierResponse != null && cashierResponse['name'].toString().startsWith('CAJERO:')) {
                  Navigator.pop(context);
                  onAuthenticated();
                  return;
                }

                // 4. ATTEMPT FULL EMAIL/PASS AUTH
                if (email.isNotEmpty) {
                  final authResponse = await _supabase.auth.signInWithPassword(
                    email: email,
                    password: password,
                  );
                  if (authResponse.user != null) {
                    Navigator.pop(context);
                    onAuthenticated();
                    return;
                  }
                }
                
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acceso denegado (PIN o Credenciales incorrectas)')));
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              } finally {
                if (context.mounted) setState(() => _isLoading = false);
              }
            }

            return AlertDialog(
              title: const Text('Acceso Administrativo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    controller: emailController, 
                    decoration: const InputDecoration(labelText: 'Usuario/Email')
                  ),
                  TextField(
                    controller: passwordController, 
                    obscureText: true, 
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    onSubmitted: (_) => attemptLogin(),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: _isLoading ? null : attemptLogin,
                  child: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Ingresar'),
                ),
              ]
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO
                Image.asset('assets/images/logo.png', height: 160),
                const SizedBox(height: 24),
                
                const Text(
                  'Gorditas Mis Hermanas',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                ),
                const SizedBox(height: 32),
                
                // PHASE 1: SELECT BRANCH
                if (!_entered) ...[
                  const Text('¿En qué sucursal te encuentras?', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF334155), width: 1.5),
                    ),
                    child: Row(
                      children: Globals.branches.asMap().entries.map((entry) {
                        final index = entry.key;
                        final branch = entry.value;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: index > 0 ? 8 : 0),
                            child: _BranchButton(
                              title: branch,
                              isSelected: Globals.currentBranch == branch,
                              onTap: () async {
                                await Globals.setBranch(branch);
                                setState(() => _hasSelectedBranch = true);
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // "ENTRAR" / "INGRESAR" BUTTON
                  if (_hasSelectedBranch)
                    ElevatedButton(
                      onPressed: () => setState(() => _entered = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6D00),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 64),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 12,
                        shadowColor: const Color(0xFFFF6D00).withOpacity(0.4),
                      ),
                      child: const Text('INGRESAR A SUCURSAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                ],
                
                // PHASE 2: SHOW ROLES
                if (_entered) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.store, color: Color(0xFFFF6D00), size: 16),
                      const SizedBox(width: 8),
                      Text(Globals.currentBranch, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () => setState(() {
                          _entered = false;
                        }),
                        child: const Text('Cambiar', style: TextStyle(color: Color(0xFFFF6D00))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _RoleCard(
                    title: 'Cliente / Menú Digital',
                    subtitle: 'Escanear QR o para llevar',
                    icon: Icons.qr_code_2,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ClientHomeView())),
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    title: 'Mesero',
                    subtitle: 'Tomar comandas y mesas',
                    icon: Icons.tablet_mac,
                    onTap: () {
                      _requireWaiterPin(context, (waiterId) {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ComandasView(waiterId: waiterId)));
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    title: 'Caja / Administrador',
                    subtitle: 'Cobros y reportes de ventas',
                    icon: Icons.point_of_sale,
                    onTap: () {
                      _requireAdminLogin(context, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminView()));
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    title: 'Línea de Producción',
                    subtitle: 'Despacho general de pedidos',
                    icon: Icons.soup_kitchen,
                    onTap: () {
                      _requirePin(context, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const KitchenView()));
                      }, pinToCheck: _kitchenPin);
                    },
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    title: 'Cocina Para Llevar',
                    subtitle: 'Solo pedidos para llevar/delivery',
                    icon: Icons.delivery_dining,
                    onTap: () {
                      _requirePin(context, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const KitchenView(isTakeoutOnly: true)));
                      }, pinToCheck: _kitchenPin);
                    },
                  ),
                  const SizedBox(height: 16),
                  _RoleCard(
                    title: 'Bar / Bebidas',
                    subtitle: 'Despacho de bebidas solamente',
                    icon: Icons.local_bar,
                    onTap: () {
                      _requirePin(context, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const KitchenView(isDrinksOnly: true)));
                      }, pinToCheck: _barPin);
                    },
                  ),
                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: () {
                      final url = '${Uri.base.origin}/#/client';
                      final encodedUrl = Uri.encodeComponent(url);
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('QR de la Sucursal', textAlign: TextAlign.center),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(16),
                                child: Image.network('https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$encodedUrl', width: 250, height: 250),
                              ),
                              const SizedBox(height: 16),
                              Text(url, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                            ],
                          ),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code, color: Color(0xFF94A3B8)),
                    label: const Text('Mostrar QR de la App', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchButton extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _BranchButton({required this.title, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF6D00) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF94A3B8), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 16),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _RoleCard({required this.title, required this.subtitle, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: const Color(0xFFFF6D00), size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF475569)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
