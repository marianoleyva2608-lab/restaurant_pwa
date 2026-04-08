import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../globals.dart';

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
      
      // Calculate balance
      double bal = 0;
      for (var row in data) {
        final amt = (row['amount'] as num).toDouble();
        final type = row['type'];
        if (type == 'pago' || type == 'salary' || type == 'tip' || type == 'bonus') {
          bal += amt;
        } else if (type == 'loan' || type == 'payment') {
          // 'payment' in ledger context usually means we are paying OUT to them
          // Wait, 'payment' type in carwash ledger was 'loan', 'tip', 'purchase', 'bonus', 'payment'
          // Let's clarify types: 
          // salary/tip/bonus = positive (money they earned)
          // payment/loan = negative (money we gave them or they owe)
          
          if (type == 'payment') {
             // If type is payment, it means we PAID the waiter. This reduces the debt or accumulates paid salary.
             // Actually, letting's define: 
             // Tips, Salary, Bonus -> Increases what we OWE the waiter.
             // Payments, Loans -> Decreases what we OWE the waiter.
             bal -= amt;
          } else {
             bal -= amt;
          }
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
            'Saldo Pendiente',
            '\$${_balance.toStringAsFixed(2)}',
            _balance >= 0 ? Colors.green : Colors.red,
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
            case 'loan':
              typeColor = Colors.red;
              typeIcon = Icons.money_off;
              typeLabel = 'Préstamo';
              break;
            case 'payment':
              typeColor = Colors.orange;
              typeIcon = Icons.check_circle;
              typeLabel = 'Pago Realizado';
              break;
            case 'bonus':
              typeColor = Colors.purple;
              typeIcon = Icons.star;
              typeLabel = 'Bono';
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
            trailing: Text(
              '\$${amount.toStringAsFixed(2)}',
              style: TextStyle(
                color: (type == 'loan' || type == 'payment') ? Colors.red[300] : Colors.green[300],
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          );
        },
      ),
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
                    decoration: const InputDecoration(labelText: 'Monto ($)', labelStyle: TextStyle(color: Colors.grey)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)),
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
