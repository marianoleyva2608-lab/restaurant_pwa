import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dish.dart';
import '../widgets/dish_card.dart';
import '../widgets/order_summary.dart';

class ComandasView extends StatefulWidget {
  final String? waiterId;

  const ComandasView({super.key, this.waiterId});

  @override
  State<ComandasView> createState() => _ComandasViewState();
}

class _ComandasViewState extends State<ComandasView> {
  final _supabase = Supabase.instance.client;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Dish> _dishes = [];
  bool _isLoading = true;
  String? _selectedTableId;
  String? _selectedTableNumber;
  String? _selectedWaiterId;
  String _selectedOrderType = 'dine_in';
  String? _customerName;
  List<Map<String, dynamic>> _waiters = [];
  StreamSubscription<List<Map<String, dynamic>>>? _orderStreamSubscription;
  final Set<String> _notifiedOrders = {};
  StreamSubscription? _dishesSubscription;
  final TransformationController _mapTransformationController = TransformationController(Matrix4.diagonal3Values(0.5, 0.5, 1.0));

  @override
  void initState() {
    super.initState();
    _selectedWaiterId = widget.waiterId;
    _loadCategoryClickCounts();
    _fetchDishes();
    _fetchWaiters();
    _setupNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTableSelectionDialog();
    });
  }

  Future<void> _loadCategoryClickCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('cat_clicks_'));
    final counts = <String, int>{};
    for (final key in keys) {
      final category = key.replaceFirst('cat_clicks_', '');
      counts[category] = prefs.getInt(key) ?? 0;
    }
    if (mounted) setState(() => _categoryClickCounts = counts);
  }

  Future<void> _onCategoryTap(String label) async {
    if (label != 'Todos') {
      final newCount = (_categoryClickCounts[label] ?? 0) + 1;
      setState(() {
        _categoryClickCounts[label] = newCount;
        _selectedCategory = label;
        if (label != 'drink') _selectedDrinkSubcat = null;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cat_clicks_$label', newCount);
    } else {
      setState(() { _selectedCategory = label; _selectedDrinkSubcat = null; });
    }
  }

  bool _isInitialLoad = true;
  String _selectedCategory = 'Todos';
  String? _selectedDrinkSubcat; // submenu de bebidas
  String _searchQuery = '';
  bool _carritoVisible = true;
  Map<String, int> _categoryClickCounts = {};

  String _translateCategory(String category) {
    return Globals.translateCategory(category);
  }

  List<Dish> get _filteredDishes {
    const gordtasPermitidas = {'gordita de maíz', 'gordita de maiz', 'gordita de harina'};
    final seenNames = <String>{};

    final result = <Dish>[];
    for (final dish in _dishes) {
      if (_selectedCategory != 'Todos') {
        if (_selectedCategory == 'drink') {
          // Filtrar solo bebidas (cualquier categoría de bebida)
          const allDrinkCats = {'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol'};
          if (!allDrinkCats.contains(dish.category)) continue;
          // Si hay subcategoría seleccionada en el submenu, filtrar por ella
          if (_selectedDrinkSubcat != null && _effectiveCat(dish) != _selectedDrinkSubcat) continue;
        } else {
          if (_effectiveCat(dish) != _selectedCategory) continue;
        }
      }

      // Gorditas: solo Maíz y Harina (nombre exacto), sin duplicados por nombre
      if (dish.category == 'gorditas') {
        final n = dish.name.toLowerCase().trim();
        if (!gordtasPermitidas.contains(n)) continue;
        if (!seenNames.add(n)) continue; // ya existe uno con ese nombre
      }

      if (_searchQuery.isNotEmpty &&
          !dish.name.toLowerCase().contains(_searchQuery.toLowerCase())) continue;

      result.add(dish);
    }
    return result;
  }


  static const _drinkSubcats = ['jugos', 'cafes', 'refrescos', 'aguas', 'alcohol'];

  // Detecta subcategoría de bebida por nombre cuando la categoría es 'drink'
  static String _drinkSubcat(String name) {
    final n = name.toLowerCase();
    if (n.contains('jugo') || n.contains('naranja') || n.contains('zanahoria') ||
        n.contains('betabel') || n.contains('verde') || n.contains('piña') ||
        n.contains('mango') || n.contains('fresa') || n.contains('apio'))
      return 'jugos';
    if (n.contains('café') || n.contains('cafe') || n.contains('capuchino') ||
        n.contains('americano') || n.contains('latte') || n.contains('espresso') ||
        n.contains('olla') || n.contains('instantáneo') || n.contains('instantaneo') ||
        n.contains('nescafé') || n.contains('nescafe'))
      return 'cafes';
    if (n.contains('agua') || n.contains('horchata') || n.contains('jamaica') ||
        n.contains('tamarindo') || n.contains('limonada') || n.contains('fresca'))
      return 'aguas';
    if (n.contains('refresco') || n.contains('coca') || n.contains('pepsi') ||
        n.contains('sprite') || n.contains('fanta') || n.contains('sidral') ||
        n.contains('squirt') || n.contains('7up') || n.contains('manzanita') ||
        n.contains('sangría') || n.contains('sangria'))
      return 'refrescos';
    if (n.contains('cerveza') || n.contains('caguama') || n.contains('tequila') ||
        n.contains('mezcal') || n.contains('michelada') || n.contains('clamato') ||
        n.contains('corona') || n.contains('modelo') || n.contains('pacifico') ||
        n.contains('victoria') || n.contains('alcohol'))
      return 'alcohol';
    return 'drink';
  }

  // Categoría efectiva: si es bebida genérica, detecta subcategoría por nombre
  static String _effectiveCat(Dish d) {
    const genericDrink = {'drink', 'bebidas'};
    return genericDrink.contains(d.category) ? _drinkSubcat(d.name) : d.category;
  }

  List<String> get _availableCategories {
    final rawCats = _dishes.map((d) => d.category).toSet();

    // Consolidar todas las categorías de bebidas en un solo chip 'drink'
    const allDrinkCats = {'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol'};
    if (rawCats.any(allDrinkCats.contains)) {
      rawCats.removeAll(allDrinkCats);
      rawCats.add('drink');
    }

    final categories = rawCats.toList();
    categories.sort((a, b) {
      final countA = _categoryClickCounts[a] ?? 0;
      final countB = _categoryClickCounts[b] ?? 0;
      if (countB != countA) return countB.compareTo(countA);
      return a.compareTo(b);
    });
    return ['Todos', ...categories];
  }

  Widget _buildCategoryChip(String label, {bool isMobile = false}) {
    final bool selected = _selectedCategory == label;
    const activeColor = Color(0xFFE07A30);
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: () => _onCategoryTap(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: isMobile
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? activeColor : Colors.white.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: isMobile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Globals.categoryIcon(label),
                      size: 20,
                      color: selected ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _translateCategory(label),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? Colors.white : Colors.white60,
                        height: 1.0,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Globals.categoryIcon(label),
                      size: 16,
                      color: selected ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _translateCategory(label),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCategoryBlock(String label) {
    final bool selected = _selectedCategory == label;
    const activeColor = Color(0xFFE07A30);
    return GestureDetector(
      onTap: () => _onCategoryTap(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 72,
        height: 64,
        decoration: BoxDecoration(
          color: selected ? activeColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFF334155),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Globals.categoryIcon(label),
              size: 24,
              color: selected ? Colors.white : Colors.white60,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _translateCategory(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? Colors.white : Colors.white60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setupNotifications() {
    if (_selectedWaiterId == null) return;

    _orderStreamSubscription = _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('waiter_id', _selectedWaiterId!)
        .listen((orders) {
          for (final order in orders) {
            final orderId = order['id'].toString();
            final status = order['status'];

            // Si está lista o incompleta y no hemos avisado aún
            if ((status == 'ready' || status == 'incomplete') && !_notifiedOrders.contains(orderId)) {
              _notifiedOrders.add(orderId);
              
              // Solo mostrar el aviso si NO es la carga inicial (para evitar spam de órdenes viejas)
              if (!_isInitialLoad) {
                _showReadyNotification(order, status == 'incomplete');
              }
            }
          }
          
          // Auto-deseleccion de mesa si se paga o cancela en otro lado
          if (_selectedTableId != null) {
            final hasActiveOrder = orders.any((o) => 
              o['table_id'] == _selectedTableId && 
              (o['status'] == 'pending' || o['status'] == 'ready')
            );
            if (!hasActiveOrder && _selectedOrderType == 'dine_in') {
               setState(() {
                 _selectedTableId = null;
                 _selectedTableNumber = null;
               });
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(
                   content: Text('La mesa seleccionada ha sido liberada o pagada.'),
                   backgroundColor: Colors.blueGrey,
                 )
               );
            }
          }
          
          // Después de procesar el primer lote de datos, apagamos la bandera
          if (_isInitialLoad) {
            _isInitialLoad = false;
          }
        }, onError: (error) {
          debugPrint('Error en el stream de notificaciones: $error');
        });
  }

  @override
  void dispose() {
    _orderStreamSubscription?.cancel();
    _dishesSubscription?.cancel();
    _audioPlayer.dispose();
    _mapTransformationController.dispose();
    super.dispose();
  }

  void _showReadyNotification(Map<String, dynamic> order, [bool isIncomplete = false]) async {
    String location = 'Orden';
    if (order['order_type'] == 'dine_in' && order['table_id'] != null) {
       try {
         final tabRes = await _supabase
             .from('restaurant_tables')
             .select('table_number')
             .eq('id', order['table_id'] as Object)
             .maybeSingle();
         if (tabRes != null) {
           location = 'Mesa ${tabRes['table_number']}';
         }
       } catch (e) {
         debugPrint('Error fetching table: $e');
       }
    } else {
       location = order['customer_name'] ?? 'Cliente';
    }

    if (!mounted) return;

    // Reproducir un sonido de notificación
    try {
      await _audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/dinner_chime.ogg'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Icon(isIncomplete ? Icons.warning_amber_rounded : Icons.restaurant, 
                 color: isIncomplete ? Colors.orange : Colors.green, size: 32),
            const SizedBox(width: 12),
            Text(isIncomplete ? '¡Alimento Agotado!' : '¡Orden Lista!', 
                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isIncomplete 
                  ? 'La orden para $location tiene platillos que están AGOTADOS o faltantes.'
                  : 'La orden para $location ya está lista en producción.',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 18),
            ),
            const SizedBox(height: 16),
            Text(
              isIncomplete 
                  ? 'Ve a producción para revisar la orden y notificar al cliente.'
                  : 'Por favor, ve por ella para entregarla al cliente.',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: isIncomplete ? Colors.orange : const Color(0xFFFF6D00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _fetchDishes() {
    _dishesSubscription = _supabase
        .from('dishes')
        .stream(primaryKey: ['id'])
        .listen((data) {
          if (mounted) {
            final dishes = data.map((d) => Dish.fromJson(d)).toList();
            setState(() {
              _dishes = dishes;
              _isLoading = false;
            });
          }
        }, onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar menú en tiempo real: $e')));
            setState(() => _isLoading = false);
          }
        });
  }

  Future<void> _fetchWaiters() async {
    try {
      final response = await _supabase.from('waiters').select().eq('branch_name', Globals.currentBranch).order('name');
      if (mounted) {
        setState(() {
          _waiters = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error loading waiters: $e');
    }
  }

  Future<void> _showTableSelectionDialog() async {
    String tempOrderType = _selectedOrderType;
    String? tempCustomerName = _customerName;
    final nameController = TextEditingController(text: _customerName);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Tipo de Orden'),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.80,
                child: Column(
                  children: [
                    // Order Type Selector
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'dine_in', label: Text('Mesa'), icon: Icon(Icons.table_restaurant)),
                        ButtonSegment(value: 'takeout', label: Text('Llevar'), icon: Icon(Icons.takeout_dining)),
                        ButtonSegment(value: 'delivery', label: Text('Delivery'), icon: Icon(Icons.delivery_dining)),
                      ],
                      selected: {tempOrderType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setStateDialog(() {
                          tempOrderType = newSelection.first;
                        });
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Theme.of(context).colorScheme.primary.withValues(alpha: 0.2);
                          }
                          return Colors.transparent;
                        }),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Conditional Content
                    Expanded(
                      child: tempOrderType == 'dine_in' 
                        ? StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _supabase
                                .from('restaurant_tables')
                                .stream(primaryKey: ['id'])
                                .eq('branch_name', Globals.currentBranch)
                                .order('table_number', ascending: true),
                            builder: (context, tablesSnapshot) {
                              if (!tablesSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                              final tables = tablesSnapshot.data!;

                              return StreamBuilder<List<Map<String, dynamic>>>(
                                stream: _supabase
                                    .from('orders')
                                    .stream(primaryKey: ['id'])
                                    .inFilter('status', ['pending', 'ready']),
                                builder: (context, ordersSnapshot) {
                                  final occupiedTableIds = (ordersSnapshot.data ?? []).map((o) => o['table_id']).toSet();

                                  return LayoutBuilder(
                                      builder: (context, constraints) {
                                        final availW = constraints.maxWidth;
                                        final availH = constraints.maxHeight;
                                        final cols = availW < 380 ? 4 : availW < 600 ? 5 : 7;
                                        final rows = (tables.length / cols).ceil();
                                        const spacing = 8.0;
                                        final ext = ((availH - (rows - 1) * spacing - 8) / rows).clamp(52.0, 120.0);
                                        return GridView.builder(
                                          physics: const NeverScrollableScrollPhysics(),
                                          padding: const EdgeInsets.all(4),
                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: cols,
                                            crossAxisSpacing: spacing,
                                            mainAxisSpacing: spacing,
                                            mainAxisExtent: ext,
                                          ),
                                          itemCount: tables.length,
                                          itemBuilder: (context, index) {
                                            final table = tables[index];
                                            final isOccupied = occupiedTableIds.contains(table['id']);
                                            return Material(
                                              color: isOccupied ? const Color(0xFF331515) : const Color(0xFF1E293B),
                                              borderRadius: BorderRadius.circular(12),
                                              child: InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    _selectedOrderType = 'dine_in';
                                                    _selectedTableId = table['id'];
                                                    _selectedTableNumber = table['table_number'].toString();
                                                    _customerName = null;
                                                  });
                                                  Navigator.pop(context);
                                                },
                                                borderRadius: BorderRadius.circular(12),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: isOccupied ? Colors.red[800]! : const Color(0xFF334155),
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.table_restaurant, size: 20,
                                                          color: isOccupied ? Colors.red[300] : const Color(0xFF94A3B8)),
                                                      const SizedBox(height: 2),
                                                      Text('Mesa ${table['table_number']}',
                                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                                              color: isOccupied ? Colors.red[100] : Colors.white)),
                                                      const SizedBox(height: 2),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: isOccupied
                                                              ? Colors.red.withValues(alpha: 0.25)
                                                              : Colors.green.withValues(alpha: 0.2),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(isOccupied ? 'Ocupada' : 'Libre',
                                                            style: TextStyle(fontSize: 9,
                                                                color: isOccupied ? Colors.red[300] : Colors.green[400])),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                },
                              );
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  tempOrderType == 'takeout' ? Icons.takeout_dining : Icons.delivery_dining,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 24),
                                TextField(
                                  controller: nameController,
                                  decoration: InputDecoration(
                                    labelText: tempOrderType == 'takeout' ? 'Nombre del Cliente' : 'Nombre/Dirección del Cliente',
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.person),
                                  ),
                                  onChanged: (value) {
                                    tempCustomerName = value;
                                  },
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {
                                    if (tempCustomerName == null || tempCustomerName!.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Ingresa el nombre del cliente'))
                                      );
                                      return;
                                    }
                                    setState(() {
                                      _selectedOrderType = tempOrderType;
                                      _customerName = tempCustomerName;
                                      _selectedTableId = null;
                                      _selectedTableNumber = null;
                                    });
                                    Navigator.pop(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                  child: const Text('Continuar a la Orden'),
                                ),
                              ],
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancelar / Volver'),
                )
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String titleStr = 'Toma de Comandas';
    if (_selectedOrderType == 'dine_in' && _selectedTableNumber != null) {
      titleStr = 'Comandas - Mesa $_selectedTableNumber';
    } else if (_selectedOrderType != 'dine_in') {
      titleStr = 'Comandas - ${_selectedOrderType == "takeout" ? "Para Llevar" : "Delivery"} (${_customerName ?? ""})';
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleStr, style: const TextStyle(fontSize: 18)),
            Text('Sucursal: ${Globals.currentBranch}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ],
        ),
        actions: [
          if (_selectedWaiterId != null && _waiters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Chip(
                avatar: const Icon(Icons.person, size: 18, color: Colors.white),
                label: Text(
                  _waiters.firstWhere(
                    (w) => w['id'] == _selectedWaiterId,
                    orElse: () => {'name': '...'}
                  )['name'],
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                backgroundColor: const Color(0xFFFF6D00),
                side: BorderSide.none,
              ),
            ),
          IconButton(
            icon: Icon(_carritoVisible ? Icons.menu_open : Icons.menu),
            tooltip: _carritoVisible ? 'Ocultar carrito' : 'Mostrar carrito',
            onPressed: () => setState(() => _carritoVisible = !_carritoVisible),
          ),
          IconButton(
            icon: const Icon(Icons.table_restaurant),
            onPressed: _showTableSelectionDialog,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _buildAdaptiveBody(context),
    );
  }

  Widget _buildAdaptiveBody(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isPhone = w < 600;
    final isDesktop = w >= 1024;

    if (isPhone) {
      // Celular: menú arriba (3/5), resumen abajo (2/5)
      return Column(
        children: [
          Expanded(flex: 3, child: _buildMenuContent(context)),
          const Divider(height: 1, thickness: 1, color: Color(0xFF334155)),
          Expanded(flex: 2, child: _buildOrderSummaryContent()),
        ],
      );
    }

    // Tablet y escritorio: lado a lado
    final sidebarWidth = isDesktop ? 380.0 : 320.0;
    return Row(
      children: [
        Expanded(child: _buildMenuContent(context)),
        if (_carritoVisible) ...[
          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF334155)),
          SizedBox(
            width: sidebarWidth,
            child: _buildOrderSummaryContent(),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderSummaryContent() {
    return (_selectedOrderType == 'dine_in' && _selectedTableId == null)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.table_restaurant, size: 64, color: Color(0xFF334155)),
                        const SizedBox(height: 16),
                        const Text('Selecciona una mesa primero', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showTableSelectionDialog,
                          icon: const Icon(Icons.touch_app),
                          label: const Text('ELEGIR MESA / TIPO'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6D00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  )
                : OrderSummaryWidget(
                    tableId: _selectedTableId,
                    tableNumber: _selectedTableNumber,
                    orderType: _selectedOrderType,
                    customerName: _customerName,
                    waiterId: _selectedWaiterId,
                    onOrderSubmitted: () {
                      if (_selectedOrderType != 'dine_in') {
                        // After submission, maybe clear or ask for next order
                        setState(() {
                           _customerName = null;
                           _selectedOrderType = 'dine_in';
                           _selectedTableId = null;
                           _selectedTableNumber = null;
                        });
                        _showTableSelectionDialog(); // show again
                      }
                    },
                  );
  }

  Widget _buildMenuContent(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredDishes = _filteredDishes;

    if (filteredDishes.isEmpty && _dishes.isEmpty) {
      return const Center(child: Text('El menú está vacío', style: TextStyle(color: Colors.grey)));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isPhone = screenWidth < 600;
    final isDesktop = screenWidth >= 1024;
    final isTablet = !isPhone && !isDesktop;
    final sidebarWidth = isDesktop ? 380.0 : (isTablet ? 320.0 : 0.0);
    final availableWidth = screenWidth - sidebarWidth;
    int crossAxisCount;
    if (isPhone) {
      crossAxisCount = (availableWidth / 110).floor().clamp(3, 4);
    } else if (isTablet) {
      crossAxisCount = (availableWidth / 130).floor().clamp(4, 6);
    } else {
      crossAxisCount = (availableWidth / 180).floor().clamp(4, 8);
    }

    return Column(
      children: [
        // ── Búsqueda (fija) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SearchBar(
            hintText: 'Buscar platillo...',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(1),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        // ── Categorías: scroll horizontal en celular, Wrap en tablet y escritorio ──
        if (isPhone)
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              children: _availableCategories
                  .map((label) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildCategoryBlock(label),
                      ))
                  .toList(),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableCategories.map(_buildCategoryBlock).toList(),
            ),
          ),
        const Divider(height: 1, thickness: 1, color: Color(0xFF1E293B)),
        // ── Submenu de bebidas ──
        if (_selectedCategory == 'drink') _buildDrinkSubmenu(),
        // ── Grid de platillos (scrollable) ──
        Expanded(
          child: CustomScrollView(
            slivers: [
              ..._buildGroupedMenu(filteredDishes, crossAxisCount, isPhone, isTablet: isTablet),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDrinkSubmenu() {
    const subcats = [
      ('refrescos','Refrescos',Icons.sports_bar),
      ('aguas',   'Aguas',     Icons.water_drop),
      ('cafes',   'Cafés',     Icons.coffee),
      ('jugos',   'Jugos',     Icons.local_drink),
      (null,      'Todas',     Icons.grid_view),
    ];
    const active = Color(0xFFE07A30);
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: subcats.map((s) {
            final key = s.$1;
            final label = s.$2;
            final icon = s.$3;
            final selected = _selectedDrinkSubcat == key;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => setState(() => _selectedDrinkSubcat = key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? active : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? active : const Color(0xFF334155),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: selected ? Colors.white : Colors.white60),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
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
    );
  }

  List<Widget> _buildGroupedMenu(List<Dish> items, int crossAxisCount, bool isPhone, {bool isTablet = false}) {
    final isMobile = isPhone;
    if (items.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: Text('No hay coincidencias', style: TextStyle(color: Colors.grey))),
          ),
        )
      ];
    }

    // Group items by effective category (auto-detects drink subcategory from name)
    final Map<String, List<Dish>> groups = {};
    for (var item in items) {
      groups.putIfAbsent(_effectiveCat(item), () => []).add(item);
    }

    final sortedCategories = groups.keys.toList()..sort();
    final List<Widget> slivers = [];

    for (var category in sortedCategories) {
      final categoryItems = groups[category]!;
      
      // Category Header
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6D00),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _translateCategory(category).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${categoryItems.length})',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      );

      // Category Grid
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8.0 : 16.0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: isMobile ? 0.78 : (isTablet ? 0.85 : 0.72),
              crossAxisSpacing: isMobile ? 6 : (isTablet ? 8 : 12),
              mainAxisSpacing: isMobile ? 6 : (isTablet ? 8 : 12),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => DishCard(dish: categoryItems[index]),
              childCount: categoryItems.length,
            ),
          ),
        ),
      );
    }

    return slivers;
  }
}

