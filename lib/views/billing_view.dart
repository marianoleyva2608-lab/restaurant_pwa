import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../globals.dart';

class BillingView extends StatefulWidget {
  final Map<String, dynamic>? ticket;
  const BillingView({super.key, this.ticket});

  @override
  State<BillingView> createState() => _BillingViewState();
}

class _BillingViewState extends State<BillingView> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _selectedTicket;
  List<Map<String, dynamic>> _realClients = [];
  bool _isLoadingClients = true;
  List<Map<String, dynamic>> _recentOrders = [];
  bool _isLoadingOrders = true;
  StreamSubscription? _clientsSubscription;
  StreamSubscription? _ordersSubscription;

  // Selected Values
  String _selectedClient = "PUBLICO EN GENERAL";
  String _currentRFC = "XAXX010101000";
  String _selectedRegimen = "616";
  String _selectedMetodoPago = "PUE";
  String _selectedUsoCFDI = "S01";
  String _selectedFormaPago = "01";
  String _selectedPersonType = "FÍSICA";

  // SAT Catalogs (Categorizados)
  final Map<String, String> _regimenesFisica = {
    "605": "605 - Sueldos y salarios",
    "606": "606 - Arrendamiento",
    "610": "610 - Residentes en el Extranjero",
    "611": "611 - Dividendos",
    "612": "612 - P. Físicas con Actividad Empresarial",
    "614": "614 - Intereses",
    "616": "616 - Sin obligaciones fiscales",
    "621": "621 - Incorporación Fiscal",
    "625": "625 - Actividades Agrícolas/Ganaderas (P. Físicas)",
    "626": "626 - RESICO (Confianza)",
  };

  final Map<String, String> _regimenesMoral = {
    "601": "601 - General de Ley Personas Morales",
    "603": "603 - Personas Morales con Fines no Lucrativos",
    "610": "610 - Residentes en el Extranjero",
    "620": "620 - Sociedades Cooperativas",
    "622": "622 - Actividades Agrícolas/Ganaderas (P. Morales)",
    "623": "623 - Opcional para Grupos de Sociedades",
    "624": "624 - Coordinados",
    "626": "626 - RESICO (Confianza)",
  };

  Map<String, String> get _currentRegimenes =>
      _selectedPersonType == "FÍSICA" ? _regimenesFisica : _regimenesMoral;

  final Map<String, String> _metodosPago = {
    "PUE": "PUE - Pago en una sola exhibición",
    "PPD": "PPD - Pago en parcialidades o diferido",
  };

  final Map<String, String> _formasPago = {
    "01": "01 - Efectivo",
    "02": "02 - Cheque nominativo",
    "03": "03 - Transferencia electrónica",
    "04": "04 - Tarjeta de crédito",
    "05": "05 - Monedero electrónico",
    "06": "06 - Dinero electrónico",
    "08": "08 - Vales de despensa",
    "12": "12 - Dación en pago",
    "13": "13 - Pago por subrogación",
    "14": "14 - Pago por consignación",
    "15": "15 - Condonación",
    "17": "17 - Compensación",
    "23": "23 - Novación",
    "24": "24 - Confusión",
    "25": "25 - Remisión de deuda",
    "26": "26 - Prescripción",
    "27": "27 - A satisfacción del acreedor",
    "28": "28 - Tarjeta de débito",
    "29": "29 - Tarjeta de servicios",
    "30": "30 - Aplicación de anticipos",
    "31": "31 - Intermediario pagos",
    "99": "99 - Por definir",
  };

  final Map<String, String> _usosCFDI = {
    "G01": "G01 - Adquisición de mercancías",
    "G02": "G02 - Devoluciones, descuentos o bonificaciones",
    "G03": "G03 - Gastos en general",
    "I01": "I01 - Construcciones",
    "S01": "S01 - Sin efectos fiscales",
    "CP01": "CP01 - Pagos",
  };

  @override
  void initState() {
    super.initState();
    _selectedTicket = widget.ticket;
    if (_selectedTicket != null && _selectedTicket!['payment_method'] != null) {
      _selectedFormaPago = _selectedTicket!['payment_method'];
    }
    _setupClientsStream();
    if (_selectedTicket == null) {
      _setupOrdersStream();
    }
  }

  void _setupOrdersStream() {
    _ordersSubscription = _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'completed')
        .order('created_at', ascending: false)
        .limit(20)
        .listen((res) {
          if (mounted) {
            setState(() {
              _recentOrders = List<Map<String, dynamic>>.from(res);
              _isLoadingOrders = false;
            });
          }
        });
  }

  void _setupClientsStream() {
    _clientsSubscription = _supabase
        .from('cw_clients')
        .stream(primaryKey: ['id'])
        .order('name')
        .listen((res) {
          if (mounted) {
            setState(() {
              _realClients = List<Map<String, dynamic>>.from(res);
              _isLoadingClients = false;
            });
          }
        });
  }

  @override
  void dispose() {
    _clientsSubscription?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Facturación (CFDI 4.0)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.red),
            label: const Text(
              'SALIR',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flex(
                    direction: isMobile ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generar Comprobante Fiscal',
                            style: TextStyle(
                              fontSize: isMobile ? 22 : 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Folio Venta: ${_selectedTicket?['id']?.substring(0, 8) ?? 'Nueva'}',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.blueGrey,
                            ),
                          ),
                          Text(
                            'Fecha: ${_selectedTicket?['created_at'] != null ? DateTime.parse(_selectedTicket!['created_at']).toLocal().toString().split('.')[0] : 'Hoy'}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                      if (isMobile) const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'CFDI 4.0 - ACTIVO',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'v1.0.12',
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_selectedTicket == null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orangeAccent),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.history, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('Seleccionar Pedido Reciente para Facturar',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isLoadingOrders)
                            const CircularProgressIndicator()
                          else if (_recentOrders.isEmpty)
                            const Text('No hay pedidos completados recientemente.')
                          else
                            DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              hint: const Text('Selecciona un pedido...'),
                              items: _recentOrders.map((o) {
                                return DropdownMenuItem<String>(
                                  value: o['id'],
                                  child: Text('Folio: ${o['id'].substring(0,8)} - \$${o['total_amount']} (${o['created_at'].toString().split('T')[0]})'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedTicket = _recentOrders.firstWhere((o) => o['id'] == val);
                                  _selectedFormaPago = _selectedTicket?['payment_method'] ?? '01';
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Customer & Regime Section
                  Flex(
                    direction: isMobile ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        flex: isMobile ? 0 : 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('CLIENTE RECEPTOR'),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return DropdownMenu<String>(
                                  width: constraints.maxWidth,
                                  initialSelection: _selectedClient,
                                  enableFilter: true,
                                  enableSearch: true,
                                  hintText: 'Buscar cliente...',
                                  textStyle: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  inputDecorationTheme: InputDecorationTheme(
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: Colors.grey[300]!),
                                    ),
                                  ),
                                  dropdownMenuEntries: [
                                    const DropdownMenuEntry(
                                      value: 'PUBLICO EN GENERAL',
                                      label: 'PUBLICO EN GENERAL (XAXX010101000)',
                                    ),
                                    ..._realClients.map(
                                      (c) => DropdownMenuEntry(
                                        value: c['name'],
                                        label: "${c['name']} (${c['rfc']})",
                                      ),
                                    ),
                                  ],
                                  onSelected: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedClient = val;
                                        if (val == 'PUBLICO EN GENERAL') {
                                          _currentRFC = 'XAXX010101000';
                                          _selectedPersonType = "FÍSICA";
                                          _selectedRegimen = '616';
                                          _selectedUsoCFDI = 'S01';
                                        } else {
                                          final client = _realClients.firstWhere(
                                            (c) => c['name'] == val,
                                          );
                                          _currentRFC = client['rfc'] ?? 'S/N';
                                          _selectedPersonType = client['person_type'] ??
                                              (client['rfc']?.length == 12 ? 'MORAL' : 'FÍSICA');
                                          
                                          String candidateRegimen = client['regimen_code'] ??
                                              (_selectedPersonType == 'FÍSICA' ? '612' : '601');
                                              
                                          if (_selectedPersonType == 'FÍSICA' && !_regimenesFisica.containsKey(candidateRegimen)) {
                                              candidateRegimen = '612';
                                          } else if (_selectedPersonType == 'MORAL' && !_regimenesMoral.containsKey(candidateRegimen)) {
                                              candidateRegimen = '601';
                                          }
                                          
                                          _selectedRegimen = candidateRegimen;
                                          _selectedUsoCFDI = client['uso_cfdi_default'] ?? 'G03';
                                        }
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      if (isMobile) const SizedBox(height: 16),
                      if (!isMobile) const SizedBox(width: 24),
                      Flexible(
                         flex: isMobile ? 0 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('RÉGIMEN FISCAL'),
                            _dropdown(
                              _selectedRegimen,
                              _currentRegimenes.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              null,
                            ), // Read-only once set in client
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Payment Info Section
                  Flex(
                    direction: isMobile ? Axis.vertical : Axis.horizontal,
                    children: [
                      Flexible(
                        flex: isMobile ? 0 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('MÉTODO DE PAGO'),
                            _dropdown(
                              _selectedMetodoPago,
                              _metodosPago.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              (val) =>
                                  setState(() => _selectedMetodoPago = val!),
                            ),
                          ],
                        ),
                      ),
                      if (isMobile) const SizedBox(height: 16),
                      if (!isMobile) const SizedBox(width: 24),
                      Flexible(
                        flex: isMobile ? 0 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('USO DE CFDI'),
                            _dropdown(
                              _selectedUsoCFDI,
                              _usosCFDI.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              (val) => setState(() => _selectedUsoCFDI = val!),
                            ),
                          ],
                        ),
                      ),
                      if (isMobile) const SizedBox(height: 16),
                      if (!isMobile) const SizedBox(width: 24),
                      Flexible(
                        flex: isMobile ? 0 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('FORMA DE PAGO'),
                            _dropdown(
                              _selectedFormaPago,
                              _formasPago.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              (val) =>
                                  setState(() => _selectedFormaPago = val!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Items Table
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (!isMobile)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: const [
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'CLAVE SAT',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Text(
                                  'DESCRIPCIÓN DEL SERVICIO',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'PRECIO U.',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'CANT.',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'TOTAL',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Item Row using Ticket Data
                        _tableRow(
                          '90101501',
                          'CONSUMO DE ALIMENTOS',
                          (_selectedTicket?['total_amount'] ?? 0.0) / 1.16,
                          1,
                          (_selectedTicket?['total_amount'] ?? 0.0).toDouble(),
                          isMobile,
                        ),

                        // Footer Totals
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey[50],
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _totalLine(
                                    'Subtotal:',
                                    (_selectedTicket?['total_amount'] ?? 0.0) /
                                        1.16,
                                  ),
                                  _totalLine(
                                    'IVA Trasladado (16%):',
                                    (_selectedTicket?['total_amount'] ?? 0.0) -
                                        ((_selectedTicket?['total_amount'] ??
                                                0.0) /
                                            1.16),
                                  ),
                                  const SizedBox(height: 8),
                                  _totalLine(
                                    'IMPORTE TOTAL:',
                                    (_selectedTicket?['total_amount'] ?? 0.0)
                                        .toDouble(),
                                    isBold: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Action Buttons
                  Flex(
                    direction: isMobile ? Axis.vertical : Axis.horizontal,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: isMobile ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 24,
                          ),
                        ),
                        child: const Text(
                          'CANCELAR',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isMobile) const SizedBox(height: 12) else const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _timbrarFactura,
                        icon: const Icon(Icons.receipt_long, size: 20),
                        label: const Text('TIMBRAR E IMPRIMIR CFDI 4.0'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo[900],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 24,
                          ),
                          elevation: 4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _printInvoice() async {
    final pdf = pw.Document();

    final totalText = _selectedTicket?['total_amount'] ?? 0.0;
    final total = totalText is num
        ? totalText.toDouble()
        : double.tryParse(totalText.toString()) ?? 0.0;
    final subtotal = total / 1.16;
    final iva = total - subtotal;

    final emisorNombre = CFDIConfig.emisorNombre.isNotEmpty
        ? CFDIConfig.emisorNombre
        : 'ESCUELA KEMPER URGATE';
    final emisorRFC = CFDIConfig.emisorRFC.isNotEmpty
        ? CFDIConfig.emisorRFC
        : 'EKU9003173C9';
    final emisorRegimen = CFDIConfig.emisorRegimen.isNotEmpty
        ? CFDIConfig.emisorRegimen
        : '601';
    final emisorRegimenDesc =
        'General de Ley Personas Morales ($emisorRegimen)';

    final receptorNombre =
        _selectedClient.isNotEmpty ? _selectedClient : 'Publico General';
    final receptorRFC =
        _currentRFC.isNotEmpty ? _currentRFC : 'XAXX010101000';
    final receptorUso = _selectedUsoCFDI;
    final receptorRegimen = _selectedRegimen;
    final receptorRegimenDesc = 'Sin obligaciones fiscales ($receptorRegimen)';
    final receptorResidencia = '45079';

    final folioFiscal = '2cd18910-539a-4e68-a210-8dbcff6706d3';
    final numCSD = '30001000000500003416';
    final lugarFecha =
        '45079 ${DateTime.now().toIso8601String().split('.')[0]}';

    String totalEnLetra = "CANTIDAD NETA ${(total).toStringAsFixed(2)} (MXN)";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Blue Factura Banner
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xff000099)),
                child: pw.Center(
                  child: pw.Text(
                    'Factura',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 10),

              // Emisor y Receptor Info
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 120),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Emisor:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: emisorNombre, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'RFC: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: emisorRFC, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Regimen Fiscal: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: emisorRegimenDesc, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.SizedBox(height: 8),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Receptor:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: receptorNombre, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'RFC: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: receptorRFC, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Uso CFDI: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: receptorUso, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Regimen Fiscal: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: receptorRegimenDesc, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Residencia Fiscal: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: receptorResidencia, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),

              // Red outlined box for Factura details
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColor.fromInt(0xffcc0000), width: 0.5, style: pw.BorderStyle.dashed),
                    bottom: pw.BorderSide(color: PdfColor.fromInt(0xffcc0000), width: 0.5, style: pw.BorderStyle.dashed),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'FACTURA: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: 'F1', style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Folio Fiscal: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: folioFiscal, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Numero Certificado CSD: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: numCSD, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                    pw.RichText(text: pw.TextSpan(children: [
                      pw.TextSpan(text: 'Lugar y Fecha: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.TextSpan(text: lugarFecha, style: const pw.TextStyle(fontSize: 10)),
                    ])),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Items Table
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColor.fromInt(0xffcc0000), width: 0.5, style: pw.BorderStyle.dashed),
                  ),
                ),
                child: pw.TableHelper.fromTextArray(
                  border: null,
                  headerStyle: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xff000099)),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  cellAlignment: pw.Alignment.centerRight,
                  headers: [
                    'CveProdServ',
                    'NoIdent',
                    'CNT',
                    'CveUnidad',
                    'Unidad',
                    'Descripcion',
                    'Precio\nUnitario',
                    'Importe',
                    'Objeto\nImpuesto',
                  ],
                  data: [
                    [
                      '90101501',
                      '999999',
                      '1',
                      'E48',
                      'Unidad de servicio',
                      'CONSUMO DE ALIMENTOS',
                      '\$${subtotal.toStringAsFixed(2)}',
                      '\$${subtotal.toStringAsFixed(2)}',
                      '02',
                    ],
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Subtotal / IVA / Total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('IMPORTE \$', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('IVA (16%)', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 8),
                      pw.Text('TOTAL \$', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('MXN', style: const pw.TextStyle(fontSize: 10)),
                    ]
                  ),
                  pw.SizedBox(width: 40),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(subtotal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10)),
                      pw.Text(iva.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 8),
                      pw.Text(total.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10)),
                    ]
                  ),
                  pw.SizedBox(width: 60),
                ]
              ),

              pw.SizedBox(height: 20),

              // Bottom section with QR and long texts
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Lado izquierdo: QR Code
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 90,
                        height: 90,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: 'https://verificacfdi.facturaelectronica.sat.gob.mx/default.aspx?id=$folioFiscal',
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text('DESCARGAR XML', style: pw.TextStyle(color: PdfColors.red, fontSize: 8, decoration: pw.TextDecoration.underline))
                    ]
                  ),
                  pw.SizedBox(width: 20),
                  // Lado derecho: Detalles
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Cantidad con Letra: $totalEnLetra', style: const pw.TextStyle(fontSize: 8)),
                        pw.RichText(text: pw.TextSpan(children: [
                          pw.TextSpan(text: 'Metodo de Pago: PAGO EN UNA SOLA EXHIBICION ($_selectedMetodoPago) | Forma de Pago: EFECTIVO ($_selectedFormaPago) | \nRegimen Fiscal: $emisorRegimenDesc Fecha Timbrado : ${lugarFecha.split(" ").last}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        ])),
                        pw.Text('Sello:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        pw.Text('QO8lKnU5LTH1ipU4pSMYmdEI5lrszHj8vt5Gzc/RMbLCtxjfrB7s9DXbz86VsUotE1vm3iHWvW7sOoKxKyn01bavjoZ+9jXeMH7REqpw4PPMK6jWzf43wkD6ZDY/BojOU4HTFqLNFvtWiPfMAfhhQfU42FUrfxY+UsSNJMajWDjHD+Cr9t3EPij4oVQd7QKGa7lrqkLgTT0NOVfLgQzKfi6f6zGHOiH7GSW2tHKbnsfGeIn7tIhJuR9q2guJ8PZIF9/Sz3MoQ1N2qoV9InovYWY7UsdkdtjRdVV7D+1mobkj0l6b7T7wD8Ub33emD71G3f0wCvouife0koaC+py6cw==', style: const pw.TextStyle(fontSize: 7)),
                        pw.Text('Sello SAT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        pw.Text('JNZ4RI2QWLZalWYIYfEXn3yOfreplyabv8sp7MOJolaRezPm48u+4oRUmswPFOqNeYMiCzVXwV/HGEdRANOXpgSAAcBylx6XjnzYWqNV/ZngE3bqbRMckta4nFK5ENdapuuwKJYL9cGhpwR01T0eaRtmRuHrkZzFhl0prChF/6y/8TNtRLtw9udWhpsqra35wmGDx9lk8TLybZwN72K4X2TPm4LYQbg1gCKOUUottEVdwlw9E8KBwCvdqdHiYPgiXBeCp0oinN50wBUkD56LHcUwDNjEocjPxCqyZmPKMjyTLzD4nSHmxlSkZ4+Ut9e6PAbz1eZkIQMagjouxbH09w==', style: const pw.TextStyle(fontSize: 7)),
                        pw.RichText(text: pw.TextSpan(children: [
                          pw.TextSpan(text: 'Numero Certificado SAT : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                          pw.TextSpan(text: '30001000000500003456', style: const pw.TextStyle(fontSize: 8)),
                        ])),
                        pw.Text('Cadena Original', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        pw.SizedBox(height: 4),
                        pw.Text('||1.1|2cd18910-539a-4e68-a210-8dbcff6706d3|2025-11-21T10:59:39|QO8lKnU5LTH1ipU4pSMYmdEI5lrszHj8vt5Gzc/RMbLCtxjfrB7s9DXbz86VsUotE1vm3iHWvW7sOoKxKyn01bavjoZ+9jXeMH7REqpw4PPMK6jWzf43wkD6ZDY/BojOU4HTFqLNFvtWiPfMAfhhQfU42FUrfxY+UsSNJMajWDjHD+Cr9t3EPij4oVQd7QKGa7lrqkLgTT0NOVfLgQzKfi6f6zGHOiH7GSW2tHKbnsfGeIn7tIhJuR9q2guJ8PZIF9/Sz3MoQ1N2qoV9InovYWY7UsdkdtjRdVV7D+1mobkj0l6b7T7wD8Ub33emD71G3f0wCvouife0koaC+py6cw==|30001000000500003456||', style: const pw.TextStyle(fontSize: 7)),
                        pw.SizedBox(height: 4),
                        pw.Text('Este documento es una representacion impresa de un CFDI EFECTOS FISCALES AL PAGO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      ]
                    )
                  )
                ]
              )
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: Color(0xFF64748B),
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _dropdown(
    String? value,
    List<DropdownMenuItem<String>> items,
    void Function(String?)? onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: onChanged == null ? Colors.grey[200] : Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: TextStyle(
            color: onChanged == null ? Colors.black54 : const Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          items: items,
          onChanged: onChanged,
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: onChanged == null ? Colors.black38 : const Color(0xFF1E3A8A),
          ),
        ),
      ),
    );
  }

  Widget _tableRow(
    String code,
    String name,
    double price,
    int qty,
    double total,
    bool isMobile,
  ) {
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${qty} x \$${price.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 24),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '\$${price.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(qty.toString(), style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalLine(String label, double amount, {bool isBold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 20 : 15,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w500,
            color: isBold ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 32),
        SizedBox(
          width: 140,
          child: Text(
            '\$${amount.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: isBold ? 22 : 15,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: isBold ? const Color(0xFF1E3A8A) : const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  /// Motor de Generación de JSON para CFDI 4.0
  Map<String, dynamic> _generateInvoiceJSON() {
    final ticket = _selectedTicket;
    if (ticket == null) return {};

    final totalText = ticket['total_amount'] ?? 0.0;
    final total = totalText is num ? totalText.toDouble() : double.tryParse(totalText.toString()) ?? 0.0;
    final subtotal = total / 1.16;
    final iva = total - subtotal;
    final folio = ticket['id']?.substring(0, 5).toUpperCase() ?? '100';

    final rfcReceptor = _currentRFC.isNotEmpty ? _currentRFC : "XAXX010101000";

    final jsonPayload = <String, dynamic>{
      "version_cfdi": "4.0",
      "validacion_local": "NO",
      "PAC": {
        "usuario": CFDIConfig.pacUser.isNotEmpty ? CFDIConfig.pacUser : "DEMO700101XXX",
        "pass": CFDIConfig.pacPass.isNotEmpty ? CFDIConfig.pacPass : "DEMO700101XXX",
        "produccion": CFDIConfig.isProduccion ? "SI" : "NO"
      },
      "conf": {
        "cer": CFDIConfig.cerBase64.isNotEmpty ? CFDIConfig.cerBase64 : "MIIFsD...",
        "key": CFDIConfig.keyBase64.isNotEmpty ? CFDIConfig.keyBase64 : "MIIFDj...",
        "pass": CFDIConfig.keyPass.isNotEmpty ? CFDIConfig.keyPass : "12345678a"
      },
      "factura": {
        "condicionesDePago": "CONTADO",
        "fecha_expedicion": "AUTO",
        "folio": folio,
        "forma_pago": _selectedFormaPago,
        "LugarExpedicion": CFDIConfig.lugarExpedicion.isNotEmpty ? CFDIConfig.lugarExpedicion : "45079",
        "metodo_pago": _selectedMetodoPago,
        "moneda": "MXN",
        "serie": "A",
        "subtotal": double.parse(subtotal.toStringAsFixed(2)),
        "tipocambio": 1,
        "tipocomprobante": "I",
        "total": double.parse(total.toStringAsFixed(2)),
        "Exportacion": "01"
      },
      "emisor": {
        "rfc": CFDIConfig.emisorRFC.isNotEmpty ? CFDIConfig.emisorRFC : "EKU9003173C9",
        "nombre": CFDIConfig.emisorNombre.isNotEmpty ? CFDIConfig.emisorNombre : "ESCUELA KEMPER URGATE",
        "RegimenFiscal": CFDIConfig.emisorRegimen.isNotEmpty ? CFDIConfig.emisorRegimen : "601"
      },
      "receptor": {
        "rfc": rfcReceptor,
        "nombre": _selectedClient.isNotEmpty ? _selectedClient : "PUBLICO EN GENERAL",
        "UsoCFDI": _selectedUsoCFDI,
        "DomicilioFiscalReceptor": "45079",
        "RegimenFiscalReceptor": _selectedRegimen
      },
    };

    if (rfcReceptor == "XAXX010101000") {
      jsonPayload["InformacionGlobal"] = {
        "Periodicidad": "02",
        "Meses": DateTime.now().month.toString().padLeft(2, '0'),
        "Año": DateTime.now().year.toString()
      };
    }

    jsonPayload["conceptos"] = [
      {
        "cantidad": 1,
        "unidad": "Unidad de servicio",
        "ID": "999999",
        "descripcion": "CONSUMO DE ALIMENTOS",
        "valorunitario": double.parse(subtotal.toStringAsFixed(2)),
        "importe": double.parse(subtotal.toStringAsFixed(2)),
        "ClaveProdServ": "90101501",
        "ClaveUnidad": "E48",
        "ObjetoImp": "02",
        "Impuestos": {
          "Traslados": [
            {
              "Base": double.parse(subtotal.toStringAsFixed(2)),
              "Impuesto": "002",
              "TipoFactor": "Tasa",
              "TasaOCuota": "0.160000",
              "Importe": double.parse(iva.toStringAsFixed(2))
            }
          ]
        }
      }
    ];

    jsonPayload["impuestos"] = {
      "TotalImpuestosTrasladados": double.parse(iva.toStringAsFixed(2)),
      "translados": [
        {
          "Base": double.parse(subtotal.toStringAsFixed(2)),
          "impuesto": "002",
          "tasa": "0.160000",
          "importe": double.parse(iva.toStringAsFixed(2)),
          "TipoFactor": "Tasa"
        }
      ]
    };

    return jsonPayload;
  }

  /// Proceso de Timbrado Real (Simulado con Vista Previa)
  void _timbrarFactura() {
    final payload = _generateInvoiceJSON();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.security, color: Colors.indigo),
            const SizedBox(width: 12),
            const Text('TIMBRAR E IMPRIMIR CFDI 4.0'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se enviarán los datos al SAT a través del PAC autorizado.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('VISTA PREVIA DEL PAYLOAD JSON:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    const JsonEncoder.withIndent('  ').convert(payload),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Al proceder, se simulará el timbrado e inmediatamente se generará el PDF de la factura.',
                style: TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CONEXIÓN EXITOSA CON PAC. GENERANDO PDF...'),
                  backgroundColor: Colors.indigo,
                ),
              );
              // Proceder con la generación del PDF
              await _printInvoice();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('SI, TIMBRAR E IMPRIMIR'),
          ),
        ],
      ),
    );
  }
}
