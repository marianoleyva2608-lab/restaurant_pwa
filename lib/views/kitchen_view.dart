import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';

class KitchenView extends StatefulWidget {
  final bool isTakeoutOnly;
  final bool isDrinksOnly;
  const KitchenView({
    super.key, 
    this.isTakeoutOnly = false,
    this.isDrinksOnly = false,
  });

  @override
  State<KitchenView> createState() => _KitchenViewState();
}

class _KitchenViewState extends State<KitchenView> {
  final _supabase = Supabase.instance.client;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Auto refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isDrinksOnly ? 'Bar de Bebidas' : (widget.isTakeoutOnly ? 'Cocina Para Llevar' : 'Línea de Producción'), 
                 style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Sucursal: ${Globals.currentBranch}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('admin_settings').stream(primaryKey: ['setting_key']).eq('setting_key', 'split_kitchen_mode'),
        builder: (context, settingsSnapshot) {
          // Actualizar valor global en tiempo real si el admin lo cambia
          if (settingsSnapshot.hasData && settingsSnapshot.data!.isNotEmpty) {
            final settingValue = settingsSnapshot.data!.first['setting_value'];
            Globals.splitKitchenMode = settingValue == 'true';
          }

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase
                .from('orders')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: true),
            builder: (context, orderSnapshot) {
              if (orderSnapshot.hasError) {
                return Center(child: Text('Error: ${orderSnapshot.error}'));
              }
              if (!orderSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              // Filtrado de órdenes según modo de cocina
              final orders = orderSnapshot.data!.where((o) {
                final isPending = o['status'] == 'pending';
                final isBranch = o['branch_name'] == Globals.currentBranch;
                final type = o['order_type'] ?? 'dine_in';
                
                if (widget.isDrinksOnly) {
                  // Bar: shows all pending orders that have drinks (filtering done in _OrderTicket)
                  return isPending && isBranch;
                }

                if (widget.isTakeoutOnly) {
                  // Vista especializada: Solo Para Llevar / Delivery
                  return isPending && isBranch && (type == 'takeout' || type == 'delivery');
                } else {
                  // Línea de Producción:
                  if (Globals.splitKitchenMode) {
                    // Modo Dividido: Solo Comensales (Mesa)
                    return isPending && isBranch && type == 'dine_in';
                  } else {
                    // Modo Unificado: TODO (Para Llevar y Dine-In)
                    return isPending && isBranch;
                  }
                }
              }).toList();

              if (orders.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 100, color: Colors.green),
                      SizedBox(height: 16),
                      Text('No hay órdenes pendientes', style: TextStyle(fontSize: 24, color: Colors.grey)),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return _OrderTicket(order: order, isDrinksOnly: widget.isDrinksOnly);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _OrderTicket extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isDrinksOnly;

  const _OrderTicket({required this.order, this.isDrinksOnly = false});

  @override
  State<_OrderTicket> createState() => _OrderTicketState();
}

class _OrderTicketState extends State<_OrderTicket> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>>? _items;
  String? _tableNumber;
  String _orderTypeStr = '...';
  String? _customerName;
  String? _waiterName;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadData();
    _updateElapsed();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateElapsed();
        });
      }
    });
  }

  void _updateElapsed() {
    if (widget.order['created_at'] != null) {
      try {
        final created = DateTime.parse(widget.order['created_at']).toLocal();
        _elapsed = DateTime.now().difference(created);
      } catch (_) {
        _elapsed = Duration.zero;
      }
    }
  }

  int get _maxAllowedMinutes {
    if (_items == null || _items!.isEmpty) return 15;
    int maxT = 0;
    for (var item in _items!) {
      final dish = item['dishes'] as Map<String, dynamic>?;
      final dynamic tRaw = dish?['max_time'];
      final int t = (tRaw is int) ? tRaw : (tRaw is num ? tRaw.toInt() : 15);
      if (t > maxT) maxT = t;
    }
    return maxT == 0 ? 15 : maxT;
  }

  String get _formattedElapsed {
    if (_elapsed.isNegative) return '00:00';
    final minutes = _elapsed.inMinutes;
    final seconds = _elapsed.inSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMins = minutes % 60;
      return '${hours.toString().padLeft(2, '0')}:${remainingMins.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final orderId = widget.order['id'];
    final orderType = widget.order['order_type'] ?? 'dine_in';
    _customerName = widget.order['customer_name'];
    
    // Load table number asynchronously if dine_in
    if (orderType == 'dine_in' && widget.order['table_id'] != null) {
      supabase.from('restaurant_tables').select('table_number').eq('id', widget.order['table_id'] as Object).single().then((value) {
        if (mounted) {
          setState(() {
            _tableNumber = value['table_number'].toString();
            _orderTypeStr = 'Mesa $_tableNumber';
          });
        }
      }).catchError((_) {});
    } else {
      if (mounted) {
        setState(() {
          _orderTypeStr = orderType == 'takeout' ? 'Para Llevar' : 'Delivery';
        });
      }
    }

    // Load waiter name asynchronously
    if (widget.order['waiter_id'] != null) {
      supabase.from('waiters').select('name').eq('id', widget.order['waiter_id']).single().then((value) {
        if (mounted) setState(() => _waiterName = value['name'].toString());
      }).catchError((_) {});
    }

    // Load items
    try {
      final response = await supabase.from('order_items').select('''
        id, quantity, status, price_at_time,
        dishes (name, category, max_time)
      ''').eq('order_id', orderId).order('id');
      
      if (mounted) {
        var itemsList = List<Map<String, dynamic>>.from(response);
        
        // Separar bebidas de comida de manera exhaustiva
        final drinkTerms = [
          'bebidas', 'bebida', 'drink', 'drinks', 'refresco', 'refrescos', 
          'jugo', 'jugos', 'cafe', 'café', 'coffee', 'aguas', 'agua', 
          'licuado', 'licuados', 'soda', 'sodas', 'beverage', 'beverages'
        ];
        
        if (widget.isDrinksOnly) {
          // Bar: Solo bebidas
          itemsList = itemsList.where((item) {
            final dish = item['dishes'] as Map<String, dynamic>?;
            final category = dish?['category']?.toString().toLowerCase().trim() ?? '';
            return drinkTerms.contains(category);
          }).toList();
        } else {
          // Cocina: Excluye absolutamente cualquier bebida
          itemsList = itemsList.where((item) {
            final dish = item['dishes'] as Map<String, dynamic>?;
            final category = dish?['category']?.toString().toLowerCase().trim() ?? '';
            return !drinkTerms.contains(category);
          }).toList();
        }

        setState(() {
          _items = itemsList;
        });
      }
    } catch (e) {
      debugPrint('Error loading items: $e');
      if (mounted) {
        setState(() {
          _items = []; // Para detener el spinner
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando pedido: Verifica que la columna "max_time" exista en "dishes". Error detallado: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          )
        );
      }
    }
  }

  void _toggleItemStatus(int index, bool currentIsReady) async {
    if (_items == null) return;
    
    final item = _items![index];
    final newStatus = currentIsReady ? 'pending' : 'ready';
    
    // Optimistic update for instant UI feedback
    setState(() {
      _items![index]['status'] = newStatus;
    });

    try {
      await supabase
          .from('order_items')
          .update({'status': newStatus})
          .eq('id', item['id']);
    } catch (e) {
      // Revert if error
      if (mounted) {
        setState(() {
          _items![index]['status'] = currentIsReady ? 'ready' : 'pending';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al actualizar estado')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si estamos en modo bebidas y este pedido no tiene bebidas cargadas, ocultamos el ticket
    if (widget.isDrinksOnly && _items != null && _items!.isEmpty) {
      return const SizedBox.shrink();
    }

    final orderId = widget.order['id'];
    final bool isOverTime = _elapsed.inMinutes >= _maxAllowedMinutes;
    final Color warningColor = _elapsed.inSeconds % 2 == 0 ? Colors.red : Colors.orange;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isOverTime ? warningColor.withValues(alpha: 0.15) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverTime ? warningColor : Colors.transparent,
          width: isOverTime ? 5 : 4, // Keep width fixed approx to avoid layout shifts
        ),
        boxShadow: isOverTime ? [
          BoxShadow(
            color: warningColor.withValues(alpha: 0.6),
            blurRadius: 30,
            spreadRadius: 8,
          )
        ] : [
          const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: Color(0xFFFF6D00), width: 6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // URGENT Banner
            if (isOverTime)
              Container(
                color: warningColor,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  '¡URGENTE! TIEMPO EXCEDIDO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    fontSize: 14,
                  ),
                ),
              ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _orderTypeStr,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Folio #${widget.order['daily_folio'] ?? '---'}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFFF6D00)),
                            ),
                            const Text(' • ', style: TextStyle(color: Color(0xFF94A3B8))),
                            Text(
                              widget.order['created_at'] != null 
                                ? widget.order['created_at'].toString().substring(0, 10).split('-').reversed.join('/')
                                : '',
                              style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Servidor: ${_waiterName ?? 'Caja'}${_customerName != null && _customerName!.isNotEmpty ? ' • $_customerName' : ''}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Timer Capsule
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOverTime ? warningColor : const Color(0xFFFF6D00).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isOverTime ? [
                        BoxShadow(color: warningColor.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)
                      ] : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isOverTime ? Icons.warning_amber_rounded : Icons.schedule, 
                             color: isOverTime ? Colors.white : const Color(0xFFFF6D00), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _formattedElapsed,
                          style: TextStyle(
                            color: isOverTime ? Colors.white : const Color(0xFFFF6D00),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(color: Color(0xFF334155), height: 1, thickness: 1),
          
            // Items list
            Expanded(
              child: _items == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items!.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = _items![index];
                        final dishName = item['dishes']['name'];
                        final isReady = item['status'] == 'ready';

                        return InkWell(
                          onTap: () => _toggleItemStatus(index, isReady),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item['quantity']}x ',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: isReady ? Colors.green : Colors.white,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    dishName,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: isReady ? Colors.grey : Colors.white,
                                      decoration: isReady ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                Checkbox(
                                  value: isReady,
                                  activeColor: Colors.green,
                                  onChanged: (bool? value) => _toggleItemStatus(index, isReady),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

          // Action button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Builder(
              builder: (context) {
                bool isAllReady = _items?.every((item) => item['status'] == 'ready') ?? false;
                
                return ElevatedButton.icon(
                  onPressed: () async {
                    if (_items == null) return;

                    if (!isAllReady) {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1E293B),
                          title: const Row(
                            children: [
                              Icon(Icons.warning, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('¿Orden Incompleta?', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                          content: const Text(
                            'Faltan platillos por marcar como listos.\n\nSi continúas, la orden desaparecerá de producción y le avisaremos al mesero que faltan platillos (agotados).',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                              child: const Text('Avisar Platillo Agotado', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );

                      if (confirm != true) return;
                    }

                    try {
                      final finalStatus = isAllReady ? 'ready' : 'incomplete';
                      
                      if (!isAllReady) {
                        num amountToDeduct = 0;
                        List<String> cancelledIds = [];
                        
                        for (var item in _items!) {
                          if (item['status'] == 'pending') {
                            cancelledIds.add(item['id'].toString());
                            num qty = item['quantity'] as num;
                            num p = item['price_at_time'] as num;
                            amountToDeduct += (qty * p);
                          }
                        }

                        if (amountToDeduct > 0) {
                           final orderRes = await supabase.from('orders').select('total_amount').eq('id', orderId).single();
                           num currentTotal = orderRes['total_amount'] as num;
                           num newTotal = currentTotal - amountToDeduct;
                           if (newTotal < 0) newTotal = 0;
                           
                           await Future.wait([
                             supabase.from('orders').update({'status': finalStatus, 'total_amount': newTotal}).eq('id', orderId),
                             supabase.from('order_items').update({'status': 'cancelled'}).inFilter('id', cancelledIds),
                           ]);
                        } else {
                           await supabase.from('orders').update({'status': finalStatus}).eq('id', orderId);
                        }
                      } else {
                        // Update the entire order status
                        await supabase.from('orders').update({'status': finalStatus}).eq('id', orderId);
                      }
                      
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isAllReady ? 'Orden marcada como Lista para entregar' : 'Aviso de platillos agotados enviado al mesero.\nSe descontaron las ausencias del total.')),
                      );
                    } catch (e) {
                      debugPrint('Error: $e');
                    }
                  },
                  icon: Icon(isAllReady ? Icons.done_all : Icons.warning_amber),
                  label: Text(isAllReady ? 'Comanda Lista' : 'Avisar Agotado'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAllReady ? Colors.green : const Color(0xFFFF6D00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                );
              }
            ),
          )
        ],
      ),
      ),
    );
  }
}
