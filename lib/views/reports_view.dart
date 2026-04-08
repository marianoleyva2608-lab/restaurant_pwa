import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:html' as html;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../globals.dart';
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
  double _ventasTransferencia = 0.0;

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
      double eff = 0.0, tar = 0.0, tra = 0.0;

      for (var o in _filteredOrders) {
        final amt = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        total += amt;
        final pm = o['ui_method'] as String;

        if (pm == 'TARJETA') {
          tar += amt;
        } else if (pm == 'TRANSFERENCIA') {
          tra += amt;
        } else {
          eff += amt;
        }
      }

      _totalSales = total;
      _totalOrders = _filteredOrders.length;
      _ticketPromedio = _totalOrders > 0 ? _totalSales / _totalOrders : 0.0;
      _efectivoEnCaja = eff;
      _ventasTarjeta = tar;
      _ventasTransferencia = tra;
    });
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
        if (pm.contains('TARJETA') || pm.contains('MERCADO')) {
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
          : (o['order_type'] == 'takeout' ? 'Para Llevar' : 'Delivery');
      final mesaStr = o['restaurant_tables']?['table_number'] != null
          ? 'Mesa ${o['restaurant_tables']['table_number']}'
          : (o['customer_name'] ?? 'Cliente');
      final mesero = o['waiters']?['name'] ?? 'N/A';
      final total = o['total_amount']?.toString() ?? '0.0';
      final sub = o['branch_name'] ?? 'N/A';
      csv.writeln('${o['id']},$date,$tipo,$mesaStr,$mesero,$sub,$total');
    }

    if (kIsWeb) {
      final bytes = utf8.encode(csv.toString());
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'reporte_ventas_restaurant.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    }
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
                            ? 'Para Llevar'
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

    if (kIsWeb) {
      final bytes = await pdf.save();
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'reporte_ventas_restaurant.pdf')
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1000;
    final isSmall = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
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
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: isSmall ? 0 : 24, height: isSmall ? 16 : 0),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _timeFilter == 'exact_date'
                                    ? 'custom'
                                    : _timeFilter,
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(color: Colors.white70),
                                icon: const Icon(
                                  Icons.calendar_today,
                                  color: Colors.white54,
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
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _branchFilter,
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(color: Colors.white70),
                                icon: const Icon(
                                  Icons.store,
                                  color: Colors.white54,
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
                            icon: const Icon(Icons.point_of_sale, color: Colors.white, size: 18),
                            label: const Text('Cortes y Movimientos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
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
                                color: Colors.white54,
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
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Exportar',
                                        style: TextStyle(
                                          color: Colors.white,
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

                  // Data Table
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Table Header Actions
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Flex(
                            direction: isMobile ? Axis.vertical : Axis.horizontal,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Flexible(
                                flex: isMobile ? 0 : 2,
                                child: TextField(
                                  onChanged: (val) {
                                    _searchQuery = val;
                                    _applyFilter();
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Buscar...',
                                    hintStyle: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: Colors.white54,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 0,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 16),
                              Flexible(
                                flex: isMobile ? 0 : 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value:
                                          _waitersList.any(
                                            (w) => w['id'] == _waiterFilter,
                                          )
                                          ? _waiterFilter
                                          : 'Todos',
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1E293B),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                          value: 'Todos',
                                          child: Text('Todos los Meseros'),
                                        ),
                                        ..._waitersList.map(
                                          (w) => DropdownMenuItem(
                                            value: w['id'],
                                            child: Text(w['name']),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _waiterFilter = val);
                                          _fetchReports();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 16),
                              Flexible(
                                flex: isMobile ? 0 : 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _paymentFilter,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1E293B),
                                      style: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'Todos',
                                          child: Text('Método de Pago: Todos'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'EFECTIVO',
                                          child: Text('Efectivo'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'TARJETA',
                                          child: Text('Tarjeta/MercadoPago'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'TRANSFERENCIA',
                                          child: Text('Transferencia'),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _paymentFilter = val);
                                          _applyFilter();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              if (!isMobile) const Spacer(),
                              if (!isMobile)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.filter_list,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Table Headers & Body with Horizontal Scroll for Mobile
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: isMobile ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: isMobile ? 900 : screenWidth - (isSmall ? 32 : 64),
                            ),
                            child: Column(
                              children: [
                                // Headers
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.5),
                                  child: Row(
                                    children: [
                                      _buildHeaderCell('ID ORDEN', 2),
                                      _buildHeaderCell('HORA', 2),
                                      _buildHeaderCell('MESA / CLIENTE', 3),
                                      _buildHeaderCell('PAGO', 2),
                                      _buildHeaderCell('MESERO', 2),
                                      _buildHeaderCell('SUCURSAL', 2),
                                  _buildHeaderCell('TOTAL', 2, textAlign: TextAlign.right),
                                  const SizedBox(width: 100), // Actions space
                                ],
                              ),
                            ),
                            
                            // Table Content - Using Column instead of ListView to avoid height issues in some browsers/layouts
                            if (_filteredOrders.isEmpty)
                              Container(
                                height: 200,
                                alignment: Alignment.center,
                                child: Text(
                                  _isLoading ? 'Cargando datos...' : 'No hay datos registrados para esta selección',
                                  style: const TextStyle(color: Colors.white54),
                                ),
                              )
                            else
                              ..._filteredOrders.map((o) {
                                final date = DateTime.tryParse(o['created_at'].toString())?.toLocal() ?? DateTime.now();
                                final hora = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                final mesaStr = _getMesaStr(o);
                                final method = o['ui_method']?.toString() ?? 'EFECTIVO';
                                Color methodColor = (method == 'TARJETA') ? const Color(0xFFFF6D00) : (method == 'TRANSFERENCIA' ? Colors.purpleAccent : Colors.green);

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Divider(color: Color(0xFF334155), height: 1),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      child: Row(
                                        children: [
                                          Expanded(flex: 2, child: Text('#ORD-${o['id'].toString().substring(0, 4)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                          Expanded(flex: 2, child: Text(hora, style: const TextStyle(color: Colors.white70))),
                                          Expanded(flex: 3, child: Text(mesaStr, style: const TextStyle(color: Colors.white))),
                                          Expanded(
                                            flex: 2,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: methodColor.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: methodColor.withValues(alpha: 0.5)),
                                                ),
                                                child: Text(method, style: TextStyle(color: methodColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                          ),
                                          Expanded(flex: 2, child: Text(o['waiters']?['name'] ?? 'N/A', style: const TextStyle(color: Colors.white70))),
                                          Expanded(flex: 2, child: Text(o['branch_name'] ?? 'N/A', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                          Expanded(flex: 2, child: Text('\$${o['total_amount']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                                          SizedBox(
                                            width: 100,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.receipt_long, color: Colors.blueAccent, size: 20),
                                                  tooltip: 'Facturación / Ticket',
                                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillingView(ticket: o))),
                                                ),
                                                const Icon(Icons.remove_red_eye, color: Colors.white54, size: 20),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                          ],
                        ),
                      ),
                    ),

                        // Pagination
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Flex(
                            direction: isSmall ? Axis.vertical : Axis.horizontal,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Mostrando 1-${_filteredOrders.length} de $_totalOrders órdenes',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              if (isSmall) const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Anterior', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFFFF6D00), borderRadius: BorderRadius.circular(6)),
                                    child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text('Siguiente', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bottom Modules - Responsive (Row to Column)
                  Flex(
                    direction: isMobile ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Productos más vendidos
                      Expanded(
                        flex: isMobile ? 0 : 2,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.star, color: Colors.white54, size: 18),
                                  SizedBox(width: 8),
                                  Text('PRODUCTOS MÁS VENDIDOS', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildProductRow('Café Americano', 85, 100, Icons.local_cafe),
                              const SizedBox(height: 16),
                              _buildProductRow('Croissant Clásico', 62, 100, Icons.bakery_dining),
                              const SizedBox(height: 16),
                              _buildProductRow('Sandwich de Pavo', 48, 100, Icons.lunch_dining),
                            ],
                          ),
                        ),
                      ),
                      if (isMobile) const SizedBox(height: 24) else const SizedBox(width: 24),
                      // Métodos de Pago
                      Expanded(
                        flex: isMobile ? 0 : 1,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.payments, color: Colors.white54, size: 18),
                                  SizedBox(width: 8),
                                  Text('MÉTODOS DE PAGO', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildPaymentMethodRow('Tarjeta', _ventasTarjeta, Icons.credit_card, const Color(0xFFFF6D00)),
                              const SizedBox(height: 16),
                              _buildPaymentMethodRow('Efectivo', _efectivoEnCaja, Icons.money, Colors.greenAccent[400]!),
                              const SizedBox(height: 16),
                              _buildPaymentMethodRow('Transferencia', _ventasTransferencia, Icons.account_balance, Colors.purpleAccent),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF334155),
                                  foregroundColor: Colors.white,
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

  Widget _buildHeaderCell(String text, int flex, {TextAlign textAlign = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
        textAlign: textAlign,
      ),
    );
  }

  Widget _buildProductRow(String name, int qty, int maxQty, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
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
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$qty unidades',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: qty / maxQty,
                backgroundColor: const Color(0xFF0F172A),
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
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Text(name, style: const TextStyle(color: Colors.white)),
          ],
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
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
                    color: Colors.white,
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
