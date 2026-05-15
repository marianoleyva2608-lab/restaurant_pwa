import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';
import 'client_menu_view.dart';

class ClientHomeView extends StatefulWidget {
  const ClientHomeView({super.key});

  @override
  State<ClientHomeView> createState() => _ClientHomeViewState();
}

class _ClientHomeViewState extends State<ClientHomeView> {
  final nameController = TextEditingController();
  final _supabase = Supabase.instance.client;

  void _navigateToMenu({
    required String type,
    String? tableId,
    String? tableNumber,
  }) {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Por favor, ingresa tu nombre para continuar')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientMenuView(
          orderType: type,
          customerName: nameController.text.trim(),
          tableId: tableId,
          tableNumber: tableNumber,
        ),
      ),
    );
  }

  Future<void> _onDineInTap() async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Por favor, ingresa tu nombre para continuar')),
      );
      return;
    }
    // Cargar mesas de la sucursal actual
    List<Map<String, dynamic>> tables = [];
    try {
      final rows = await _supabase
          .from('restaurant_tables')
          .select('id, table_number, status')
          .eq('branch_name', Globals.currentBranch)
          .order('table_number');
      tables = (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar las mesas: $e')));
      return;
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selecciona tu mesa'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: tables.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay mesas registradas'),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 1.1,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (_, i) {
                    final t = tables[i];
                    final occupied = (t['status'] as String?) == 'occupied';
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _navigateToMenu(
                          type: 'dine_in',
                          tableId: t['id'] as String,
                          tableNumber: t['table_number'].toString(),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: occupied
                              ? Colors.orange.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: occupied
                                ? Colors.orange
                                : Colors.green,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.table_restaurant,
                              size: 16,
                              color: occupied ? Colors.orange : Colors.green,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${t['table_number']}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              occupied ? 'Ocupada' : 'Libre',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: occupied
                                      ? Colors.orange[800]
                                      : Colors.green[800]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pedido'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.takeout_dining,
                    size: 80, color: Color(0xFFFF6D00)),
                const SizedBox(height: 24),
                const Text(
                  'Ordena tu comida',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ingresa tu nombre para comenzar:',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Tu Nombre',
                    hintText: 'Ej. Ana Gómez',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onSubmitted: (_) => _navigateToMenu(type: 'takeout'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _navigateToMenu(type: 'takeout'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Pedido Para Llevar',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _onDineInTap,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Comer Aquí',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
