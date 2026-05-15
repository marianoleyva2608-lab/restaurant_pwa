import 'package:flutter/material.dart';
import '../models/dish.dart';
import '../globals.dart';
import 'dish_card.dart';

class MenuBrowser extends StatefulWidget {
  final List<Dish> dishes;

  const MenuBrowser({super.key, required this.dishes});

  @override
  State<MenuBrowser> createState() => _MenuBrowserState();
}

class _MenuBrowserState extends State<MenuBrowser> {
  String _selectedCategory = 'Todos';
  String? _selectedDrinkSubcat;
  String _searchQuery = '';

  static String _drinkSubcat(String name) {
    final n = name.toLowerCase();
    if (n.contains('jugo')) return 'jugos';
    if (n.contains('café') ||
        n.contains('cafe') ||
        n.contains('americano') ||
        n.contains('capuchino') ||
        n.contains('latte') ||
        n.contains('espresso') ||
        n.contains('olla') ||
        n.contains('instantáneo') ||
        n.contains('instantaneo') ||
        n.contains('nescafé') ||
        n.contains('nescafe')) {
      return 'cafes';
    }
    if (n.contains('agua') ||
        n.contains('horchata') ||
        n.contains('jamaica') ||
        n.contains('tamarindo') ||
        n.contains('limonada') ||
        n.contains('fresca')) {
      return 'aguas';
    }
    if (n.contains('refresco') ||
        n.contains('coca') ||
        n.contains('pepsi') ||
        n.contains('sprite') ||
        n.contains('fanta') ||
        n.contains('sidral') ||
        n.contains('squirt') ||
        n.contains('7up') ||
        n.contains('manzanita') ||
        n.contains('sangría') ||
        n.contains('sangria')) {
      return 'refrescos';
    }
    if (n.contains('cerveza') ||
        n.contains('caguama') ||
        n.contains('tequila') ||
        n.contains('mezcal') ||
        n.contains('michelada') ||
        n.contains('clamato') ||
        n.contains('corona') ||
        n.contains('modelo') ||
        n.contains('pacifico') ||
        n.contains('victoria') ||
        n.contains('alcohol')) {
      return 'alcohol';
    }
    return 'drink';
  }

  static String _effectiveCat(Dish d) {
    const genericDrink = {'drink', 'bebidas'};
    return genericDrink.contains(d.category) ? _drinkSubcat(d.name) : d.category;
  }

  List<Dish> get _filteredDishes {
    const gordtasPermitidas = {
      'gordita de maíz',
      'gordita de maiz',
      'gordita de harina'
    };
    final seenNames = <String>{};
    final result = <Dish>[];
    for (final dish in widget.dishes) {
      if (dish.category == 'platillos') continue;
      if (_selectedCategory != 'Todos') {
        if (_selectedCategory == 'drink') {
          const allDrinkCats = {
            'drink',
            'bebidas',
            'jugos',
            'cafes',
            'refrescos',
            'aguas',
            'alcohol'
          };
          if (!allDrinkCats.contains(dish.category)) continue;
          if (_selectedDrinkSubcat != null &&
              _effectiveCat(dish) != _selectedDrinkSubcat) continue;
        } else {
          if (_effectiveCat(dish) != _selectedCategory) continue;
        }
      }
      if (dish.category == 'gorditas') {
        final n = dish.name.toLowerCase().trim();
        if (!gordtasPermitidas.contains(n)) continue;
        if (!seenNames.add(n)) continue;
      }
      if (_searchQuery.isNotEmpty &&
          !dish.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        continue;
      }
      result.add(dish);
    }
    return result;
  }

