import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  final List<String> _incomeCategories = ['retardo', 'aporte', 'otro'];
  final List<String> _expenseCategories = ['prestamo', 'gasto', 'propina', 'vacaciones', 'corte', 'otro'];

  @override
  void initState() {
    super.initState();
    _fetchMovements();
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
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Registrar Movimiento de Caja', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                            title: const Text('Salida', style: TextStyle(color: Colors.white)),
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
                            title: const Text('Entrada', style: TextStyle(color: Colors.white)),
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
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
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
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Dirigido a / Destinatario',
                          labelStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Monto (\$)',
                        labelStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.attach_money, color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Método de pago
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPaymentMethod,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Medio de Pago',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: ['EFECTIVO', 'TARJETA', 'TRANSFERENCIA']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) => setDialogState(() => _selectedPaymentMethod = val!),
                    ),
                    const SizedBox(height: 16),

                    // Descripción
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Concepto / Descripción detallada (opcional)',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addMovement();
                  },
                  child: const Text('Guardar Movimiento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

    // Calculo de totales del dia según movimientos de salida/entrada en EFECTIVO
    double entradasEfectivo = 0;
    double salidasEfectivo = 0;
    double prestamosHoy = 0;

    for (var m in _movements) {
      double amount = double.tryParse(m['amount'].toString()) ?? 0.0;
      if (m['type'] == 'entrada' && m['payment_method'] == 'EFECTIVO') entradasEfectivo += amount;
      if (m['type'] == 'salida' && m['payment_method'] == 'EFECTIVO') salidasEfectivo += amount;
      if (m['category'] == 'prestamo') prestamosHoy += amount;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Cortes y Movimientos de Caja', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: _showNewMovementDialog,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Nuevo Movimiento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
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
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Historial de Movimientos de Caja', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                // Lista de movimientos
                Expanded(
                  child: _movements.isEmpty 
                    ? const Center(child: Text('No hay movimientos registrados.', style: TextStyle(color: Colors.white54, fontSize: 16)))
                    : ListView.separated(
                        itemCount: _movements.length,
                        separatorBuilder: (_,_) => const Divider(color: Color(0xFF334155)),
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
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            subtitle: Text(
                              '$dateStr\n${(movement['recipient'] != null && movement['recipient'] != 'N/A') ? 'Destinatario: ${movement['recipient']} - ' : ''}${movement['description'] ?? 'Sin descripción'}',
                              style: const TextStyle(color: Colors.white70),
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

  Widget _buildSummaryCard(String title, String value, Color accentColor, bool isMobile) {
    return Container(
      width: isMobile ? (MediaQuery.of(context).size.width - 64) / 1 : 250, // Adaptive width
      constraints: BoxConstraints(minWidth: isMobile ? 150 : 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: accentColor, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
