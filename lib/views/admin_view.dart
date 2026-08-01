import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dish_management_view.dart';
import 'drinks_management_view.dart';
import 'guisados_management_view.dart';
import 'drink_flavors_management_view.dart';
import 'subscriptions_management_view.dart';
import 'waiter_management_view.dart';
import 'table_management_view.dart';
import 'security_management_view.dart';
import 'reports_view.dart';
import 'access_management_view.dart';
import 'billing_view.dart';
import 'clients_view.dart';
import 'payroll_view.dart';
import 'print_status_view.dart';
import '../utils/app_updater.dart';
import '../utils/url_opener.dart';

/// Refrescos/Aguas/Jugos comparten un solo dish_id representativo en la
/// BD sin importar el TAMAÑO elegido, así que `dishes.name` puede no
/// reflejar el tamaño real — el primer guisado sí lo trae (ej. "600 ml").
/// Espejo de `correctDrinkName` en print-worker/index.js.
String _correctDrinkName(String rawName, dynamic rawGuisados) {
  List<String> guisados;
  try {
    guisados = rawGuisados == null
        ? []
        : (jsonDecode(rawGuisados as String) as List).cast<String>();
  } catch (_) {
    guisados = [];
  }
  if (guisados.isEmpty) return rawName;
  final sizeStr = guisados.first.trim();
  if (!RegExp(r'^\d+\s?(ml|litro)$', caseSensitive: false).hasMatch(sizeStr)) return rawName;
  final n = rawName.toLowerCase();
  if (n.contains('refresco')) {
    if (sizeStr.contains('355')) return 'Refresco de vidrio';
    if (sizeStr.contains('600')) return 'Refresco no retornable';
    return 'Refresco';
  }
  if (n.contains('jugo')) return 'Jugo';
  if (n.contains('agua') && !n.contains('natural')) return 'Agua Fresca';
  return rawName;
}