  List<String> get _availableCategories {
    final rawCats = widget.dishes.map((d) => d.category).toSet();
    const allDrinkCats = {
      'drink',
      'bebidas',
      'jugos',
      'cafes',
      'refrescos',
      'aguas',
      'alcohol'
    };
    if (rawCats.any(allDrinkCats.contains)) {
      rawCats.removeAll(allDrinkCats);
      rawCats.add('drink');
    }
    rawCats.remove('platillos');
    const pinned = [
      'gorditas',
      'drink',
      'chilaquiles',
      'huevos',
      'molletes',
      'enchiladas',
      'huaraches',
      'arrachera',
    ];
    final rest = rawCats.where((c) => !pinned.contains(c)).toList()..sort();
    final ordered = [...pinned.where(rawCats.contains), ...rest];
    return ['Todos', ...ordered];
  }

  String _translateCategory(String c) => Globals.translateCategory(c);

  /// Abre el diálogo directo si la categoría produce exactamente 1 tarjeta.
  /// Devuelve true si se abrió el diálogo (no hace falta filtrar).
  bool _triggerSingleCardAction(BuildContext context, String label) {
    final items = widget.dishes
        .where((d) => _effectiveCat(d) == label)
        .toList();
    if (items.isEmpty) return false;

    const skipMultiFlavor = {
      'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol', 'gorditas',
    };
    final cat = items.first.category.toLowerCase();

    // Múltiples platillos en categoría no-skip → siempre 1 MultiFlavorVariantCard
    if (items.length > 1 && !skipMultiFlavor.contains(cat)) {
      final displayName = _translateCategory(cat);
      addMultiFlavorVariantToCart(context, items, displayName, displayName);
      return true;
    }

    // Lógica byBase (categorías skip o ítem único)
    final byBase = <String, Map<String, Dish>>{};
    for (final dish in items) {
      final isMedia = dish.name.toLowerCase().contains('1/2');
      final base = dish.name
          .replaceAll(RegExp(r'\s*\(Orden\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*\(1/2\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*1/2\s*$', caseSensitive: false), '')
          .trim();
      byBase.putIfAbsent(base, () => {});
      byBase[base]![isMedia ? 'media' : 'orden'] = dish;
    }

    if (byBase.length == 1) {
      final entry = byBase.entries.first;
      final orden = entry.value['orden'];
      final media = entry.value['media'];
      if (orden != null && media != null) {
        addOrdenVariantToCart(context, orden, media);
      } else {
        addDishToCart(context, orden ?? media!);
      }
      return true;
    }

    return false; // Múltiples tarjetas → filtrar normalmente
  }

  void _onCategoryTap(String label) {
    if (label != 'Todos' && label != 'drink') {
      if (_triggerSingleCardAction(context, label)) return;
    }
    setState(() {
      _selectedCategory = label;
      if (label != 'drink') _selectedDrinkSubcat = null;
    });
  }

