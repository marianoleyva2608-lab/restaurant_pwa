import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../globals.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PayrollView extends StatefulWidget {
  const PayrollView({super.key});

  @override
  State<PayrollView> createState() => _PayrollViewState();
}

class _PayrollViewState extends State<PayrollView> {
  final _supabase = Supabase.instance.client;
  String? _selectedWaiterId;
  String? _selectedWaiterName;
  bool _isLoadingLedger = false;
  List<Map<String, dynamic>> _ledger = [];
  double _balance = 0.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Row(
            children: [
              _buildWaiterList(),
              const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF334155)),
              Expanded(
                child: _selectedWaiterId == null
                    ? _buildEmptyState()
                    : _buildLedgerView(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet, color: Color(0xFFFF6D00), size: 32),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nómina y Pagos',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                'Gestión de sueldos, préstamos y propinas para meseros',
                style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const Spacer(),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showWeeklyReportDialog(),
            icon: const Icon(Icons.print),
            label: const Text('Reporte Semanal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              side: const BorderSide(color: Color(0xFF334155)),
            ),
          ),
          const SizedBox(width: 8),
          if (_selectedWaiterId != null)
            ElevatedButton.icon(
              onPressed: () => _showMovementDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo Movimiento'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWaiterList() {
    return Container(
      width: 300,
      color: const Color(0xFF0F172A),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('waiters').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch).order('name', ascending: true),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final waiters = snapshot.data!;

          if (waiters.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No hay meseros registrados', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
              ),
            );
          }

          return ListView.builder(
            itemCount: waiters.length,
            itemBuilder: (context, index) {
              final waiter = waiters[index];
              final isSelected = _selectedWaiterId == waiter['id'];

              return ListTile(
                selected: isSelected,
                selectedTileColor: const Color(0xFFFF6D00).withValues(alpha: 0.1),
                leading: CircleAvatar(
                  backgroundColor: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF334155),
                  child: Text(waiter['name'][0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                title: Text(waiter['name'], style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF94A3B8), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                onTap: () {
                  setState(() {
                    _selectedWaiterId = waiter['id'];
                    _selectedWaiterName = waiter['name'];
                  });
                  _fetchLedger();
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search, size: 64, color: Color(0xFF334155)),
          SizedBox(height: 16),
          Text(
            'Selecciona un mesero para ver su historial',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchLedger() async {
    if (_selectedWaiterId == null) return;
    setState(() => _isLoadingLedger = true);

    try {
      final response = await _supabase
          .from('waiter_ledger')
          .select()
          .eq('waiter_id', _selectedWaiterId as Object)
          .eq('branch_name', Globals.currentBranch)
          .order('created_at', ascending: false);

      final data = List<Map<String, dynamic>>.from(response);
      
      // Cálculo del saldo pendiente:
      // Positivos (lo que el negocio le DEBE al mesero): salary, bonus, tip
      // Negativos (reducen lo que se le debe): payment (pago entregado), loan (préstamo), deduction (descuento)
      // Saldo > 0: el negocio le debe al mesero
      // Saldo < 0: el mesero le debe al negocio
      double bal = 0;
      for (var row in data) {
        final amt = (row['amount'] as num).toDouble();
        final type = row['type'];
        if (type == 'salary' || type == 'tip' || type == 'bonus') {
          bal += amt;
        } else if (type == 'payment' || type == 'loan' || type == 'deduction') {
          bal -= amt;
        }
      }

      if (mounted) {
        setState(() {
          _ledger = data;
          _balance = bal;
          _isLoadingLedger = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching ledger: $e');
      if (mounted) setState(() => _isLoadingLedger = false);
    }
  }

  Widget _buildLedgerView() {
    return Column(
      children: [
        _buildSummaryCards(),
        Expanded(
          child: _isLoadingLedger
              ? const Center(child: CircularProgressIndicator())
              : _ledger.isEmpty
                  ? const Center(child: Text('No hay movimientos registrados', style: TextStyle(color: Colors.white54)))
                  : _buildLedgerTable(),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          _buildCard(
            _balance > 0
                ? 'Saldo a Pagar al Mesero'
                : _balance < 0
                    ? 'Saldo que Debe el Mesero'
                    : 'Saldo Pendiente',
            '\$${_balance.abs().toStringAsFixed(2)}',
            _balance > 0 ? Colors.green : _balance < 0 ? Colors.red : Colors.grey,
            Icons.account_balance,
          ),
          const SizedBox(width: 24),
          _buildCard(
            'Último Movimiento',
            _ledger.isEmpty ? 'N/A' : DateFormat('dd MMM').format(DateTime.parse(_ledger.first['created_at'])),
            const Color(0xFFFF6D00),
            Icons.history,
          ),
          const SizedBox(width: 24),
          _buildCard(
            'Registros',
            '${_ledger.length} movimientos',
            Colors.blue,
            Icons.list_alt,
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerTable() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.separated(
        itemCount: _ledger.length,
        separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
        itemBuilder: (context, index) {
          final row = _ledger[index];
          final type = row['type'];
          final amount = (row['amount'] as num).toDouble();
          
          Color typeColor;
          IconData typeIcon;
          String typeLabel;

          // Tipos que suman al saldo a favor del mesero (positivos)
          final bool isPositive = type == 'salary' || type == 'tip' || type == 'bonus';
          // Tipos que restan del saldo (negativos): payment = pago entregado, loan = préstamo, deduction = descuento

          switch (type) {
            case 'salary':
              typeColor = Colors.blue;
              typeIcon = Icons.payments;
              typeLabel = 'Sueldo';
              break;
            case 'tip':
              typeColor = Colors.green;
              typeIcon = Icons.monetization_on;
              typeLabel = 'Propina';
              break;
            case 'bonus':
              typeColor = Colors.purple;
              typeIcon = Icons.star;
              typeLabel = 'Bono';
              break;
            case 'payment':
              // Pago que el negocio le entrega al mesero — reduce la deuda del negocio
              typeColor = Colors.orange;
              typeIcon = Icons.check_circle;
              typeLabel = 'Pago Entregado';
              break;
            case 'loan':
              // Préstamo al mesero — el mesero debe devolver este dinero
              typeColor = Colors.red;
              typeIcon = Icons.money_off;
              typeLabel = 'Préstamo';
              break;
            case 'deduction':
              // Descuento aplicado al mesero
              typeColor = Colors.deepOrange;
              typeIcon = Icons.remove_circle;
              typeLabel = 'Descuento';
              break;
            default:
              typeColor = Colors.grey;
              typeIcon = Icons.help;
              typeLabel = type.toString().toUpperCase();
          }

          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(typeIcon, color: typeColor, size: 20),
            ),
            title: Text(typeLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(row['created_at']))}${row['description'] != null ? ' - ${row['description']}' : ''}',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isPositive ? Colors.green[300] : Colors.red[300],
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isPositive ? Colors.green[300] : Colors.red[300],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showWeeklyReportDialog() async {
    DateTime selectedDate = DateTime.now();
    
    // Find Monday of selected week
    DateTime getMonday(DateTime date) => date.subtract(Duration(days: date.weekday - 1));
    DateTime startOfWeek = getMonday(selectedDate);
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String weekRange = '${DateFormat('dd/MM').format(startOfWeek)} al ${DateFormat('dd/MM/yyyy').format(endOfWeek)}';
            
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Row(
                children: [
                   const Icon(Icons.summarize, color: Color(0xFFFF6D00)),
                   const SizedBox(width: 12),
                   const Text('Reporte Semanal', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Seleccione la semana para generar el reporte:',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                          startOfWeek = getMonday(selectedDate);
                          endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(weekRange, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const Icon(Icons.calendar_month, color: Color(0xFFFF6D00)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                ElevatedButton.icon(
                  onPressed: () => _generateReport(startOfWeek, endOfWeek, false),
                  icon: const Icon(Icons.person),
                  label: const Text('Solo Mesero Actual'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _generateReport(startOfWeek, endOfWeek, true),
                  icon: const Icon(Icons.people),
                  label: const Text('Todos los Meseros'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _generateReport(DateTime start, DateTime end, bool allWaiters) async {
    // 1. Fetch data
    late List<Map<String, dynamic>> movements;
    late List<Map<String, dynamic>> waitersList;

    try {
      if (allWaiters) {
        final waitersRes = await _supabase.from('waiters').select();
        waitersList = List<Map<String, dynamic>>.from(waitersRes);
        
        final ledgerRes = await _supabase
            .from('waiter_ledger')
            .select()
            .gte('created_at', start.toIso8601String())
            .lte('created_at', end.toIso8601String())
            .eq('branch_name', Globals.currentBranch);
        movements = List<Map<String, dynamic>>.from(ledgerRes);
      } else {
        if (_selectedWaiterId == null) return;
        final waitersRes = await _supabase.from('waiters').select().eq('id', _selectedWaiterId as Object);
        waitersList = List<Map<String, dynamic>>.from(waitersRes);

        final ledgerRes = await _supabase
            .from('waiter_ledger')
            .select()
            .eq('waiter_id', _selectedWaiterId as Object)
            .gte('created_at', start.toIso8601String())
            .lte('created_at', end.toIso8601String())
            .eq('branch_name', Globals.currentBranch);
        movements = List<Map<String, dynamic>>.from(ledgerRes);
      }
    } catch (e) {
      debugPrint('Error generating report data: $e');
      return;
    }

    // 2. Build PDF
    final pdf = pw.Document();
    final weekText = '${DateFormat('dd/MM').format(start)} al ${DateFormat('dd/MM/yyyy').format(end)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Reporte de Nomina - ${Globals.currentBranch}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Semana: $weekText', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            
            ...waitersList.map((waiter) {
              final waiterMovements = movements.where((m) => m['waiter_id'] == waiter['id']).toList();
              if (waiterMovements.isEmpty && !allWaiters) {
                 return pw.Text('No hay movimientos en esta semana para ${waiter['name']}');
              }
              if (waiterMovements.isEmpty) return pw.SizedBox();

              // Resumen del período:
              // earned = salary + bonus + tip (lo que el negocio le debe al mesero)
              // paid   = payment (pagos ya entregados al mesero)
              // loans  = loan (préstamos al mesero)
              // deductions = deduction (descuentos)
              // saldo neto = earned - paid - loans - deductions
              double earned = 0;
              double paid = 0;
              double loans = 0;
              double deductions = 0;
              for (var m in waiterMovements) {
                final amt = (m['amount'] as num).toDouble();
                final t = m['type'];
                if (t == 'salary' || t == 'tip' || t == 'bonus') {
                  earned += amt;
                } else if (t == 'payment') {
                  paid += amt;
                } else if (t == 'loan') {
                  loans += amt;
                } else if (t == 'deduction') {
                  deductions += amt;
                }
              }
              final double netBalance = earned - paid - loans - deductions;

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    color: PdfColors.grey200,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Mesero: ${waiter['name']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text(
                          netBalance >= 0
                              ? 'Saldo a pagar: \$${netBalance.toStringAsFixed(2)}'
                              : 'Saldo que debe el mesero: \$${netBalance.abs().toStringAsFixed(2)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Fecha', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Tipo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Descripción', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Efecto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                          pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Monto', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                        ],
                      ),
                      ...waiterMovements.map((m) {
                        final amt = (m['amount'] as num).toDouble();
                        final t = m['type'];
                        String label;
                        String effect;
                        switch (t) {
                          case 'salary':
                            label = 'Sueldo';
                            effect = '+';
                            break;
                          case 'tip':
                            label = 'Propina';
                            effect = '+';
                            break;
                          case 'bonus':
                            label = 'Bono';
                            effect = '+';
                            break;
                          case 'payment':
                            label = 'Pago Entregado';
                            effect = '-';
                            break;
                          case 'loan':
                            label = 'Préstamo';
                            effect = '-';
                            break;
                          case 'deduction':
                            label = 'Descuento';
                            effect = '-';
                            break;
                          default:
                            label = t.toString().toUpperCase();
                            effect = '?';
                        }

                        return pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(DateFormat('dd/MM HH:mm').format(DateTime.parse(m['created_at'])), style: const pw.TextStyle(fontSize: 9))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(label, style: const pw.TextStyle(fontSize: 9))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(m['description'] ?? '', style: const pw.TextStyle(fontSize: 9))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(effect, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('\$${amt.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4, bottom: 20),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text('Devengado (sueldo+bono+propina): \$${earned.toStringAsFixed(2)}  |  '),
                        pw.Text('Pagos entregados: \$${paid.toStringAsFixed(2)}  |  '),
                        pw.Text('Préstamos: \$${loans.toStringAsFixed(2)}  |  '),
                        pw.Text('Descuentos: \$${deductions.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ];
        },
      ),
    );

    // 3. Print or share
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Nomina_${allWaiters ? 'General' : _selectedWaiterName}_$weekText.pdf',
    );
  }

  Future<void> _showMovementDialog() async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    String type = 'salary';

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Registrar Movimiento', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Tipo de Movimiento', labelStyle: TextStyle(color: Colors.grey)),
                    items: const [
                      DropdownMenuItem(value: 'salary', child: Text('Sueldo / Jornada')),
                      DropdownMenuItem(value: 'tip', child: Text('Propina')),
                      DropdownMenuItem(value: 'loan', child: Text('Préstamo')),
                      DropdownMenuItem(value: 'payment', child: Text('Pago de Nómina')),
                      DropdownMenuItem(value: 'bonus', child: Text('Bono')),
                    ],
                    onChanged: (val) => setDialogState(() => type = val!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Monto (\$)', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Descripción / Comentario', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    final amt = double.tryParse(amountController.text);
                    if (amt == null || amt <= 0) return;

                    await _supabase.from('waiter_ledger').insert({
                      'waiter_id': _selectedWaiterId,
                      'amount': amt,
                      'type': type,
                      'description': descriptionController.text.trim(),
                      'branch_name': Globals.currentBranch,
                    });

                    if (context.mounted) {
                       Navigator.pop(context);
                       _fetchLedger();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
