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

  double get _existingTotal => _existingItems.fold(
      0.0,
      (sum, item) =>
          sum +
          (item['price'] as num).toDouble() *
              (item['quantity'] as num).toInt());

  List<String> get _existingOrderIds =>
      _existingItems.map((i) => i['order_id'] as String).toSet().toList();

  Future<double?> _askPropina(BuildContext context, double total) async {
    int selectedPct = -1;
    final customController = TextEditingController();
    double propinaAmount = 0.0;

    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void recalc() {
            if (selectedPct == -1) {
              propinaAmount = 0;
            } else if (selectedPct == 0) {
              propinaAmount = double.tryParse(customController.text) ?? 0;
            } else {
              propinaAmount = total * selectedPct / 100;
            }
          }

          recalc();
          final totalFinal = total + propinaAmount;

          Widget pctBtn(String label, int pct) {
            final active = selectedPct == pct;
            return Expanded(
              child: GestureDetector(
                onTap: () => setS(() {
                  selectedPct = pct;
                  recalc();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFFF6D00)
                        : const Color(0xFFFAF1DE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: active
                            ? const Color(0xFFFF6D00)
                            : const Color(0xFFE5DCC4),
                        width: 1.5),
                  ),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: active
                              ? Color(0xFFFAF1DE)
                              : const Color(0xFFA08F70),
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
              ),
            );
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Row(
              children: [
                Icon(Icons.volunteer_activism,
                    color: Color(0xFFFF6D00), size: 28),
                SizedBox(width: 12),
                Text('¿Desea dejar propina?',
                    style: TextStyle(
                        color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFAF1DE),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total de la cuenta:',
                          style: TextStyle(
                              color: Color(0xFFA08F70), fontSize: 15)),
                      Text('\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Color(0xFFFF6D00),
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  pctBtn('Sin\npropina', -1),
                  pctBtn('10%', 10),
                  pctBtn('15%', 15),
                  pctBtn('20%', 20),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: customController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: Color(0xFFFF6D00),
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Monto personalizado',
                    labelStyle: const TextStyle(color: Color(0xFFA08F70)),
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixIcon: const Icon(Icons.edit, color: Color(0xFFFF6D00)),
                    prefixText: '\$  ',
                    prefixStyle: const TextStyle(
                        color: Color(0xFFFF6D00), fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: const Color(0xFFFAF1DE),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setS(() {
                    selectedPct = 0;
                    recalc();
                  }),
                ),
                const SizedBox(height: 20),
                if (propinaAmount > 0) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFFF6D00).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFFFF6D00)
                              .withValues(alpha: 0.4),
                          width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Propina:',
                                  style: TextStyle(
                                      color: Color(0xFFFF6D00), fontSize: 15)),
                              Text('+\$${propinaAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Color(0xFFFF6D00),
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ]),
                        const Divider(color: Color(0xFFFF6D00), height: 16),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TOTAL A COBRAR:',
                                  style: TextStyle(
                                      color: Color(0xFFFF6D00),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16)),
                              Text('\$${totalFinal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Color(0xFFFF6D00),
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900)),
                            ]),
                      ],
                    ),
                  ),
                ] else ...[
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL A COBRAR:',
                            style: TextStyle(
                                color: Color(0xFF3D2E1A),
                                fontWeight: FontWeight.w900,
                                fontSize: 16)),
                        Text('\$${totalFinal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Color(0xFFFF6D00),
                                fontSize: 26,
                                fontWeight: FontWeight.w900)),
                      ]),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar',
                    style: TextStyle(color: Color(0xFFA08F70))),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, totalFinal),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continuar al cobro',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Color(0xFFFAF1DE),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPaymentDialog(
      BuildContext context, List<String> orderIds, double total) async {
    final tableId = widget.tableId;
    final supabase = Supabase.instance.client;

    String? method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Row(
          children: [
            Icon(Icons.point_of_sale, color: Color(0xFFFF6D00), size: 28),
            SizedBox(width: 12),
            Text('Método de Pago',
                style: TextStyle(
                    color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFFAF1DE),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total a Cobrar:',
                      style:
                          TextStyle(color: Color(0xFFA08F70), fontSize: 16)),
                  Text('\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Color(0xFFFF6D00),
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cash'),
              icon: const Icon(Icons.payments),
              label: const Text('Efectivo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Colors.green,
                foregroundColor: Color(0xFFFAF1DE),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'card'),
              icon: const Icon(Icons.credit_card),
              label: const Text('Tarjeta / TPV',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Color(0xFFFAF1DE),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'clip'),
              icon: const Icon(Icons.contactless),
              label: const Text('Clip',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: const Color(0xFFFF6D00),
                foregroundColor: Color(0xFFFAF1DE),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFFA08F70))),
          ),
        ],
      ),
    );

    if (method == null || !context.mounted) return;

    if (method == 'cash') {
      final cashController = TextEditingController();
      double change = 0.0;

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setS) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Row(
              children: [
                Icon(Icons.payments, color: Colors.green, size: 28),
                SizedBox(width: 12),
                Text('Cobro en Efectivo',
                    style: TextStyle(
                        color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFAF1DE),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total a Cobrar:',
                          style: TextStyle(
                              color: Color(0xFFA08F70), fontSize: 16)),
                      Text('\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Color(0xFFFF6D00),
                              fontSize: 24,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: cashController,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6D00)),
                  decoration: InputDecoration(
                    labelText: 'Monto Recibido',
                    hintText: '0.00',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.attach_money),
                  ),
                  onChanged: (value) {
                    final cash = double.tryParse(value) ?? 0.0;
                    setS(() {
                      change = cash - total;
                      if (change < 0) change = 0;
                    });
                  },
                ),
                const SizedBox(height: 24),
                if (change > 0 ||
                    (double.tryParse(cashController.text) ?? 0) >= total)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text('CAMBIO PARA EL CLIENTE',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text('\$${change.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.green,
                                fontSize: 40,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar',
                    style: TextStyle(color: Color(0xFFA08F70))),
              ),
              ElevatedButton(
                onPressed:
                    (double.tryParse(cashController.text) ?? 0) < total
                        ? null
                        : () async {
                            try {
                              await supabase.from('orders').update({
                                'status': 'completed',
                                'payment_method': 'cash',
                                'amount_cash': total,
                              }).inFilter('id', orderIds);
                              if (tableId != null) {
                                await supabase
                                    .from('restaurant_tables')
                                    .update({'status': 'available'}).eq(
                                        'id', tableId as Object);
                              }
                              if (ctx2.mounted) {
                                Navigator.pop(ctx2);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Pago finalizado con éxito'),
                                        backgroundColor: Colors.green),
                                  );
                                  setState(() => _existingItems = []);
                                }
                              }
                            } catch (e) {
                              if (ctx2.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')));
                              }
                            }
                          },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Color(0xFFFAF1DE),
                  minimumSize: const Size(150, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('FINALIZAR COBRO',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      );
    } else {
      // Tarjeta o Clip — mark as completed directly
      final isClip = method == 'clip';
      try {
        await supabase.from('orders').update({
          'status': 'completed',
          'payment_method': isClip ? 'clip' : 'card',
        }).inFilter('id', orderIds);
        if (tableId != null) {
          await supabase
              .from('restaurant_tables')
              .update({'status': 'available'}).eq('id', tableId as Object);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(isClip
                    ? 'Pago con Clip registrado'
                    : 'Pago con tarjeta registrado'),
                backgroundColor: Colors.green),
          );
          setState(() => _existingItems = []);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _cobrarCuenta(BuildContext context) async {
    final total = _existingTotal;
    final orderIds = _existingOrderIds;
    if (orderIds.isEmpty) return;

    final totalConPropina = await _askPropina(context, total);
    if (totalConPropina == null || !context.mounted) return;

    await _showPaymentDialog(context, orderIds, totalConPropina);
  }

  Future<void> _deleteExistingItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Text('¿Quitar elemento?', style: TextStyle(color: Color(0xFF3D2E1A))),
        content: Text('¿Deseas eliminar "${item['name']}" de la cuenta?', style: const TextStyle(color: Color(0xFF7A6E5A))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70)))),
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

      final orderItems = cart.items.values.map((item) {
        final isDeliveryFee = item.dish.id == CartProvider.deliveryFeeId;
        return {
          'order_id': orderId,
          'dish_id': isDeliveryFee ? null : item.dish.id,
          'quantity': item.quantity,
          'price_at_time': item.dish.price,
          'status': isDeliveryFee ? 'ready' : 'pending',
          'client_label': item.clientLabel,
          'guisados_selected': isDeliveryFee
              ? jsonEncode(['Envío FLASH'])
              : (item.guisados.isNotEmpty ? jsonEncode(item.guisados) : null),
        };
      }).toList();

      await supabase.from('order_items').insert(orderItems);

      if (widget.tableId != null) {
        await supabase.from('restaurant_tables').update({'status': 'occupied'}).eq('id', widget.tableId as Object);
      }

      if (mounted) {
        cart.clearCart(keepDeliveryFee: false);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¡Comanda Enviada!'),
            content: Text(
              widget.orderType == 'dine_in'
                  ? 'La comanda para la mesa ${widget.tableNumber} se envió a producción.'
                  : 'La comanda para ${widget.customerName ?? 'Cliente'} (${widget.orderType == 'takeout' ? 'To Go' : 'Delivery'}) se envió a producción.',
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
              backgroundColor: const Color(0xFFFAF1DE),
              title: Text(
                '¿Qué guisado lleva el ${dish.name}?',
                style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 16),
              ),
              content: guisados.isEmpty
                  ? const Text(
                      'No hay guisados disponibles.',
                      style: TextStyle(color: Color(0xFF7A6E5A)),
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
                                    color: Color(0xFF3D2E1A), fontSize: 14)),
                            checkColor: Color(0xFFFAF1DE),
                            activeColor: const Color(0xFFFF6D00),
                            side: const BorderSide(color: Color(0xFFA08F70)),
                          );
                        }).toList(),
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar',
                      style: TextStyle(color: Color(0xFFA08F70))),
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
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Text('Nuevo cliente', style: TextStyle(color: Color(0xFF3D2E1A))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF3D2E1A)),
          decoration: InputDecoration(
            hintText: 'Nombre del cliente',
            hintStyle: const TextStyle(color: Color(0xFFB6A88A)),
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
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
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
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Text('¿Eliminar cliente?', style: TextStyle(color: Color(0xFF3D2E1A))),
        content: Text(
          'Se eliminarán "$clientName" y todos sus platillos.',
          style: const TextStyle(color: Color(0xFF7A6E5A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
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

  void _showRenameClientDialog(BuildContext context, CartProvider cart, String client) {
    final controller = TextEditingController(text: client);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF1DE),
        title: const Text('Editar nombre', style: TextStyle(color: Color(0xFF3D2E1A))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF3D2E1A)),
          decoration: const InputDecoration(
            hintText: 'Nombre del cliente',
            hintStyle: TextStyle(color: Color(0xFFB6A88A)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6D00))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFFF6D00), width: 2)),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) cart.renameClient(client, v.trim());
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFFA08F70))),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) cart.renameClient(client, name);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(backgroundColor: const Color(0xFFFF6D00).withOpacity(0.15)),
            child: const Text('Guardar', style: TextStyle(color: Color(0xFFFF6D00))),
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
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── LISTA COMPLETA (ya pedido + nuevos artículos) ──────
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              // YA PEDIDO
              if (_existingItems.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                    title: Text(
                      item['name'],
                      style: const TextStyle(color: Color(0xFF7A6E5A)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$${item['price']} x ${item['quantity']}',
                          style: const TextStyle(color: Color(0xFFB6A88A), fontSize: 10),
                        ),
                        if (guisadosList.isNotEmpty)
                          Text(
                            guisadosList.join(', '),
                            style: const TextStyle(color: Color(0xFFA08F70), fontSize: 10),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('x${item['quantity']}',
                            style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
                          onPressed: () => _deleteExistingItem(item),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(color: Color(0xFFE5DCC4), indent: 16, endIndent: 16),
              ],

              // NUEVOS ARTÍCULOS agrupados por cliente
              if (cart.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'Agrega platillos del menú',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                )
              else
                for (final client in cart.clients) ...[
                  if (grouped[client] != null && grouped[client]!.isNotEmpty) ...[
                    // Client header — tap to select, pencil to rename
                    GestureDetector(
                      onTap: () => cart.setCurrentClient(client),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: cart.currentClient == client
                              ? const Color(0xFFFF6D00).withOpacity(0.15)
                              : const Color(0xFFFAF1DE),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: cart.currentClient == client
                                ? const Color(0xFFFF6D00)
                                : const Color(0xFFE5DCC4),
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
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _showRenameClientDialog(context, cart, client),
                              child: const Icon(Icons.edit, size: 16, color: Color(0xFFFF6D00)),
                            ),
                            const Spacer(),
                            Text(
                              '\$${grouped[client]!.fold(0.0, (sum, e) => sum + e.value.dish.price * e.value.quantity).toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFFA08F70), fontSize: 12),
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
                    for (final entry in grouped[client]!)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        title: Text(
                          entry.value.dish.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF3D2E1A)),
                          maxLines: 3,
                          softWrap: true,
                        ),
                        subtitle: Text(
                          '\$${entry.value.dish.price.toStringAsFixed(2)}${entry.value.guisados.isNotEmpty ? ' · ${entry.value.guisados.join(', ')}' : ''}',
                          style: const TextStyle(color: Color(0xFFA08F70), fontSize: 11),
                          maxLines: 3,
                          softWrap: true,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 18, color: Color(0xFFA08F70)),
                              onPressed: () => cart.decrementQuantity(entry.key),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              visualDensity: VisualDensity.compact,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(
                                '${entry.value.quantity}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFFF6D00)),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFFFF6D00)),
                              onPressed: () => cart.incrementQuantity(entry.key),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
            ],
          ),
        ),

        // ── TOTAL GENERAL + BOTONES ────────────────────────────
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 400;
            final btnHeight = isCompact ? 44.0 : 52.0;
            final totalFontSize = isCompact ? 16.0 : 20.0;
            final amountFontSize = isCompact ? 20.0 : 24.0;
            final btnFontSize = isCompact ? 14.0 : 18.0;
            final pad = isCompact ? 10.0 : 16.0;

            return Container(
          padding: EdgeInsets.all(pad),
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
                  Text('Total',
                      style: TextStyle(fontSize: totalFontSize, fontWeight: FontWeight.bold)),
                  Text(
                    '\$${cart.totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: amountFontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 8 : 12),

              if (_existingItems.isNotEmpty) ...[
                ElevatedButton.icon(
                  onPressed: () => _cobrarCuenta(context),
                  icon: Icon(Icons.point_of_sale, size: isCompact ? 18 : 22),
                  label: Text(
                    'Cobrar · \$${_existingTotal.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: btnFontSize, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.fromHeight(btnHeight),
                    backgroundColor: Colors.green,
                    foregroundColor: Color(0xFFFAF1DE),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                SizedBox(height: isCompact ? 6 : 10),
              ],
              ElevatedButton.icon(
                onPressed: (_isSubmitting || widget.waiterId == null || cart.items.isEmpty)
                    ? null
                    : () => _submitOrder(cart),
                icon: _isSubmitting
                    ? SizedBox(
                        height: isCompact ? 16 : 20,
                        width: isCompact ? 16 : 20,
                        child: const CircularProgressIndicator(
                            color: Color(0xFFFAF1DE), strokeWidth: 2))
                    : Icon(Icons.send, size: isCompact ? 18 : 22),
                label: Text(
                  widget.waiterId == null
                      ? 'Selecciona Mesero'
                      : isCompact ? 'Enviar' : 'Enviar a Producción',
                  style: TextStyle(fontSize: btnFontSize),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size.fromHeight(btnHeight),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Color(0xFFFAF1DE),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
            );
          },
        ),
      ],
    );
  }
}
