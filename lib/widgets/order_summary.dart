import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../models/dish.dart';
import '../globals.dart';

class OrderSummaryWidget extends StatefulWidget {
  final String? tableId;
  final String? tableNumber;
  final String orderType;
  final String? customerName;
  final String? waiterId;
  final VoidCallback onOrderSubmitted;

  const OrderSummaryWidget({
    super.key,
    this.tableId,
    this.tableNumber,
    required this.orderType,
    this.customerName,
    required this.waiterId,
    required this.onOrderSubmitted,
  });

  @override
  State<OrderSummaryWidget> createState() => _OrderSummaryWidgetState();
}

class _OrderSummaryWidgetState extends State<OrderSummaryWidget> {
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _existingItems = [];

  @override
  void initState() {
    super.initState();
    _fetchExistingItems();
  }

  @override
  void didUpdateWidget(OrderSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableId != widget.tableId) {
      _fetchExistingItems();
    }
  }

  Future<void> _deleteExistingItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Quitar elemento?', style: TextStyle(color: Colors.white)),
        content: Text('¿Deseas eliminar "${item['name']}" de la cuenta?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.2)),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final supabase = Supabase.instance.client;
      final itemId = item['order_item_id'];
      final orderId = item['order_id'];
      final subtotal = (item['price'] as num).toDouble() * (item['quantity'] as num).toInt();

      await supabase.from('order_items').delete().eq('id', itemId);

      final orderRes = await supabase.from('orders').select('total_amount').eq('id', orderId).single();
      final currentTotal = (orderRes['total_amount'] as num).toDouble();
      await supabase.from('orders').update({
        'total_amount': currentTotal - subtotal,
      }).eq('id', orderId);

      _fetchExistingItems();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado de la cuenta')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  Future<void> _fetchExistingItems() async {
    try {
      if (widget.tableId == null) {
        if (mounted) setState(() => _existingItems = []);
        return;
      }

      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('orders')
          .select('*, order_items(*, dishes(*))')
          .eq('table_id', widget.tableId as Object)
          .eq('branch_name', Globals.currentBranch)
          .eq('status', 'pending');

      List<Map<String, dynamic>> items = [];
      for (var order in (response as List)) {
        for (var item in (order['order_items'] as List)) {
          items.add({
            'order_item_id': item['id'],
            'order_id': order['id'],
            'name': item['dishes']['name'],
            'quantity': item['quantity'],
            'price': item['price_at_time'],
            'guisados_selected': item['guisados_selected'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _existingItems = items;
        });
      }
    } catch (e) {
      debugPrint('Error fetching existing items: $e');
    }
  }

  Future<void> _submitOrder(CartProvider cart) async {
    if (cart.items.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;

      String orderId;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      final countRes = await supabase
          .from('orders')
          .select('id')
          .eq('branch_name', Globals.currentBranch)
          .gte('created_at', todayStart);

      final nextFolio = (countRes as List).length + 1;

      if (widget.tableId != null) {
        final existingOrder = await supabase
            .from('orders')
            .select('id, total_amount')
            .eq('table_id', widget.tableId as Object)
            .eq('branch_name', Globals.currentBranch)
            .eq('status', 'pending')
            .maybeSingle();

        if (existingOrder != null) {
          orderId = existingOrder['id'] as String;
          final newTotal = (existingOrder['total_amount'] as num).toDouble() + cart.totalAmount;
          await supabase.from('orders').update({
            'total_amount': newTotal,
          }).eq('id', orderId);
        } else {
          final orderResponse = await supabase.from('orders').insert({
            'table_id': widget.tableId,
            'waiter_id': widget.waiterId,
            'status': 'pending',
            'total_amount': cart.totalAmount,
            'order_type': widget.orderType,
            'customer_name': widget.customerName,
            'branch_name': Globals.currentBranch,
            'daily_folio': nextFolio,
          }).select().single();
          orderId = orderResponse['id'] as String;
        }
      } else {
        final orderResponse = await supabase.from('orders').insert({
          'table_id': null,
          'waiter_id': widget.waiterId,
          'status': 'pending',
          'total_amount': cart.totalAmount,
          'order_type': widget.orderType,
          'customer_name': widget.customerName,
          'branch_name': Globals.currentBranch,
          'daily_folio': nextFolio,
        }).select().single();
        orderId = orderResponse['id'] as String;
      }

      final orderItems = cart.items.values.map((item) => {
            'order_id': orderId,
            'dish_id': item.dish.id,
            'quantity': item.quantity,
            'price_at_time': item.dish.price,
            'status': 'pending',
            'guisados_selected': item.guisados.isNotEmpty
                ? jsonEncode(item.guisados)
                : null,
          }).toList();

      await supabase.from('order_items').insert(orderItems);

      if (widget.tableId != null) {
        await supabase.from('restaurant_tables').update({'status': 'occupied'}).eq('id', widget.tableId as Object);
      }

      if (mounted) {
        cart.clearCart();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¡Comanda Enviada!'),
            content: Text(
              widget.orderType == 'dine_in'
                  ? 'La comanda para la mesa ${widget.tableNumber} se envió a producción.'
                  : 'La comanda para ${widget.customerName ?? 'Cliente'} (${widget.orderType == 'takeout' ? 'Para LLevar' : 'Delivery'}) se envió a producción.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _fetchExistingItems();
                },
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar comanda: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Called by external widgets (e.g. comandas_view) to add a dish to the cart.
  /// If the dish requires a guisado, shows the selector dialog first.
  Future<void> handleAddDish(BuildContext context, Dish dish) async {
    final cart = context.read<CartProvider>();
    if (dish.requiresGuisado) {
      await _showGuisadoSelectorDialog(context, cart, dish);
    } else {
      cart.addItem(dish);
    }
  }

  Future<void> _showGuisadoSelectorDialog(
      BuildContext context, CartProvider cart, Dish dish) async {
    final supabase = Supabase.instance.client;
    List<Map<String, dynamic>> guisados = [];
    List<String> selected = [];

    try {
      final rows = await supabase
          .from('guisados')
          .select()
          .eq('available', true)
          .order('name');
      guisados = (rows as List)
          .cast<Map<String, dynamic>>()
          .where((g) {
            final branch = g['branch_name'] as String?;
            return branch == null || branch == Globals.currentBranch;
          })
          .toList();
    } catch (e) {
      debugPrint('Error cargando guisados: $e');
    }

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                '¿Qué guisado lleva el ${dish.name}?',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              content: guisados.isEmpty
                  ? const Text(
                      'No hay guisados disponibles.',
                      style: TextStyle(color: Colors.white70),
                    )
                  : SizedBox(
                      width: 320,
                      child: ListView(
                        shrinkWrap: true,
                        children: guisados.map((g) {
                          final name = g['name'] as String;
                          final isChecked = selected.contains(name);
                          return CheckboxListTile(
                            value: isChecked,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  selected = [...selected, name];
                                } else {
                                  selected =
                                      selected.where((s) => s != name).toList();
                                }
                              });
                            },
                            title: Text(name,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            checkColor: Colors.white,
                            activeColor: const Color(0xFFFF6D00),
                            side: const BorderSide(color: Color(0xFF94A3B8)),
                          );
                        }).toList(),
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar',
                      style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    cart.addItemWithGuisados(dish, selected);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00).withOpacity(0.15),
                  ),
                  child: const Text('Agregar a la orden',
                      style: TextStyle(color: Color(0xFFFF6D00))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddClientDialog(BuildContext context, CartProvider cart) {
    final nextNumber = cart.clients.length + 1;
    final controller = TextEditingController(text: 'Cliente $nextNumber');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Nuevo cliente', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nombre del cliente',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF6D00)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF6D00), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                cart.addClient(name);
                cart.setCurrentClient(name);
              }
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00).withOpacity(0.15),
            ),
            child: const Text('Agregar', style: TextStyle(color: Color(0xFFFF6D00))),
          ),
        ],
      ),
    );
  }

  void _showRemoveClientDialog(BuildContext context, CartProvider cart, String clientName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Eliminar cliente?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Se eliminarán "$clientName" y todos sus platillos.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              cart.removeClient(clientName);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.15)),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    // Group items by client
    final Map<String, List<MapEntry<String, CartItem>>> grouped = {};
    for (final client in cart.clients) {
      grouped[client] = [];
    }
    for (final entry in cart.items.entries) {
      final label = entry.value.clientLabel;
      grouped.putIfAbsent(label, () => []);
      grouped[label]!.add(entry);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── YA PEDIDO ──────────────────────────────────────────
        if (_existingItems.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'YA PEDIDO (En cuenta)',
              style: TextStyle(
                color: Color(0xFFFF6D00),
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ..._existingItems.map((item) {
            final rawGuisados = item['guisados_selected'] as String?;
            List<String> guisadosList = [];
            if (rawGuisados != null && rawGuisados.isNotEmpty) {
              try {
                guisadosList = (jsonDecode(rawGuisados) as List).cast<String>();
              } catch (_) {}
            }
            return ListTile(
                dense: true,
                title: Text(item['name'], style: const TextStyle(color: Colors.white70)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\$${item['price']} x ${item['quantity']}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    if (guisadosList.isNotEmpty)
                      Text(
                        guisadosList.join(', '),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('x${item['quantity']}',
                        style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
                      onPressed: () => _deleteExistingItem(item),
                    ),
                  ],
                ),
              );
          }),
          const Divider(color: Color(0xFF334155), indent: 16, endIndent: 16),
        ],

        // ── ENCABEZADO NUEVOS ARTÍCULOS ────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: [
              const Text(
                'NUEVOS ARTÍCULOS',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.person_add, size: 16, color: Color(0xFFFF6D00)),
                label: const Text(
                  'Agregar Cliente',
                  style: TextStyle(
                    color: Color(0xFFFF6D00),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00).withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () {
                  final name = 'Cliente ${cart.clients.length + 1}';
                  cart.addClient(name);
                  cart.setCurrentClient(name);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── LISTA AGRUPADA POR CLIENTE ─────────────────────────
        Expanded(
          child: cart.items.isEmpty
              ? Center(
                  child: Text(
                    'Agrega platillos del menú',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final client in cart.clients) ...[
                      if (grouped[client] != null && grouped[client]!.isNotEmpty) ...[
                        // Client header — tap to select, X to remove
                        GestureDetector(
                          onTap: () => cart.setCurrentClient(client),
                          onDoubleTap: () {
                            final controller = TextEditingController(text: client);
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF1E293B),
                                title: const Text('Editar nombre', style: TextStyle(color: Colors.white)),
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
                                  onSubmitted: (v) {
                                    cart.renameClient(client, v);
                                    Navigator.pop(ctx);
                                  },
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      cart.renameClient(client, controller.text);
                                      Navigator.pop(ctx);
                                    },
                                    style: TextButton.styleFrom(backgroundColor: const Color(0xFFFF6D00).withOpacity(0.15)),
                                    child: const Text('Guardar', style: TextStyle(color: Color(0xFFFF6D00))),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: cart.currentClient == client
                                  ? const Color(0xFFFF6D00).withOpacity(0.15)
                                  : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: cart.currentClient == client
                                    ? const Color(0xFFFF6D00)
                                    : const Color(0xFF334155),
                                width: cart.currentClient == client ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  cart.currentClient == client
                                      ? Icons.person
                                      : Icons.person_outline,
                                  color: const Color(0xFFFF6D00),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  client,
                                  style: const TextStyle(
                                    color: Color(0xFFFF6D00),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (cart.currentClient == client) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit, size: 11, color: Color(0xFFFF6D00)),
                                ],
                                const Spacer(),
                                Text(
                                  '\$${grouped[client]!.fold(0.0, (sum, e) => sum + e.value.dish.price * e.value.quantity).toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                if (cart.clients.length > 1) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => cart.removeClient(client),
                                    child: const Icon(Icons.close, size: 15, color: Colors.white30),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // Items for this client
                        for (final entry in grouped[client]!) ...[
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: SizedBox(
                              width: 44,
                              height: 44,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  entry.value.dish.imageUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            title: Text(
                              entry.value.dish.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '\$${entry.value.dish.price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                                if (entry.value.guisados.isNotEmpty)
                                  Text(
                                    entry.value.guisados.join(', '),
                                    style: const TextStyle(
                                        color: Color(0xFF94A3B8), fontSize: 10),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 20, color: Colors.white54),
                                  onPressed: () =>
                                      cart.decrementQuantity(entry.key),
                                ),
                                Text(
                                  '${entry.value.quantity}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 20, color: Color(0xFFFF6D00)),
                                  onPressed: () =>
                                      cart.incrementQuantity(entry.key),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
        ),

        // ── TOTAL GENERAL + BOTÓN ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(
                    '\$${cart.totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_isSubmitting || widget.waiterId == null)
                    ? null
                    : () => _submitOrder(cart),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        widget.waiterId == null
                            ? 'Selecciona Mesero'
                            : 'Enviar a Producción',
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
