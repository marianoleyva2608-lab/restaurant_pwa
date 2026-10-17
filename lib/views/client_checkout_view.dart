import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/cart_provider.dart';
import '../globals.dart';
import '../services/clip_service.dart';
import '../widgets/clip_brick_widget.dart';

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
  bool _clipDialogOpen = false;
  // Paso 1: revisar el carrito. Paso 2: datos y pago con tarjeta.
  bool _showPayment = false;
  final String _paymentMethod = 'Clip'; // único método disponible
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  // La cuota de envío ahora vive como CartItem dentro del CartProvider
  // (id = CartProvider.deliveryFeeId), por lo que el subtotal/total ya
  // la incluyen automáticamente. No se suma aparte.

  @override
  void initState() {
    super.initState();
    if (widget.orderType == 'delivery' || widget.orderType == 'takeout') {
      _loadSavedDeliveryInfo();
    }
  }

  Future<void> _loadSavedDeliveryInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAddress = prefs.getString('delivery_address') ?? '';
    final savedPhone = prefs.getString('delivery_phone') ?? '';
    if (savedAddress.isNotEmpty && _addressController.text.trim().isEmpty) {
      _addressController.text = savedAddress;
    }
    if (savedPhone.isNotEmpty && _phoneController.text.trim().isEmpty) {
      _phoneController.text = savedPhone;
    }
  }

  bool _isValidEmail(String s) {
    final r = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return r.hasMatch(s.trim());
  }

  /// Flujo de Checkout Redireccionado de Clip:
  /// 1. Crea un Payment Link en la edge function
  /// 2. Abre el link en una nueva pestaña
  /// 3. Muestra un diálogo esperando que el usuario complete el pago
  /// 4. Cuando confirma, crea la orden y manda el ticket
  /// Pago con Clip usando el SDK de Checkout Transparente (JS embebido).
  /// El cliente captura la tarjeta dentro de la app, el SDK la tokeniza, y
  /// el token se manda al edge function para cobrar vía /payments.
  Future<void> _payWithClip(CartProvider cart) async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa un correo válido para recibir el ticket')));
      return;
    }
    // El envío ya viene incluido como CartItem (si aplica) — el total es el subtotal del cart.
    final double finalTotal = cart.totalAmount;
    final items = cart.items.values
        .map((it) => {
              // El envío (Envío FLASH) se incluye como un renglón más del
              // ticket por correo; los platillos llevan su detalle.
              'nombre': it.guisados.isEmpty ||
                      it.dish.id == CartProvider.deliveryFeeId
                  ? it.dish.name
                  : '${it.dish.name} (${it.guisados.join(', ')})',
              'precio': it.dish.price,
              'cantidad': it.quantity,
            })
        .toList();

    setState(() => _clipDialogOpen = true);
    ClipResult? result;
    String? errorMsg;
    bool dismissed = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFFFAF1DE),
            title: const Text('Pago con tarjeta',
                style: TextStyle(color: Color(0xFF3D2E1A))),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Total: \$${finalTotal.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFAF1DE))),
                  const SizedBox(height: 12),
                  ClipBrickWidget(
                    amount: finalTotal,
                    onSubmit: (data) async {
                      final token = data['token_id']?.toString() ?? '';
                      if (token.isEmpty) {
                        setDialogState(() {
                          errorMsg = 'No se recibió token de la tarjeta';
                        });
                        return;
                      }
                      // Procesar pago contra /payments vía edge function.
                      try {
                        result = await ClipService.procesarPago(
                          token: token,
                          amount: finalTotal,
                          email: email,
                          items: items,
                        );
                      } catch (e) {
                        result = ClipResult(
                            approved: false, errorMessage: e.toString());
                      }
                      // 3D Secure: el banco pide verificar la compra.
                      // Mostramos su página y esperamos el resultado final.
                      final r = result;
                      if (r != null &&
                          r.status == 'pending' &&
                          (r.threeDsUrl ?? '').isNotEmpty &&
                          (r.paymentId ?? '').isNotEmpty) {
                        setDialogState(() {
                          errorMsg = 'Completa la verificación de tu banco…';
                        });
                        ClipBrickWidget.show3DS(r.threeDsUrl!);
                        String? st = 'pending';
                        for (var i = 0; i < 100 && st == 'pending'; i++) {
                          await Future.delayed(const Duration(seconds: 3));
                          st = await ClipService.paymentStatus(
                                  paymentId: r.paymentId!) ??
                              'pending';
                        }
                        ClipBrickWidget.hide3DS();
                        result = ClipResult(
                          approved: st == 'approved',
                          paymentId: r.paymentId,
                          status: st,
                          errorMessage: st == 'approved'
                              ? null
                              : (st == 'pending'
                                  ? 'No se completó la verificación del banco'
                                  : 'Pago $st por el banco'),
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    onError: (err) {
                      setDialogState(() {
                        errorMsg = err;
                      });
                    },
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(errorMsg!,
                                style: const TextStyle(
                                    color: Color(0xFFFAF1DE), fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  dismissed = true;
                  Navigator.pop(ctx);
                },
                child: const Text('Cancelar',
                    style: TextStyle(color: Color(0xFFA08F70))),
              ),
            ],
          ),
        );
      },
    );

    if (mounted) setState(() => _clipDialogOpen = false);

    if (dismissed || result == null) return;
    if (!result!.approved) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pago rechazado: ${result!.errorMessage ?? result!.detail ?? "Inténtalo de nuevo"}'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    // Pago aprobado → crear orden + mandar ticket.
    final paymentId = result!.paymentId ?? 'CLIP-${DateTime.now().millisecondsSinceEpoch}';
    await _createOrderAndNotify(
      cart: cart,
      finalTotal: finalTotal,
      paymentMethodForDb: 'clip',
      onAfterCreate: () async {
        try {
          await ClipService.enviarTicket(
            email: email,
            paymentId: paymentId,
            total: finalTotal,
            items: items,
          );
        } catch (_) {}
      },
    );
  }

  Future<void> _submitOrder(CartProvider cart) async {
    if (cart.items.isEmpty) return;
    if (widget.orderType == 'delivery' && _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, ingresa tu dirección de entrega')));
      return;
    }
    if ((widget.orderType == 'takeout' || widget.orderType == 'delivery') &&
        _phoneController.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa tu teléfono a 10 dígitos para avisarte de tu pedido')));
      return;
    }
    if (_paymentMethod == 'Clip') {
      await _payWithClip(cart);
      return;
    }

    // El envío ya viene incluido como CartItem (si aplica) — el total es el subtotal del cart.
    final double finalTotal = cart.totalAmount;
    final String? paymentMethodForDb =
        _paymentMethod == 'Tarjeta' ? 'card' : null;
    await _createOrderAndNotify(
      cart: cart,
      finalTotal: finalTotal,
      paymentMethodForDb: paymentMethodForDb,
    );
  }

  /// Construye la URL pública del ticket virtual para el QR.
  /// Formato: `<origin>/#/ticket/<orderId>` (hash routing de Flutter web).
  /// En dev (mobile/desktop) usa un placeholder para que el QR no falle.
  String _buildTicketUrl(String orderId) {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/#/ticket/$orderId';
    }
    return 'https://gorditasmh.com/#/ticket/$orderId';
  }

  /// Crea la orden y muestra el diálogo de éxito.
  /// [onAfterCreate] se ejecuta después de crear la orden (ej. enviar ticket).
  Future<void> _createOrderAndNotify({
    required CartProvider cart,
    required double finalTotal,
    String? paymentMethodForDb,
    Future<void> Function()? onAfterCreate,
  }) async {
    setState(() => _isSubmitting = true);

    try {
      // Create a combined name to store the payment method, address and phone
      String combinedCustomerName = widget.customerName ?? 'Cliente';
      combinedCustomerName += ' (Pago: $_paymentMethod)';
      if (widget.orderType == 'delivery') {
        combinedCustomerName += ' - DIR: ${_addressController.text.trim()}';
        final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
        if (phone.isNotEmpty) {
          combinedCustomerName += ' - TEL: $phone';
        }
        // Persistir los datos para próximas órdenes (por si se editaron aquí)
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('delivery_address', _addressController.text.trim());
          prefs.setString('delivery_phone', phone);
        });
      } else if (widget.orderType == 'takeout') {
        final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
        if (phone.isNotEmpty) {
          combinedCustomerName += ' - TEL: $phone';
        }
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setString('delivery_phone', phone));
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
          final updateData = <String, dynamic>{
            'total_amount': newTotal,
            'customer_name': combinedCustomerName,
          };
          if (paymentMethodForDb != null) {
            updateData['payment_method'] = paymentMethodForDb;
          }
          await _supabase.from('orders').update(updateData).eq('id', orderId);
        } else {
          // Obtener el branch_name desde la mesa para que la cocina filtre correctamente
          String? branchFromTable;
          try {
            final tableRow = await _supabase
                .from('restaurant_tables')
                .select('branch_name')
                .eq('id', widget.tableId as Object)
                .maybeSingle();
            branchFromTable = tableRow?['branch_name'] as String?;
          } catch (_) {}
          final orderResponse = await _supabase.from('orders').insert({
            'table_id': widget.tableId,
            'branch_name': branchFromTable ?? Globals.currentBranch,
            'waiter_id': null,
            'status': 'pending',
            'total_amount': finalTotal,
            'order_type': widget.orderType,
            'customer_name': combinedCustomerName,
            if (paymentMethodForDb != null) 'payment_method': paymentMethodForDb,
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
          if (paymentMethodForDb != null) 'payment_method': paymentMethodForDb,
        }).select().single();
        orderId = orderResponse['id'] as String;
      }

      final orderItems = cart.items.values.map((item) {
        final isDeliveryFee = item.dish.id == CartProvider.deliveryFeeId;
        return {
          'order_id': orderId,
          // El envío no es un platillo real → dish_id: null (la columna lo permite).
          'dish_id': isDeliveryFee ? null : item.dish.id,
          'quantity': item.quantity,
          'price_at_time': item.dish.price,
          // El envío se marca como listo: la cocina no lo prepara.
          'status': isDeliveryFee ? 'ready' : 'pending',
          // Guisados / sabor / opciones (con queso, tamaño, etc.) igual que
          // en la tablet del mesero, para que salgan en la comanda y en el
          // ticket. El envío guarda la etiqueta "Envío FLASH".
          'guisados_selected': isDeliveryFee
              ? jsonEncode(['Envío FLASH'])
              : (item.guisados.isNotEmpty ? jsonEncode(item.guisados) : null),
          'client_label': item.clientLabel,
        };
      }).toList();

      await _supabase.from('order_items').insert(orderItems);

      // Pedido ya PAGADO con Clip → se manda a cocina de una vez (sin esperar
      // aprobación del mesero). El print-worker solo imprime órdenes con
      // sent_to_kitchen_at; se marca DESPUÉS de insertar los items para que
      // el realtime UPDATE ya los encuentre. También se asigna folio del día
      // (mismo criterio que order_summary.dart).
      if (paymentMethodForDb == 'clip') {
        try {
          final now = DateTime.now();
          final todayStart =
              DateTime(now.year, now.month, now.day).toIso8601String();
          final ord = await _supabase
              .from('orders')
              .select('branch_name, daily_folio')
              .eq('id', orderId)
              .maybeSingle();
          final branch =
              (ord?['branch_name'] as String?) ?? Globals.currentBranch;
          final countRes = await _supabase
              .from('orders')
              .select('id')
              .eq('branch_name', branch)
              .gte('created_at', todayStart);
          await _supabase.from('orders').update({
            if (ord?['daily_folio'] == null)
              'daily_folio': (countRes as List).length,
            'sent_to_kitchen_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', orderId);
        } catch (e) {
          debugPrint('No se pudo mandar a cocina la orden $orderId: $e');
        }
      }

      if (widget.tableId != null) {
        await _supabase.from('restaurant_tables').update({'status': 'occupied'}).eq('id', widget.tableId as Object);
      }

      if (onAfterCreate != null) await onAfterCreate();

      if (mounted) {
        // Orden enviada → limpiamos TODO incluyendo el envío.
        cart.clearCart(keepDeliveryFee: false);

        final ticketUrl = _buildTicketUrl(orderId);
        final subtitle = widget.orderType == 'dine_in'
            ? 'Tu orden para la mesa ${widget.tableNumber} ha sido enviada a producción.\n\nMétodo de pago: $_paymentMethod.'
            : widget.orderType == 'delivery'
                ? 'Tu pedido a domicilio está en camino de preparación.\n\nTotal a pagar (con envío): \$${finalTotal.toStringAsFixed(2)}.'
                : 'Tu pedido To Go está en producción.\n\nMétodo de pago: $_paymentMethod.\nTotal a pagar: \$${finalTotal.toStringAsFixed(2)}';

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('¡Orden Enviada!', style: TextStyle(color: Colors.green)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(subtitle, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Escanea para ver tu ticket',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: QrImageView(
                      data: ticketUrl,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    ticketUrl,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
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
    // El envío ya es un CartItem dentro del cart — no se suma aparte.
    final double deliveryFee = cart.deliveryFee;
    final double subtotalSinEnvio = cart.totalAmount - deliveryFee;
    final double finalTotal = cart.totalAmount;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_showPayment ? 'Pago' : 'Tu carrito'),
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
          // Todo se desplaza junto: primero la lista COMPLETA de lo que el
          // cliente se lleva (para revisarla) y abajo los datos y el pago.
          : ListView(
              children: [
                if (!_showPayment) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    'Revisa tu pedido (${cart.itemCount} ${cart.itemCount == 1 ? 'producto' : 'productos'})',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3D2E1A)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.zero,
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isDeliveryFee =
                          item.dish.id == CartProvider.deliveryFeeId;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: isDeliveryFee
                              ? Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6D00)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.delivery_dining,
                                      color: Color(0xFFFF6D00), size: 28),
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(item.dish.imageUrl,
                                      width: 50, height: 50, fit: BoxFit.cover),
                                ),
                          title: Text(item.dish.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          // Detalle de lo que se lleva: guisados, sabor,
                          // tamaño, extras… para que el cliente lo revise.
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isDeliveryFee && item.guisados.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                                  child: Text(
                                    item.guisados.join(' · '),
                                    style: const TextStyle(
                                        fontSize: 13, color: Color(0xFF3D2E1A)),
                                  ),
                                ),
                              Text(isDeliveryFee
                                  ? '\$${item.dish.price.toStringAsFixed(2)}'
                                  : '\$${item.dish.price.toStringAsFixed(2)} c/u · Subtotal \$${(item.dish.price * item.quantity).toStringAsFixed(2)}'),
                            ],
                          ),
                          trailing: isDeliveryFee
                              ? null
                              : Row(
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
                // Total + botón para pasar al pago
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF6D00))),
                          Text('\$${cart.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF6D00))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _showPayment = true),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continuar al pago',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          backgroundColor: const Color(0xFFFC4C02),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Seguir agregando productos'),
                      ),
                    ],
                  ),
                ),
                ],
                if (_showPayment)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF1DE), // Slate-800
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -5))],
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _showPayment = false),
                            icon: const Icon(Icons.arrow_back),
                            label: Text('Regresar al carrito (${cart.itemCount})'),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                          const SizedBox(height: 12),
                        ],
                        if (widget.orderType == 'delivery' || widget.orderType == 'takeout') ...[
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Teléfono (obligatorio)',
                              hintText: '10 dígitos',
                              prefixIcon: const Icon(Icons.phone),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Subtotal:', style: TextStyle(color: Colors.grey)),
                            Text('\$${subtotalSinEnvio.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF3D2E1A))),
                          ],
                        ),
                        if (deliveryFee > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Envío FLASH:', style: TextStyle(color: Colors.grey)),
                              Text('\$${deliveryFee.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                        const Divider(height: 32, color: Colors.grey),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total a Pagar:', style: TextStyle(fontSize: isMobile ? 15 : 18, fontWeight: FontWeight.bold, color: Color(0xFFFF6D00))),
                            Text(
                              '\$${finalTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: isMobile ? 20 : 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('Método de Pago:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 14 : 16)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFC4C02).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFC4C02), width: 1.5),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.contactless, color: Color(0xFFFC4C02), size: 26),
                              SizedBox(width: 12),
                              Text('Pago con tarjeta',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFC4C02))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Correo para recibir el ticket',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (!_clipDialogOpen) ...[
                          ElevatedButton.icon(
                            onPressed: _isSubmitting ? null : () => _submitOrder(cart),
                            icon: _isSubmitting
                                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Color(0xFFFAF1DE), strokeWidth: 2))
                                : const Icon(Icons.contactless, color: Color(0xFFFAF1DE)),
                            label: Text(
                              _isSubmitting ? 'Procesando...' : 'Pagar con tarjeta',
                              style: TextStyle(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold, color: Color(0xFFFFFFFF)),
                            ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: const Color(0xFFFC4C02),
                              foregroundColor: Color(0xFFFAF1DE),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Simula un pago aprobado sin llamar a Clip — útil para probar el flujo
  /// de orden + cocina + ticket sin depender del SDK de pago.
  // ignore: unused_element
  Future<void> _simularPagoDemo(CartProvider cart) async {
    if (cart.items.isEmpty) return;
    if (widget.orderType == 'delivery' &&
        _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Por favor, ingresa tu dirección de entrega')));
      return;
    }
    final email = _emailController.text.trim();
    // El envío ya viene incluido como CartItem (si aplica) — el total es el subtotal del cart.
    final double finalTotal = cart.totalAmount;
    final items = cart.items.values
        .map((it) => {
              // El envío (Envío FLASH) se incluye como un renglón más del
              // ticket por correo; los platillos llevan su detalle.
              'nombre': it.guisados.isEmpty ||
                      it.dish.id == CartProvider.deliveryFeeId
                  ? it.dish.name
                  : '${it.dish.name} (${it.guisados.join(', ')})',
              'precio': it.dish.price,
              'cantidad': it.quantity,
            })
        .toList();
    final fakePaymentId =
        'DEMO-CLIP-${DateTime.now().millisecondsSinceEpoch}';

    await _createOrderAndNotify(
      cart: cart,
      finalTotal: finalTotal,
      paymentMethodForDb: 'clip',
      onAfterCreate: () async {
        if (_isValidEmail(email)) {
          try {
            await ClipService.enviarTicket(
              email: email,
              paymentId: fakePaymentId,
              total: finalTotal,
              items: items,
            );
          } catch (_) {}
        }
      },
    );
  }
}
