import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dish.dart';
import '../providers/cart_provider.dart';
import '../globals.dart';

/// Devuelve la imagen del platillo o un placeholder con el icono de la categoría.
/// Si no hay URL válida muestra el icono grande de la categoría con un gradiente.
Widget _dishImageOrIcon(Dish dish, {IconData? overrideIcon}) {
  final url = dish.imageUrl;
  final hasUrl = url.isNotEmpty && url.startsWith('http');
  final icon = overrideIcon ?? Globals.categoryIcon(dish.category);
  final placeholder = Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.grey.shade800, Colors.grey.shade900],
      ),
    ),
    alignment: Alignment.center,
    child: Icon(icon, color: const Color(0xFFFF6D00), size: 56),
  );
  if (!hasUrl) return placeholder;
  return Image.network(
    url,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => placeholder,
  );
}

const _refrescoFallback = [
  'Coca-Cola', 'Pepsi', 'Sprite', 'Fanta Naranja', 'Fanta Uva',
  '7-Up', 'Manzanita Sol', 'Squirt', 'Mirinda', 'Del Valle',
  'Sidral Mundet', 'Sangría Señorial', 'Agua Mineral', 'Otro',
];

const _aguaFallback = [
  'Jamaica', 'Horchata', 'Tamarindo', 'Limón', 'Naranja',
  'Pepino', 'Melón', 'Sandía', 'Guayaba', 'Fresa', 'Maracuyá', 'Otro',
];

const _jugoFallback = [
  'Naranja', 'Zanahoria', 'Verde', 'Piña', 'Manzana', 'Betabel', 'Otro',
];

Future<List<String>> _loadDrinkFlavors(String type) async {
  try {
    final supabase = Supabase.instance.client;
    List<String> types;
    if (type == 'refresco') {
      types = ['refresco', 'refresco_255', 'refresco_355', 'refresco_600'];
    } else if (type == 'refresco_355') {
      // Incluye también refresco_255 por compatibilidad con datos previos
      types = ['refresco_355', 'refresco_255', 'refresco'];
    } else if (type.startsWith('agua_')) {
      types = [type, 'agua_fresca'];
    } else if (type == 'jugo_330' || type == 'jugo_1litro') {
      types = [type, 'jugo'];
    } else {
      types = [type];
    }
    final rows = await supabase
        .from('drink_flavors')
        .select('name')
        .inFilter('type', types)
        .eq('available', true)
        .order('name');
    final list = (rows as List)
        .map((r) => r['name'] as String)
        .toSet()
        .toList()..sort();
    if (list.isNotEmpty) return list;
    if (type.startsWith('refresco')) return _refrescoFallback;
    if (type.startsWith('jugo')) return _jugoFallback;
    return _aguaFallback;
  } catch (_) {
    if (type.startsWith('refresco')) return _refrescoFallback;
    if (type.startsWith('jugo')) return _jugoFallback;
    return _aguaFallback;
  }
}

Future<double?> _loadDrinkPrice(String type) async {
  try {
    final supabase = Supabase.instance.client;
    final row = await supabase
        .from('drink_type_prices')
        .select('price')
        .eq('type', type)
        .maybeSingle();
    if (row != null) return (row['price'] as num).toDouble();
  } catch (_) {}
  return null;
}

String _formatDrinkSizeLabel(String type) {
  // Strip category prefix (refresco_, agua_, jugo_)
  final suffix = type.replaceFirst(RegExp(r'^(refresco|agua|jugo)_'), '');
  if (suffix == '1litro' || suffix == '1_litro') return '1 litro';
  if (RegExp(r'^\d+ml$').hasMatch(suffix)) return '${suffix.replaceAll('ml', '')} ml';
  if (RegExp(r'^\d+$').hasMatch(suffix)) return '$suffix ml';
  return suffix;
}

