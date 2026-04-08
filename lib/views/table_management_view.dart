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
  bool _isLoading = true;
  List<Map<String, dynamic>> _tables = [];
  final TransformationController _transformationController = TransformationController();

  Future<void> _updateTablePosition(String id, double x, double y) async {
    try {
      await _supabase.from('restaurant_tables').update({
        'pos_x': x,
        'pos_y': y,
      }).eq('id', id);
    } catch (e) {
      debugPrint('Error saving position: $e');
    }
  }

  // Removed manual _fetchTables as it will be handled by StreamBuilder

  Future<void> _addTable() async {
    final controller = TextEditingController();
    // Suggest the next table number
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

  Future<void> _saveAllPositions() async {
    setState(() => _isLoading = true);
    try {
      for (final table in _tables) {
        final id = table['id'] as String;
        final x = (table['pos_x'] as num?)?.toDouble() ?? 50.0;
        final y = (table['pos_y'] as num?)?.toDouble() ?? 50.0;
        await _supabase.from('restaurant_tables').update({
          'pos_x': x,
          'pos_y': y,
        }).eq('id', id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mapa guardado exitosamente', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar mapa: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _transformationController.value = Matrix4.identity()..scale(0.5);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase.from('restaurant_tables')
          .stream(primaryKey: ['id'])
          .eq('branch_name', Globals.currentBranch)
          .order('table_number', ascending: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        _tables = snapshot.data!;
        _isLoading = false;

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
                  Text('Gestión de Mesas', style: TextStyle(fontSize: screenWidth < 800 ? 24 : 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Text('Configura el mapa de tu restaurante', style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8))),
                ],
              ),
              if (screenWidth < 800) const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saveAllPositions,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar Mapa'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      side: const BorderSide(color: Color(0xFF334155)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
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
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ClipRRect(
                    borderRadius: BorderRadius.circular(16),
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
                        // Draw a grid pattern for guidance
                        child: CustomPaint(
                          painter: GridPainter(),
                          child: Stack(
                            children: _tables.map((table) {
                              final id = table['id'] as String;
                              final number = table['table_number'] as int;
                              final status = table['status'] as String;
                              double x = (table['pos_x'] as num?)?.toDouble() ?? 50.0;
                              double y = (table['pos_y'] as num?)?.toDouble() ?? 50.0;
                              
                              return Positioned(
                                left: x,
                                top: y,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      final index = _tables.indexWhere((t) => t['id'] == id);
                                      if (index != -1) {
                                        _tables[index]['pos_x'] = x + details.delta.dx;
                                        _tables[index]['pos_y'] = y + details.delta.dy;
                                      }
                                    });
                                  },
                                  onPanEnd: (details) {
                                    final currentIndex = _tables.indexWhere((t) => t['id'] == id);
                                    if (currentIndex != -1) {
                                        _updateTablePosition(id, _tables[currentIndex]['pos_x'], _tables[currentIndex]['pos_y']);
                                    }
                                  },
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFF334155), width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.3),
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        )
                                      ],
                                    ),
                                    child: Stack(
                                      children: [
                                        Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.drag_indicator, size: 20, color: Colors.grey),
                                              const SizedBox(height: 4),
                                              const Icon(Icons.table_restaurant, size: 36, color: Color(0xFFFF6D00)),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Mesa $number',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                              Text(
                                                status.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: status == 'free' ? Colors.green : Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Positioned(
                                          top: -4,
                                          right: -4,
                                          child: IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                            onPressed: () => _deleteTable(id, number),
                                          ),
                                        ),
                                      ],
                                    ),
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
      ),
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
