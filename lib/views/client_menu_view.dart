import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';
import '../models/dish.dart';
import '../providers/cart_provider.dart';
import '../widgets/menu_browser.dart';
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
    Globals.isClientMode = true;
    _fetchDishes();
    // Clear cart when starting a new client session to avoid old items
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().clearCart();
    });
  }

  @override
  void dispose() {
    Globals.isClientMode = false;
    super.dispose();
  }

  Future<void> _fetchDishes() async {
    try {
      final response = await _supabase.from('dishes').select();
      final dishes = (response as List)
          .map((data) => Dish.fromJson(data))
          .where((d) => d.isSale)
          // Las cortesías ($0) son solo para uso interno de caja/mesero:
          // nunca deben poder pedirse desde el menú para el cliente.
          .where((d) => d.category != 'cortesias' && d.price > 0)
          // Refresco de vidrio (355 ml): no se vende en pedidos para llevar.
          .where((d) {
            final n = d.name.toLowerCase();
            return !(n.contains('vidrio') ||
                (n.contains('refresco') && n.contains('355')));
          })
          .toList();
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
          // Botón visible con texto: "Carrito" + número de productos.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _openCheckout,
              icon: Badge(
                isLabelVisible: cart.itemCount > 0,
                label: Text('${cart.itemCount}'),
                child: const Icon(Icons.shopping_cart),
              ),
              label: const Text('Carrito',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dishes.isEmpty
              ? const Center(child: Text('El menú está vacío', style: TextStyle(color: Colors.grey)))
              // Espacio abajo para que el botón "Ir al carrito" no tape la
              // última fila del menú.
              : Padding(
                  padding: EdgeInsets.only(bottom: cart.itemCount > 0 ? 80 : 0),
                  child: MenuBrowser(dishes: _dishes),
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: cart.itemCount > 0
          ? LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = MediaQuery.of(context).size.width < 600;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FloatingActionButton.extended(
                      onPressed: _openCheckout,
                      backgroundColor: const Color(0xFFFF6D00),
                      foregroundColor: Colors.white,
                      label: Text(
                        isMobile
                            ? 'Ir al carrito (${cart.itemCount}) · \$${cart.totalAmount.toStringAsFixed(2)}'
                            : 'Ir al carrito (${cart.itemCount}) - \$${cart.totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 15 : 16),
                      ),
                      icon: const Icon(Icons.shopping_cart, color: Color(0xFFFAF1DE)),
                    ),
                  ),
                );
              },
            )
          : null,
    );
  }
}