class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  final _supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  final String _branchFilter = 'Todas';
  List<Map<String, dynamic>> _waiters = [];
  // For selecting a table/order to see details/comandas
  String? _selectedTableId;
  String? _selectedTableNumber;
  String? _selectedOrderId;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _fetchWaiters();
    // Al abrir el admin, revisa si YA se registró la apertura de caja
    // de HOY. Si no, muestra el diálogo automáticamente para pedirle
    // a la cajera el fondo inicial.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAperturaCajaHoy();
    });
  }

  /// Consulta la BD para ver si ya hay un cash_movement de categoría
  /// 'apertura' con fecha de HOY para la sucursal activa. Si no lo hay,
  /// muestra el diálogo para registrarla al momento.
  Future<void> _checkAperturaCajaHoy() async {
    try {
      final startOfDay = DateTime.now().toUtc().copyWith(
          hour: 0, minute: 0, second: 0, microsecond: 0, millisecond: 0);
      // 6 AM local en México ≈ 12:00 UTC. Usamos inicio del día local
      // aproximado con offset -6h para no perder aperturas de madrugada.
      final startOfDayLocal =
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
              .toUtc();
      final res = await _supabase
          .from('cash_movements')
          .select('id')
          .eq('branch_name', Globals.currentBranch)
          .eq('category', 'apertura')
          .gte('created_at', startOfDayLocal.toIso8601String())
          .limit(1);
      final has = (res as List).isNotEmpty;
      if (!has && mounted) {
        _showAperturaCajaAutoDialog();
      }
      // startOfDay used as sanity anchor (linter)
      startOfDay.hashCode;
    } catch (_) {
      // Si falla (tabla no existe, red, etc.) ignora silenciosamente —
      // no queremos bloquear al usuario si el chequeo no puede hacerse.
    }
  }

  void _showAperturaCajaAutoDialog() {
    final amountController = TextEditingController();
    final noteController =
        TextEditingController(text: 'Fondo inicial de caja');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Row(
          children: [
            Icon(Icons.savings, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text('Apertura de Caja',
                  style: TextStyle(
                      color: Color(0xFF3D2E1A),
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'Buen día. Aún no se ha registrado la apertura de caja de '
                'hoy. Ingresa el monto de efectivo con el que INICIA la '
                'caja para poder llevar el corte al final del turno.',
                style: TextStyle(color: Color(0xFF7A6E5A), fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Fondo inicial',
                prefixText: '\$ ',
                prefixIcon: Icon(Icons.attach_money, color: Colors.green),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              style: const TextStyle(color: Colors.black),
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                prefixIcon:
                    Icon(Icons.note_outlined, color: Color(0xFFA08F70)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Después',
                style: TextStyle(color: Color(0xFFA08F70))),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Monto inválido'),
                    backgroundColor: Colors.red));
                return;
              }
              try {
                await _supabase.from('cash_movements').insert({
                  'type': 'entrada',
                  'category': 'apertura',
                  'amount': amount,
                  'payment_method': 'EFECTIVO',
                  'description': noteController.text.trim().isNotEmpty
                      ? noteController.text.trim()
                      : 'Fondo inicial de caja',
                  'branch_name': Globals.currentBranch,
                  'registered_by': Globals.currentUser,
                  'recipient': 'N/A',
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Caja abierta con \$${amount.toStringAsFixed(2)}'),
                    backgroundColor: Colors.green,
                  ));
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Error: $e')));
                }
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Registrar Apertura'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchWaiters() async {
    final response = await _supabase.from('waiters').select('id, name').eq('branch_name', Globals.currentBranch);
    if (mounted) {
      setState(() => _waiters = List<Map<String, dynamic>>.from(response));
    }
  }

  Widget _buildSubItem(int index, IconData icon, String label, bool isDrawer) {
    final selected = _selectedIndex == index;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 32),
      leading: Icon(icon, size: 20, color: selected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
      title: Text(label, style: TextStyle(fontSize: 13, color: selected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      selected: selected,
      selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
      onTap: () {
        setState(() => _selectedIndex = index);
        if (isDrawer) Navigator.pop(context);
      },
    );
  }

  Widget _buildSidebar(bool isDrawer) {
    return Container(
      width: isDrawer ? null : 250,
      color: const Color(0xFFFAF1DE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Image.asset('assets/images/logo.png', height: 80),
                  ),
                  InkWell(
                    onTap: () => _showRenameBranchDialog(context),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF1DE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFF6D00).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SUCURSAL ACTIVA', style: TextStyle(color: Color(0xFFFF6D00), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(child: Text(Globals.currentBranch, style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 14))),
                              const Icon(Icons.edit, color: Color(0xFFA08F70), size: 16),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.dashboard, color: _selectedIndex == 0 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Mesas Activas', style: TextStyle(color: _selectedIndex == 0 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 0 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 0,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 0);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.restaurant_menu, color: _selectedIndex == 1 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Gestión de Menú', style: TextStyle(color: _selectedIndex == 1 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 1 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 1,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 1);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.soup_kitchen, color: _selectedIndex == 10 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Guisados', style: TextStyle(color: _selectedIndex == 10 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 10 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 10,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 10);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.local_drink, color: _selectedIndex == 11 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Sabores de Bebidas', style: TextStyle(color: _selectedIndex == 11 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 11 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 11,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 11);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.verified_user, color: _selectedIndex == 12 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Vigencia de Pago', style: TextStyle(color: _selectedIndex == 12 ? const Color(0xFFA08F70) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 12 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 12,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 12);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.print, color: _selectedIndex == 13 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Estado de Impresión', style: TextStyle(color: _selectedIndex == 13 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 13 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 13,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 13);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.people, color: _selectedIndex == 2 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Gestión de Meseros', style: TextStyle(color: _selectedIndex == 2 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 2 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 2,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 2);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.grid_view, color: _selectedIndex == 3 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Gestión de Mesas', style: TextStyle(color: _selectedIndex == 3 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 3 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 3,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 3);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.insert_chart, color: _selectedIndex == 5 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Reportes de Ventas', style: TextStyle(color: _selectedIndex == 5 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 5 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 5,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 5);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.manage_accounts, color: _selectedIndex == 6 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Gestión de Acceso', style: TextStyle(color: _selectedIndex == 6 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 6 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 6,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 6);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.receipt_long, color: _selectedIndex == 7 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Facturación CFDI', style: TextStyle(color: _selectedIndex == 7 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 7 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 7,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 7);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.people_alt, color: _selectedIndex == 8 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Gestión de Clientes', style: TextStyle(color: _selectedIndex == 8 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 8 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 8,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 8);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.account_balance_wallet, color: _selectedIndex == 9 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                    title: Text('Nómina', style: TextStyle(color: _selectedIndex == 9 ? const Color(0xFFFF6D00) : const Color(0xFFA08F70), fontWeight: _selectedIndex == 9 ? FontWeight.bold : FontWeight.normal)),
                    selected: _selectedIndex == 9,
                    selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                    onTap: () {
                      setState(() => _selectedIndex = 9);
                      if (isDrawer) Navigator.pop(context);
                    },
                  ),
                  const Divider(color: Color(0xFFE5DCC4)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CONFIGURACIÓN', style: TextStyle(color: Color(0xFFFF6D00), fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Sucursal de este dispositivo', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11)),
                        const SizedBox(height: 6),
                        ...Globals.branches.map((branch) {
                          final selected = Globals.currentBranch == branch;
                          return GestureDetector(
                            onTap: () async {
                              await Globals.setBranch(branch);
                              setState(() {});
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: selected ? const Color(0xFFFF6D00).withValues(alpha: 0.15) : const Color(0xFFFAF1DE),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: selected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      branch,
                                      style: TextStyle(
                                        color: selected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
                                        fontSize: 12,
                                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        const Divider(color: Color(0xFFFAF1DE)),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          value: Globals.splitKitchenModeFor(Globals.currentBranch),
                          title: const Text('Cocina Especializada', style: TextStyle(color: Color(0xFF3D2E1A), fontSize: 13)),
                          subtitle: const Text('Separa pedidos To Go', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) async {
                            await Globals.setSplitKitchenMode(Globals.currentBranch, val);
                            setState(() {});
                          },
                        ),
                        SwitchListTile(
                          value: Globals.displayModeFor(Globals.currentBranch) == 'screen',
                          title: const Text('Modo Pantalla', style: TextStyle(color: Color(0xFF3D2E1A), fontSize: 13)),
                          subtitle: Text(
                            Globals.displayModeFor(Globals.currentBranch) == 'screen'
                                ? 'Cocina ve órdenes en pantalla; no imprime'
                                : 'Imprime tickets en impresora térmica',
                            style: const TextStyle(color: Color(0xFFA08F70), fontSize: 11),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) async {
                            await Globals.setDisplayMode(
                              Globals.currentBranch,
                              val ? 'screen' : 'printer',
                            );
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFFE5DCC4)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SISTEMA', style: TextStyle(color: Color(0xFFFF6D00), fontSize: 10, fontWeight: FontWeight.bold)),
                        const Text('Versión: 1.0.12', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11)),
                        const SizedBox(height: 8),
                        const UpdateAppButton(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFFE5DCC4)),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFA08F70)),
            title: const Text('Salir al menú', style: TextStyle(color: Color(0xFFA08F70))),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String get _currentSectionTitle {
    const titles = {
      0: 'Mesas Activas',
      1: 'Gestión de Menú',
      2: 'Gestión de Meseros',
      3: 'Gestión de Mesas',
      5: 'Reportes de Ventas',
      6: 'Gestión de Acceso',
      7: 'Facturación CFDI',
      8: 'Gestión de Clientes',
      9: 'Nómina',
      10: 'Guisados',
      11: 'Sabores de Bebidas',
      12: 'Vigencia de Pago',
      13: 'Estado de Impresión',
    };
    return titles[_selectedIndex] ?? 'Administrador';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1100;

    return Scaffold(
      key: _scaffoldKey,
      appBar: isMobile
          ? AppBar(
              backgroundColor: const Color(0xFFFAF1DE),
              foregroundColor: Color(0xFFFAF1DE),
              leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              title: Text(_currentSectionTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Color(0xFFA08F70)),
                  tooltip: 'Salir al menú',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            )
          : null,
      drawer: isMobile ? Drawer(child: _buildSidebar(true)) : null,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Left Sidebar: Navigation (Only for Desktop)
                if (!isMobile) _buildSidebar(false),

                if (!isMobile) const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE5DCC4)),

                // Main Content Section
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ),
          // Barra fija con el estado de las impresoras (LEDs), visible en
          // cualquier sección de Caja/Admin — no solo en "Estado de
          // Impresión". Tocar la barra lleva a esa pantalla para más detalle.
          InkWell(
            onTap: () => setState(() => _selectedIndex = 13),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFFAF1DE),
                border: Border(top: BorderSide(color: Color(0xFFE5DCC4))),
              ),
              child: const PrinterLedsRow(compact: true),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameBranchDialog(BuildContext context) {
    final controller = TextEditingController(text: Globals.currentBranch);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Renombrar Sucursal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Escribe el nuevo nombre de la sucursal activa. Los datos existentes también se actualizarán de forma automática.', style: TextStyle(color: Color(0xFF7A6E5A), fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Nombre de la Sucursal', border: OutlineInputBorder()),
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != Globals.currentBranch) {
                  Navigator.pop(context);
                  try {
                    await Globals.renameBranch(Globals.currentBranch, newName);
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sucursal renombrada con éxito.'), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al renombrar: $e'), backgroundColor: Colors.red));
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0: return _buildTablesDashboard();
      case 1: return const DishManagementView();
      case 2: return const WaiterManagementView();
      case 3: return const TableManagementView();
      case 4: return const SecurityManagementView();
      case 5: return const ReportsView();
      case 6: return const AccessManagementView();
      case 7: return const BillingView();
      case 8: return const ClientsView();
      case 9: return const PayrollView();
      case 10: return const GuisadosManagementView();
      case 11: return const DrinkFlavorsManagementView();
      case 12: return const SubscriptionsManagementView();
      case 13: return const PrintStatusView();
      default: return _buildTablesDashboard();
    }
  }

  Widget _buildTablesDashboard() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1200; // Un poco más ancho para dar espacio al mapa y panel

    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: const Text(
                      'Vista General',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _supabase.from('restaurant_tables').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch).order('table_number', ascending: true),
                      builder: (context, tablesSnapshot) {
                        return StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _supabase.from('orders').stream(primaryKey: ['id']),
                          builder: (context, ordersSnapshot) {
                            if (!tablesSnapshot.hasData || !ordersSnapshot.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            
                            final tables = (tablesSnapshot.data as List<Map<String, dynamic>>).where((t) => t['branch_name'] == Globals.currentBranch).toList();
                            final activeOrders = (ordersSnapshot.data as List<Map<String, dynamic>>).where((o) => 
                              o['branch_name'] == Globals.currentBranch && 
                              ['pending', 'ready', 'incomplete'].contains(o['status'])
                            ).toList();
                            final nonTableOrders = activeOrders.where((o) => o['table_id'] == null).toList();

                            // Separate map items and floating items
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (nonTableOrders.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                    color: const Color(0xFFFAF1DE),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Órdenes To Go / Delivery Activas', style: TextStyle(color: Color(0xFF7A6E5A), fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          height: 170,
                                          child: ListView.separated(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: nonTableOrders.length,
                                            separatorBuilder: (context, index) => const SizedBox(width: 16),
                                            itemBuilder: (context, index) {
                                              final order = nonTableOrders[index];
                                              final isSelected = _selectedOrderId == order['id'];
                                              final orderType = order['order_type'];
                                              final orderTypeStr = orderType == 'takeout' ? 'To Go' : 'Delivery';

                                               String? waiterName;
                                               if (order['waiter_id'] != null) {
                                                 try {
                                                   final w = _waiters.firstWhere((w) => w['id'] == order['waiter_id']);
                                                   waiterName = w['name'].toString().split(' ').first;
                                                 } catch (_) {}
                                               }

                                              // Para delivery: extraer la dirección del customer_name
                                              // (formato "Nombre (Pago: X) - DIR: ... - TEL: ...").
                                              String? cleanName = order['customer_name'] as String?;
                                              String? deliveryAddress;
                                              String? deliveryPhone;
                                              if (orderType == 'delivery' && cleanName != null) {
                                                final dirMatch = RegExp(r'-\s*DIR:\s*([^-]+?)(?:\s*-\s*TEL:|$)')
                                                    .firstMatch(cleanName);
                                                final telMatch = RegExp(r'-\s*TEL:\s*(.+?)(?:\s*-\s*|$)')
                                                    .firstMatch(cleanName);
                                                deliveryAddress = dirMatch?.group(1)?.trim();
                                                deliveryPhone = telMatch?.group(1)?.trim();
                                                // Nombre visible: quitar DIR / TEL del subtitle.
                                                cleanName = cleanName
                                                    .replaceAll(RegExp(r'\s*-\s*DIR:.*'), '')
                                                    .trim();
                                              }
                                              final extraInfo = [
                                                if (deliveryAddress != null && deliveryAddress.isNotEmpty)
                                                  deliveryAddress,
                                                if (deliveryPhone != null && deliveryPhone.isNotEmpty)
                                                  '☎ $deliveryPhone',
                                              ].join('\n');

                                              return SizedBox(
                                                width: 180,
                                                child: _TableCard(
                                                  title: orderTypeStr,
                                                  subtitle: cleanName ?? 'Cliente',
                                                  icon: orderType == 'takeout' ? Icons.takeout_dining : Icons.delivery_dining,
                                                  color: orderType == 'takeout' ? const Color(0xFFE07A30) : const Color(0xFFB7472A),
                                                  waiterName: waiterName,
                                                  isOccupied: true, // It's an active order
                                                  isSelected: isSelected,
                                                  extraInfo: extraInfo.isEmpty ? null : extraInfo,
                                                  onTap: () {
                                                    setState(() {
                                                      _selectedOrderId = order['id'] as String;
                                                      _selectedTableId = null;
                                                      _selectedTableNumber = null;
                                                    });
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Expanded(
                                  child: GridView.builder(
                                    padding: const EdgeInsets.all(16),
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 160,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 1,
                                    ),
                                    itemCount: tables.length,
                                    itemBuilder: (context, index) {
                                      final table = tables[index];
                                      final isOccupied = table['status'] == 'occupied';
                                      final isSelected = _selectedTableId == table['id'];
                                      String? waiterName;
                                      if (isOccupied) {
                                        final tOrders = activeOrders.where((o) => o['table_id'] == table['id']).toList();
                                        if (tOrders.isNotEmpty && tOrders.first['waiter_id'] != null) {
                                          try {
                                            final wName = _waiters.firstWhere((w) => w['id'] == tOrders.first['waiter_id'])['name'];
                                            waiterName = wName.toString().split(' ').first;
                                          } catch (_) {}
                                        }
                                      }
                                      return _TableCard(
                                        title: 'Mesa ${table['table_number']}',
                                        subtitle: isOccupied ? 'Ocupada' : 'Libre',
                                        icon: Icons.table_restaurant,
                                        isOccupied: isOccupied,
                                        isSelected: isSelected,
                                        waiterName: waiterName,
                                        onTap: () {
                                          setState(() {
                                            _selectedTableId = table['id'];
                                            _selectedTableNumber = table['table_number'].toString();
                                            _selectedOrderId = null;
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (!isMobile) const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE5DCC4)),
            // Right Section: Order detail for selected table (Only for Desktop)
            if (!isMobile)
              Container(
                width: 350,
                color: const Color(0xFFFAF1DE),
                child: (_selectedTableId == null && _selectedOrderId == null)
                    ? const Center(
                        child: Text('Selecciona una mesa u orden', style: TextStyle(color: Colors.grey)),
                      )
                    : _TableDetailPanel(
                        tableId: _selectedTableId, 
                        tableNumber: _selectedTableNumber,
                        orderId: _selectedOrderId,
                        waitersList: _waiters,
                        onDeselect: () => setState(() {
                          _selectedTableId = null;
                          _selectedOrderId = null;
                        }),
                      ),
              ),
          ],
        ),
        
        // Modal / Overlay for Table Detail (Mobile/Tablet)
        if (isMobile && (_selectedTableId != null || _selectedOrderId != null))
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedTableId = null;
                _selectedOrderId = null;
              }),
              child: Container(
                color: Colors.black54,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: screenWidth * 0.85,
                    constraints: const BoxConstraints(maxWidth: 400),
                    color: const Color(0xFFFAF1DE),
                    child: Stack(
                      children: [
                        _TableDetailPanel(
                          tableId: _selectedTableId, 
                          tableNumber: _selectedTableNumber,
                          orderId: _selectedOrderId,
                          waitersList: _waiters,
                          onDeselect: () => setState(() {
                            _selectedTableId = null;
                            _selectedOrderId = null;
                          }),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFFFAF1DE)),
                            onPressed: () => setState(() {
                              _selectedTableId = null;
                              _selectedOrderId = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isOccupied;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;
  final String? waiterName;
  /// Texto opcional (p.ej. dirección de entrega) que se muestra debajo
  /// del chip de subtitle en hasta 2 líneas.
  final String? extraInfo;

  const _TableCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isOccupied,
    required this.isSelected,
    required this.onTap,
    this.color,
    this.waiterName,
    this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = color ?? (isOccupied ? Colors.red[400]! : const Color(0xFFA08F70));
    final borderColor = isSelected ? const Color(0xFFFF6D00) : (color ?? (isOccupied ? Colors.red.withValues(alpha: 0.5) : const Color(0xFFE5DCC4)));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isSelected 
              ? (color ?? const Color(0xFFFF6D00)).withValues(alpha: 0.1) 
              : const Color(0xFFFAF1DE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: displayColor,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color != null 
                    ? color!.withValues(alpha: 0.2)
                    : (isOccupied ? Colors.red.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: color ?? (isOccupied ? Colors.red[300] : Colors.green[300]),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (waiterName != null && waiterName!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6D00),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  waiterName!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFAF1DE),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (extraInfo != null && extraInfo!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on,
                        size: 11, color: Color(0xFFA08F70)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        extraInfo!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF7A6E5A),
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TableDetailPanel extends StatefulWidget {
  final String? tableId;
  final String? tableNumber;
  final String? orderId;
  final List<Map<String, dynamic>> waitersList;
  final VoidCallback? onDeselect;

  const _TableDetailPanel({
    this.tableId, 
    this.tableNumber, 
    this.orderId, 
    this.waitersList = const [],
    this.onDeselect,
  });

  @override
  State<_TableDetailPanel> createState() => _TableDetailPanelState();
}

class _TableDetailPanelState extends State<_TableDetailPanel> {
  double _discountPercent = 0.0;

  Future<void> _showAddItemDialog(BuildContext context, String orderId) async {
    final supabase = Supabase.instance.client;
    List<Map<String, dynamic>> dishes = [];
    List<Map<String, dynamic>> guisados = [];
    try {
      final rows = await supabase.from('dishes').select().eq('available', true).order('name', ascending: true);
      dishes = (rows as List).cast<Map<String, dynamic>>();
      final gRows = await supabase.from('guisados').select().eq('available', true).order('name', ascending: true);
      guisados = (gRows as List).cast<Map<String, dynamic>>()
          .where((g) { final b = g['branch_name'] as String?; return b == null || b == Globals.currentBranch; })
          .toList();
    } catch (_) {}

    if (!context.mounted) return;

    final searchCtrl = TextEditingController();
    Map<String, dynamic>? selectedDish;
    List<String> selectedGuisados = [];
    String? filterCategory;

    // Categorías únicas
    final categories = dishes.map((d) => d['category'] as String? ?? '').toSet().toList()..sort();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = dishes.where((d) {
            final name = (d['name'] as String).toLowerCase();
            final cat = d['category'] as String? ?? '';
            final matchSearch = query.isEmpty || name.contains(query);
            final matchCat = filterCategory == null || cat == filterCategory;
            return matchSearch && matchCat;
          }).toList();

          if (selectedDish != null) {
            // Vista de personalización
            final requiresGuisado = selectedDish!['requires_guisado'] as bool? ?? false;
            return AlertDialog(
              backgroundColor: const Color(0xFFFAF1DE),
              title: Text(selectedDish!['name'] as String,
                  style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 16)),
              content: requiresGuisado && guisados.isNotEmpty
                  ? SizedBox(
                      width: 360,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('GUISADO', style: TextStyle(color: Color(0xFF7A6E5A), fontSize: 11,
                              fontWeight: FontWeight.w600, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 320),
                            child: GridView.builder(
                              shrinkWrap: true,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 6, childAspectRatio: 2.6),
                              itemCount: guisados.length,
                              itemBuilder: (_, i) {
                                final name = guisados[i]['name'] as String;
                                final checked = selectedGuisados.contains(name);
                                return InkWell(
                                  onTap: () => setS(() {
                                    if (checked) selectedGuisados.remove(name);
                                    else if (selectedGuisados.length < 5) selectedGuisados.add(name);
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: checked ? const Color(0xFFFF6D00).withValues(alpha: 0.15) : const Color(0xFFFAF1DE),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: checked ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4), width: 1.5),
                                    ),
                                    child: Row(children: [
                                      Icon(checked ? Icons.check_circle : Icons.radio_button_unchecked,
                                          size: 13, color: checked ? const Color(0xFFFF6D00) : const Color(0xFFA08F70)),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(name,
                                          style: TextStyle(color: checked ? const Color(0xFFFF6D00) : Color(0xFF7A6E5A), fontSize: 10),
                                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
              actions: [
                TextButton(onPressed: () => setS(() { selectedDish = null; selectedGuisados = []; }),
                    child: const Text('Atrás', style: TextStyle(color: Color(0xFFA08F70)))),
                TextButton(
                  onPressed: requiresGuisado && selectedGuisados.isEmpty ? null : () async {
                    Navigator.pop(ctx);
                    try {
                      await supabase.from('order_items').insert({
                        'order_id': orderId,
                        'dish_id': selectedDish!['id'],
                        'quantity': 1,
                        'price_at_time': selectedDish!['price'],
                        'status': 'pending',
                        'guisados_selected': selectedGuisados.isNotEmpty ? jsonEncode(selectedGuisados) : null,
                      });
                      final orderRes = await supabase.from('orders').select('total_amount').eq('id', orderId).single();
                      final newTotal = (orderRes['total_amount'] as num).toDouble() + (selectedDish!['price'] as num).toDouble();
                      await supabase.from('orders').update({'total_amount': newTotal}).eq('id', orderId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${selectedDish!['name']} agregado'),
                          duration: const Duration(milliseconds: 800),
                        ));
                      }
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  style: TextButton.styleFrom(backgroundColor: const Color(0xFFFF6D00).withValues(alpha: 0.15)),
                  child: const Text('Agregar', style: TextStyle(color: Color(0xFFFF6D00))),
                ),
              ],
            );
          }

          // Vista de búsqueda de platillos
          return AlertDialog(
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Text('Agregar artículo', style: TextStyle(color: Color(0xFF3D2E1A))),
            content: SizedBox(
              width: 420,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    onChanged: (_) => setS(() {}),
                    style: const TextStyle(color: Color(0xFF3D2E1A)),
                    decoration: const InputDecoration(
                      hintText: 'Buscar platillo...',
                      hintStyle: TextStyle(color: Color(0xFFB6A88A)),
                      prefixIcon: Icon(Icons.search, color: Color(0xFFB6A88A)),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6D00))),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6D00), width: 2)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _CatChip(label: 'Todos', selected: filterCategory == null,
                            onTap: () => setS(() => filterCategory = null)),
                        ...categories.map((c) => _CatChip(label: c, selected: filterCategory == c,
                            onTap: () => setS(() => filterCategory = c))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(color: Color(0xFFE5DCC4), height: 1),
                      itemBuilder: (_, i) {
                        final d = filtered[i];
                        return ListTile(
                          dense: true,
                          title: Text(d['name'] as String,
                              style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.w600)),
                          subtitle: Text(d['category'] as String? ?? '',
                              style: const TextStyle(color: Color(0xFFB6A88A), fontSize: 11)),
                          trailing: Text('\$${(d['price'] as num).toStringAsFixed(0)}',
                              style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                          onTap: () => setS(() { selectedDish = d; selectedGuisados = []; }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70)))),
            ],
          );
        },
      ),
    );
  }

  // Pregunta propina y devuelve el total final (con propina), o null si se canceló
  /// Pide la propina al cobrar una cuenta. Devuelve un mapa con
  /// 'total' (cuenta + propina, lo que se cobra) y 'propina' (solo el
  /// monto de propina) para que el monto quede registrado por separado
  /// en cash_movements y no se pierda dentro del total de la venta.
  Future<Map<String, double>?> _askPropina(BuildContext context, double total) async {
    int selectedPct = -1; // -1 = sin propina
    final customController = TextEditingController();
    double propinaAmount = 0.0;

    return showDialog<Map<String, double>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void recalc() {
            if (selectedPct == -1) {
              propinaAmount = 0;
            } else if (selectedPct == 0) {
              propinaAmount = double.tryParse(customController.text) ?? 0;
            } else {
              propinaAmount = total * selectedPct / 100;
            }
          }

          recalc();
          final totalFinal = total + propinaAmount;

          Widget pctBtn(String label, int pct) {
            final active = selectedPct == pct;
            return Expanded(
              child: GestureDetector(
                onTap: () => setS(() { selectedPct = pct; recalc(); }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFFF6D00) : const Color(0xFFFAF1DE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: active ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4), width: 1.5),
                  ),
                  child: Text(label, textAlign: TextAlign.center,
                    style: TextStyle(color: active ? Color(0xFFFAF1DE) : const Color(0xFFA08F70), fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Row(
              children: [
                Icon(Icons.volunteer_activism, color: Color(0xFFFF6D00), size: 28),
                SizedBox(width: 12),
                Text('¿Desea dejar propina?', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Total base
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFFAF1DE), borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total de la cuenta:', style: TextStyle(color: Color(0xFFA08F70), fontSize: 15)),
                      Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Botones de porcentaje
                Row(children: [
                  pctBtn('Sin\npropina', -1),
                  pctBtn('10%', 10),
                  pctBtn('15%', 15),
                  pctBtn('20%', 20),
                ]),
                const SizedBox(height: 16),
                // Campo personalizado
                TextField(
                  controller: customController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Monto personalizado',
                    labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.edit, color: Color(0xFFFF6D00)),
                    prefixText: '\$  ',
                    prefixStyle: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: const Color(0xFFFAF1DE),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setS(() { selectedPct = 0; recalc(); }),
                ),
                const SizedBox(height: 20),
                // Total final con propina
                if (propinaAmount > 0) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6D00).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFF6D00).withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Propina:', style: TextStyle(color: Color(0xFFFF6D00), fontSize: 15)),
                          Text('+\$${propinaAmount.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFF6D00), fontSize: 18, fontWeight: FontWeight.bold)),
                        ]),
                        const Divider(color: Color(0xFFFF6D00), height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('TOTAL A COBRAR:', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.w900, fontSize: 16)),
                          Text('\$${totalFinal.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 26, fontWeight: FontWeight.w900)),
                        ]),
                      ],
                    ),
                  ),
                ] else ...[
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TOTAL A COBRAR:', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('\$${totalFinal.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 26, fontWeight: FontWeight.w900)),
                  ]),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, {'total': totalFinal, 'propina': propinaAmount}),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continuar al cobro', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Color(0xFFFAF1DE),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Registra la propina capturada al cobrar una cuenta como movimiento de
  /// caja (categoría 'propina'), atribuida al mesero de esa cuenta cuando
  /// se conoce. No bloquea el cobro si el registro falla.
  Future<void> _registerPropinaMovement({
    required double propina,
    required String paymentMethod,
    required String waiterName,
  }) async {
    if (propina <= 0) return;
    try {
      await Supabase.instance.client.from('cash_movements').insert({
        'type': 'salida',
        'category': 'propina',
        'amount': propina,
        'payment_method': paymentMethod,
        'description': 'Propina registrada al cobrar cuenta',
        'branch_name': Globals.currentBranch,
        'registered_by': Globals.currentUser,
        'recipient': waiterName.isNotEmpty ? waiterName : 'Todos',
      });
    } catch (_) {
      // Si cash_movements no está disponible, no interrumpe el cobro.
    }
  }

  Future<void> _showCashPaymentDialog(
    BuildContext context,
    List<String> orderIds,
    double total,
    String? tableId, {
    double propina = 0.0,
    String waiterName = '',
  }) async {
    final cashController = TextEditingController();
    double change = 0.0;
    bool wantFactura = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: const Color(0xFFFAF1DE),
          title: Row(
            children: [
              const Icon(Icons.payments, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              const Text('Cobro en Efectivo', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF1DE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total a Cobrar:', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: cashController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFFF6D00)),
                decoration: InputDecoration(
                  labelText: 'Monto Recibido',
                  hintText: '0.00',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.attach_money),
                ),
                onChanged: (value) {
                  final cash = double.tryParse(value) ?? 0.0;
                  setState(() {
                    change = cash - total;
                    if (change < 0) change = 0;
                  });
                },
              ),
              const SizedBox(height: 24),
                if (change > 0 || (double.tryParse(cashController.text) ?? 0) >= total)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text('CAMBIO PARA EL CLIENTE', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text('\$${change.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontSize: 40, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF1DE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(children: [
                      Icon(Icons.receipt_long, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text('¿REQUIERE FACTURA?', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                    Switch(
                      value: wantFactura,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => wantFactura = val),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
            ),
            // Si lo que ingresó el cajero no alcanza para cubrir el total,
            // en vez de solo bloquear el botón, se ofrece cobrar el resto
            // con tarjeta (mismo flujo/registro que Pago Mixto) sin tener
            // que cancelar y volver a empezar desde ese botón aparte.
            if ((double.tryParse(cashController.text) ?? 0) > 0 &&
                (double.tryParse(cashController.text) ?? 0) < total)
              ElevatedButton.icon(
                onPressed: () async {
                  final cashEntered = double.tryParse(cashController.text) ?? 0;
                  final remaining = total - cashEntered;
                  final confirmed = await _confirmCardPortion(context, remaining);
                  if (confirmed != true || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  await _executeFinalizeMixedPayment(context, orderIds, total, tableId, cashEntered, remaining,
                      propina: propina, waiterName: waiterName);
                },
                icon: const Icon(Icons.credit_card, size: 20),
                label: Text(
                  'Cobrar \$${(total - (double.tryParse(cashController.text) ?? 0)).toStringAsFixed(2)} con Tarjeta',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(150, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              )
            else
              ElevatedButton(
                onPressed: (double.tryParse(cashController.text) ?? 0) < total
                  ? null
                  : () async {
                    final supabase = Supabase.instance.client;
                    try {
                      await supabase.from('orders').update({
                        'status': 'completed',
                        'payment_method': 'cash',
                        'amount_cash': total
                      }).inFilter('id', orderIds);

                      if (tableId != null) {
                        await supabase.from('restaurant_tables').update({'status': 'available'}).eq('id', tableId as Object);
                      }

                      await _registerPropinaMovement(
                          propina: propina, paymentMethod: 'EFECTIVO', waiterName: waiterName);

                      if (ctx.mounted) {
                        Navigator.pop(ctx); // Cerrar diálogo ahora
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago finalizado con éxito'), backgroundColor: Colors.green));
                        if (context.mounted) {
                          await _showTicketQrDialog(context, orderIds);
                        }
                        widget.onDeselect?.call();
                      }
                    } catch (e) {
                      if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Color(0xFFFAF1DE),
                  minimumSize: const Size(150, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('FINALIZAR COBRO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }

  /// Confirmación SIN conectarse a ninguna terminal — el cajero ya cobró
  /// esa parte en su terminal física aparte, esto solo registra que esa
  /// porción del cobro mixto va como tarjeta.
  Future<bool> _confirmCardPortion(BuildContext context, double amount) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Row(
          children: [
            Icon(Icons.credit_card, color: Colors.blueAccent, size: 28),
            SizedBox(width: 12),
            Text('Confirmar tarjeta', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Confirma que ya cobraste \$${amount.toStringAsFixed(2)} en tu terminal física.\n\n'
          'Esto NO se conecta a ninguna terminal — solo registra esa parte del cobro mixto como pagada con tarjeta.',
          style: const TextStyle(color: Color(0xFF7A6E5A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            child: const Text('Ya cobré, confirmar'),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _showMixedPaymentDialog(
    BuildContext context,
    List<String> orderIds,
    double total,
    String? tableId, {
    double propina = 0.0,
    String waiterName = '',
  }) async {
    final cashPartController = TextEditingController(text: total.toStringAsFixed(2));
    final cardPartController = TextEditingController(text: '0.00');
    final cashReceivedController = TextEditingController();
    double change = 0.0;
    bool isCardValidated = false;
    bool wantFactura = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          double cashAmount = double.tryParse(cashPartController.text) ?? 0.0;
          double cardAmount = double.tryParse(cardPartController.text) ?? 0.0;
          double totalEntered = cashAmount + cardAmount;
          double cashReceived = double.tryParse(cashReceivedController.text) ?? 0.0;
          change = cashReceived - cashAmount;
          if (change < 0) change = 0;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.orangeAccent, size: 28),
                SizedBox(width: 12),
                Text('Cobro Mixto', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF1DE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(color: Color(0xFFA08F70), fontSize: 16)),
                        Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cardPartController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Color(0xFF3D2E1A)),
                          decoration: InputDecoration(
                            labelText: 'Tarjeta (\$)',
                            labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                            filled: true,
                            fillColor: const Color(0xFFFAF1DE),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.credit_card, color: Colors.blueAccent),
                          ),
                          onChanged: (val) {
                            double amount = double.tryParse(val) ?? 0.0;
                            if (amount > total) amount = total;
                            setState(() {
                              // We don't update cardPartController.text here to avoid losing cursor
                              cashPartController.text = (total - amount).toStringAsFixed(2);
                              isCardValidated = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: cashPartController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Color(0xFF3D2E1A)),
                          decoration: InputDecoration(
                            labelText: 'Efectivo (\$)',
                            labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                            filled: true,
                            fillColor: const Color(0xFFFAF1DE),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.payments, color: Colors.greenAccent),
                          ),
                          onChanged: (val) {
                            double amount = double.tryParse(val) ?? 0.0;
                            if (amount > total) amount = total;
                            setState(() {
                              // We don't update cashPartController.text here to avoid losing cursor
                              cardPartController.text = (total - amount).toStringAsFixed(2);
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF1DE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(children: [
                          Icon(Icons.receipt_long, color: Colors.blueAccent),
                          SizedBox(width: 8),
                          Text('¿REQUIERE FACTURA?', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 13)),
                        ]),
                        Switch(
                          value: wantFactura,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) => setState(() => wantFactura = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (cardAmount > 0)
                    ElevatedButton.icon(
                      onPressed: isCardValidated ? null : () async {
                        final ok = await _confirmCardPortion(context, cardAmount);
                        if (!ok) return;
                        setState(() { isCardValidated = true; });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago con tarjeta confirmado'), backgroundColor: Colors.blue));
                      },
                      icon: Icon(isCardValidated ? Icons.check : Icons.point_of_sale),
                      label: Text(isCardValidated ? 'TARJETA CONFIRMADA' : 'CONFIRMAR \$${cardAmount.toStringAsFixed(2)} DE TARJETA'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCardValidated ? Colors.green : const Color(0xFF009EE3),
                        minimumSize: const Size.fromHeight(40),
                      ),
                    ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: cashReceivedController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFFF6D00)),
                    decoration: InputDecoration(
                      labelText: '¿CUÁNTO EFECTIVO RECIBES? (Cualquier monto restante irá a Tarjeta)',
                      labelStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      prefixIcon: const Icon(Icons.money, color: Colors.green),
                      filled: true,
                      fillColor: const Color(0xFFFAF1DE),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.orangeAccent, width: 2)),
                      hintText: '0.00',
                      hintStyle: const TextStyle(color: Color(0xFFCFC7B2)),
                    ),
                    onChanged: (val) {
                      double received = double.tryParse(val) ?? 0.0;
                      setState(() {
                         if (received <= total) {
                            // The amount received is the cash portion, the rest is card
                            cashPartController.text = received.toStringAsFixed(2);
                            cardPartController.text = (total - received).toStringAsFixed(2);
                            isCardValidated = false;
                         } else {
                            // Pay the total with cash, calculate change
                            cashPartController.text = total.toStringAsFixed(2);
                            cardPartController.text = "0.00";
                            isCardValidated = false;
                         }
                      });
                    },
                  ),
                  if (change > 0 || (double.tryParse(cashReceivedController.text) ?? 0) >= (double.tryParse(cashPartController.text) ?? 0))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          const Text('CAMBIO (Efectivo)', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('\$${change.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontSize: 32, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: totalEntered < total
                  ? null
                  : () async {
                      if (cardAmount > 0 && !isCardValidated) {
                        final ok = await _confirmCardPortion(context, cardAmount);
                        if (!ok) return;
                        setState(() { isCardValidated = true; });
                      }
                      await _executeFinalizeMixedPayment(context, orderIds, total, tableId, cashAmount, cardAmount,
                          propina: propina, waiterName: waiterName);
                    },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (cardAmount > 0 && !isCardValidated) ? Colors.blueAccent : Colors.orangeAccent,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  (cardAmount > 0 && !isCardValidated) ? 'CONFIRMAR TARJETA Y FINALIZAR' : 'FINALIZAR TODO EL COBRO',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16)
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Construye la URL pública del ticket virtual.
  /// Formato: `<origin>/#/ticket/<orderId>` (hash routing de Flutter web).
  String _buildTicketUrl(String orderId) {
    if (kIsWeb) {
      return '${Uri.base.origin}/#/ticket/$orderId';
    }
    return 'https://gorditasmh.com/#/ticket/$orderId';
  }

  /// Muestra un diálogo con el/los QR(s) del ticket virtual de las
  /// órdenes que se acaban de pagar. El cliente escanea, ve su ticket.
  Future<void> _showTicketQrDialog(BuildContext context, List<String> orderIds) async {
    if (orderIds.isEmpty) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ticket del cliente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'El cliente puede escanear este QR para ver su ticket:',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < orderIds.length; i++) ...[
                if (orderIds.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Orden ${i + 1} de ${orderIds.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: QrImageView(
                    data: _buildTicketUrl(orderIds[i]),
                    version: QrVersions.auto,
                    size: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _buildTicketUrl(orderIds[i]),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                if (i < orderIds.length - 1) const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeFinalizeMixedPayment(
    BuildContext context,
    List<String> orderIds,
    double total,
    String? tableId,
    double cashAmount,
    double cardAmount, {
    double propina = 0.0,
    String waiterName = '',
  }) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase.from('orders').update({
        'status': 'completed',
        'payment_method': 'mixed',
        'amount_cash': cashAmount,
        'amount_card': cardAmount
      }).inFilter('id', orderIds);

      if (tableId != null) {
        await supabase.from('restaurant_tables').update({'status': 'available'}).eq('id', tableId as Object);
      }

      // La propina se reparte proporcional a cómo se dividió el cobro
      // entre efectivo y tarjeta.
      if (propina > 0) {
        final cashCardTotal = cashAmount + cardAmount;
        final propinaEfectivo = cashCardTotal > 0 ? propina * (cashAmount / cashCardTotal) : propina;
        final propinaTarjeta = cashCardTotal > 0 ? propina * (cardAmount / cashCardTotal) : 0.0;
        await _registerPropinaMovement(propina: propinaEfectivo, paymentMethod: 'EFECTIVO', waiterName: waiterName);
        await _registerPropinaMovement(propina: propinaTarjeta, paymentMethod: 'TARJETA', waiterName: waiterName);
      }

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago Mixto finalizado'), backgroundColor: Colors.green));
        if (context.mounted) {
          await _showTicketQrDialog(context, orderIds);
        }
        widget.onDeselect?.call();
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al finalizar: $e')));
    }
  }

  Future<void> _cancelOrdersWithPin(BuildContext context, List<String> orderIds, String? tableId) async {
    final pinController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Acción Peligrosa'),
          content: TextField(
            controller: pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Ingrese el PIN Maestro',
              hintText: 'PIN Maestro',
              prefixIcon: Icon(Icons.lock, color: Colors.redAccent),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext), 
              child: const Text('Volver', style: TextStyle(color: Colors.grey))
            ),
            ElevatedButton(
              onPressed: () async {
                final supabase = Supabase.instance.client;
                try {
                  final response = await supabase
                      .from('admin_settings')
                      .select('setting_value')
                      .eq('setting_key', 'master_pin')
                      .maybeSingle();

                  String correctPin = '1234'; 
                  if (response != null && response['setting_value'] != null) {
                    correctPin = response['setting_value'] as String;
                  }

                  if (pinController.text == correctPin) {
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    
                    await supabase.from('orders').update({'status': 'cancelled'}).inFilter('id', orderIds);
                    if (tableId != null) {
                      await supabase.from('restaurant_tables').update({'status': 'available'}).eq('id', tableId);
                    }
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cuenta cancelada exitosamente', style: TextStyle(color: Color(0xFF3D2E1A))), backgroundColor: Colors.red)
                      );
                      widget.onDeselect?.call();
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PIN Incorrecto', style: TextStyle(color: Color(0xFF3D2E1A))), backgroundColor: Colors.red)
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e', style: const TextStyle(color: Color(0xFF3D2E1A))), backgroundColor: Colors.red)
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Cancelar Cuenta', style: TextStyle(color: Color(0xFF3D2E1A))),
            ),
          ]
        );
      }
    );
  }

  /// Pide el PIN maestro para autorizar la reimpresión de una cuenta que
  /// ya se había impreso antes (misma regla anti-fraude que en mesero).
  Future<bool> _askAdminPinForReprint(BuildContext context) async {
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Cuenta ya impresa'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta cuenta ya se imprimió al menos una vez. Para reimprimirla, ingresa el PIN maestro:',
                style: TextStyle(color: Color(0xFF7A6E5A)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'PIN Maestro',
                  prefixIcon: Icon(Icons.lock, color: Colors.redAccent),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
            ),
            ElevatedButton(
              onPressed: () async {
                final supabase = Supabase.instance.client;
                try {
                  final response = await supabase
                      .from('admin_settings')
                      .select('setting_value')
                      .eq('setting_key', 'master_pin')
                      .maybeSingle();
                  String correctPin = '1234';
                  if (response != null && response['setting_value'] != null) {
                    correctPin = response['setting_value'] as String;
                  }
                  if (pinController.text == correctPin) {
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  } else {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('PIN Incorrecto'), backgroundColor: Colors.red),
                      );
                    }
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              child: const Text('Autorizar'),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  /// Manda a imprimir la CUENTA (mesa o To Go) al ticket de caja, igual
  /// que el botón equivalente del mesero. Sirve para dar el ticket al
  /// cliente antes de cobrar, incluyendo pedidos To Go sin mesa.
  Future<void> _imprimirCuenta(BuildContext context, List<Map<String, dynamic>> orders, List<String> orderIds) async {
    if (orderIds.isEmpty) return;
    final supabase = Supabase.instance.client;
    final alreadyPrinted = orders.any((o) => o['caja_printed_at'] != null);

    if (alreadyPrinted) {
      final ok = await _askAdminPinForReprint(context);
      if (!ok) return;
    }

    try {
      await supabase.from('orders').update({
        'cuenta_requested_at': DateTime.now().toUtc().toIso8601String(),
        'caja_printed_at': null,
      }).inFilter('id', orderIds);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(alreadyPrinted ? 'Reimprimiendo cuenta…' : 'Imprimiendo cuenta…'),
            backgroundColor: const Color(0xFFFF6D00),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al pedir cuenta: $e')));
      }
    }
  }

  /// Cobro con "Tarjeta" SIN conectarse a ninguna terminal (Clip,
  /// Mercado Pago, etc.). Solo registra la venta como pagada con
  /// tarjeta para el corte de caja, cuando el cobro real ya se hizo en
  /// una terminal física aparte que no está integrada.
  Future<void> _markCardPaymentNoTerminal(
    BuildContext context,
    List<String> orderIds,
    double amount,
    String? tableId, {
    double propina = 0.0,
    String waiterName = '',
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Row(
          children: [
            Icon(Icons.credit_card, color: Colors.blueAccent, size: 28),
            SizedBox(width: 12),
            Text('Cobro con Tarjeta', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Confirma que ya cobraste \$${amount.toStringAsFixed(2)} en tu terminal física.\n\n'
          'Este botón NO se conecta a ninguna terminal: solo registra la venta como pagada con tarjeta para el corte de caja.',
          style: const TextStyle(color: Color(0xFF7A6E5A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            child: const Text('Confirmar cobro con tarjeta'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('orders').update({
        'status': 'completed',
        'payment_method': 'card',
        'amount_card': amount,
      }).inFilter('id', orderIds);

      if (tableId != null) {
        await supabase.from('restaurant_tables').update({'status': 'available'}).eq('id', tableId);
      }

      await _registerPropinaMovement(propina: propina, paymentMethod: 'TARJETA', waiterName: waiterName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pago con tarjeta registrado'),
          backgroundColor: Colors.green,
        ));
        await _showTicketQrDialog(context, orderIds);
        widget.onDeselect?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _payWithMercadoPago(BuildContext context, double amount, void Function() onFinish) async {
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Verificando Conexión...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Contactando a la red de Mercado Pago...', style: TextStyle(fontWeight: FontWeight.bold)),
          ]
        )
      )
    );

    const token = 'APP_USR-100748864275415-031901-832413e47604a619eb72c29e5528a188-1958092994';
    const deviceId = 'NEWLAND_N950__N950NCC303051358';
    
    try {
      try {
        final pingResp = await http.get(
          Uri.parse('http://192.168.1.88:8081/mp/point/integration-api/devices'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 4)); 

        if (pingResp.statusCode != 200) {
          if (context.mounted) {
             Navigator.pop(context); 
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rechazo de Mercado Pago. Verifica el token o el internet de la terminal.'), backgroundColor: Colors.red));
          }
          return; 
        }
      } catch (e) {
        if (context.mounted) {
           Navigator.pop(context); 
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error Crítico: No hay red hacia el Servidor Proxy de la terminal.'), backgroundColor: Colors.red));
        }
        return; 
      }

      final response = await http.post(
        Uri.parse('http://192.168.1.88:8081/mp/point/integration-api/devices/$deviceId/payment-intents'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "amount": (amount * 100).toInt()
        })
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final respData = json.decode(response.body);
        final intentId = respData['id']?.toString() ?? '';

        if (context.mounted) {
           Navigator.pop(context); 
           
           bool isPollingDialogOpen = true;

           showDialog(
             context: context,
             barrierDismissible: false,
             builder: (ctx) => AlertDialog(
               title: const Text('Terminal Despertada 🟢', style: TextStyle(color: Colors.green)),
               content: Column(
                 mainAxisSize: MainAxisSize.min,
                 crossAxisAlignment: CrossAxisAlignment.center,
                 children: [
                   Text('La maquinita ahora está pidiendo cobrar \$${amount.toStringAsFixed(2)}.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                   const SizedBox(height: 24),
                   const CircularProgressIndicator(),
                   const SizedBox(height: 16),
                   const Text('Esperando a que el cliente pase su tarjeta...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                 ]
               ),
               actions: [
                 TextButton(
                   onPressed: () {
                     isPollingDialogOpen = false;
                     Navigator.pop(ctx);
                   },
                   child: const Text('Cancelar cobro manual o cerrar alerta', style: TextStyle(color: Colors.red)),
                 ),
               ]
             )
           ).then((_) => isPollingDialogOpen = false); 

           while (isPollingDialogOpen) {
             await Future.delayed(const Duration(seconds: 2));
             if (!isPollingDialogOpen) break;

             if (!context.mounted) break;

             try {
                final pollResp = await http.get(
                  Uri.parse('http://192.168.1.88:8081/mp/point/integration-api/payment-intents/$intentId'),
                  headers: {'Authorization': 'Bearer $token'},
                );

                if (pollResp.statusCode == 200) {
                  final pollData = json.decode(pollResp.body);
                  final state = pollData['state'] as String?;
                  
                  if (state == 'FINISHED') {
                    isPollingDialogOpen = false;
                    if (context.mounted) {
                      Navigator.pop(context); 
                      onFinish(); 
                    }
                    break;
                  } else if (state == 'CANCELED' || state == 'ABANDONED' || state == 'ERROR') {
                    isPollingDialogOpen = false;
                    if (context.mounted) {
                      Navigator.pop(context); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('El pago no procedió, fue cancelado o rechazado ($state). Intentar nuevamente.', style: const TextStyle(color: Color(0xFF3D2E1A))), backgroundColor: Colors.red)
                      );
                    }
                    break;
                  }
                }
             } catch(e) {
                debugPrint('Poll error: $e'); 
             }
           }
        }
      } else {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error Terminal: ${response.body}')));
        }
      }
    } catch (e) {
      if (context.mounted) {
         Navigator.pop(context);
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de red: $e')));
      }
    }
  }

  Future<void> _payWithClip(
    BuildContext context,
    List<String> orderIds,
    double amount,
    String? tableId,
    String tableLabel,
  ) async {
    // 1. Crear link de pago en Clip
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFFFAF1DE),
        title: Row(children: [
          SizedBox(width: 8),
          Text('Generando link...', style: TextStyle(color: Color(0xFF3D2E1A))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Color(0xFFFF6D00)),
          SizedBox(height: 16),
          Text('Contactando Clip...', style: TextStyle(color: Color(0xFF7A6E5A))),
        ]),
      ),
    );

    String? paymentUrl;
    String? checkoutId;

    try {
      final orderNumber = 'REST-${tableLabel.replaceAll(' ', '')}-${DateTime.now().millisecondsSinceEpoch}';
      final response = await http.post(
        Uri.parse('http://192.168.1.88:8081/clip/v1/checkout'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'amount': amount,
          'purchase_order_number': orderNumber,
          'redirect_url': 'https://restaurant-pwa.c4o2yg.easypanel.host',
        }),
      ).timeout(const Duration(seconds: 10));

      if (context.mounted) Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        paymentUrl = data['payment_request_url'] ??
            data['url'] ??
            data['checkout_url'] ??
            data['link'];
        checkoutId = data['id']?.toString();
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error Clip (${response.statusCode}): ${response.body}'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error de red con Clip: $e'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    if (paymentUrl == null || paymentUrl.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Clip no devolvió un link de pago válido.'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    // 2. Abrir el link de pago en nueva pestaña
    openInNewTab(paymentUrl);

    // 3. Mostrar diálogo de confirmación manual
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Row(children: [
          Icon(Icons.credit_card, color: Color(0xFFFF6D00), size: 28),
          SizedBox(width: 12),
          Text('Pago con Clip', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF1DE),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                const Text('Total a cobrar:', style: TextStyle(color: Color(0xFFA08F70), fontSize: 14)),
                const SizedBox(height: 4),
                Text('\$${amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 32, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 16),
            const Icon(Icons.open_in_new, color: Color(0xFFFF6D00), size: 40),
            const SizedBox(height: 8),
            const Text(
              'Se abrió la página de pago de Clip en una nueva pestaña.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF7A6E5A)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando el cliente haya pagado, presiona "Confirmar pago".',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFA08F70), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirmar pago', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00),
              foregroundColor: Color(0xFFFAF1DE),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 4. Marcar órdenes como pagadas
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('orders').update({
        'status': 'completed',
        'payment_method': 'card',
        'amount_card': amount,
      }).inFilter('id', orderIds);

      if (tableId != null) {
        await supabase.from('restaurant_tables').update({'status': 'available'}).eq('id', tableId as Object);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pago con Clip registrado correctamente'),
          backgroundColor: Colors.green,
        ));
        if (context.mounted) {
          await _showTicketQrDialog(context, orderIds);
        }
        widget.onDeselect?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('orders')
          .stream(primaryKey: ['id'])
          .inFilter('status', ['pending', 'ready', 'incomplete']),
      builder: (context, orderSnapshot) {
        if (!orderSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = orderSnapshot.data!.where((o) => 
          widget.tableId != null ? o['table_id'] == widget.tableId : o['id'] == widget.orderId
        ).toList();

        final panelTitle = widget.tableId != null 
            ? 'Mesa ${widget.tableNumber}' 
            : (orders.isNotEmpty 
                ? (orders.first['order_type'] == 'takeout' ? 'To Go' : 'Delivery') 
                : 'Orden');

        if (orders.isEmpty) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long, size: 64, color: Color(0xFFE5DCC4)),
              const SizedBox(height: 16),
              Text('$panelTitle libre', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('No hay cuentas pendientes.', style: TextStyle(color: Colors.grey)),
            ],
          );
        }

        final orderIds = orders.map((o) => o['id'] as String).toList();

        String waiterName = '';
        if (orders.isNotEmpty && orders.first['waiter_id'] != null) {
          try {
            final waiter = widget.waitersList.firstWhere(
              (w) => w['id'] == orders.first['waiter_id'],
              orElse: () => {},
            );
            if (waiter.isNotEmpty) {
              waiterName = waiter['name'] ?? '';
            }
          } catch (_) {}
        }

        final orderType = orders.isNotEmpty ? orders.first['order_type'] : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.tableId != null ? Icons.receipt : (orderType == 'takeout' ? Icons.takeout_dining : Icons.delivery_dining), 
                        color: const Color(0xFFFF6D00), 
                        size: 28
                      ),
                      const SizedBox(width: 16),
                      Text(panelTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (orderType != 'dine_in' && orderType != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: (orderType == 'takeout' ? Colors.orangeAccent : Colors.purpleAccent).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: (orderType == 'takeout' ? Colors.orangeAccent : Colors.purpleAccent).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          orderType == 'takeout' ? 'PEDIDO TO GO' : 'ENTREGA A DOMICILIO',
                          style: TextStyle(
                            color: orderType == 'takeout' ? Colors.orangeAccent : Colors.purpleAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (waiterName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 16, color: Color(0xFFA08F70)),
                          const SizedBox(width: 4),
                          Text('Mesero: $waiterName', style: const TextStyle(color: Color(0xFFA08F70), fontSize: 14)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5DCC4)),
            
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: supabase.from('order_items')
                    .stream(primaryKey: ['id'])
                    .inFilter('order_id', orderIds)
                    .asyncMap((_) async {
                      final items = await supabase.from('order_items').select('''
                        id, order_id, quantity, status, price_at_time,
                        guisados_selected, dishes (name)
                      ''').inFilter('order_id', orderIds).order('id');
                      return List<Map<String, dynamic>>.from(items);
                    }),
                builder: (context, itemsSnapshot) {
                  if (!itemsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final items = itemsSnapshot.data!;
                  double subtotal = 0.0;
                  for (var it in items) {
                    if (it['status'] != 'cancelled') {
                      subtotal += ((it['quantity'] as num) * (it['price_at_time'] as num));
                    }
                  }

                  double discountAmount = subtotal * (_discountPercent / 100);
                  double totalToPay = subtotal - discountAmount;

                  return Column(
                    children: [
                       Expanded(
                         child: ListView.separated(
                            padding: const EdgeInsets.all(24),
                            itemCount: items.length,
                            separatorBuilder: (context, index) => const Divider(color: Color(0xFFE5DCC4)),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final dishName = _correctDrinkName(item['dishes']['name'], item['guisados_selected']);
                              final quantity = item['quantity'];
                              final price = item['price_at_time'];
                              final itemSubtotal = quantity * price;
                              
                              final itemId = item['id']?.toString() ?? '';
                              final itemOrderId = item['order_id']?.toString() ?? '';

                              final isItemReady = item['status'] == 'ready';
                              final isCancelled = item['status'] == 'cancelled';
                              final displayTitle = '$quantity x $dishName${isCancelled ? ' (Agotado)' : ''}';
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        displayTitle,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isItemReady ? Colors.green[700] : (isCancelled ? Colors.red[400] : Colors.black),
                                          decoration: isItemReady || isCancelled ? TextDecoration.lineThrough : null,
                                        )
                                      ),
                                    ),
                                    if (isItemReady)
                                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                                    if (isCancelled)
                                      const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text('\$${itemSubtotal.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, decoration: isCancelled ? TextDecoration.lineThrough : null, color: isCancelled ? Colors.red[400] : Colors.black)),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                                      tooltip: 'Quitar de la cuenta',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Eliminar platillo'),
                                            content: Text('¿Seguro de quitar $quantity x $dishName de la cuenta?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                onPressed: () => Navigator.pop(ctx, true), 
                                                child: const Text('Quitar', style: TextStyle(color: Color(0xFF3D2E1A))),
                                              ),
                                            ]
                                          )
                                        );
                                        
                                        if (confirm == true) {
                                          try {
                                            final orderResp = await supabase.from('orders').select('total_amount').eq('id', itemOrderId).maybeSingle();
                                            num currentTotal = orderResp != null ? (orderResp['total_amount'] as num) : 0;
                                            num newTotal = currentTotal - itemSubtotal;
                                            if (newTotal < 0) newTotal = 0;

                                            await Future.wait([
                                              supabase.from('orders').update({'total_amount': newTotal}).eq('id', itemOrderId),
                                              supabase.from('order_items').delete().eq('id', itemId)
                                            ]);

                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eliminado: $dishName', style: const TextStyle(color: Color(0xFF3D2E1A))), backgroundColor: Colors.orange));
                                            }
                                          } catch(e) {
                                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                       ),
                       Container(
                        padding: const EdgeInsets.all(24),
                        color: const Color(0xFFFAF1DE),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // DISCOUNT UI
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Añadir descuento:',
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                SizedBox(
                                  width: 130,
                                  height: 48,
                                  child: TextFormField(
                                    initialValue: _discountPercent > 0
                                        ? _discountPercent.toStringAsFixed(0)
                                        : '',
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Color(0xFFFF6D00),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 20),
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      hintStyle: const TextStyle(
                                          color: Color(0xFFA08F70),
                                          fontSize: 20),
                                      suffixText: '%',
                                      suffixStyle: const TextStyle(
                                          color: Color(0xFFFF6D00),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18),
                                      contentPadding: EdgeInsets.zero,
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFF6D00), width: 2),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFF6D00), width: 2),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFFF6D00), width: 3),
                                      ),
                                    ),
                                    onChanged: (val) {
                                      double? parsed = double.tryParse(val);
                                      setState(() {
                                        _discountPercent = parsed ?? 0.0;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (discountAmount > 0) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Subtotal:',
                                      style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                  Text('\$${subtotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Descuento (${_discountPercent.toInt()}%):',
                                      style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                  Text('-\$${discountAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total a pagar:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                Text(
                                  '\$${totalToPay.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFFF6D00)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () => _showAddItemDialog(context, orderIds.first),
                              icon: const Icon(Icons.add_shopping_cart, size: 22),
                              label: const Text('Agregar artículos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                foregroundColor: const Color(0xFFFF6D00),
                                side: const BorderSide(color: Color(0xFFFF6D00), width: 2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _imprimirCuenta(context, orders, orderIds),
                              icon: const Icon(Icons.receipt_long, size: 22),
                              label: const Text('Imprimir Cuenta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                foregroundColor: const Color(0xFFFF6D00),
                                side: const BorderSide(color: Color(0xFFFF6D00), width: 2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final propinaResult = await _askPropina(context, totalToPay);
                                if (propinaResult == null || !context.mounted) return;
                                _showCashPaymentDialog(context, orderIds, propinaResult['total']!, widget.tableId,
                                    propina: propinaResult['propina']!, waiterName: waiterName);
                              },
                              icon: const Icon(Icons.payments, size: 28),
                              label: const Text('Efectivo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                                backgroundColor: Colors.green[600],
                                foregroundColor: Color(0xFFFAF1DE),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final propinaResult = await _askPropina(context, totalToPay);
                                if (propinaResult == null || !context.mounted) return;
                                _markCardPaymentNoTerminal(context, orderIds, propinaResult['total']!, widget.tableId,
                                    propina: propinaResult['propina']!, waiterName: waiterName);
                              },
                              icon: const Icon(Icons.credit_card, size: 26),
                              label: const Text('Tarjeta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final propinaResult = await _askPropina(context, totalToPay);
                                if (propinaResult == null || !context.mounted) return;
                                _showMixedPaymentDialog(context, orderIds, propinaResult['total']!, widget.tableId,
                                    propina: propinaResult['propina']!, waiterName: waiterName);
                              },
                              icon: const Icon(Icons.pie_chart, size: 26),
                              label: const Text('Pago Mixto (Efectivo + Tarjeta)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                                backgroundColor: Colors.orangeAccent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                elevation: 4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () => _cancelOrdersWithPin(context, orderIds, widget.tableId),
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Cancelar toda la cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent, width: 2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ],
                        ),
                      )
                    ]
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF6D00) : const Color(0xFFFAF1DE),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Color(0xFFFAF1DE) : Color(0xFFA08F70),
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
