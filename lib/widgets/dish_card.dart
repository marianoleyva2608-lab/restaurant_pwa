import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dish.dart';
import '../providers/cart_provider.dart';
import '../globals.dart';

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
      types = ['refresco', 'refresco_255', 'refresco_600'];
    } else if (type == 'agua_600' || type == 'agua_1litro') {
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

Future<void> addDishToCart(BuildContext context, Dish dish) async {
  final cart = context.read<CartProvider>();
  final nameLower = dish.name.toLowerCase();
  final bool isRefresco = nameLower.contains('refresco');
  final bool isAguaFresca = (nameLower.contains('agua fresca') || nameLower.startsWith('agua')) &&
      !nameLower.contains('natural');
  final bool isJugo = dish.category == 'jugos' || nameLower.contains('jugo');

  if (isRefresco || isAguaFresca || isJugo) {
    final drinkType = isJugo ? 'jugo' : isRefresco ? 'refresco' : 'agua_fresca';
    final List<String> sabores255 = isRefresco ? await _loadDrinkFlavors('refresco_255') : [];
    final List<String> sabores600 = isRefresco ? await _loadDrinkFlavors('refresco_600') : [];
    final List<String> sabores330 = isJugo ? await _loadDrinkFlavors('jugo_330') : [];
    final List<String> sabores1litro = isJugo ? await _loadDrinkFlavors('jugo_1litro') : [];
    final List<String> saboresAgua600 = isAguaFresca ? await _loadDrinkFlavors('agua_600') : [];
    final List<String> saboresAgua1litro = isAguaFresca ? await _loadDrinkFlavors('agua_1litro') : [];
    final List<String> sabores = (isRefresco || isJugo || isAguaFresca) ? [] : await _loadDrinkFlavors(drinkType);
    String? selectedSabor;
    String? aguaSize;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                isRefresco
                    ? '¿De qué sabor/marca?'
                    : isJugo
                        ? '¿Qué jugo?'
                        : '¿De qué sabor?',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selector de tamaño para refrescos, aguas y jugos
                    if (isRefresco || isAguaFresca || isJugo) ...[
                      const Text(
                        'TAMAÑO',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (isRefresco) ...[
                            _ToggleOption(
                              icon: Icons.sports_bar,
                              label: '355 ml',
                              value: aguaSize == '355 ml',
                              onChanged: (v) => setDialogState(() {
                                aguaSize = v ? '355 ml' : null;
                                if (!sabores255.contains(selectedSabor)) selectedSabor = null;
                              }),
                            ),
                            const SizedBox(width: 10),
                            _ToggleOption(
                              icon: Icons.sports_bar,
                              label: '600 ml',
                              value: aguaSize == '600 ml',
                              onChanged: (v) => setDialogState(() {
                                aguaSize = v ? '600 ml' : null;
                                if (!sabores600.contains(selectedSabor)) selectedSabor = null;
                              }),
                            ),
                          ] else if (isJugo) ...[
                            _ToggleOption(
                              icon: Icons.blender,
                              label: '330 ml',
                              value: aguaSize == '330 ml',
                              onChanged: (v) => setDialogState(() {
                                aguaSize = v ? '330 ml' : null;
                                if (!sabores330.contains(selectedSabor)) selectedSabor = null;
                              }),
                            ),
                            const SizedBox(width: 10),
                            _ToggleOption(
                              icon: Icons.blender,
                              label: '1 litro',
                              value: aguaSize == '1 litro',
                              onChanged: (v) => setDialogState(() {
                                aguaSize = v ? '1 litro' : null;
                                if (!sabores1litro.contains(selectedSabor)) selectedSabor = null;
                              }),
                            ),
                          ] else ...[
                            _ToggleOption(
                              icon: Icons.local_drink,
                              label: '600 ml',
                              value: aguaSize == '600 ml',
                              onChanged: (v) => setDialogState(() {
                                aguaSize = v ? '600 ml' : null;
                                if (!saboresAgua600.contains(selectedSabor)) selectedSabor = null;
                              }),
                            ),
                            const SizedBox(width: 10),
                            _ToggleOption(
                              icon: Icons.local_drink,
                              label: '1 litro',
                              value: aguaSize == '1 litro',
                              onChanged: (v) => setDialogState(() {
                                aguaSize = v ? '1 litro' : null;
                                if (!saboresAgua1litro.contains(selectedSabor)) selectedSabor = null;
                              }),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFF334155)),
                      const SizedBox(height: 8),
                    ],
                    const Text(
                      'SABOR',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    Builder(builder: (ctx2) {
                      final currentSabores = isRefresco
                          ? (aguaSize == '355 ml'
                              ? sabores255
                              : aguaSize == '600 ml'
                                  ? sabores600
                                  : ({...sabores255, ...sabores600}.toList()..sort()))
                          : isJugo
                              ? (aguaSize == '330 ml'
                                  ? sabores330
                                  : aguaSize == '1 litro'
                                      ? sabores1litro
                                      : ({...sabores330, ...sabores1litro}.toList()..sort()))
                              : isAguaFresca
                                  ? (aguaSize == '600 ml'
                                      ? saboresAgua600
                                      : aguaSize == '1 litro'
                                          ? saboresAgua1litro
                                          : ({...saboresAgua600, ...saboresAgua1litro}.toList()..sort()))
                                  : sabores;
                      return GridView.builder(
                      shrinkWrap: true,
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
                    );
                    }),
                  ],
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
                    final extras = [
                      if (aguaSize != null) aguaSize!,
                      selectedSabor!,
                    ];
                    Dish finalDish = dish;
                    if (isAguaFresca && aguaSize != null) {
                      final priceType = aguaSize == '600 ml' ? 'agua_600' : 'agua_1litro';
                      final aguaPrice = await _loadDrinkPrice(priceType);
                      if (aguaPrice != null) finalDish = dish.copyWith(price: aguaPrice);
                    } else if (isRefresco && aguaSize != null) {
                      final priceType = aguaSize == '600 ml' ? 'refresco_600' : 'refresco_355';
                      final refrescoPrice = await _loadDrinkPrice(priceType);
                      if (refrescoPrice != null) {
                        finalDish = dish.copyWith(price: refrescoPrice);
                      } else {
                        finalDish = dish.copyWith(price: aguaSize == '600 ml' ? 30 : 25);
                      }
                    } else if (isJugo && aguaSize != null) {
                      final priceType = aguaSize == '330 ml' ? 'jugo_330' : 'jugo_1litro';
                      final jugoPrice = await _loadDrinkPrice(priceType);
                      if (jugoPrice != null) finalDish = dish.copyWith(price: jugoPrice);
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
  final bool isHuevo = dish.category == 'huevos' && !isChilaquil;

  if (isHuevo) {
    String? selectedTermino;
    const List<String> terminos = ['Tierno', 'Cocido', 'Sellados'];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            '${dish.name} — ¿Término?',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: terminos.map((t) {
                final selected = selectedTermino == t;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setDialogState(() => selectedTermino = t),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFFF6D00).withValues(alpha: 0.2)
                            : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? const Color(0xFFFF6D00) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: selected ? const Color(0xFFFF6D00) : Colors.white54,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            t,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: selectedTermino == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      cart.addItemWithGuisados(dish, [selectedTermino!]);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${dish.name} ($selectedTermino) agregado'),
                          duration: const Duration(milliseconds: 600),
                          behavior: SnackBarBehavior.floating,
                          width: 260,
                        ));
                      }
                    },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00).withValues(alpha: 0.15),
              ),
              child: const Text('Agregar a la orden', style: TextStyle(color: Color(0xFFFF6D00))),
            ),
          ],
        ),
      ),
    );
    return;
  }

  if (isArrachera) {
    bool conQueso = false;
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
                'Opciones',
                style: TextStyle(color: Colors.white70, fontSize: 12,
                    fontWeight: FontWeight.w600, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              _ToggleOption(
                icon: Icons.egg_alt,
                label: 'Con Queso  (+\$5)',
                value: conQueso,
                onChanged: (v) => setDialogState(() => conQueso = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                final finalDish = conQueso
                    ? dish.copyWith(price: dish.price + 5)
                    : dish;
                final extras = [if (conQueso) 'Con queso'];
                cart.addItemWithGuisados(finalDish, extras);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${dish.name} agregado'),
                    duration: const Duration(milliseconds: 500),
                    behavior: SnackBarBehavior.floating,
                    width: 200,
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

  const salsasChilaquil = ['Roja', 'Verde', 'Ranchera'];

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
              width: 520,
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
                            onChanged: (v) => setDialogState(() => conHuevo = v),
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
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: GridView.builder(
                        shrinkWrap: true,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 6,
                          childAspectRatio: 2.8,
                        ),
                        itemCount: guisados.length,
                        itemBuilder: (ctx2, gi) {
                          final g = guisados[gi];
                          final name = g['name'] as String;
                          final isChecked = selected.contains(name);
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              setDialogState(() {
                                if (isChecked) {
                                  selected = selected.where((s) => s != name).toList();
                                } else if (selected.length < 5) {
                                  selected = [...selected, name];
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: isChecked
                                    ? const Color(0xFFFF6D00)
                                        .withValues(alpha: 0.15)
                                    : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isChecked
                                      ? const Color(0xFFFF6D00)
                                      : const Color(0xFF334155),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isChecked
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: isChecked
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        color: isChecked
                                            ? Colors.white
                                            : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: isChecked
                                            ? FontWeight.w600
                                            : FontWeight.w400,
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
                    ),
                  ],
                ],
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
                  Navigator.pop(ctx);
                  final extras = [
                    if (isChilaquil && selectedSalsa != null) 'Salsa $selectedSalsa',
                    if (isChilaquil && conHuevo) 'Con huevo',
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
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
