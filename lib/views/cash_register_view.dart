import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../globals.dart';

class CashRegisterView extends StatefulWidget {
  const CashRegisterView({super.key});

  @override
  State<CashRegisterView> createState() => _CashRegisterViewState();
}

class _CashRegisterViewState extends State<CashRegisterView> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _tableError;
  List<Map<String, dynamic>> _movements = [];
  
  // Variables para agregar un nuevo movimiento
  String _selectedType = 'salida';
  String _selectedCategory = 'prestamo';
  String _selectedPaymentMethod = 'EFECTIVO';
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedRecipient = 'N/A';

  final List<String> _recipientOptions = ['N/A', 'Mesero', 'Cajera', 'Cocina', 'Barra de Alimentos', 'Barra de Bebidas', 'Barra de Postres'];

  final List<String> _incomeCategories = ['apertura', 'retardo', 'aporte', 'otro'];
  final List<String> _expenseCategories = ['prestamo', 'gasto', 'propina', 'vacaciones', 'corte', 'otro'];

  List<Map<String, dynamic>> _closings = [];

  // Meseros de la sucursal — para atribuir cada propina a quien le pertenece.
  List<Map<String, dynamic>> _waiters = [];

  @override
  void initState() {
    super.initState();
    _fetchMovements();
    _fetchClosings();
    _fetchWaitersForTips();
  }

  Future<void> _fetchWaitersForTips() async {
    try {
      final response = await _supabase
          .from('waiters')
          .select('id, name')
          .eq('branch_name', Globals.currentBranch)
          .order('name', ascending: true);
      if (mounted) {
        setState(() => _waiters = List<Map<String, dynamic>>.from(response));
      }
    } catch (_) {
      // Si la tabla de meseros no está disponible, el diálogo de propinas
      // sigue funcionando con recipient genérico 'Mesero'.
    }
  }

  Future<void> _fetchClosings() async {
    try {
      final response = await _supabase
          .from('cash_closings')
          .select()
          .eq('branch_name', Globals.currentBranch)
          .order('closed_at', ascending: false)
          .limit(10);
      if (mounted) {
        setState(() => _closings = List<Map<String, dynamic>>.from(response));
      }
    } catch (_) {
      // Tabla nueva — si aún no existe la migración, simplemente no mostramos historial.
    }
  }

  /// Calcula cuánto efectivo debería haber en caja HOY: fondo inicial
  /// (apertura) + ventas cobradas en efectivo (incluye la parte en
  /// efectivo de pagos mixtos) + entradas extra − salidas/gastos, todo
  /// filtrado a partir de la medianoche de hoy.
  Future<Map<String, double>> _computeExpectedCash() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    double fondoInicial = 0, entradas = 0, salidas = 0;
    for (final m in _movements) {
      final createdAt = DateTime.tryParse(m['created_at']?.toString() ?? '');
      if (createdAt == null || createdAt.isBefore(startOfDay)) continue;
      final amt = double.tryParse(m['amount']?.toString() ?? '0') ?? 0.0;
      if (m['payment_method'] != 'EFECTIVO') continue;
      if (m['category'] == 'apertura') {
        fondoInicial += amt;
      } else if (m['type'] == 'entrada') {
        entradas += amt;
      } else if (m['type'] == 'salida') {
        salidas += amt;
      }
    }

    double efectivoVentas = 0;
    double tarjetaVentas = 0;
    try {
      final orders = await _supabase
          .from('orders')
          .select('total_amount, payment_method, amount_cash, amount_card')
          .eq('branch_name', Globals.currentBranch)
          .eq('status', 'completed')
          .gte('created_at', startOfDay.toIso8601String());
      for (final o in (orders as List)) {
        final pm = (o['payment_method']?.toString() ?? '').toLowerCase();
        final total = double.tryParse(o['total_amount']?.toString() ?? '0') ?? 0.0;
        if (pm.contains('mixed') || o['amount_cash'] != null || o['amount_card'] != null) {
          efectivoVentas += double.tryParse(o['amount_cash']?.toString() ?? '0') ?? 0.0;
          tarjetaVentas += double.tryParse(o['amount_card']?.toString() ?? '0') ?? 0.0;
        } else if (pm.contains('cash') || pm.contains('efectivo')) {
          efectivoVentas += total;
        } else {
          tarjetaVentas += total;
        }
      }
    } catch (_) {}

    final expected = fondoInicial + efectivoVentas + entradas - salidas;
    return {
      'fondoInicial': fondoInicial,
      'efectivoVentas': efectivoVentas,
      'tarjetaVentas': tarjetaVentas,
      'entradas': entradas,
      'salidas': salidas,
      'expected': expected,
    };
  }

  /// El Cierre de Caja también cierra el día: marca las órdenes
  /// pending/ready como completadas y libera todas las mesas de la
  /// sucursal (antes esto era un botón "Cerrar Día" aparte). Por eso pide
  /// PIN Maestro — es una acción que no se puede deshacer.
  Future<void> _showCierreCajaDialog() async {
    final breakdown = await _computeExpectedCash();
    final expected = breakdown['expected']!;
    final countedController = TextEditingController();
    final notesController = TextEditingController();
    final pinController = TextEditingController();

    int pendingCount = 0;
    try {
      final res = await _supabase
          .from('orders')
          .select('id')
          .eq('branch_name', Globals.currentBranch)
          .inFilter('status', ['pending', 'ready']);
      pendingCount = (res as List).length;
    } catch (_) {}

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final counted = double.tryParse(countedController.text.trim());
          final difference = counted != null ? counted - expected : null;

          return AlertDialog(
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Row(
              children: [
                Icon(Icons.point_of_sale, color: Color(0xFFFF6D00)),
                SizedBox(width: 8),
                Text('Cierre de Caja',
                    style: TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5DCC4).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SEGÚN EL SISTEMA',
                            style: TextStyle(color: Color(0xFFA08F70), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                        const SizedBox(height: 6),
                        Text('Fondo inicial: \$${breakdown['fondoInicial']!.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF3D2E1A))),
                        Text('Ventas en efectivo: \$${breakdown['efectivoVentas']!.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF3D2E1A))),
                        Text('Ventas en tarjeta: \$${breakdown['tarjetaVentas']!.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF3D2E1A))),
                        if (breakdown['entradas']! > 0)
                          Text('Entradas extra: \$${breakdown['entradas']!.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFF3D2E1A))),
                        if (breakdown['salidas']! > 0)
                          Text('Salidas/gastos: -\$${breakdown['salidas']!.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFF3D2E1A))),
                        const Divider(color: Color(0xFFA08F70)),
                        Text('Efectivo esperado: \$${expected.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: countedController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    onChanged: (_) => setDlgState(() {}),
                    style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Efectivo real contado',
                      prefixText: '\$ ',
                      prefixIcon: Icon(Icons.calculate, color: Color(0xFFFF6D00)),
                    ),
                  ),
                  if (difference != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (difference == 0 ? Colors.green : (difference < 0 ? Colors.red : Colors.blue)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        difference == 0
                            ? '✓ Coincide exactamente'
                            : difference < 0
                                ? 'Falta \$${(-difference).toStringAsFixed(2)}'
                                : 'Sobra \$${difference.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: difference == 0 ? Colors.green : (difference < 0 ? Colors.red : Colors.blue),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      prefixIcon: Icon(Icons.note, color: Color(0xFFA08F70)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Esto también CIERRA EL DÍA: se marcarán $pendingCount orden(es) '
                      'pendiente(s) como completadas y se liberarán todas las mesas. '
                      'No se puede deshacer.',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'PIN Maestro',
                      prefixIcon: Icon(Icons.lock, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
              ),
              ElevatedButton.icon(
                onPressed: counted == null
                    ? null
                    : () async {
                        try {
                          final pinRes = await _supabase
                              .from('admin_settings')
                              .select('setting_value')
                              .eq('setting_key', 'master_pin')
                              .maybeSingle();
                          final correctPin = (pinRes != null && pinRes['setting_value'] != null)
                              ? pinRes['setting_value'] as String
                              : '1234';
                          if (pinController.text != correctPin) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                                content: Text('PIN Incorrecto'),
                                backgroundColor: Colors.red,
                              ));
                            }
                            return;
                          }

                          await _supabase.from('cash_closings').insert({
                            'branch_name': Globals.currentBranch,
                            'expected_cash': expected,
                            'counted_cash': counted,
                            'difference': difference,
                            'registered_by': Globals.currentUser,
                            'notes': notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
                          });

                          // Cierra el día: completa pendientes + libera mesas.
                          await _supabase
                              .from('orders')
                              .update({'status': 'completed'})
                              .eq('branch_name', Globals.currentBranch)
                              .inFilter('status', ['pending', 'ready']);
                          await _supabase
                              .from('restaurant_tables')
                              .update({'status': 'available'})
                              .eq('branch_name', Globals.currentBranch);

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text((difference == 0
                                      ? 'Cierre registrado — coincide exactamente'
                                      : 'Cierre registrado — diferencia de \$${difference!.abs().toStringAsFixed(2)}') +
                                  ' · Día cerrado ($pendingCount orden(es) + mesas liberadas)'),
                              backgroundColor: difference == 0 ? Colors.green : Colors.orange,
                              duration: const Duration(seconds: 4),
                            ));
                            _fetchClosings();
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        }
                      },
                icon: const Icon(Icons.check),
                label: const Text('Registrar Cierre'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _fetchMovements() async {
    setState(() {
      _isLoading = true;
      _tableError = null;
    });
    try {
      final response = await _supabase
          .from('cash_movements')
          .select()
          .eq('branch_name', Globals.currentBranch)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _movements = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        final isTableMissing = errorMsg.contains('42P01') ||
            errorMsg.contains('relation') ||
            errorMsg.contains('does not exist') ||
            errorMsg.contains('cash_movements');
        setState(() {
          _isLoading = false;
          _tableError = isTableMissing
              ? 'La tabla "cash_movements" no existe en Supabase.\n\n'
                'Ejecuta el script SQL para crearla y vuelve a intentarlo.'
              : 'Error al cargar movimientos: $errorMsg';
        });
      }
    }
  }

  Future<void> _addMovement() async {
    if (_amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un monto')));
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido')));
       return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.from('cash_movements').insert({
        'type': _selectedType,
        'category': _selectedCategory,
        'amount': amount,
        'payment_method': _selectedPaymentMethod,
        'description': _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : 'Sin descripción',
        'branch_name': Globals.currentBranch,
        'registered_by': Globals.currentUser,
        'recipient': _selectedRecipient,
      });

      _amountController.clear();
      _descriptionController.clear();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movimiento registrado con éxito'), backgroundColor: Colors.green));
        _fetchMovements();
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        final isTableMissing = errorMsg.contains('42P01') ||
            errorMsg.contains('relation') ||
            errorMsg.contains('does not exist') ||
            errorMsg.contains('cash_movements');
        setState(() {
          _isLoading = false;
          _tableError = isTableMissing
              ? 'La tabla "cash_movements" no existe en Supabase.\n\n'
                'Ejecuta el script SQL para crearla y vuelve a intentarlo.'
              : 'Error al guardar movimiento: $errorMsg';
        });
      }
    }
  }

  /// Diálogo simple para registrar el FONDO INICIAL de la caja (dinero
  /// con el que se abre el día). Se guarda como movimiento tipo 'entrada'
  /// con categoría 'apertura' y método EFECTIVO.
  void _showAperturaCajaDialog() {
    _amountController.clear();
    _descriptionController.text = 'Fondo inicial de caja';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Row(
          children: [
            Icon(Icons.savings, color: Colors.green),
            SizedBox(width: 8),
            Text('Apertura de Caja',
                style: TextStyle(
                    color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Ingresa el monto de efectivo con el que INICIA la caja hoy '
                '(fondo inicial / caja chica).',
                style: TextStyle(color: Color(0xFF7A6E5A), fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Monto en efectivo',
                prefixText: '\$ ',
                prefixIcon: Icon(Icons.attach_money, color: Colors.green),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.black),
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                prefixIcon: Icon(Icons.note, color: Color(0xFFA08F70)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFFA08F70))),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final amount = double.tryParse(_amountController.text.trim());
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
                  'description': _descriptionController.text.trim().isNotEmpty
                      ? _descriptionController.text.trim()
                      : 'Fondo inicial de caja',
                  'branch_name': Globals.currentBranch,
                  'registered_by': Globals.currentUser,
                  'recipient': 'N/A',
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Caja abierta con \$${amount.toStringAsFixed(2)} de fondo inicial'),
                    backgroundColor: Colors.green,
                  ));
                  _fetchMovements();
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

  /// Diálogo rápido para reportar el total de PROPINAS del día, separado
  /// por medio de pago (efectivo y tarjeta). Registra hasta dos movimientos
  /// tipo 'salida' / categoría 'propina' — uno por cada monto distinto de
  /// cero — para que queden reflejados en el historial y en la nómina.
  Future<void> _showReportarPropinasDialog() async {
    final efectivoController = TextEditingController();
    final tarjetaController = TextEditingController();
    final notesController = TextEditingController();
    String? selectedWaiterId = 'none';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final efectivo = double.tryParse(efectivoController.text.trim()) ?? 0;
          final tarjeta = double.tryParse(tarjetaController.text.trim()) ?? 0;
          final total = efectivo + tarjeta;
          final selectedWaiter = (selectedWaiterId != null && selectedWaiterId != 'none')
              ? _waiters.firstWhere(
                  (w) => w['id'] == selectedWaiterId,
                  orElse: () => <String, dynamic>{},
                )
              : <String, dynamic>{};
          final recipientName = (selectedWaiter['name'] as String?) ?? 'Todos';

          return AlertDialog(
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Row(
              children: [
                Icon(Icons.volunteer_activism, color: Colors.teal),
                SizedBox(width: 8),
                Text('Reportar Propinas del Día',
                    style: TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Captura el total de propinas recibidas hoy, separado por medio de pago.',
                    style: TextStyle(color: Color(0xFF7A6E5A), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedWaiterId,
                    dropdownColor: const Color(0xFFFAF1DE),
                    style: const TextStyle(color: Color(0xFF3D2E1A)),
                    decoration: InputDecoration(
                      labelText: '¿Para quién es la propina?',
                      labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                      prefixIcon: const Icon(Icons.person, color: Color(0xFFA08F70)),
                      filled: true,
                      fillColor: const Color(0xFFFAF1DE),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      const DropdownMenuItem(value: 'none', child: Text('Todos (propina compartida)')),
                      ..._waiters.map((w) => DropdownMenuItem<String>(
                            value: w['id'] as String,
                            child: Text(w['name'] as String),
                          )),
                    ],
                    onChanged: (val) => setDlgState(() => selectedWaiterId = val),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: efectivoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    onChanged: (_) => setDlgState(() {}),
                    style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Propina en Efectivo',
                      prefixText: '\$ ',
                      prefixIcon: Icon(Icons.payments, color: Colors.green),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tarjetaController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setDlgState(() {}),
                    style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Propina en Tarjeta',
                      prefixText: '\$ ',
                      prefixIcon: Icon(Icons.credit_card, color: Colors.blueAccent),
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Total del día: \$${total.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      prefixIcon: Icon(Icons.note, color: Color(0xFFA08F70)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
              ),
              ElevatedButton.icon(
                onPressed: total <= 0
                    ? null
                    : () async {
                        try {
                          final notes = notesController.text.trim();
                          if (efectivo > 0) {
                            await _supabase.from('cash_movements').insert({
                              'type': 'salida',
                              'category': 'propina',
                              'amount': efectivo,
                              'payment_method': 'EFECTIVO',
                              'description': notes.isNotEmpty ? 'Propinas del día (efectivo) - $notes' : 'Propinas del día (efectivo)',
                              'branch_name': Globals.currentBranch,
                              'registered_by': Globals.currentUser,
                              'recipient': recipientName,
                            });
                          }
                          if (tarjeta > 0) {
                            await _supabase.from('cash_movements').insert({
                              'type': 'salida',
                              'category': 'propina',
                              'amount': tarjeta,
                              'payment_method': 'TARJETA',
                              'description': notes.isNotEmpty ? 'Propinas del día (tarjeta) - $notes' : 'Propinas del día (tarjeta)',
                              'branch_name': Globals.currentBranch,
                              'registered_by': Globals.currentUser,
                              'recipient': recipientName,
                            });
                          }

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Propinas registradas para $recipientName: \$${total.toStringAsFixed(2)}'),
                              backgroundColor: Colors.teal,
                            ));
                            _fetchMovements();
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        }
                      },
                icon: const Icon(Icons.check),
                label: const Text('Registrar Propinas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Reporte de propinas de UN DÍA, agrupado por mesero — responde a
  /// "cuánto se sacó de propina hoy y para quién es". Lee los movimientos
  /// de cash_movements con categoría 'propina' del día seleccionado y los
  /// agrupa por 'recipient' (mesero asignado al reportar la propina).
  Future<void> _showTipsReportDialog() async {
    DateTime selectedDate = DateTime.now();
    String mode = 'dia'; // 'dia' = un día específico, 'historial' = últimos 30 días

    Future<List<Map<String, dynamic>>> fetchTipsRange(DateTime start, DateTime endExclusive) async {
      try {
        final response = await _supabase
            .from('cash_movements')
            .select()
            .eq('branch_name', Globals.currentBranch)
            .eq('category', 'propina')
            .gte('created_at', start.toIso8601String())
            .lt('created_at', endExclusive.toIso8601String())
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(response);
      } catch (_) {
        return [];
      }
    }

    Future<List<Map<String, dynamic>>> fetchTips(DateTime date) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      return fetchTipsRange(startOfDay, startOfDay.add(const Duration(days: 1)));
    }

    Future<List<Map<String, dynamic>>> fetchTipsHistory() {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final start = today.subtract(const Duration(days: 29));
      return fetchTipsRange(start, today.add(const Duration(days: 1)));
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('$mode-${selectedDate.toIso8601String()}'),
            future: mode == 'dia' ? fetchTips(selectedDate) : fetchTipsHistory(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? [];

              // Agrupa por mesero (recipient) sumando efectivo y tarjeta.
              final Map<String, Map<String, double>> byWaiter = {};
              double totalEfectivo = 0, totalTarjeta = 0;
              for (final r in rows) {
                final rawName = (r['recipient'] as String?)?.trim();
                final key = (rawName == null || rawName.isEmpty || rawName == 'N/A')
                    ? 'Sin asignar'
                    : rawName;
                final amt = double.tryParse(r['amount']?.toString() ?? '0') ?? 0.0;
                final pm = r['payment_method']?.toString() ?? 'EFECTIVO';
                byWaiter.putIfAbsent(key, () => {'efectivo': 0.0, 'tarjeta': 0.0});
                if (pm == 'TARJETA') {
                  byWaiter[key]!['tarjeta'] = byWaiter[key]!['tarjeta']! + amt;
                  totalTarjeta += amt;
                } else {
                  byWaiter[key]!['efectivo'] = byWaiter[key]!['efectivo']! + amt;
                  totalEfectivo += amt;
                }
              }
              final total = totalEfectivo + totalTarjeta;
              final entries = byWaiter.entries.toList()
                ..sort((a, b) => (b.value['efectivo']! + b.value['tarjeta']!)
                    .compareTo(a.value['efectivo']! + a.value['tarjeta']!));

              // Agrupa por día (para el modo Historial) — últimos 30 días.
              final Map<String, Map<String, double>> byDay = {};
              for (final r in rows) {
                final createdAt = DateTime.tryParse(r['created_at']?.toString() ?? '');
                if (createdAt == null) continue;
                final local = createdAt.toLocal();
                final key = DateFormat('dd/MM/yyyy').format(local);
                final amt = double.tryParse(r['amount']?.toString() ?? '0') ?? 0.0;
                final pm = r['payment_method']?.toString() ?? 'EFECTIVO';
                byDay.putIfAbsent(key, () => {'efectivo': 0.0, 'tarjeta': 0.0, 'sortKey': local.millisecondsSinceEpoch.toDouble()});
                if (pm == 'TARJETA') {
                  byDay[key]!['tarjeta'] = byDay[key]!['tarjeta']! + amt;
                } else {
                  byDay[key]!['efectivo'] = byDay[key]!['efectivo']! + amt;
                }
              }
              final dayEntries = byDay.entries.toList()
                ..sort((a, b) => b.value['sortKey']!.compareTo(a.value['sortKey']!));

              return AlertDialog(
                backgroundColor: const Color(0xFFFAF1DE),
                title: const Row(
                  children: [
                    Icon(Icons.summarize, color: Colors.teal),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Reporte de Propinas',
                          style: TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildTipsModeTab(
                                  'Un Día', mode == 'dia', () => setDlgState(() => mode = 'dia')),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTipsModeTab(
                                  'Historial (30 días)', mode == 'historial', () => setDlgState(() => mode = 'historial')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (mode == 'dia')
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDlgState(() => selectedDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5DCC4).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(DateFormat('dd/MM/yyyy').format(selectedDate),
                                    style: const TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
                                const Icon(Icons.calendar_month, color: Color(0xFFFF6D00)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                  mode == 'dia'
                                      ? 'No se registraron propinas este día.'
                                      : 'No se registraron propinas en los últimos 30 días.',
                                  style: const TextStyle(color: Color(0xFFA08F70))),
                            ),
                          )
                        else if (mode == 'dia') ...[
                          // Lo principal: cuánto se debe en total, por medio de pago.
                          // Las propinas son compartidas entre todo el personal, así
                          // que esto es lo que hay que repartir hoy.
                          Row(
                            children: [
                              Expanded(
                                child: _buildTipTotalCard(
                                    'Debido en Efectivo', totalEfectivo, Icons.payments, Colors.green),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildTipTotalCard(
                                    'Debido en Tarjeta', totalTarjeta, Icons.credit_card, Colors.blueAccent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL DEL DÍA',
                                    style: TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
                                Text('\$${total.toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 18)),
                              ],
                            ),
                          ),
                          if (entries.length > 1 || entries.first.key != 'Todos') ...[
                            const SizedBox(height: 20),
                            const Text('Detalle por persona asignada',
                                style: TextStyle(color: Color(0xFFA08F70), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ...entries.map((e) {
                              final ef = e.value['efectivo']!;
                              final ta = e.value['tarjeta']!;
                              final tot = ef + ta;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE5DCC4)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.teal.withValues(alpha: 0.2),
                                      child: Text(
                                        e.key.isNotEmpty ? e.key[0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(e.key,
                                              style: const TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Efectivo: \$${ef.toStringAsFixed(2)}  ·  Tarjeta: \$${ta.toStringAsFixed(2)}',
                                            style: const TextStyle(color: Color(0xFFA08F70), fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text('\$${tot.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ] else ...[
                          // Historial: una fila por día con su efectivo/tarjeta/total.
                          ...dayEntries.map((e) {
                            final ef = e.value['efectivo']!;
                            final ta = e.value['tarjeta']!;
                            final tot = ef + ta;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE5DCC4)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.calendar_today, color: Colors.teal, size: 16),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(e.key,
                                            style: const TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Efectivo: \$${ef.toStringAsFixed(2)}  ·  Tarjeta: \$${ta.toStringAsFixed(2)}',
                                          style: const TextStyle(color: Color(0xFFA08F70), fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text('\$${tot.toStringAsFixed(2)}',
                                      style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            );
                          }),
                          const Divider(color: Color(0xFFA08F70)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TOTAL DEL PERIODO',
                                  style: TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold)),
                              Text('\$${total.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Efectivo: \$${totalEfectivo.toStringAsFixed(2)}  ·  Tarjeta: \$${totalTarjeta.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFFA08F70), fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar', style: TextStyle(color: Color(0xFFA08F70))),
                  ),
                  ElevatedButton.icon(
                    onPressed: rows.isEmpty
                        ? null
                        : () => mode == 'dia'
                            ? _exportTipsReportPdf(
                                selectedDate,
                                entries,
                                totalEfectivo,
                                totalTarjeta,
                                total,
                              )
                            : _exportTipsHistoryPdf(dayEntries, totalEfectivo, totalTarjeta, total),
                    icon: const Icon(Icons.print),
                    label: const Text('Exportar / Imprimir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Genera un PDF con el desglose de propinas por mesero del día
  /// seleccionado (para imprimir o compartir al momento de repartirlas).
  Future<void> _exportTipsReportPdf(
    DateTime date,
    List<MapEntry<String, Map<String, double>>> entries,
    double totalEfectivo,
    double totalTarjeta,
    double total,
  ) async {
    final pdf = pw.Document();
    final dateStr = DateFormat('dd/MM/yyyy').format(date);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Reporte de Propinas - ${Globals.currentBranch}',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Fecha: $dateStr', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Mesero', 'Efectivo', 'Tarjeta', 'Total'],
                data: entries.map((e) {
                  final ef = e.value['efectivo']!;
                  final ta = e.value['tarjeta']!;
                  final tot = ef + ta;
                  return [
                    e.key,
                    '\$${ef.toStringAsFixed(2)}',
                    '\$${ta.toStringAsFixed(2)}',
                    '\$${tot.toStringAsFixed(2)}',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Efectivo: \$${totalEfectivo.toStringAsFixed(2)}'),
                    pw.Text('Tarjeta: \$${totalTarjeta.toStringAsFixed(2)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('TOTAL DEL DÍA: \$${total.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Propinas_${Globals.currentBranch}_$dateStr.pdf',
    );
  }

  /// Genera un PDF con el historial de propinas (últimos 30 días),
  /// una fila por día con su efectivo/tarjeta/total.
  Future<void> _exportTipsHistoryPdf(
    List<MapEntry<String, Map<String, double>>> dayEntries,
    double totalEfectivo,
    double totalTarjeta,
    double total,
  ) async {
    final pdf = pw.Document();
    final now = DateTime.now();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Historial de Propinas - ${Globals.currentBranch}',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Últimos 30 días (al ${DateFormat('dd/MM/yyyy').format(now)})',
                      style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Fecha', 'Efectivo', 'Tarjeta', 'Total'],
                data: dayEntries.map((e) {
                  final ef = e.value['efectivo']!;
                  final ta = e.value['tarjeta']!;
                  final tot = ef + ta;
                  return [
                    e.key,
                    '\$${ef.toStringAsFixed(2)}',
                    '\$${ta.toStringAsFixed(2)}',
                    '\$${tot.toStringAsFixed(2)}',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Efectivo: \$${totalEfectivo.toStringAsFixed(2)}'),
                    pw.Text('Tarjeta: \$${totalTarjeta.toStringAsFixed(2)}'),
                    pw.SizedBox(height: 4),
                    pw.Text('TOTAL DEL PERIODO: \$${total.toStringAsFixed(2)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Propinas_Historial_${Globals.currentBranch}.pdf',
    );
  }

  void _showNewMovementDialog() {
    // Resetea controladores antes de mostrar
    _amountController.clear();
    _descriptionController.clear();
    _selectedType = 'salida';
    _selectedCategory = 'prestamo';
    _selectedPaymentMethod = 'EFECTIVO';
    _selectedRecipient = 'N/A';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<String> validCategories = _selectedType == 'entrada' ? _incomeCategories : _expenseCategories;
            if (!validCategories.contains(_selectedCategory)) {
              _selectedCategory = validCategories.first;
            }

            return AlertDialog(
              backgroundColor: const Color(0xFFFAF1DE),
              title: const Text('Registrar Movimiento de Caja', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tipo (Entrada / Salida)
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Salida', style: TextStyle(color: Color(0xFF3D2E1A))),
                            value: 'salida',
                            groupValue: _selectedType,
                            activeColor: Colors.redAccent,
                            onChanged: (val) {
                              setDialogState(() => _selectedType = val!);
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            title: const Text('Entrada', style: TextStyle(color: Color(0xFF3D2E1A))),
                            value: 'entrada',
                            groupValue: _selectedType,
                            activeColor: Colors.greenAccent,
                            onChanged: (val) {
                              setDialogState(() => _selectedType = val!);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Categoría
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      dropdownColor: const Color(0xFFFAF1DE),
                      style: const TextStyle(color: Color(0xFF3D2E1A)),
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                        filled: true,
                        fillColor: const Color(0xFFFAF1DE),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: validCategories.map((c) => DropdownMenuItem(value: c, child: Text(c.toUpperCase()))).toList(),
                      onChanged: (val) => setDialogState(() => _selectedCategory = val!),
                    ),
                    const SizedBox(height: 16),

                    // Destinatario / Área (Solo si es Salida)
                    if (_selectedType == 'salida') ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRecipient,
                        dropdownColor: const Color(0xFFFAF1DE),
                        style: const TextStyle(color: Color(0xFF3D2E1A)),
                        decoration: InputDecoration(
                          labelText: 'Dirigido a / Destinatario',
                          labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                          filled: true,
                          fillColor: const Color(0xFFFAF1DE),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _recipientOptions.map((c) => DropdownMenuItem(value: c, child: Text(c.toUpperCase()))).toList(),
                        onChanged: (val) => setDialogState(() => _selectedRecipient = val!),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Monto
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Color(0xFF3D2E1A)),
                      decoration: InputDecoration(
                        labelText: 'Monto (\$)',
                        labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                        prefixIcon: const Icon(Icons.attach_money, color: Color(0xFFA08F70)),
                        filled: true,
                        fillColor: const Color(0xFFFAF1DE),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Método de pago
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPaymentMethod,
                      dropdownColor: const Color(0xFFFAF1DE),
                      style: const TextStyle(color: Color(0xFF3D2E1A)),
                      decoration: InputDecoration(
                        labelText: 'Medio de Pago',
                        labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                        filled: true,
                        fillColor: const Color(0xFFFAF1DE),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: ['EFECTIVO', 'TARJETA', 'CLIP', 'TRANSFERENCIA']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) => setDialogState(() => _selectedPaymentMethod = val!),
                    ),
                    const SizedBox(height: 16),

                    // Descripción
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Color(0xFF3D2E1A)),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Concepto / Descripción detallada (opcional)',
                        labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                        filled: true,
                        fillColor: const Color(0xFFFAF1DE),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addMovement();
                  },
                  child: const Text('Guardar Movimiento', style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Calculo de totales de HOY según movimientos de salida/entrada en
    // EFECTIVO. Excluye 'apertura' de "Entradas Extra" — el fondo inicial
    // no es un ingreso adicional del día, se muestra aparte en el
    // historial y se usa en el Cierre de Caja.
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    double entradasEfectivo = 0;
    double salidasEfectivo = 0;
    double prestamosHoy = 0;
    double propinasEfectivoHoy = 0;
    double propinasTarjetaHoy = 0;

    for (var m in _movements) {
      final createdAt = DateTime.tryParse(m['created_at']?.toString() ?? '');
      if (createdAt == null || createdAt.isBefore(startOfDay)) continue;
      double amount = double.tryParse(m['amount'].toString()) ?? 0.0;
      if (m['type'] == 'entrada' && m['payment_method'] == 'EFECTIVO' && m['category'] != 'apertura') entradasEfectivo += amount;
      if (m['type'] == 'salida' && m['payment_method'] == 'EFECTIVO') salidasEfectivo += amount;
      if (m['category'] == 'prestamo') prestamosHoy += amount;
      if (m['category'] == 'propina' && m['payment_method'] == 'EFECTIVO') propinasEfectivoHoy += amount;
      if (m['category'] == 'propina' && m['payment_method'] == 'TARJETA') propinasTarjetaHoy += amount;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAF1DE),
      appBar: AppBar(
        title: const Text('Cortes y Movimientos de Caja', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF6D00))),
        backgroundColor: const Color(0xFFFAF1DE),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFFAF1DE)),
        actions: [
          // Botón dedicado para registrar el fondo inicial de la caja
          // (cash de arranque del día). Abre el mismo diálogo pero pre-configurado
          // como entrada de tipo 'apertura'.
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: _showAperturaCajaDialog,
              icon: const Icon(Icons.savings, color: Colors.white),
              label: const Text('Apertura de Caja', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: _showTipsReportDialog,
              icon: const Icon(Icons.summarize, color: Colors.teal),
              label: const Text('Reporte de Propinas', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFAF1DE),
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: _showCierreCajaDialog,
              icon: const Icon(Icons.point_of_sale, color: Colors.white),
              label: const Text('Cierre de Caja', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: _showNewMovementDialog,
              icon: const Icon(Icons.add, color: Color(0xFFFAF1DE)),
              label: const Text('Nuevo Movimiento', style: TextStyle(color: Color(0xFFFAF1DE), fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _tableError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      _tableError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF7A6E5A), fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _fetchMovements,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)),
                    ),
                  ],
                ),
              ),
            )
          : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tarjetas resumen superrápidas
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildSummaryCard('Entradas Extra\n(Efectivo)', '+\$${entradasEfectivo.toStringAsFixed(2)}', Colors.greenAccent, isMobile),
                    _buildSummaryCard('Salidas / Gastos\n(Efectivo)', '-\$${salidasEfectivo.toStringAsFixed(2)}', Colors.redAccent, isMobile),
                    _buildSummaryCard('Préstamos \nEntregados Hoy', '\$${prestamosHoy.toStringAsFixed(2)}', Colors.orangeAccent, isMobile),
                    _buildSummaryCard('Propinas Hoy\n(Efectivo)', '\$${propinasEfectivoHoy.toStringAsFixed(2)}', Colors.teal, isMobile),
                    _buildSummaryCard('Propinas Hoy\n(Tarjeta)', '\$${propinasTarjetaHoy.toStringAsFixed(2)}', Colors.teal, isMobile),
                  ],
                ),
                if (_closings.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Últimos Cierres de Caja', style: TextStyle(color: Color(0xFF3D2E1A), fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _closings.map((c) {
                      final diff = double.tryParse(c['difference']?.toString() ?? '0') ?? 0.0;
                      final color = diff == 0 ? Colors.green : (diff < 0 ? Colors.red : Colors.blue);
                      final dateStr = c['closed_at'] != null
                          ? DateTime.parse(c['closed_at']).toLocal().toString().substring(0, 16)
                          : '';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateStr, style: const TextStyle(color: Color(0xFFA08F70), fontSize: 11)),
                            Text(
                              diff == 0 ? 'Coincide' : (diff < 0 ? 'Falta \$${(-diff).toStringAsFixed(2)}' : 'Sobra \$${diff.toStringAsFixed(2)}'),
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 24),
                const Text('Historial de Movimientos de Caja', style: TextStyle(color: Color(0xFF3D2E1A), fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Lista de movimientos
                Expanded(
                  child: _movements.isEmpty 
                    ? const Center(child: Text('No hay movimientos registrados.', style: TextStyle(color: Color(0xFFA08F70), fontSize: 16)))
                    : ListView.separated(
                        itemCount: _movements.length,
                        separatorBuilder: (_,_) => const Divider(color: Color(0xFFE5DCC4)),
                        itemBuilder: (context, index) {
                          final movement = _movements[index];
                          final isEntrada = movement['type'] == 'entrada';
                          final dateStr = movement['created_at'] != null ? DateTime.parse(movement['created_at']).toLocal().toString().substring(0, 16) : '';
                          final amount = double.tryParse(movement['amount']?.toString() ?? '0') ?? 0.0;
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isEntrada ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                              child: Icon(
                                isEntrada ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isEntrada ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                            title: Text(
                              '${movement['category'].toString().toUpperCase()} - ${movement['payment_method']}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF6D00)),
                            ),
                            subtitle: Text(
                              '$dateStr\n${(movement['recipient'] != null && movement['recipient'] != 'N/A') ? 'Destinatario: ${movement['recipient']} - ' : ''}${movement['description'] ?? 'Sin descripción'}',
                              style: const TextStyle(color: Color(0xFF7A6E5A)),
                            ),
                            trailing: Text(
                              '${isEntrada ? '+' : '-'}\$${amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isEntrada ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                          );
                        },
                      ),
                )
              ],
            ),
          ),
    );
  }

  /// Botón tipo pestaña para alternar entre "Un Día" e "Historial" dentro
  /// del Reporte de Propinas.
  Widget _buildTipsModeTab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.teal : const Color(0xFFFAF1DE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.teal : const Color(0xFFE5DCC4)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFA08F70),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// Tarjeta compacta para el Reporte de Propinas — resalta cuánto se debe
  /// por medio de pago (efectivo o tarjeta).
  Widget _buildTipTotalCard(String title, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: const TextStyle(color: Color(0xFF7A6E5A), fontSize: 11, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('\$${amount.toStringAsFixed(2)}',
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color accentColor, bool isMobile) {
    return Container(
      width: isMobile ? (MediaQuery.of(context).size.width - 64) / 1 : 250, // Adaptive width
      constraints: BoxConstraints(minWidth: isMobile ? 150 : 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DCC4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF7A6E5A), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: accentColor, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
