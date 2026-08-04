import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../globals.dart';
import '../utils/download_helper.dart';
import 'billing_view.dart';
import 'cash_register_view.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  String _searchQuery = '';
  double _totalSales = 0.0;
  int _totalOrders = 0;
  double _ticketPromedio = 0.0;
  double _efectivoEnCaja = 0.0;
  double _ventasTarjeta = 0.0;
  double _ventasClip = 0.0;
  double _ventasTransferencia = 0.0;
  double _ventasCredito = 0.0;
  List<Map<String, dynamic>> _topProducts = [];

  // Vista activa: 'historial' o 'cortes'
  String _activeView = 'historial';
  bool _isPrintingCorte = false;

  // Filtros
  String _timeFilter = 'all'; // all, day, week, month, exact_date
  String _branchFilter = 'Todas'; 
  String _waiterFilter = 'Todos';
  String _paymentFilter = 'Todos';
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _waitersList = [];

  @override
  void initState() {
    super.initState();
    _branchFilter = Globals.currentBranch;
    _fetchWaiters();
    _fetchReports();
  }

  String _getMesaStr(Map<String, dynamic> o) {
    if (o['restaurant_tables']?['table_number'] != null) {
      return 'Mesa ${o['restaurant_tables']['table_number']}';
    }
    if (o['customer_name'] != null &&
        o['customer_name'].toString().trim().isNotEmpty) {
      return o['customer_name'].toString();
    }
    return 'Venta al Público';
  }

  void _applyFilter() {
    setState(() {
      var localFiltered = List<Map<String, dynamic>>.from(_orders);

      if (_paymentFilter != 'Todos') {
        localFiltered = localFiltered
            .where((o) => o['ui_method'] == _paymentFilter)
            .toList();
      }

      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        localFiltered = localFiltered.where((o) {
          final mesa = _getMesaStr(o).toLowerCase();
          final idStr = o['id'].toString().toLowerCase();
          final mesero = (o['waiters']?['name'] ?? 'N/A')
              .toString()
              .toLowerCase();
          return mesa.contains(q) || idStr.contains(q) || mesero.contains(q);
        }).toList();
      }

      _filteredOrders = localFiltered;

      double total = 0.0;
      double eff = 0.0, tar = 0.0, clip = 0.0, tra = 0.0, cred = 0.0;

      for (var o in _filteredOrders) {
        final amt = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        total += amt;
        final pm = o['ui_method'] as String;

        if (pm == 'TARJETA') {
          tar += amt;
        } else if (pm == 'CLIP') {
          clip += amt;
        } else if (pm == 'TRANSFERENCIA') {
          tra += amt;
        } else if (pm == 'CREDITO') {
          cred += amt;
        } else {
          eff += amt;
        }
      }

      _totalSales = total;
      _totalOrders = _filteredOrders.length;
      _ticketPromedio = _totalOrders > 0 ? _totalSales / _totalOrders : 0.0;
      _efectivoEnCaja = eff;
      _ventasTarjeta = tar;
      _ventasClip = clip;
      _ventasTransferencia = tra;
      _ventasCredito = cred;
    });
    _fetchTopProducts();
  }

  /// Agrega la cantidad vendida por platillo entre las órdenes actualmente
  /// filtradas (mismos filtros de fecha/sucursal/mesero/pago que la tabla),
  /// para la sección "Productos Más Vendidos".
  Future<void> _fetchTopProducts() async {
    if (_filteredOrders.isEmpty) {
      if (mounted) setState(() => _topProducts = []);
      return;
    }
    try {
      final orderIds = _filteredOrders.map((o) => o['id']).toList();
      final items = await _supabase
          .from('order_items')
          .select('quantity, dishes(name)')
          .inFilter('order_id', orderIds);
      final Map<String, int> counts = {};
      for (final it in (items as List)) {
        final name = it['dishes']?['name'] as String?;
        if (name == null) continue;
        final qty = (it['quantity'] as num?)?.toInt() ?? 0;
        counts[name] = (counts[name] ?? 0) + qty;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (mounted) {
        setState(() {
          _topProducts = sorted.take(5).map((e) => {'name': e.key, 'qty': e.value}).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchWaiters() async {
    try {
      final response = await _supabase.from('waiters').select('id, name').eq('branch_name', Globals.currentBranch);
      if (mounted) {
        setState(() {
          _waitersList = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase
          .from('orders')
          .select('*, restaurant_tables(table_number), waiters(name)')
          .eq('status', 'completed');

      final now = DateTime.now();
      if (_timeFilter == 'day') {
        final startOfDay = DateTime(
          now.year,
          now.month,
          now.day,
        ).toUtc().toIso8601String();
        query = query.gte('created_at', startOfDay);
      } else if (_timeFilter == 'week') {
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeekMidnight = DateTime(
          startOfWeek.year,
          startOfWeek.month,
          startOfWeek.day,
        ).toUtc().toIso8601String();
        query = query.gte('created_at', startOfWeekMidnight);
      } else if (_timeFilter == 'month') {
        final startOfMonth = DateTime(
          now.year,
          now.month,
          1,
        ).toUtc().toIso8601String();
        query = query.gte('created_at', startOfMonth);
      } else if (_timeFilter == 'exact_date' && _selectedDate != null) {
        final startOfDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
        ).toUtc().toIso8601String();
        final endOfDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          23,
          59,
          59,
        ).toUtc().toIso8601String();
        query = query
            .gte('created_at', startOfDate)
            .lte('created_at', endOfDate);
      }

      if (_branchFilter != 'Todas') {
        query = query.eq('branch_name', _branchFilter);
      }

      if (_waiterFilter != 'Todos') {
        query = query.eq('waiter_id', _waiterFilter);
      }

      final response = await query.order('created_at', ascending: false);

      final orders = List<Map<String, dynamic>>.from(response);

      for (var o in orders) {
        final pm = o['payment_method']?.toString().toUpperCase() ?? 'EFECTIVO';
        if (pm.contains('CREDITO')) {
          o['ui_method'] = 'CREDITO';
        } else if (pm.contains('CLIP')) {
          o['ui_method'] = 'CLIP';
        } else if (pm.contains('TARJETA') || pm.contains('CARD') || pm.contains('MERCADO')) {
          o['ui_method'] = 'TARJETA';
        } else if (pm.contains('TRANS')) {
          o['ui_method'] = 'TRANSFERENCIA';
        } else {
          o['ui_method'] = 'EFECTIVO';
        }
      }

      if (mounted) {
        _orders = orders;
        _applyFilter();
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  void _downloadCsv() {
    if (_filteredOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar')),
      );
      return;
    }

    final StringBuffer csv = StringBuffer();
    // Headers
    csv.writeln('ID,Fecha,Tipo,Mesa/Cliente,Mesero,Sucursal,Total');

    for (var o in _filteredOrders) {
      final date = DateTime.parse(
        o['created_at'],
      ).toLocal().toString().split('.').first;
      final tipo = o['order_type'] == 'dine_in'
          ? 'Local'
          : (o['order_type'] == 'takeout' ? 'To Go' : 'Delivery');
      final mesaStr = o['restaurant_tables']?['table_number'] != null
          ? 'Mesa ${o['restaurant_tables']['table_number']}'
          : (o['customer_name'] ?? 'Cliente');
      final mesero = o['waiters']?['name'] ?? 'N/A';
      final total = o['total_amount']?.toString() ?? '0.0';
      final sub = o['branch_name'] ?? 'N/A';
      csv.writeln('${o['id']},$date,$tipo,$mesaStr,$mesero,$sub,$total');
    }

    final bytes = utf8.encode(csv.toString());
    downloadBytes(bytes, 'reporte_ventas_restaurant.csv',
        mimeType: 'text/csv');
  }

  Future<void> _downloadPdf() async {
    if (_filteredOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar')),
      );
      return;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Reporte de Ventas - El Sazón (Restaurant)',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Cuentas Cerradas en total: $_totalOrders',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Text(
                'Ingresos Totales: \$${_totalSales.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Fecha', 'Tipo', 'Mesa/Cliente', 'Mesero', 'Sucursal', 'Total'],
                data: _filteredOrders.map((o) {
                  final date = DateTime.parse(
                    o['created_at'],
                  ).toLocal().toString().split('.').first;
                  final tipo = o['order_type'] == 'dine_in'
                      ? 'Local'
                      : (o['order_type'] == 'takeout'
                            ? 'To Go'
                            : 'Delivery');
                  final mesaStr =
                      o['restaurant_tables']?['table_number'] != null
                      ? 'Mesa ${o['restaurant_tables']['table_number']}'
                      : (o['customer_name'] ?? 'Cliente');
                  final mesero = o['waiters']?['name'] ?? 'N/A';
                  final total = o['total_amount']?.toString() ?? '0.0';
                  final sub = o['branch_name'] ?? 'N/A';

                  return [date, tipo, mesaStr, mesero, sub, '\$$total'];
                }).toList(),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    downloadBytes(bytes, 'reporte_ventas_restaurant.pdf',
        mimeType: 'application/pdf');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1000;
    final isSmall = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF1DE),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isSmall ? 16.0 : 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title and actions header
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 16.0,
                    children: [
                      Flex(
                        direction: isSmall ? Axis.vertical : Axis.horizontal,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isSmall ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Historial de Ventas',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6D00),
                            ),
                          ),
                          SizedBox(width: isSmall ? 0 : 24, height: isSmall ? 16 : 0),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF1DE),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _timeFilter == 'exact_date'
                                    ? 'custom'
                                    : _timeFilter,
                                dropdownColor: const Color(0xFFFAF1DE),
                                style: const TextStyle(color: Color(0xFF7A6E5A)),
                                icon: const Icon(
                                  Icons.calendar_today,
                                  color: Color(0xFFA08F70),
                                  size: 16,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'day',
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Text('Hoy'),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'week',
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Text('Esta Semana'),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'month',
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Text('Este Mes'),
                                    ),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'all',
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Text('Histórico Total'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'custom',
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Text(
                                        _selectedDate != null
                                            ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                                            : 'Fecha Específica...',
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) async {
                                  if (value == 'custom') {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date != null) {
                                      setState(() {
                                        _selectedDate = date;
                                        _timeFilter = 'exact_date';
                                      });
                                      _fetchReports();
                                    }
                                  } else if (value != null) {
                                    setState(() {
                                      _timeFilter = value;
                                      _selectedDate = null;
                                    });
                                    _fetchReports();
                                  }
                                },
                              ),
                            ),
                          ),
                          SizedBox(width: isSmall ? 0 : 16, height: isSmall ? 8 : 0),
                          // Branch Filter
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF1DE),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _branchFilter,
                                dropdownColor: const Color(0xFFFAF1DE),
                                style: const TextStyle(color: Color(0xFF7A6E5A)),
                                icon: const Icon(
                                  Icons.store,
                                  color: Color(0xFFA08F70),
                                  size: 16,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'Todas',
                                    child: Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Text('Global (Todas)'),
                                    ),
                                  ),
                                  ...Globals.branches.map((b) => DropdownMenuItem(
                                    value: b,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Text(b),
                                    ),
                                  )),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _branchFilter = value;
                                    });
                                    _fetchReports();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      Flex(
                        direction: isSmall ? Axis.vertical : Axis.horizontal,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isSmall ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CashRegisterView(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.point_of_sale, color: Color(0xFFFAF1DE), size: 18),
                            label: const Text('Cortes y Movimientos', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          SizedBox(width: isSmall ? 0 : 12, height: isSmall ? 12 : 0),
                          ElevatedButton.icon(
                            onPressed: _showVentaHoyDialog,
                            icon: const Icon(Icons.bar_chart, color: Color(0xFFFAF1DE), size: 18),
                            label: const Text('Venta de Hoy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          SizedBox(width: isSmall ? 0 : 12, height: isSmall ? 12 : 0),
                          Row(
                            mainAxisAlignment: isSmall ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.notifications,
                                color: Color(0xFFA08F70),
                              ),
                              const SizedBox(width: 16),
                              PopupMenuButton<String>(
                                onSelected: (val) {
                                  if (val == 'csv') _downloadCsv();
                                  if (val == 'pdf') _downloadPdf();
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'csv',
                                    child: Text('Exportar a Excel (CSV)'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'pdf',
                                    child: Text('Exportar a PDF (Imprimir)'),
                                  ),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6D00),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.file_download,
                                        size: 18,
                                        color: Color(0xFFFAF1DE),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Exportar',
                                        style: TextStyle(
                                          color: Color(0xFFFAF1DE),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // 4 Top Cards - Responsive GRID
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cardWidth = (constraints.maxWidth - (isMobile ? 12 : 48)) / (isMobile ? 2 : 4);
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: cardWidth,
                            child: _buildMetricCard(
                              title: 'VENTAS DEL DÍA',
                              value: '\$${_totalSales.toStringAsFixed(2)}',
                              additionalInfo: '+12%',
                              infoColor: Colors.greenAccent[400],
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _buildMetricCard(
                              title: 'ÓRDENES',
                              value: '$_totalOrders',
                              additionalInfo: 'Hoy',
                              infoColor: Colors.grey,
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _buildMetricCard(
                              title: 'PROMEDIO',
                              value: '\$${_ticketPromedio.toStringAsFixed(2)}',
                              additionalInfo: '-2%',
                              infoColor: Colors.redAccent[400],
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _buildMetricCard(
                              title: 'EFECTIVO',
                              value: '\$${_efectivoEnCaja.toStringAsFixed(2)}',
                              additionalInfo: 'Arqueo',
                              infoColor: const Color(0xFFFF6D00),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // Toggle Historial / Cortes por Día
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildViewTab('historial', Icons.list_alt, 'Historial de Órdenes'),
                      _buildViewTab('cortes', Icons.calendar_today, 'Cortes por Día'),
                      ElevatedButton.icon(
                        onPressed: _isPrintingCorte ? null : _imprimirCorteDelDia,
                        icon: _isPrintingCorte
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.print, size: 18),
                        label: const Text('Imprimir Corte del Día'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6D00),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Data Table
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF1DE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5DCC4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Table Header Actions
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: isMobile
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildSearchField(),
                                    const SizedBox(height: 12),
                                    _buildWaiterDropdown(),
                                    const SizedBox(height: 12),
                                    _buildPaymentDropdown(),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(flex: 2, child: _buildSearchField()),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 1, child: _buildWaiterDropdown()),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 1, child: _buildPaymentDropdown()),
                                    const SizedBox(width: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFAF1DE),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.filter_list, color: Color(0xFFA08F70), size: 20),
                                    ),
                                  ],
                                ),
                        ),
                        
                        // Tabla activa (historial o cortes)
                        _buildActiveTable(),

                        // Pagination
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Mostrando 1-${_filteredOrders.length} de $_totalOrders órdenes',
                                style: const TextStyle(color: Color(0xFFA08F70), fontSize: 12),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Anterior', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12)),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFFFF6D00), borderRadius: BorderRadius.circular(6)),
                                    child: const Text('1', style: TextStyle(color: Color(0xFF3D2E1A), fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Siguiente', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bottom Modules - Responsive
                  if (isMobile) ...[
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF1DE),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5DCC4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: const [
                            Icon(Icons.star, color: Color(0xFFA08F70), size: 18),
                            SizedBox(width: 8),
                            Text('PRODUCTOS MÁS VENDIDOS', style: TextStyle(color: Color(0xFFA08F70), fontWeight: FontWeight.bold, fontSize: 12)),
                          ]),
                          const SizedBox(height: 16),
                          ..._buildTopProductsRows(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF1DE),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5DCC4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: const [
                            Icon(Icons.payments, color: Color(0xFFA08F70), size: 18),
                            SizedBox(width: 8),
                            Text('MÉTODOS DE PAGO', style: TextStyle(color: Color(0xFFA08F70), fontWeight: FontWeight.bold, fontSize: 12)),
                          ]),
                          const SizedBox(height: 24),
                          _buildPaymentMethodRow('Tarjeta', _ventasTarjeta, Icons.credit_card, const Color(0xFFFF6D00)),
                          const SizedBox(height: 16),
                          _buildPaymentMethodRow('Clip', _ventasClip, Icons.contactless, Colors.amberAccent),
                          const SizedBox(height: 16),
                          _buildPaymentMethodRow('Efectivo', _efectivoEnCaja, Icons.money, Colors.greenAccent[400]!),
                          const SizedBox(height: 16),
                          _buildPaymentMethodRow('Crédito (Uber/Didi)', _ventasCredito, Icons.receipt_long, Colors.purpleAccent),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE5DCC4),
                              foregroundColor: Color(0xFFFAF1DE),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('Ver Desglose Detallado'),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF1DE),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5DCC4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(children: const [
                                  Icon(Icons.star, color: Color(0xFFA08F70), size: 18),
                                  SizedBox(width: 8),
                                  Text('PRODUCTOS MÁS VENDIDOS', style: TextStyle(color: Color(0xFFA08F70), fontWeight: FontWeight.bold, fontSize: 12)),
                                ]),
                                const SizedBox(height: 16),
                                ..._buildTopProductsRows(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF1DE),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5DCC4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(children: const [
                                  Icon(Icons.payments, color: Color(0xFFA08F70), size: 18),
                                  SizedBox(width: 8),
                                  Text('MÉTODOS DE PAGO', style: TextStyle(color: Color(0xFFA08F70), fontWeight: FontWeight.bold, fontSize: 12)),
                                ]),
                                const SizedBox(height: 24),
                                _buildPaymentMethodRow('Tarjeta', _ventasTarjeta, Icons.credit_card, const Color(0xFFFF6D00)),
                                const SizedBox(height: 16),
                                _buildPaymentMethodRow('Efectivo', _efectivoEnCaja, Icons.money, Colors.greenAccent[400]!),
                                const SizedBox(height: 16),
                                _buildPaymentMethodRow('Crédito (Uber/Didi)', _ventasCredito, Icons.receipt_long, Colors.purpleAccent),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE5DCC4),
                                    foregroundColor: Color(0xFFFAF1DE),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: const Text('Ver Desglose Detallado'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (val) {
        _searchQuery = val;
        _applyFilter();
      },
      decoration: InputDecoration(
        hintText: 'Buscar...',
        hintStyle: const TextStyle(color: Color(0xFFA08F70)),
        prefixIcon: const Icon(Icons.search, color: Color(0xFFA08F70)),
        filled: true,
        fillColor: const Color(0xFFFAF1DE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
      ),
      style: const TextStyle(color: Color(0xFF3D2E1A)),
    );
  }

  Widget _buildWaiterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _waitersList.any((w) => w['id'] == _waiterFilter) ? _waiterFilter : 'Todos',
          isExpanded: true,
          dropdownColor: const Color(0xFFFAF1DE),
          style: const TextStyle(color: Color(0xFFA08F70)),
          items: [
            const DropdownMenuItem(value: 'Todos', child: Text('Todos los Meseros')),
            ..._waitersList.map((w) => DropdownMenuItem(value: w['id'], child: Text(w['name']))),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _waiterFilter = val);
              _fetchReports();
            }
          },
        ),
      ),
    );
  }

  Widget _buildPaymentDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _paymentFilter,
          isExpanded: true,
          dropdownColor: const Color(0xFFFAF1DE),
          style: const TextStyle(color: Color(0xFFA08F70)),
          items: const [
            DropdownMenuItem(value: 'Todos', child: Text('Pago: Todos')),
            DropdownMenuItem(value: 'EFECTIVO', child: Text('Efectivo')),
            DropdownMenuItem(value: 'TARJETA', child: Text('Tarjeta')),
            DropdownMenuItem(value: 'TRANSFERENCIA', child: Text('Transferencia')),
            DropdownMenuItem(value: 'CREDITO', child: Text('Crédito (Uber/Didi)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _paymentFilter = val);
              _applyFilter();
            }
          },
        ),
      ),
    );
  }

  Widget _buildActiveTable() {
    if (_activeView == 'cortes') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildCortesWidget(),
      );
    }

    if (_filteredOrders.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          _isLoading ? 'Cargando datos...' : 'No hay datos registrados',
          style: const TextStyle(color: Color(0xFFA08F70)),
        ),
      );
    }

    final List<Widget> filas = [];

    // Encabezado
    filas.add(Container(
      color: const Color(0xFFFAF1DE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: const [
        Expanded(flex: 2, child: Text('ID ORDEN', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('TICKET', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('HORA', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(flex: 3, child: Text('MESA / CLIENTE', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('PAGO', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('MESERO', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: Text('TOTAL', style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
      ]),
    ));

    // Filas de datos
    for (int i = 0; i < _filteredOrders.length; i++) {
      final o = _filteredOrders[i];
      final date = DateTime.tryParse(o['created_at'].toString())?.toLocal() ?? DateTime.now();
      final hora = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      final mesaStr = _getMesaStr(o);
      final method = o['ui_method']?.toString() ?? 'EFECTIVO';
      final Color methodColor = method == 'TARJETA'
          ? const Color(0xFFFF6D00)
          : method == 'TRANSFERENCIA'
              ? Colors.purpleAccent
              : method == 'CREDITO'
                  ? Colors.indigoAccent
                  : Colors.green;
      final String idShort = o['id'].toString().length >= 8
          ? o['id'].toString().substring(0, 8)
          : o['id'].toString();
      final ticketLabel = o['daily_folio'] != null
          ? 'Folio #${o['daily_folio'].toString().padLeft(3, '0')}'
          : '#${idShort.toUpperCase()}';

      filas.add(Container(
        decoration: BoxDecoration(
          color: i.isEven ? const Color(0xFFF0E4C8) : const Color(0xFFFAF1DE),
          border: const Border(top: BorderSide(color: Color(0xFFE5DCC4), width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(flex: 2, child: Text('#${idShort.toUpperCase()}', style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(ticketLabel, style: const TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(hora, style: const TextStyle(color: Color(0xFF7A6E5A), fontSize: 13), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text(mesaStr, style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 13), overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: methodColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: methodColor.withValues(alpha: 0.5)),
              ),
              child: Text(method, style: TextStyle(color: methodColor, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            ),
          ),
          Expanded(flex: 2, child: Text(o['waiters']?['name'] ?? 'N/A', style: const TextStyle(color: Color(0xFF7A6E5A), fontSize: 13), overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('\$${o['total_amount']}', style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillingView(ticket: o))),
                  child: const Icon(Icons.receipt_long, color: Colors.blueAccent, size: 16),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => _reimprimirCuenta(o),
                  child: const Icon(Icons.print, color: Colors.teal, size: 16),
                ),
              ],
            ),
          ),
        ]),
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filas,
    );
  }

  Widget _tableCell(String text, {bool isHeader = false, bool bold = false, TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          color: isHeader ? Color(0xFFA08F70) : Color(0xFFFAF1DE),
          fontSize: isHeader ? 11 : 13,
          fontWeight: (isHeader || bold) ? FontWeight.bold : FontWeight.normal,
          letterSpacing: isHeader ? 0.5 : 0,
        ),
        textAlign: align,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  List<Widget> _buildCortesWidget() {
    final cuts = _buildDailyCuts();
    if (cuts.isEmpty) {
      return [
        Container(
          height: 200,
          alignment: Alignment.center,
          child: const Text('No hay datos para este período', style: TextStyle(color: Color(0xFFA08F70))),
        ),
      ];
    }
    return [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: const Color(0xFFFAF1DE).withValues(alpha: 0.5),
        child: const Row(
          children: [
            Expanded(flex: 3, child: Text('FECHA', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('ÓRDENES', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('EFECTIVO', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('TARJETA', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('TRANSFERENCIA', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold))),
            Expanded(flex: 2, child: Text('TOTAL DÍA', style: TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          ],
        ),
      ),
      // Rows
      ...cuts.map((c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(color: Color(0xFFE5DCC4), height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_today, color: Color(0xFFFF6D00), size: 14),
                      ),
                      const SizedBox(width: 10),
                      Text(c['label'] as String, style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${c['count']} órdenes', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(flex: 2, child: Text('\$${(c['efectivo'] as double).toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent))),
                Expanded(flex: 2, child: Text('\$${(c['tarjeta'] as double).toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFF6D00)))),
                Expanded(flex: 2, child: Text('\$${(c['transferencia'] as double).toStringAsFixed(2)}', style: const TextStyle(color: Colors.purpleAccent))),
                Expanded(
                  flex: 2,
                  child: Text(
                    '\$${(c['total'] as double).toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.w900, fontSize: 15),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      )),
    ];
  }

  /// Manda a imprimir el corte del día en la impresora térmica de Caja.
  /// Solo inserta la solicitud — el print-worker (PRINT_AREA=receipt)
  /// la detecta vía Realtime, agrega las ventas de hoy y la imprime.
  Future<void> _imprimirCorteDelDia() async {
    setState(() => _isPrintingCorte = true);
    try {
      await _supabase.from('corte_requests').insert({
        'branch_name': Globals.currentBranch,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Corte del día enviado a la impresora de ${Globals.currentBranch}'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al solicitar el corte: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isPrintingCorte = false);
    }
  }

  /// Diálogo de solo consulta con el total vendido HOY (efectivo + tarjeta),
  /// independiente del filtro de fecha/sucursal seleccionado arriba —
  /// respeta la sucursal filtrada si hay una elegida (no 'Todas').
  Future<void> _showVentaHoyDialog() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    double efectivo = 0, tarjeta = 0, credito = 0;
    int ordenesHoy = 0;
    try {
      var query = _supabase
          .from('orders')
          .select('total_amount, payment_method, amount_cash, amount_card')
          .eq('status', 'completed')
          .gte('created_at', startOfDay.toIso8601String());
      if (_branchFilter != 'Todas') {
        query = query.eq('branch_name', _branchFilter);
      }
      final orders = await query;
      for (final o in (orders as List)) {
        ordenesHoy++;
        final pm = (o['payment_method']?.toString() ?? '').toLowerCase();
        final total = double.tryParse(o['total_amount']?.toString() ?? '0') ?? 0.0;
        if (pm.contains('credito')) {
          credito += total;
        } else if (pm.contains('mixed') || o['amount_cash'] != null || o['amount_card'] != null) {
          efectivo += double.tryParse(o['amount_cash']?.toString() ?? '0') ?? 0.0;
          tarjeta += double.tryParse(o['amount_card']?.toString() ?? '0') ?? 0.0;
        } else if (pm.contains('cash') || pm.contains('efectivo')) {
          efectivo += total;
        } else {
          tarjeta += total;
        }
      }
    } catch (_) {}

    final total = efectivo + tarjeta + credito;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Text('Venta de Hoy', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Órdenes completadas: $ordenesHoy', style: const TextStyle(color: Color(0xFF7A6E5A))),
            const SizedBox(height: 8),
            Text('Ventas en efectivo: \$${efectivo.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF7A6E5A))),
            Text('Ventas en tarjeta: \$${tarjeta.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF7A6E5A))),
            if (credito > 0)
              Text('Ventas a crédito (Uber/Didi): \$${credito.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF7A6E5A))),
            const Divider(),
            Text('Total del día: \$${total.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar', style: TextStyle(color: Color(0xFFFF6D00)))),
        ],
      ),
    );
  }

  /// Manda a reimprimir el ticket de esta orden en la impresora de cuenta
  /// (la Pi con PRINT_AREA=receipt lo detecta vía `cuenta_requested_at`,
  /// igual que el botón "Imprimir Cuenta" del mesero). Como esta pantalla
  /// ya es de Admin, no se vuelve a pedir PIN de reimpresión.
  Future<void> _reimprimirCuenta(Map<String, dynamic> o) async {
    try {
      await _supabase.from('orders').update({
        'cuenta_requested_at': DateTime.now().toUtc().toIso8601String(),
        'caja_printed_at': null,
      }).eq('id', o['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imprimiendo ticket de ${o['branch_name'] ?? Globals.currentBranch}…'),
          backgroundColor: Colors.teal,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al imprimir: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> _buildDailyCuts() {
    final Map<String, Map<String, dynamic>> byDay = {};
    for (final o in _filteredOrders) {
      final date = DateTime.tryParse(o['created_at'].toString())?.toLocal() ?? DateTime.now();
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => {
        'date': key,
        'label': '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
        'count': 0,
        'total': 0.0,
        'efectivo': 0.0,
        'tarjeta': 0.0,
        'transferencia': 0.0,
        'credito': 0.0,
      });
      final amt = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
      byDay[key]!['count'] = (byDay[key]!['count'] as int) + 1;
      byDay[key]!['total'] = (byDay[key]!['total'] as double) + amt;
      final pm = o['ui_method'] as String;
      if (pm == 'TARJETA') {
        byDay[key]!['tarjeta'] = (byDay[key]!['tarjeta'] as double) + amt;
      } else if (pm == 'TRANSFERENCIA') {
        byDay[key]!['transferencia'] = (byDay[key]!['transferencia'] as double) + amt;
      } else if (pm == 'CREDITO') {
        byDay[key]!['credito'] = (byDay[key]!['credito'] as double) + amt;
      } else {
        byDay[key]!['efectivo'] = (byDay[key]!['efectivo'] as double) + amt;
      }
    }
    final result = byDay.values.toList();
    result.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return result;
  }

  Widget _buildViewTab(String value, IconData icon, String label) {
    final isSelected = _activeView == value;
    return GestureDetector(
      onTap: () => setState(() => _activeView = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFFAF1DE),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Color(0xFFFAF1DE) : Color(0xFFA08F70)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Color(0xFFFAF1DE) : Color(0xFFA08F70), fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, int flex, {TextAlign textAlign = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold),
        textAlign: textAlign,
      ),
    );
  }

  List<Widget> _buildTopProductsRows() {
    if (_topProducts.isEmpty) {
      return const [
        Text('Sin ventas registradas en este período', style: TextStyle(color: Color(0xFFA08F70), fontSize: 13)),
      ];
    }
    final top3 = _topProducts.take(3).toList();
    final maxQty = top3.first['qty'] as int;
    final rows = <Widget>[];
    for (var i = 0; i < top3.length; i++) {
      if (i > 0) rows.add(const SizedBox(height: 16));
      rows.add(_buildProductRow(top3[i]['name'] as String, top3[i]['qty'] as int, maxQty, Icons.local_dining));
    }
    return rows;
  }

  Widget _buildProductRow(String name, int qty, int maxQty, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF1DE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFFFF6D00), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF3D2E1A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$qty unidades',
                    style: const TextStyle(color: Color(0xFFA08F70)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: qty / maxQty,
                backgroundColor: const Color(0xFFFAF1DE),
                color: const Color(0xFFFF6D00),
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodRow(
    String name,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF1DE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Text(name, style: const TextStyle(color: Color(0xFF3D2E1A))),
          ],
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            color: Color(0xFFFF6D00),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String additionalInfo,
    required Color? infoColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DCC4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFA08F70),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFFF6D00),
                    fontSize: 24, // Reducido para evitar overflows
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                additionalInfo,
                style: TextStyle(
                  color: infoColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
