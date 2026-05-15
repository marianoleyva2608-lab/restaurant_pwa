import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../models/dish.dart';
import '../providers/cart_provider.dart';
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
  final Set<String> _notifiedDrinksOrders = {};
  final Set<String> _notifiedFoodOrders = {};
  StreamSubscription? _dishesSubscription;
  final TransformationController _mapTransformationController = TransformationController(Matrix4.diagonal3Values(0.5, 0.5, 1.0));

  bool _argsParsed = false;

  @override
  void initState() {
    super.initState();
    _selectedWaiterId = widget.waiterId;
    _loadCategoryClickCounts();
    _fetchDishes();
    _fetchWaiters();
    _setupNotifications();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsParsed) {
      _argsParsed = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['tableId'] != null) {
        // Llegamos desde admin con mesa preseleccionada
        setState(() {
          _selectedTableId = args['tableId'] as String;
          _selectedTableNumber = args['tableNumber']?.toString();
          _selectedOrderType = 'dine_in';
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTableSelectionDialog();
        });
      }
    }
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

  /// Abre el diálogo directo si la categoría produce exactamente 1 tarjeta.
  /// Devuelve true si se abrió el diálogo (no hace falta filtrar).
  bool _triggerSingleCardAction(BuildContext context, String label) {
    final items = _dishes
        .where((d) => _effectiveCat(d) == label)
        .toList();
    if (items.isEmpty) return false;

    const skipMultiFlavor = {
      'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol', 'gorditas',
    };
    final cat = items.first.category.toLowerCase();

    // Múltiples platillos en categoría no-skip → siempre 1 MultiFlavorVariantCard
    if (items.length > 1 && !skipMultiFlavor.contains(cat)) {
      final displayName = _translateCategory(cat);
      addMultiFlavorVariantToCart(context, items, displayName, displayName);
      return true;
    }

    // Lógica byBase (categorías skip o ítem único)
    final byBase = <String, Map<String, Dish>>{};
    for (final dish in items) {
      final isMedia = dish.name.toLowerCase().contains('1/2');
      final base = dish.name
          .replaceAll(RegExp(r'\s*\(Orden\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*\(1/2\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*1/2\s*$', caseSensitive: false), '')
          .trim();
      byBase.putIfAbsent(base, () => {});
      byBase[base]![isMedia ? 'media' : 'orden'] = dish;
    }

    if (byBase.length == 1) {
      final entry = byBase.entries.first;
      final orden = entry.value['orden'];
      final media = entry.value['media'];
      if (orden != null && media != null) {
        addOrdenVariantToCart(context, orden, media);
      } else {
        addDishToCart(context, orden ?? media!);
      }
      return true;
    }

    return false; // Múltiples tarjetas → filtrar normalmente
  }

  Future<void> _onCategoryTap(String label) async {
    if (label != 'Todos' && label != 'drink') {
      if (_triggerSingleCardAction(context, label)) return;
    }
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
  bool _carritoVisible = false;
  Map<String, int> _categoryClickCounts = {};

  String _translateCategory(String category) {
    return Globals.translateCategory(category);
  }

  List<Dish> get _filteredDishes {
    const gordtasPermitidas = {'gordita de maíz', 'gordita de maiz', 'gordita de harina'};
    final seenNames = <String>{};

    final result = <Dish>[];
    for (final dish in _dishes) {
      if (dish.category == 'platillos') continue;
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

    rawCats.remove('platillos'); // ocultar categoría Platillos
    // Orden fijo solicitado para las primeras categorías
    const pinned = [
      'gorditas',
      'drink',
      'chilaquiles',
      'huevos',
      'molletes',
      'enchiladas',
      'huaraches',
      'arrachera',
    ];
    final rest = rawCats.where((c) => !pinned.contains(c)).toList()..sort();
    final ordered = [...pinned.where(rawCats.contains), ...rest];
    return ['Todos', ...ordered];
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
        width: 60,
        height: 54,
        decoration: BoxDecoration(
          color: selected ? activeColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
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
              size: 20,
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

  void _showAddClientDialog(BuildContext context, CartProvider cart) {
    final controller = TextEditingController(text: 'Cliente ${cart.clients.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Nuevo cliente', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nombre del cliente',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6D00))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6D00), width: 2)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                cart.addClient(name);
                cart.setCurrentClient(name);
                if (!_carritoVisible) setState(() => _carritoVisible = true);
              }
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(backgroundColor: const Color(0xFFFF6D00).withOpacity(0.15)),
            child: const Text('Agregar', style: TextStyle(color: Color(0xFFFF6D00))),
          ),
        ],
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

            // Notificación: bebidas listas (bar completó su estación)
            if (order['drinks_ready'] == true && !_notifiedDrinksOrders.contains(orderId)) {
              _notifiedDrinksOrders.add(orderId);
              if (!_isInitialLoad) {
                _showStationReadyNotification(order, isDrinks: true);
              }
            }

            // Notificación: alimentos listos (cocina completó su estación)
            if (order['food_ready'] == true && !_notifiedFoodOrders.contains(orderId)) {
              _notifiedFoodOrders.add(orderId);
              if (!_isInitialLoad) {
                _showStationReadyNotification(order, isDrinks: false);
              }
            }

            // Notificación final: toda la orden lista o incompleta
            if ((status == 'ready' || status == 'incomplete') && !_notifiedOrders.contains(orderId)) {
              _notifiedOrders.add(orderId);
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

  void _showStationReadyNotification(Map<String, dynamic> order, {required bool isDrinks}) async {
    String location = 'Orden';
    if (order['order_type'] == 'dine_in' && order['table_id'] != null) {
      try {
        final tabRes = await _supabase
            .from('restaurant_tables')
            .select('table_number')
            .eq('id', order['table_id'] as Object)
            .maybeSingle();
        if (tabRes != null) location = 'Mesa ${tabRes['table_number']}';
      } catch (e) {
        debugPrint('Error fetching table: $e');
      }
    } else {
      location = order['customer_name'] ?? 'Cliente';
    }

    if (!mounted) return;

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
            Icon(
              isDrinks ? Icons.local_bar : Icons.soup_kitchen,
              color: isDrinks ? const Color(0xFF38BDF8) : const Color(0xFFFF6D00),
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              isDrinks ? '¡Bebidas Listas!' : '¡Alimentos Listos!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isDrinks
                  ? 'Las bebidas de $location ya están listas en el bar.'
                  : 'Los alimentos de $location ya están listos en cocina.',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              isDrinks
                  ? 'Pasa por las bebidas para llevarlas a la mesa.'
                  : 'Pasa por los alimentos para llevarlos a la mesa.',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDrinks ? const Color(0xFF38BDF8) : const Color(0xFFFF6D00),
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
        }, onError: (e) async {
          debugPrint('Realtime dishes error, falling back to one-shot fetch: $e');
          try {
            final rows = await _supabase.from('dishes').select();
            if (mounted) {
              final dishes = (rows as List).map((d) => Dish.fromJson(d)).toList();
              setState(() {
                _dishes = dishes;
                _isLoading = false;
              });
            }
          } catch (_) {
            if (mounted) setState(() => _isLoading = false);
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isPhone = screenWidth < 600;

    String titleStr = 'Toma de Comandas';
    if (_selectedOrderType == 'dine_in' && _selectedTableNumber != null) {
      titleStr = isPhone ? 'Mesa $_selectedTableNumber' : 'Comandas - Mesa $_selectedTableNumber';
    } else if (_selectedOrderType != 'dine_in') {
      final typeLabel = _selectedOrderType == 'takeout' ? 'Para Llevar' : 'Delivery';
      titleStr = isPhone
          ? '$typeLabel (${_customerName ?? ""})'
          : 'Comandas - $typeLabel (${_customerName ?? ""})';
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleStr, style: TextStyle(fontSize: isPhone ? 15 : 18),
                overflow: TextOverflow.ellipsis),
            if (!isPhone)
              Text('Sucursal: ${Globals.currentBranch}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ],
        ),
        actions: [
          Consumer<CartProvider>(
            builder: (context, cart, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isPhone && cart.clients.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6D00).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF6D00), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person, size: 14, color: Color(0xFFFF6D00)),
                          const SizedBox(width: 5),
                          Text(
                            cart.currentClient,
                            style: const TextStyle(
                              color: Color(0xFFFF6D00),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // En móvil: solo ícono; en tablet+: ícono + texto
                isPhone
                    ? IconButton(
                        icon: const Icon(Icons.person_add, color: Color(0xFFFF6D00)),
                        tooltip: 'Agregar cliente',
                        onPressed: () {
                          final currentHasItems = cart.items.values
                              .any((item) => item.clientLabel == cart.currentClient);
                          if (!currentHasItems) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Agrega al menos un platillo al cliente actual primero'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ));
                            return;
                          }
                          final name = 'Cliente ${cart.clients.length + 1}';
                          cart.addClient(name);
                          cart.setCurrentClient(name);
                          if (!_carritoVisible) setState(() => _carritoVisible = true);
                        },
                      )
                    : TextButton.icon(
                        icon: const Icon(Icons.person_add, size: 18, color: Color(0xFFFF6D00)),
                        label: const Text('Cliente', style: TextStyle(color: Color(0xFFFF6D00), fontSize: 12)),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6D00).withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        onPressed: () {
                          final currentHasItems = cart.items.values
                              .any((item) => item.clientLabel == cart.currentClient);
                          if (!currentHasItems) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Agrega al menos un platillo al cliente actual primero'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              width: 340,
                            ));
                            return;
                          }
                          final name = 'Cliente ${cart.clients.length + 1}';
                          cart.addClient(name);
                          cart.setCurrentClient(name);
                          if (!_carritoVisible) setState(() => _carritoVisible = true);
                        },
                      ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (!isPhone && _selectedWaiterId != null && _waiters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
          if (!isPhone) const SizedBox(width: 16),
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
      // Celular: pantalla completa para menú o comanda (toggle con botón ≡)
      return _carritoVisible
          ? _buildOrderSummaryContent()
          : _buildMenuContent(context);
    }

    // Tablet y escritorio: lado a lado
    final sidebarWidth = isDesktop ? 380.0 : (w < 800 ? 230.0 : 280.0);
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
    // isTablet se usa en _buildGroupedMenu via LayoutBuilder

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
        // ── Categorías: 2 filas fijas con scroll horizontal ──
        SizedBox(
          height: 2 * 54 + 1 * 6 + 8,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 6,
              childAspectRatio: 54 / 60,
            ),
            itemCount: _availableCategories.length,
            itemBuilder: (_, i) => _buildCategoryBlock(_availableCategories[i]),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFF1E293B)),
        // ── Submenu de bebidas ──
        if (_selectedCategory == 'drink') _buildDrinkSubmenu(),
        // ── Grid de platillos (scrollable) ──
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final realWidth = constraints.maxWidth;
              int cols;
              if (isPhone) {
                cols = (realWidth / 130).floor().clamp(2, 3);
              } else if (isTablet) {
                cols = (realWidth / 150).floor().clamp(2, 5);
              } else {
                cols = (realWidth / 180).floor().clamp(4, 8);
              }
              return CustomScrollView(
                slivers: [
                  ..._buildGroupedMenu(filteredDishes, cols, isPhone, isTablet: isTablet),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDrinkSubmenu() {
    const subcats = [
      ('refrescos', 'Refrescos',  Icons.sports_bar),
      ('aguas',     'Aguas',      Icons.water_drop),
      ('cafes',     'Cafés',      Icons.coffee),
      ('jugos',     'Jugos',      Icons.local_drink),
      (null,        'Todas',      Icons.grid_view),
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
                onTap: () {
                  if (key != null && _triggerSingleCardAction(context, key)) return;
                  setState(() => _selectedDrinkSubcat = key);
                },
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

      // Group dishes into cards: pair Orden + 1/2 Orden variants, rest stay solo
      final List<Widget> cards = _buildCategoryCards(categoryItems);

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
                  '(${cards.length})',
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
              childAspectRatio: isMobile ? 1.6 : (isTablet ? 1.7 : 1.8),
              crossAxisSpacing: isMobile ? 6 : (isTablet ? 8 : 12),
              mainAxisSpacing: isMobile ? 6 : (isTablet ? 8 : 12),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => cards[index],
              childCount: cards.length,
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  /// Agrupa platillos con variantes Orden/1/2 Orden en una sola tarjeta.
  List<Widget> _buildCategoryCards(List<Dish> items) {
    if (items.isEmpty) return [];

    // Categorías que mantienen tarjetas individuales (lógica especial)
    const skipMultiFlavor = {
      'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol',
      'gorditas',
    };
    final cat = items.first.category.toLowerCase();
    if (items.length > 1 && !skipMultiFlavor.contains(cat)) {
      final displayName = _translateCategory(cat);
      return [
        MultiFlavorVariantCard(
          dishes: items,
          displayName: displayName,
          categoryPrefix: displayName,
        ),
      ];
    }

    // Mapa: nombre base → {orden: Dish?, media: Dish?}
    final Map<String, Map<String, Dish>> byBase = {};
    for (final dish in items) {
      final name = dish.name;
      final isMedia = name.toLowerCase().contains('1/2');
      // Extraer nombre base quitando sufijo de variante
      final base = name
          .replaceAll(RegExp(r'\s*\(Orden\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*\(1/2\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*1/2\s*$', caseSensitive: false), '')
          .trim();
      byBase.putIfAbsent(base, () => {});
      byBase[base]![isMedia ? 'media' : 'orden'] = dish;
    }

    final List<Widget> cards = [];
    for (final entry in byBase.entries) {
      final orden = entry.value['orden'];
      final media = entry.value['media'];
      if (orden != null && media != null) {
        cards.add(OrdenVariantCard(ordenDish: orden, mediaDish: media));
      } else {
        // Solo una variante — tarjeta normal
        final solo = orden ?? media!;
        cards.add(DishCard(dish: solo));
      }
    }
    return cards;
  }
}