  Widget _buildCategoryBlock(String label) {
    final selected = _selectedCategory == label;
    const activeColor = Color(0xFFE07A30);
    return GestureDetector(
      onTap: () => _onCategoryTap(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 60,
        height: 54,
        decoration: BoxDecoration(
          color: selected ? activeColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFF334155),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Globals.categoryIcon(label),
              size: 20,
              color: selected ? Colors.white : Colors.white60,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _translateCategory(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? Colors.white : Colors.white60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrinkSubmenu() {
    const subcats = [
      ('refrescos', 'Refrescos', Icons.sports_bar),
      ('aguas', 'Aguas', Icons.water_drop),
      ('cafes', 'Cafés', Icons.coffee),
      ('jugos', 'Jugos', Icons.local_drink),
      (null, 'Todas', Icons.grid_view),
    ];
    const active = Color(0xFFE07A30);
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: subcats.map((s) {
            final key = s.$1;
            final label = s.$2;
            final icon = s.$3;
            final selected = _selectedDrinkSubcat == key;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () {
                  if (key != null && _triggerSingleCardAction(context, key)) return;
                  setState(() => _selectedDrinkSubcat = key);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? active : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? active : const Color(0xFF334155),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 16,
                          color: selected ? Colors.white : Colors.white60),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Categorías que mantienen tarjetas individuales (lógica especial)
  static const _skipMultiFlavor = {
    'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol',
    'gorditas',
  };

  List<Widget> _buildCategoryCards(List<Dish> items) {
    if (items.isEmpty) return [];
    final cat = items.first.category.toLowerCase();

    // Para categorías con 2+ platillos, colapsar a una sola tarjeta multi-sabor
    if (items.length > 1 && !_skipMultiFlavor.contains(cat)) {
      final displayName = _translateCategory(cat);
      return [
        MultiFlavorVariantCard(
          dishes: items,
          displayName: displayName,
          categoryPrefix: displayName,
        ),
      ];
    }
    final Map<String, Map<String, Dish>> byBase = {};
    for (final dish in items) {
      final isMedia = dish.name.toLowerCase().contains('1/2');
      final base = dish.name
          .replaceAll(RegExp(r'\s*\(Orden\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*\(1/2\)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*1/2\s*$', caseSensitive: false), '')
          .trim();
      byBase.putIfAbsent(base, () => {});
      byBase[base]![isMedia ? 'media' : 'orden'] = dish;
    }
    final List<Widget> cards = [];
    for (final entry in byBase.entries) {
      final orden = entry.value['orden'];
      final media = entry.value['media'];
      if (orden != null && media != null) {
        cards.add(OrdenVariantCard(ordenDish: orden, mediaDish: media));
      } else {
        cards.add(DishCard(dish: orden ?? media!));
      }
    }
    return cards;
  }

  List<Widget> _buildGroupedMenu(
      List<Dish> items, int crossAxisCount, bool isPhone,
      {bool isTablet = false}) {
    final isMobile = isPhone;
    if (items.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(
              child: Text('No hay coincidencias',
                  style: TextStyle(color: Colors.grey)),
            ),
          ),
        ),
      ];
    }
    final Map<String, List<Dish>> groups = {};
    for (var item in items) {
      groups.putIfAbsent(_effectiveCat(item), () => []).add(item);
    }
    final sortedCategories = groups.keys.toList()..sort();
    final List<Widget> slivers = [];
    for (var category in sortedCategories) {
      final categoryItems = groups[category]!;
      final cards = _buildCategoryCards(categoryItems);
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6D00),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _translateCategory(category).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${cards.length})',
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8.0 : 16.0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio:
                  isMobile ? 1.6 : (isTablet ? 1.7 : 1.8),
              crossAxisSpacing: isMobile ? 6 : (isTablet ? 8 : 12),
              mainAxisSpacing: isMobile ? 6 : (isTablet ? 8 : 12),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => cards[index],
              childCount: cards.length,
            ),
          ),
        ),
      );
    }
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final filteredDishes = _filteredDishes;
    final screenWidth = MediaQuery.of(context).size.width;
    final isPhone = screenWidth < 600;
    final isDesktop = screenWidth >= 1024;
    final isTablet = !isPhone && !isDesktop;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SearchBar(
            hintText: 'Buscar platillo...',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(1),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        SizedBox(
          height: 2 * 54 + 1 * 6 + 8,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 6,
              childAspectRatio: 54 / 60,
            ),
            itemCount: _availableCategories.length,
            itemBuilder: (_, i) => _buildCategoryBlock(_availableCategories[i]),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFF1E293B)),
        if (_selectedCategory == 'drink') _buildDrinkSubmenu(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final realWidth = constraints.maxWidth;
              int cols;
              if (isPhone) {
                cols = 3;
              } else if (isTablet) {
                cols = (realWidth / 150).floor().clamp(2, 5);
              } else {
                cols = (realWidth / 180).floor().clamp(4, 8);
              }
              return CustomScrollView(
                slivers: [
                  ..._buildGroupedMenu(filteredDishes, cols, isPhone,
                      isTablet: isTablet),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
