import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dish.dart';
import '../providers/cart_provider.dart';
import '../globals.dart';

Future<void> addDishToCart(BuildContext context, Dish dish) async {
  final cart = context.read<CartProvider>();

  if (!dish.requiresGuisado) {
    cart.addItem(dish);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${dish.name} agregado'),
        duration: const Duration(milliseconds: 500),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ),
    );
    return;
  }

  // Load guisados
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> guisados = [];
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

  List<String> selected = [];

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
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${dish.name} agregado'),
                        duration: const Duration(milliseconds: 500),
                        behavior: SnackBarBehavior.floating,
                        width: 200,
                      ),
                    );
                  }
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

class DishCard extends StatelessWidget {
  final Dish dish;

  const DishCard({super.key, required this.dish});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => addDishToCart(context, dish),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image Section
            Expanded(
              flex: 4,
              child: Image.network(
                dish.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.fastfood, color: Colors.grey),
                ),
              ),
            ),
            // Content Section
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dish.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        dish.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[500],
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final cart = context.watch<CartProvider>();
                        final quantity = cart.items[dish.id]?.quantity ?? 0;
                        
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '\$${dish.price.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (quantity > 0) 
                                  IconButton.filledTonal(
                                    onPressed: () {
                                      context.read<CartProvider>().decrementQuantity(dish.id);
                                    },
                                    icon: const Icon(Icons.remove, size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minHeight: 32,
                                      minWidth: 32,
                                    ),
                                  ),
                                if (quantity > 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      '$quantity',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                IconButton.filledTonal(
                                  onPressed: () => addDishToCart(context, dish),
                                  icon: const Icon(Icons.add, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minHeight: 32,
                                    minWidth: 32,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
