import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dish_management_view.dart';
import 'guisados_management_view.dart';
import 'waiter_management_view.dart';
import 'table_management_view.dart';
import 'security_management_view.dart';
import 'reports_view.dart';
import 'access_management_view.dart';
import 'billing_view.dart';
import 'clients_view.dart';
import 'payroll_view.dart';
import 'dart:html' as html if (dart.library.io) 'dart:io'; 

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

  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _transformationController.value = Matrix4.identity()..scale(0.5);
    _fetchWaiters();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _fetchWaiters() async {
    final response = await _supabase.from('waiters').select('id, name').eq('branch_name', Globals.currentBranch);
    if (mounted) {
      setState(() => _waiters = List<Map<String, dynamic>>.from(response));
    }
  }

  Widget _buildSidebar(bool isDrawer) {
    return Container(
      width: isDrawer ? null : 250,
      color: const Color(0xFF0F172A),
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
                color: const Color(0xFF1E293B),
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
                      Expanded(child: Text(Globals.currentBranch, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                      const Icon(Icons.edit, color: Colors.white54, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.dashboard, color: _selectedIndex == 0 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Mesas Activas', style: TextStyle(color: _selectedIndex == 0 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 0 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 0,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 0);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.restaurant_menu, color: _selectedIndex == 1 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Gestión de Menú', style: TextStyle(color: _selectedIndex == 1 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 1 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 1,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 1);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.soup_kitchen, color: _selectedIndex == 10 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Guisados', style: TextStyle(color: _selectedIndex == 10 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 10 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 10,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 10);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.people, color: _selectedIndex == 2 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Gestión de Meseros', style: TextStyle(color: _selectedIndex == 2 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 2 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 2,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 2);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.grid_view, color: _selectedIndex == 3 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Gestión de Mesas', style: TextStyle(color: _selectedIndex == 3 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 3 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 3,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 3);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.insert_chart, color: _selectedIndex == 5 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Reportes de Ventas', style: TextStyle(color: _selectedIndex == 5 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 5 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 5,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 5);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.manage_accounts, color: _selectedIndex == 6 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Gestión de Acceso', style: TextStyle(color: _selectedIndex == 6 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 6 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 6,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 6);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.receipt_long, color: _selectedIndex == 7 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Facturación CFDI', style: TextStyle(color: _selectedIndex == 7 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 7 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 7,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 7);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.people_alt, color: _selectedIndex == 8 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Gestión de Clientes', style: TextStyle(color: _selectedIndex == 8 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 8 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 8,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 8);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.account_balance_wallet, color: _selectedIndex == 9 ? const Color(0xFFFF6D00) : const Color(0xFF94A3B8)),
            title: Text('Nómina', style: TextStyle(color: _selectedIndex == 9 ? Colors.white : const Color(0xFF94A3B8), fontWeight: _selectedIndex == 9 ? FontWeight.bold : FontWeight.normal)),
            selected: _selectedIndex == 9,
            selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
            onTap: () {
              setState(() => _selectedIndex = 9);
              if (isDrawer) Navigator.pop(context);
            },
          ),
          const Divider(color: Color(0xFF334155)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CONFIGURACIÓN', style: TextStyle(color: Color(0xFFFF6D00), fontSize: 10, fontWeight: FontWeight.bold)),
                SwitchListTile(
                  value: Globals.splitKitchenMode,
                  title: const Text('Cocina Especializada', style: TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: const Text('Separa pedidos Para Llevar', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) async {
                    await Globals.setSplitKitchenMode(val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF334155)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SISTEMA', style: TextStyle(color: Color(0xFFFF6D00), fontSize: 10, fontWeight: FontWeight.bold)),
                const Text('Versión: 1.0.12', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    if (identical(0, 0.0)) { 
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Recargando aplicación para limpiar caché...'), backgroundColor: Colors.blue)
                       );
                       Future.delayed(const Duration(seconds: 1), () {
                         try {
                           (html.window as dynamic).location.reload();
                         } catch (e) {
                           debugPrint('Reload error: $e');
                         }
                       });
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Limpiar Caché', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(32),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Divider(color: Color(0xFF334155)),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFF94A3B8)),
            title: const Text('Salir al menú', style: TextStyle(color: Color(0xFF94A3B8))),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1100;

    return Scaffold(
      drawer: isMobile ? Drawer(child: _buildSidebar(true)) : null,
      body: Row(
        children: [
          // Left Sidebar: Navigation (Only for Desktop)
          if (!isMobile) _buildSidebar(false),
          
          if (!isMobile) const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF334155)),
          
          // Main Content Section
          Expanded(
            child: _buildMainContent(),
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
              const Text('Escribe el nuevo nombre de la sucursal activa. Los datos existentes también se actualizarán de forma automática.', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                    child: Row(
                      children: [
                        if (isMobile)
                          IconButton(
                            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        const SizedBox(width: 8),
                        const Text(
                          'Vista General',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ],
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
                                    color: const Color(0xFF1E293B),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Órdenes Para Llevar / Delivery Activas', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          height: 130,
                                          child: ListView.separated(
                                            scrollDirection: Axis.horizontal,
                                            itemCount: nonTableOrders.length,
                                            separatorBuilder: (context, index) => const SizedBox(width: 16),
                                            itemBuilder: (context, index) {
                                              final order = nonTableOrders[index];
                                              final isSelected = _selectedOrderId == order['id'];
                                              final orderType = order['order_type'];
                                              final orderTypeStr = orderType == 'takeout' ? 'Para Llevar' : 'Delivery';
                                               
                                               String? waiterName;
                                               if (order['waiter_id'] != null) {
                                                 try {
                                                   final w = _waiters.firstWhere((w) => w['id'] == order['waiter_id']);
                                                   waiterName = w['name'].toString().split(' ').first;
                                                 } catch (_) {}
                                               }

                                              return SizedBox(
                                                width: 160,
                                                child: _TableCard(
                                                  title: orderTypeStr,
                                                  subtitle: order['customer_name'] ?? 'Cliente',
                                                  icon: orderType == 'takeout' ? Icons.takeout_dining : Icons.delivery_dining,
                                                  color: orderType == 'takeout' ? Colors.orangeAccent : Colors.purpleAccent,
                                                  waiterName: waiterName,
                                                  isOccupied: true, // It's an active order
                                                  isSelected: isSelected,
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
                                  child: ClipRRect(
                                    child: InteractiveViewer(
                                      transformationController: _transformationController,
                                      constrained: false,
                                      panEnabled: true,
                                      scaleEnabled: true,
                                      boundaryMargin: const EdgeInsets.all(2000),
                                      minScale: 0.1,
                                      maxScale: 2.0,
                                      child: Container(
                                        width: 2000,
                                        height: 2000,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F172A),
                                          border: Border.all(color: const Color(0xFF334155)),
                                        ),
                                        child: CustomPaint(
                                          painter: GridPainter(),
                                          child: Stack(
                                            children: tables.map((table) {
                                              final isOccupied = table['status'] == 'occupied';
                                              final isSelected = _selectedTableId == table['id'];
                                              double x = (table['pos_x'] as num?)?.toDouble() ?? 50.0;
                                              double y = (table['pos_y'] as num?)?.toDouble() ?? 50.0;
                                              String calculatedSubtitle = isOccupied ? 'Ocupada' : 'Libre';
                                              String? waiterName;
                                              if (isOccupied) {
                                                final tOrders = activeOrders.where((o) => o['table_id'] == table['id']).toList();
                                                if (tOrders.isNotEmpty && tOrders.first['waiter_id'] != null) {
                                                  try {
                                                    final wName = _waiters.firstWhere((w) => w['id'] == tOrders.first['waiter_id'])['name'];
                                                    waiterName = wName.toString().split(' ').first; // Solo primer nombre para el badge
                                                  } catch (_) {}
                                                }
                                              }

                                              return Positioned(
                                                left: x,
                                                top: y,
                                                child: SizedBox(
                                                  width: 120,
                                                  height: 120,
                                                  child: _TableCard(
                                                    title: 'Mesa ${table['table_number']}',
                                                    subtitle: calculatedSubtitle,
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
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ),
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
            if (!isMobile) const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF334155)),
            // Right Section: Order detail for selected table (Only for Desktop)
            if (!isMobile)
              Container(
                width: 350,
                color: const Color(0xFF0F172A),
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
                    color: const Color(0xFF0F172A),
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
                            icon: const Icon(Icons.close, color: Colors.white),
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

  const _TableCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isOccupied,
    required this.isSelected,
    required this.onTap,
    this.color,
    this.waiterName,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = color ?? (isOccupied ? Colors.red[400]! : const Color(0xFF94A3B8));
    final borderColor = isSelected ? const Color(0xFFFF6D00) : (color ?? (isOccupied ? Colors.red.withValues(alpha: 0.5) : const Color(0xFF334155)));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isSelected 
              ? (color ?? const Color(0xFFFF6D00)).withValues(alpha: 0.1) 
              : const Color(0xFF1E293B),
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
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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


  Future<void> _showCashPaymentDialog(BuildContext context, List<String> orderIds, double total, String? tableId) async {
    final cashController = TextEditingController();
    double change = 0.0;
    bool wantFactura = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: const Color(0xFF0F172A),
          title: Row(
            children: [
              const Icon(Icons.payments, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              const Text('Cobro en Efectivo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total a Cobrar:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16)),
                    Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
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
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(children: [
                      Icon(Icons.receipt_long, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text('¿REQUIERE FACTURA?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
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
                    
                    if (ctx.mounted) {
                      Navigator.pop(ctx); // Cerrar diálogo ahora
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago finalizado con éxito'), backgroundColor: Colors.green));
                      
                      widget.onDeselect?.call(); 

                    }
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
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

  Future<void> _showMixedPaymentDialog(BuildContext context, List<String> orderIds, double total, String? tableId) async {
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
            backgroundColor: const Color(0xFF0F172A),
            title: const Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.orangeAccent, size: 28),
                SizedBox(width: 12),
                Text('Cobro Mixto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16)),
                        Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
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
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Tarjeta (\$)',
                            labelStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
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
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Efectivo (\$)',
                            labelStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
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
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(children: [
                          Icon(Icons.receipt_long, color: Colors.blueAccent),
                          SizedBox(width: 8),
                          Text('¿REQUIERE FACTURA?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
                      onPressed: isCardValidated ? null : () {
                        _payWithMercadoPago(context, cardAmount, () {
                          setState(() { isCardValidated = true; });
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago con tarjeta validado con éxito'), backgroundColor: Colors.blue));
                        });
                      },
                      icon: Icon(isCardValidated ? Icons.check : Icons.point_of_sale),
                      label: Text(isCardValidated ? 'TARJETA VALIDADA' : 'CUIDADO: COBRAR \$${cardAmount.toStringAsFixed(2)} EN TERMINAL'),
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
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '¿CUÁNTO EFECTIVO RECIBES? (Cualquier monto restante irá a Tarjeta)',
                      labelStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      prefixIcon: const Icon(Icons.money, color: Colors.green),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.orangeAccent, width: 2)),
                      hintText: '0.00',
                      hintStyle: const TextStyle(color: Colors.white24),
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
                        _payWithMercadoPago(context, cardAmount, () async {
                           setState(() { isCardValidated = true; });
                           await _executeFinalizeMixedPayment(context, orderIds, total, tableId, cashAmount, cardAmount);
                        });
                        return;
                      }
                      await _executeFinalizeMixedPayment(context, orderIds, total, tableId, cashAmount, cardAmount);
                    },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (cardAmount > 0 && !isCardValidated) ? Colors.blueAccent : Colors.orangeAccent,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  (cardAmount > 0 && !isCardValidated) ? 'COBRAR TARJETA Y FINALIZAR' : 'FINALIZAR TODO EL COBRO', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16)
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _executeFinalizeMixedPayment(BuildContext context, List<String> orderIds, double total, String? tableId, double cashAmount, double cardAmount) async {
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

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago Mixto finalizado'), backgroundColor: Colors.green));
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
                        const SnackBar(content: Text('Cuenta cancelada exitosamente', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)
                      );
                      widget.onDeselect?.call();
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PIN Incorrecto', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red)
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Cancelar Cuenta', style: TextStyle(color: Colors.white)),
            ),
          ]
        );
      }
    );
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
                        SnackBar(content: Text('El pago no procedió, fue cancelado o rechazado ($state). Intentar nuevamente.', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red)
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
                ? (orders.first['order_type'] == 'takeout' ? 'Para Llevar' : 'Delivery') 
                : 'Orden');

        if (orders.isEmpty) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long, size: 64, color: Color(0xFF334155)),
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
                          orderType == 'takeout' ? 'PEDIDO PARA LLEVAR' : 'ENTREGA A DOMICILIO',
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
                          const Icon(Icons.person_outline, size: 16, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text('Mesero: $waiterName', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF334155)),
            
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: supabase.from('order_items')
                    .stream(primaryKey: ['id'])
                    .inFilter('order_id', orderIds)
                    .asyncMap((_) async {
                      final items = await supabase.from('order_items').select('''
                        id, order_id, quantity, status, price_at_time,
                        dishes (name)
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
                            separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155)),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final dishName = item['dishes']['name'];
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
                                          color: isItemReady ? Colors.green[300] : (isCancelled ? Colors.red[300] : Colors.white),
                                          decoration: isItemReady || isCancelled ? TextDecoration.lineThrough : null,
                                        )
                                      ),
                                    ),
                                    if (isItemReady)
                                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                                    if (isCancelled)
                                      const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text('\$${itemSubtotal.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, decoration: isCancelled ? TextDecoration.lineThrough : null, color: isCancelled ? Colors.red[300] : Colors.white)),
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
                                                child: const Text('Quitar', style: TextStyle(color: Colors.white)),
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
                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eliminado: $dishName', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.orange));
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
                        color: const Color(0xFF1E293B),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // DISCOUNT UI
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Añadir descuento:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                SizedBox(
                                  width: 120,
                                  height: 40,
                                  child: TextFormField(
                                    initialValue: _discountPercent > 0 ? _discountPercent.toStringAsFixed(0) : '',
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      hintStyle: const TextStyle(color: Colors.white30),
                                      suffixText: '%',
                                      suffixStyle: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold),
                                      contentPadding: EdgeInsets.zero,
                                      filled: true,
                                      fillColor: const Color(0xFF0F172A),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                                  const Text('Subtotal:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                                  Text('\$${subtotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Descuento (${_discountPercent.toInt()}%):', style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                                  Text('-\$${discountAmount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
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
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _showCashPaymentDialog(context, orderIds, totalToPay, widget.tableId),
                                    icon: const Icon(Icons.payments, size: 28),
                                    label: const Text('Efectivo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(60),
                                      backgroundColor: Colors.green[600],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      elevation: 4,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                        _payWithMercadoPago(context, totalToPay, () async {
                                          try {
                                            await supabase.from('orders').update({
                                              'status': 'completed',
                                              'payment_method': 'card',
                                              'amount_card': totalToPay
                                            }).inFilter('id', orderIds);
                                            if (widget.tableId != null) {
                                              await supabase.from('restaurant_tables').update({'status': 'available'}).eq('id', widget.tableId as Object);
                                            }
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cobro con terminal exitoso')));
                                              widget.onDeselect?.call();
                                            }
                                          } catch (e) {
                                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                          }
                                        });
                                    },
                                    icon: const Icon(Icons.point_of_sale),
                                    label: const Text('Terminal M.P.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(60),
                                      backgroundColor: const Color(0xFF009EE3), 
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _showMixedPaymentDialog(context, orderIds, totalToPay, widget.tableId),
                              icon: const Icon(Icons.pie_chart, size: 28),
                              label: const Text('PAGO MIXTO (Efectivo + Tarjeta)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(64),
                                backgroundColor: Colors.orange[700],
                                foregroundColor: Colors.white,
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

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
