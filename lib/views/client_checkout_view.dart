import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../globals.dart';

class ClientCheckoutView extends StatefulWidget {
  final String orderType;
  final String? tableId;
  final String? tableNumber;
  final String? customerName;

  const ClientCheckoutView({
    super.key,
    required this.orderType,
    this.tableId,
    this.tableNumber,
    this.customerName,
  });

  @override
  State<ClientCheckoutView> createState() => _ClientCheckoutViewState();
}

class _ClientCheckoutViewState extends State<ClientCheckoutView> {
  final _supabase = Supabase.instance.client;
  bool _isSubmitting = false;
  String _paymentMethod = 'Efectivo'; // 'Efectivo' or 'Tarjeta'
  final _addressController = TextEditingController();
  final double _shippingCost = 35.0;

  Future<void> _submitOrder(CartProvider cart) async {
    if (cart.items.isEmpty) return;
    if (widget.orderType == 'delivery' && _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, ingresa tu dirección de entrega')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      double shippingToApply = widget.orderType == 'delivery' ? _shippingCost : 0.0;
      double finalTotal = cart.totalAmount + shippingToApply;

      // Create a combined name to store the payment method and address
      String combinedCustomerName = widget.customerName ?? 'Cliente';
      combinedCustomerName += ' (Pago: $_paymentMethod)';
      if (widget.orderType == 'delivery') {
        combinedCustomerName += ' - DIR: ${_addressController.text.trim()}';
      }

      String orderId;

      if (widget.tableId != null) {
        final existingOrder = await _supabase
            .from('orders')
            .select('id, total_amount')
            .eq('table_id', widget.tableId as Object)
            .eq('status', 'pending')
            .maybeSingle();

        if (existingOrder != null) {
          orderId = existingOrder['id'] as String;
          final newTotal = (existingOrder['total_amount'] as num).toDouble() + cart.totalAmount;
          await _supabase.from('orders').update({
            'total_amount': newTotal,
            'customer_name': combinedCustomerName,
          }).eq('id', orderId);
        } else {
          final orderResponse = await _supabase.from('orders').insert({
            'table_id': widget.tableId,
            'waiter_id': null, 
            'status': 'pending',
            'total_amount': finalTotal,
            'order_type': widget.orderType,
            'customer_name': combinedCustomerName,
          }).select().single();
          orderId = orderResponse['id'] as String;
        }
      } else {
        // Takeout/Delivery
        final orderResponse = await _supabase.from('orders').insert({
          'table_id': null, 'branch_name': Globals.currentBranch, 
          'waiter_id': null,
          'status': 'pending',
          'total_amount': finalTotal,
          'order_type': widget.orderType,
          'customer_name': combinedCustomerName,
        }).select().single();
        orderId = orderResponse['id'] as String;
      }

      final orderItems = cart.items.values.map((item) => {
            'order_id': orderId,
            'dish_id': item.dish.id,
            'quantity': item.quantity,
            'price_at_time': item.dish.price,
            'status': 'pending', 
          }).toList();

      await _supabase.from('order_items').insert(orderItems);

      if (widget.tableId != null) {
        await _supabase.from('restaurant_tables').update({'status': 'occupied'}).eq('id', widget.tableId as Object);
      }

      if (mounted) {
        cart.clearCart();
        
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('¡Orden Enviada!', style: TextStyle(color: Colors.green)),
            content: Text(
              widget.orderType == 'dine_in' 
                ? 'Tu orden para la mesa ${widget.tableNumber} ha sido enviada a producción.\n\nMétodo de pago: $_paymentMethod.'
                : widget.orderType == 'delivery'
                  ? 'Tu pedido a domicilio está en camino de preparación.\n\nTotal a pagar (con envío): \$${finalTotal.toStringAsFixed(2)}.'
                  : 'Tu pedido para llevar está en producción.\n\nMétodo de pago: $_paymentMethod.\nTotal a pagar: \$${finalTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Terminar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al procesar la orden: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final items = cart.items.values.toList();
    final double shippingToApply = widget.orderType == 'delivery' ? _shippingCost : 0.0;
    final double finalTotal = cart.totalAmount + shippingToApply;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Resumen y Pago'),
        leading: null,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('No hay artículos en tu pedido.', style: TextStyle(color: Colors.grey)))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(item.dish.imageUrl, width: 50, height: 50, fit: BoxFit.cover),
                          ),
                          title: Text(item.dish.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('\$${item.dish.price.toStringAsFixed(2)} c/u'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                onPressed: () => cart.decrementQuantity(item.dish.id),
                              ),
                              Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                onPressed: () => cart.incrementQuantity(item.dish.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B), // Slate-800
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -5))],
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.orderType == 'delivery') ...[
                          const Text('Dirección de Envío:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _addressController,
                            decoration: InputDecoration(
                              hintText: 'Ej. Calle 5 de Mayo #123, Col. Centro',
                              prefixIcon: const Icon(Icons.location_on),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Subtotal:', style: TextStyle(color: Colors.grey)),
                            Text('\$${cart.totalAmount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                        if (widget.orderType == 'delivery') ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Envío:', style: TextStyle(color: Colors.grey)),
                              Text('\$${_shippingCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amber)),
                            ],
                          ),
                        ],
                        const Divider(height: 32, color: Colors.grey),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total a Pagar:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            Text(
                              '\$${finalTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Método de Pago:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Theme.of(context).colorScheme.primary.withValues(alpha: 0.2);
                              }
                              return Colors.transparent;
                            }),
                          ),
                          segments: const [
                            ButtonSegment(value: 'Efectivo', label: Text('Efectivo (Pagar en caja)'), icon: Icon(Icons.money)),
                            ButtonSegment(value: 'Tarjeta', label: Text('Tarjeta (TPV)'), icon: Icon(Icons.credit_card)),
                          ],
                          selected: {_paymentMethod},
                          onSelectionChanged: (newSelection) {
                            setState(() => _paymentMethod = newSelection.first);
                          },
                        ),
                        if (widget.orderType == 'takeout') ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.amber, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Al ser pedido para llevar, favor de pasar a la caja para realizar su pago.',
                                    style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _isSubmitting ? null : () => _submitOrder(cart),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Confirmar y Enviar a Producción', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