Future<void> addDishToCart(BuildContext context, Dish dish) async {
  final cart = context.read<CartProvider>();
  final nameLower = dish.name.toLowerCase();
  final bool isRefresco = nameLower.contains('refresco');
  final bool isAguaFresca = (nameLower.contains('agua fresca') || nameLower.startsWith('agua')) &&
      !nameLower.contains('natural');
  final bool isJugo = dish.category == 'jugos' || nameLower.contains('jugo');

  if (isRefresco || isAguaFresca || isJugo) {
    final categoryPrefix = isJugo ? 'jugo' : isRefresco ? 'refresco' : 'agua';
    final drinkIcon = isJugo ? Icons.blender : isRefresco ? Icons.sports_bar : Icons.local_drink;

    // Cargar tamaños desde drink_type_prices
    List<Map<String, dynamic>> drinkSizes = [];
    try {
      final supabase = Supabase.instance.client;
      final rows = await supabase.from('drink_type_prices').select('type, price').order('price');
      drinkSizes = (rows as List).cast<Map<String, dynamic>>()
          .where((r) => (r['type'] as String).startsWith(categoryPrefix))
          .toList();
    } catch (_) {}

    // Precargar sabores por cada tipo de tamaño
    final Map<String, List<String>> flavorsByType = {};
    for (final s in drinkSizes) {
      final t = s['type'] as String;
      flavorsByType[t] = await _loadDrinkFlavors(t);
    }
    // Sabores genéricos (sin tamaño) como fallback
    final genericFlavors = await _loadDrinkFlavors(categoryPrefix);

    String? selectedSizeType; // e.g. 'refresco_600', 'agua_500ml'
    String? selectedSabor;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Sabores según el tamaño seleccionado
            final currentSabores = selectedSizeType != null
                ? (flavorsByType[selectedSizeType!] ?? genericFlavors)
                : flavorsByType.values.fold<Set<String>>({}, (s, l) => s..addAll(l)).toList()..sort();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                isRefresco ? '¿De qué sabor/marca?' : isJugo ? '¿Qué jugo?' : '¿De qué sabor?',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (drinkSizes.isNotEmpty) ...[
                        const Text('TAMAÑO',
                            style: TextStyle(color: Colors.white70, fontSize: 11,
                                fontWeight: FontWeight.w600, letterSpacing: 1)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: drinkSizes.map((s) {
                            final type = s['type'] as String;
                            final label = _formatDrinkSizeLabel(type);
                            return _ToggleOption(
                              icon: drinkIcon,
                              label: label,
                              value: selectedSizeType == type,
                              onChanged: (v) => setDialogState(() {
                                selectedSizeType = v ? type : null;
                                // reset sabor si no está en los sabores del nuevo tamaño
                                if (selectedSabor != null &&
                                    !(flavorsByType[selectedSizeType ?? ''] ?? genericFlavors)
                                        .contains(selectedSabor)) {
                                  selectedSabor = null;
                                }
                              }),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Color(0xFF334155)),
                        const SizedBox(height: 8),
                      ],
                      const Text('SABOR',
                          style: TextStyle(color: Colors.white70, fontSize: 11,
                              fontWeight: FontWeight.w600, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 6,
                          childAspectRatio: 2.4,
                        ),
                        itemCount: currentSabores.length,
                        itemBuilder: (ctx3, i) {
                          final sabor = currentSabores[i];
                          final isSelected = selectedSabor == sabor;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setDialogState(() => selectedSabor = sabor),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                                    : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF334155),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      sabor,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: selectedSabor == null ? null : () async {
                    Navigator.pop(ctx);
                    final sizeLabel = selectedSizeType != null
                        ? _formatDrinkSizeLabel(selectedSizeType!)
                        : null;
                    final extras = [
                      if (sizeLabel != null) sizeLabel,
                      selectedSabor!,
                    ];
                    Dish finalDish = dish;
                    if (selectedSizeType != null) {
                      final price = await _loadDrinkPrice(selectedSizeType!);
                      if (price != null) finalDish = dish.copyWith(price: price);
                    }
                    cart.addItemWithGuisados(finalDish, extras);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${dish.name} ($selectedSabor) agregado'),
                          duration: const Duration(milliseconds: 500),
                          behavior: SnackBarBehavior.floating,
                          width: 260,
                        ),
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                  ),
                  child: const Text('Agregar a la orden', style: TextStyle(color: Color(0xFFFF6D00))),
                ),
              ],
            );
          },
        );
      },
    );
    return;
  }

  final bool isChilaquil = dish.category == 'chilaquiles' ||
      dish.name.toLowerCase().contains('chilaquil');
  final bool isArrachera = dish.category == 'arrachera' ||
      nameLower.contains('arrachera');

  // Bebidas que no necesitan modal (agua natural, té, leche simple, etc.)
  final bool isBebidaSimple = (dish.category == 'aguas' ||
          dish.category == 'cafes' ||
          dish.category == 'drink' ||
          dish.category == 'bebidas') &&
      !isRefresco &&
      !isAguaFresca &&
      !isJugo;
  if (isBebidaSimple) {
    cart.addItemWithGuisados(dish, []);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${dish.name} agregado'),
        duration: const Duration(milliseconds: 500),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ));
    }
    return;
  }

  if (isArrachera) {
    cart.addItemWithGuisados(dish, []);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${dish.name} agregado'),
        duration: const Duration(milliseconds: 500),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ));
    }
    return;
  }

  final bool isHuevo = dish.category == 'huevos' ||
      nameLower.contains('huevo');

  if (isHuevo) {
    const terminosHuevo = ['Tierno', 'Cocido', 'Sellados'];
    String? selectedTermino;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(dish.name, style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TÉRMINO DEL HUEVO',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1),
              ),
              const SizedBox(height: 10),
              Row(
                children: terminosHuevo.map((termino) {
                  final isSelected = selectedTermino == termino;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setDialogState(() => selectedTermino = termino),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF334155),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                              size: 16,
                              color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              termino,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white60,
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: selectedTermino == null ? null : () {
                Navigator.pop(ctx);
                cart.addItemWithGuisados(dish, ['Huevo $selectedTermino']);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${dish.name} ($selectedTermino) agregado'),
                    duration: const Duration(milliseconds: 500),
                    behavior: SnackBarBehavior.floating,
                    width: 260,
                  ));
                }
              },
              style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00).withValues(alpha: 0.15)),
              child: const Text('Agregar a la orden',
                  style: TextStyle(color: Color(0xFFFF6D00))),
            ),
          ],
        ),
      ),
    );
    return;
  }

  if (!dish.requiresGuisado && !isChilaquil) {
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
  final bool isGordita = dish.category == 'gorditas' ||
      dish.name.toLowerCase().contains('gordita');
  final bool isTapa = dish.category == 'tapas' ||
      dish.name.toLowerCase().contains('tapa');
  final bool showOptions = isGordita || isTapa || isChilaquil;
  final bool canBeFrita = isGordita && !dish.name.toLowerCase().contains('harina');
  bool conQueso = false;
  bool conHuevo = false; // solo para chilaquiles
  bool frita = false;
  String? selectedSalsa; // solo para chilaquiles
  String? selectedTerminoHuevo; // solo para chilaquiles con huevo

  const salsasChilaquil = ['Roja', 'Verde', 'Ranchera'];
  const terminosHuevo = ['Tierno', 'Cocido', 'Sellados'];

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(
              isChilaquil
                  ? '¿Cómo quieres los ${dish.name}?'
                  : '¿Qué guisado lleva el ${dish.name}?',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Toggles de queso y frita
                  if (showOptions) ...[
                    const Text(
                      'Opciones',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (isChilaquil)
                          _ToggleOption(
                            icon: Icons.egg,
                            label: 'Con Huevo',
                            value: conHuevo,
                            onChanged: (v) => setDialogState(() {
                              conHuevo = v;
                              if (!v) selectedTerminoHuevo = null;
                            }),
                          )
                        else
                          _ToggleOption(
                            icon: Icons.egg_alt,
                            label: 'Con Queso',
                            value: conQueso,
                            onChanged: (v) => setDialogState(() => conQueso = v),
                          ),
                        if (isGordita) ...[
                          const SizedBox(width: 10),
                          _ToggleOption(
                            icon: Icons.local_fire_department,
                            label: 'Frita',
                            value: frita,
                            enabled: canBeFrita,
                            onChanged: canBeFrita
                                ? (v) => setDialogState(() => frita = v)
                                : (_) {},
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 8),
                  ],

                  // Término del huevo (solo cuando conHuevo está activo)
                  if (isChilaquil && conHuevo) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'TÉRMINO DEL HUEVO',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: terminosHuevo.map((termino) {
                        final isSelected = selectedTerminoHuevo == termino;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setDialogState(() => selectedTerminoHuevo = termino),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                                    : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF334155),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    termino,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white60,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF334155)),
                  ],

                  // Selector de salsa para chilaquiles
                  if (isChilaquil) ...[
                    const Text(
                      'SALSA',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: salsasChilaquil.map((salsa) {
                        final isSelected = selectedSalsa == salsa;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setDialogState(() => selectedSalsa = salsa),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                                    : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF334155),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    salsa,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white60,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ]

                  // Lista de guisados (no para chilaquiles)
                  else if (guisados.isEmpty)
                    const Text(
                      'No hay guisados disponibles.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GUISADO',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1),
                        ),
                        Text(
                          '${selected.length}/5',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected.length >= 5
                                ? const Color(0xFFFF6D00)
                                : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (ctx2, constraints2) {
                        final w = constraints2.maxWidth;
                        final itemW = (w - 12) / 3;
                        Widget buildItem(Map<String, dynamic> g) {
                          final name = g['name'] as String;
                          final isChecked = selected.contains(name);
                          return SizedBox(
                            width: itemW,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setDialogState(() {
                                if (isChecked) {
                                  selected = selected.where((s) => s != name).toList();
                                } else if (selected.length < 5) {
                                  selected = [...selected, name];
                                }
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                                      : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isChecked ? const Color(0xFFFF6D00) : const Color(0xFF334155),
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
                                      size: 14,
                                      color: isChecked ? const Color(0xFFFF6D00) : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      name,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isChecked ? Colors.white : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: isChecked ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        return Stack(
                          children: [
                            SizedBox(
                              height: 340,
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: guisados.map(buildItem).toList(),
                                ),
                              ),
                            ),
                            // Degradado inferior indicando que hay más contenido
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        const Color(0xFF1E293B).withValues(alpha: 0),
                                        const Color(0xFF1E293B).withValues(alpha: 0.9),
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.keyboard_arrow_down,
                                        color: Colors.white54, size: 20),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
                ),
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
                  // Chilaquiles requieren salsa seleccionada
                  if (isChilaquil && selectedSalsa == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Selecciona la salsa (Roja, Verde o Ranchera)'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  if (isChilaquil && conHuevo && selectedTerminoHuevo == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Selecciona el término del huevo'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final extras = [
                    if (isChilaquil && selectedSalsa != null) 'Salsa $selectedSalsa',
                    if (isChilaquil && conHuevo) 'Con huevo ${selectedTerminoHuevo != null ? "(${selectedTerminoHuevo})" : ""}',
                    if (!isChilaquil && conQueso) 'Con queso',
                    if (frita) 'Frita',
                    if (!isChilaquil) ...selected,
                  ];
                  final finalDish = (isTapa && conQueso)
                      ? dish.copyWith(price: dish.price + 25)
                      : dish;
                  cart.addItemWithGuisados(finalDish, extras);
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
                  backgroundColor:
                      const Color(0xFFFF6D00).withValues(alpha: 0.15),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dish.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final cart = context.watch<CartProvider>();
                      final quantity = cart.items[dish.id]?.quantity ?? 0;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '\$${dish.price.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                                  icon: const Icon(Icons.remove, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minHeight: 28,
                                    minWidth: 28,
                                  ),
                                ),
                              if (quantity > 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '$quantity',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              IconButton.filledTonal(
                                onPressed: () => addDishToCart(context, dish),
                                icon: const Icon(Icons.add, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minHeight: 28,
                                  minWidth: 28,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _extractFlavor(String name, String categoryPrefix) {
  // Strip variant markers anywhere
  var base = name
      .replaceAll(RegExp(r'\s*\(Orden\)\s*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s*\(1/2\)\s+orden\s*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s*\(1/2\)\s*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s*\(\d+\s*pzas?\.?\)\s*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s*1/2\s+orden\s*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Strip category prefix like "Enmoladas de " → "Cebolla"
  final prefix = RegExp(
    r'^' + RegExp.escape(categoryPrefix) + r'\s+(?:de\s+|del\s+|con\s+|en\s+)?',
    caseSensitive: false,
  );
  return base.replaceFirst(prefix, '').trim();
}

int? _extractQuantity(String name) {
  final m =
      RegExp(r'\((\d+)\s*pzas?\.?\)', caseSensitive: false).firstMatch(name);
  return m != null ? int.tryParse(m.group(1)!) : null;
}

String _extractSize(String name) {
  return name.toLowerCase().contains('1/2') ? 'media' : 'orden';
}

Future<void> addMultiFlavorVariantToCart(BuildContext context,
    List<Dish> dishes, String displayName, String categoryPrefix) async {
  final cart = context.read<CartProvider>();

  // Detectar qué dimensiones tienen variación real
  final sizes = dishes.map((d) => _extractSize(d.name)).toSet();
  final quantities =
      dishes.map((d) => _extractQuantity(d.name)).whereType<int>().toSet();
  final flavors =
      dishes.map((d) => _extractFlavor(d.name, categoryPrefix)).toSet();
  final sortedFlavors = flavors.toList()..sort();
  final sortedQty = quantities.toList()..sort();

  final showSize = sizes.length > 1;
  final showQty = quantities.length > 1;
  final showFlavor = flavors.length > 1;

  String? selectedSize = showSize ? null : (sizes.isNotEmpty ? sizes.first : null);
  int? selectedQty = showQty ? null : (quantities.isNotEmpty ? quantities.first : null);
  String? selectedFlavor =
      showFlavor ? null : (flavors.isNotEmpty ? flavors.first : null);

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Dish? matched;
        for (final d in dishes) {
          final dSize = _extractSize(d.name);
          final dQty = _extractQuantity(d.name);
          final dFlavor = _extractFlavor(d.name, categoryPrefix);
          if (showSize && dSize != selectedSize) continue;
          if (showQty && dQty != selectedQty) continue;
          if (showFlavor && dFlavor != selectedFlavor) continue;
          if (!showSize && sizes.isNotEmpty && dSize != sizes.first) continue;
          if (!showQty && quantities.isNotEmpty && dQty != quantities.first) {
            continue;
          }
          if (!showFlavor && flavors.isNotEmpty && dFlavor != flavors.first) {
            continue;
          }
          matched = d;
          break;
        }
        final canAdd = matched != null &&
            (!showSize || selectedSize != null) &&
            (!showQty || selectedQty != null) &&
            (!showFlavor || selectedFlavor != null);
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(displayName,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSize) ...[
                    const Text('TAMAÑO',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (sizes.contains('orden'))
                          _ToggleOption(
                            icon: Icons.restaurant,
                            label: '1 Orden',
                            value: selectedSize == 'orden',
                            onChanged: (v) => setDialogState(
                                () => selectedSize = v ? 'orden' : null),
                          ),
                        if (sizes.contains('media'))
                          _ToggleOption(
                            icon: Icons.content_cut,
                            label: '1/2 Orden',
                            value: selectedSize == 'media',
                            onChanged: (v) => setDialogState(
                                () => selectedSize = v ? 'media' : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 8),
                  ],
                  if (showQty) ...[
                    const Text('CANTIDAD',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: sortedQty
                          .map((q) => _ToggleOption(
                                icon: Icons.numbers,
                                label: q == 1 ? '$q pza' : '$q pzas',
                                value: selectedQty == q,
                                onChanged: (v) => setDialogState(
                                    () => selectedQty = v ? q : null),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 8),
                  ],
                  if (showFlavor) ...[
                    const Text('SABOR',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: sortedFlavors
                          .map((fl) => _ToggleOption(
                                icon: Icons.local_dining,
                                label: fl.isEmpty ? displayName : fl,
                                value: selectedFlavor == fl,
                                onChanged: (v) => setDialogState(
                                    () => selectedFlavor = v ? fl : null),
                              ))
                          .toList(),
                    ),
                  ],
                  if (canAdd) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Total: \$${matched!.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Color(0xFFFF6D00),
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: !canAdd
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      cart.addItemWithGuisados(matched!, []);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${matched.name} agregado'),
                          duration: const Duration(milliseconds: 500),
                          behavior: SnackBarBehavior.floating,
                          width: 260,
                        ));
                      }
                    },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00).withValues(alpha: 0.15),
              ),
              child: const Text('Agregar a la orden',
                  style: TextStyle(color: Color(0xFFFF6D00))),
            ),
          ],
        );
      },
    ),
  );
}

class MultiFlavorVariantCard extends StatelessWidget {
  final List<Dish> dishes;
  final String displayName;
  final String categoryPrefix;

  const MultiFlavorVariantCard({
    super.key,
    required this.dishes,
    required this.displayName,
    required this.categoryPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final minPrice =
        dishes.map((d) => d.price).reduce((a, b) => a < b ? a : b);
    final maxPrice =
        dishes.map((d) => d.price).reduce((a, b) => a > b ? a : b);
    final firstDish = dishes.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => addMultiFlavorVariantToCart(
            context, dishes, displayName, categoryPrefix),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final cart = context.watch<CartProvider>();
                      final totalQ = dishes.fold<int>(
                          0,
                          (sum, d) =>
                              sum + (cart.items[d.id]?.quantity ?? 0));
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '\$${minPrice.toStringAsFixed(0)} - \$${maxPrice.toStringAsFixed(0)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (totalQ > 0) ...[
                                Text('$totalQ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const SizedBox(width: 4),
                              ],
                              IconButton.filledTonal(
                                onPressed: () => addMultiFlavorVariantToCart(
                                    context,
                                    dishes,
                                    displayName,
                                    categoryPrefix),
                                icon: const Icon(Icons.add, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minHeight: 28, minWidth: 28),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _baseOrdenName(String name) {
  return name
      .replaceAll(RegExp(r'\s*\(Orden\)\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(1/2\)\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*1/2\s*$', caseSensitive: false), '')
      .trim();
}

Future<void> addOrdenVariantToCart(
    BuildContext context, Dish ordenDish, Dish mediaDish) async {
  final cart = context.read<CartProvider>();
  Dish? selected;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          _baseOrdenName(ordenDish.name),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TAMAÑO',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _ToggleOption(
                  icon: Icons.restaurant,
                  label: '1 Orden  \$${ordenDish.price.toStringAsFixed(0)}',
                  value: selected?.id == ordenDish.id,
                  onChanged: (v) =>
                      setDialogState(() => selected = v ? ordenDish : null),
                ),
                _ToggleOption(
                  icon: Icons.content_cut,
                  label: '1/2 Orden  \$${mediaDish.price.toStringAsFixed(0)}',
                  value: selected?.id == mediaDish.id,
                  onChanged: (v) =>
                      setDialogState(() => selected = v ? mediaDish : null),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: selected == null
                ? null
                : () {
                    Navigator.pop(ctx);
                    cart.addItemWithGuisados(selected!, []);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${selected!.name} agregado'),
                        duration: const Duration(milliseconds: 500),
                        behavior: SnackBarBehavior.floating,
                        width: 260,
                      ));
                    }
                  },
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00).withValues(alpha: 0.15),
            ),
            child: const Text('Agregar a la orden',
                style: TextStyle(color: Color(0xFFFF6D00))),
          ),
        ],
      ),
    ),
  );
}

