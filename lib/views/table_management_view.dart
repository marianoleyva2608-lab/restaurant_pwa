import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';

class TableManagementView extends StatefulWidget {
  const TableManagementView({super.key});

  @override
  State<TableManagementView> createState() => _TableManagementViewState();
}

class _TableManagementViewState extends State<TableManagementView> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;
  List<Map<String, dynamic>> _tables = [];

  Future<void> _addTable() async {
    final controller = TextEditingController();
    int nextNumber = 1;
    if (_tables.isNotEmpty) {
      final numbers = _tables.map((t) => t['table_number'] as int).toList();
      numbers.sort();
      nextNumber = numbers.last + 1;
    }
    controller.text = nextNumber.toString();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Nueva Mesa'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Número de Mesa',
            hintText: 'Ej: 5',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true && controller.text.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await _supabase.from('restaurant_tables').insert({
          'table_number': int.parse(controller.text),
          'status': 'free',
          'pos_x': 50.0,
          'pos_y': 50.0,
          'branch_name': Globals.currentBranch,
        });
        setState(() => _isLoading = false);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al agregar mesa: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteTable(String id, int number) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Mesa'),
        content: Text('¿Estás seguro de que deseas eliminar la Mesa $number?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await _supabase.from('restaurant_tables').delete().eq('id', id);
        setState(() => _isLoading = false);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar mesa: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase
          .from('restaurant_tables')
          .stream(primaryKey: ['id'])
          .eq('branch_name', Globals.currentBranch)
          .order('table_number', ascending: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        _tables = snapshot.data!;

        return Padding(
          padding: EdgeInsets.all(screenWidth < 800 ? 16.0 : 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flex(
                direction: screenWidth < 800 ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: screenWidth < 800 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gestión de Mesas',
                          style: TextStyle(
                              fontSize: screenWidth < 800 ? 24 : 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const Text('Administra las mesas de tu restaurante',
                          style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8))),
                    ],
                  ),
                  if (screenWidth < 800) const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _addTable,
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva Mesa'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6D00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1,
                        ),
                        itemCount: _tables.length,
                        itemBuilder: (context, index) {
                          final table = _tables[index];
                          final id = table['id'] as String;
                          final number = table['table_number'] as int;
                          final status = table['status'] as String;
                          final isOccupied = status != 'free';

                          return Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isOccupied ? Colors.red[700]! : const Color(0xFF334155),
                                    width: isOccupied ? 2 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.table_restaurant,
                                        size: 36,
                                        color: isOccupied ? Colors.red[400] : const Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Mesa $number',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isOccupied
                                              ? Colors.red.withValues(alpha: 0.2)
                                              : Colors.green.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          isOccupied ? 'Ocupada' : 'Libre',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: isOccupied ? Colors.red[300] : Colors.green[400],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: InkWell(
                                  onTap: () => _deleteTable(id, number),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
