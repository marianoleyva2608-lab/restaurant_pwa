import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
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
            'name': item['dishes']['name'],
            'quantity': item['quantity'],
            'price': item['price_at_time'],
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

      // Calculate daily folio for NEW orders
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

      // Create order items
      final orderItems = cart.items.values.map((item) => {
            'order_id': orderId,
            'dish_id': item.dish.id,
            'quantity': item.quantity,
            'price_at_time': item.dish.price,
            'status': 'pending',
          }).toList();

      await supabase.from('order_items').insert(orderItems);

      // 3. Mark table as occupied
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
                  : 'La comanda para ${widget.customerName ?? 'Cliente'} (${widget.orderType == 'takeout' ? 'Para LLevar' : 'Delivery'}) se envió a producción.'
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _fetchExistingItems(); // Refresh the list of ordered items
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
          SnackBar(content: Text('Error al enviar comanda: \$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final items = cart.items.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          ..._existingItems.map((item) => ListTile(
                dense: true,
                title: Text(item['name'], style: const TextStyle(color: Colors.white70)),
                trailing: Text('x${item['quantity']}', style: const TextStyle(color: Colors.white70)),
              )),
          const Divider(color: Color(0xFF334155), indent: 16, endIndent: 16),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'NUEVOS ARTÍCULOS',
            style: TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty 
            ? Center(child: Text('Agrega platillos del menú', style: TextStyle(color: Colors.grey[600])))
            : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: SizedBox(
                  width: 50,
                  height: 50,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(item.dish.imageUrl, width: 50, height: 50, fit: BoxFit.cover),
                  ),
                ),
                title: Text(item.dish.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('\$${item.dish.price.toStringAsFixed(2)} x ${item.quantity}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: () => cart.decrementQuantity(item.dish.id),
                    ),
                    Text('${item.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () => cart.incrementQuantity(item.dish.id),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                onPressed: (_isSubmitting || widget.waiterId == null) ? null : () => _submitOrder(cart),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting 
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(widget.waiterId == null ? 'Selecciona Mesero' : 'Enviar a Producción', style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