class OrdenVariantCard extends StatelessWidget {
  final Dish ordenDish;
  final Dish mediaDish;

  const OrdenVariantCard({
    super.key,
    required this.ordenDish,
    required this.mediaDish,
  });

  @override
  Widget build(BuildContext context) {
    final baseName = _baseOrdenName(ordenDish.name);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => addOrdenVariantToCart(context, ordenDish, mediaDish),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    baseName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final cart = context.watch<CartProvider>();
                      final qOrden = cart.items[ordenDish.id]?.quantity ?? 0;
                      final qMedia = cart.items[mediaDish.id]?.quantity ?? 0;
                      final totalQ = qOrden + qMedia;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\$${ordenDish.price.toStringAsFixed(0)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                '1/2: \$${mediaDish.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (totalQ > 0) ...[
                                Text(
                                  '$totalQ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                const SizedBox(width: 4),
                              ],
                              IconButton.filledTonal(
                                onPressed: () => addOrdenVariantToCart(
                                    context, ordenDish, mediaDish),
                                icon: const Icon(Icons.add, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minHeight: 28, minWidth: 28),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFFF6D00);
    final effectiveColor = enabled
        ? (value ? activeColor : const Color(0xFF334155))
        : const Color(0xFF1E293B);
    final borderColor = enabled
        ? (value ? activeColor : const Color(0xFF475569))
        : const Color(0xFF2D3748);
    final contentColor = enabled
        ? (value ? Colors.white : Colors.white54)
        : Colors.white24;

    return GestureDetector(
      onTap: enabled ? () => onChanged(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: effectiveColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: contentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: value ? FontWeight.w700 : FontWeight.w400,
                color: contentColor,
              ),
            ),
            if (!enabled) ...[
              const SizedBox(width: 6),
              Icon(Icons.block, size: 14, color: Colors.white24),
            ],
          ],
        ),
      ),
    );
  }
}
