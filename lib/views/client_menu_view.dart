import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dish.dart';
import '../providers/cart_provider.dart';
import '../widgets/dish_card.dart';
import 'client_checkout_view.dart';

class ClientMenuView extends StatefulWidget {
  final String orderType;
  final String? tableId;
  final String? tableNumber;
  final String? customerName;

  const ClientMenuView({
    super.key,
    required this.orderType,
    this.tableId,
    this.tableNumber,
    this.customerName,
  });

  @override
  State<ClientMenuView> createState() => _ClientMenuViewState();
}

class _ClientMenuViewState extends State<ClientMenuView> {
  final _supabase = Supabase.instance.client;
  List<Dish> _dishes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDishes();
    // Clear cart when starting a new client session to avoid old items
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().clearCart();
    });
  }

  Future<void> _fetchDishes() async {
    try {
      final response = await _supabase.from('dishes').select();
      final dishes = (response as List).map((data) => Dish.fromJson(data)).toList();
      if (mounted) {
        setState(() {
          _dishes = dishes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar menú: \$e')));
        setState(() => _isLoading = false);
      }
    }
  }

  void _openCheckout() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: ClientCheckoutView(
              orderType: widget.orderType,
              tableId: widget.tableId,
              tableNumber: widget.tableNumber,
              customerName: widget.customerName,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orderType == 'dine_in' 
            ? 'Mesa ${widget.tableNumber}' 
            : 'Menú (${widget.customerName})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: _openCheckout,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dishes.isEmpty
              ? const Center(child: Text('El menú está vacío', style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16).copyWith(bottom: 100), // padding for FAB
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _dishes.length,
                  itemBuilder: (context, index) {
                    final dish = _dishes[index];
                    return DishCard(dish: dish);
                  },
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: cart.itemCount > 0
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FloatingActionButton.extended(
                  onPressed: _openCheckout,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  label: Text(
                    'Ver Carrito (${cart.itemCount}) - \$${cart.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  icon: const Icon(Icons.shopping_cart, color: Colors.white),
                ),
              ),
            )
          : null,
    );
  }
}
