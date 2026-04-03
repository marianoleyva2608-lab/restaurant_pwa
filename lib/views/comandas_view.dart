import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final TransformationController _mapTransformationController = TransformationController(Matrix4.diagonal3Values(0.5, 0.5, 1.0));

  @override
  void initState() {
    super.initState();
    _selectedWaiterId = widget.waiterId;
    _fetchDishes();
    _fetchWaiters();
    _setupNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTableSelectionDialog();
    });
  }

  bool _isInitialLoad = true;
  String _selectedCategory = 'Todos';
  String _searchQuery = '';

  List<Dish> get _filteredDishes {
    return _dishes.where((dish) {
      if (_selectedCategory != 'Todos') {
        if (_selectedCategory == 'Entradas' && dish.category != CourseCategory.appetizer) return false;
        if (_selectedCategory == 'Plato Fuerte' && dish.category != CourseCategory.mainCourse) return false;
        if (_selectedCategory == 'Postres' && dish.category != CourseCategory.dessert) return false;
        if (_selectedCategory == 'Bebidas' && dish.category != CourseCategory.drink) return false;
      }
      if (_searchQuery.isNotEmpty) {
        if (!dish.name.toLowerCase().contains(_searchQuery.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  Widget _buildCategoryChip(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: _selectedCategory == label,
        onSelected: (_) {
          setState(() {
            _selectedCategory = label;
          });
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  Future<void> _fetchDishes() async {
    try {
      final response = await Supabase.instance.client.from('dishes').select();
      final dishes = (response as List).map((data) => Dish.fromJson(data)).toList();
      setState(() {
        _dishes = dishes;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar menú: \$e')));
        setState(() => _isLoading = false);
      }
    }
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
      debugPrint('Error loading waiters: \$e');
    }
  }

  Future<void> _showTableSelectionDialog() async {
    final tablesResponse = await _supabase
        .from('restaurant_tables')
        .select()
        .eq('branch_name', Globals.currentBranch)
        .order('table_number', ascending: true);

    final ordersResponse = await _supabase
        .from('orders')
        .select('table_id')
        .eq('status', 'pending');
        
    final occupiedTableIds = (ordersResponse as List).map((o) => o['table_id']).toSet();

    if (!mounted) return;

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
                width: 800,
                height: 600,
                child: Column(
                  children: [
                    // Order Type Selector
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'dine_in', label: Text('En Mesa'), icon: Icon(Icons.table_restaurant)),
                        ButtonSegment(value: 'takeout', label: Text('Para Llevar'), icon: Icon(Icons.takeout_dining)),
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
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: InteractiveViewer(
                              transformationController: _mapTransformationController,
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
                                child: Stack(
                                  children: tablesResponse.map((table) {
                                    final isOccupied = occupiedTableIds.contains(table['id']);
                                    double x = (table['pos_x'] as num?)?.toDouble() ?? 50.0;
                                    double y = (table['pos_y'] as num?)?.toDouble() ?? 50.0;
                                    
                                    return Positioned(
                                      left: x,
                                      top: y,
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
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          width: 120,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            color: isOccupied ? const Color(0xFF331515) : const Color(0xFF1E293B),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isOccupied ? Colors.red[900]! : const Color(0xFF334155),
                                              width: isOccupied ? 2 : 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.3),
                                                blurRadius: 10,
                                                offset: const Offset(0, 5),
                                              )
                                            ],
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.table_restaurant,
                                                size: 40,
                                                color: isOccupied ? Colors.red[400] : const Color(0xFF94A3B8),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Mesa ${table['table_number']}',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: isOccupied ? Colors.red[200] : Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isOccupied ? Colors.red.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  isOccupied ? 'Ocupada' : 'Libre',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w500,
                                                    color: isOccupied ? Colors.red[300] : Colors.green[400],
                                                  ),
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
            icon: const Icon(Icons.table_restaurant),
            onPressed: _showTableSelectionDialog,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: MediaQuery.of(context).size.width < 800
        ? Column(
            children: [
              Expanded(
                flex: 3,
                child: _buildMenuContent(context),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFF334155)),
              Expanded(
                flex: 2,
                child: _buildOrderSummaryContent(),
              ),
            ],
          )
        : Row(
            children: [
              // Left Side: Menu Grid
              Expanded(
                flex: 2,
                child: _buildMenuContent(context),
              ),
              
              const VerticalDivider(width: 1, thickness: 1, color: Color(0xFF334155)),
              
              // Right Side: Order Summary Persistent Sidebar
              Container(
                width: 380,
                color: const Color(0xFF0F172A),
                child: _buildOrderSummaryContent(),
              ),
            ],
          ),
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

    // Determine cross axis count based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth < 800 ? screenWidth : (screenWidth - 380);
    int crossAxisCount = (availableWidth / 250).floor();
    if (crossAxisCount < 1) crossAxisCount = 1;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SearchBar(
              hintText: 'Buscar platillo...',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(1),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildCategoryChip('Todos'),
                _buildCategoryChip('Entradas'),
                _buildCategoryChip('Plato Fuerte'),
                _buildCategoryChip('Postres'),
                _buildCategoryChip('Bebidas'),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          sliver: filteredDishes.isEmpty 
          ? const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: Text('No hay coincidencias', style: TextStyle(color: Colors.grey))),
              ),
            )
          : SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final dish = filteredDishes[index];
                return DishCard(dish: dish);
              },
              childCount: filteredDishes.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

