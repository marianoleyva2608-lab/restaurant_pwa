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
    final n = name.toLowerCase().trim();
    if (n.contains('choco')) return 'choco';
    if (n == 'té' || n == 'te') return 'te';
    if (n.contains('leche')) return 'leche';
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

  // Categorías de bebida: NO se muestran como tarjetas (DishCard) en la lista.
  // El chip de categoría y el submenú de bebidas se conservan.
  static const _allDrinkCats = {
    'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol', 'choco', 'te', 'leche',
  };
  static bool _isDrinkCategory(String category) =>
      _allDrinkCats.contains(category.toLowerCase());

  List<Dish> get _filteredDishes {
    // Sin categoría seleccionada y sin búsqueda: no mostrar tarjetas,
    // solo la cuadrícula de categorías.
    if (_selectedCategory == 'Todos' && _searchQuery.isEmpty) return [];
    final result = <Dish>[];
    for (final dish in widget.dishes) {
      if (_isPlatillosCategory(dish.category)) continue;
      if (_selectedCategory != 'Todos') {
        if (_selectedCategory == 'drink') {
          const allDrinkCats = {
            'drink',
            'bebidas',
            'jugos',
            'cafes',
            'refrescos',
            'aguas',
            'alcohol',
            'choco',
            'te',
            'leche',
          };
          if (!allDrinkCats.contains(dish.category)) continue;
          if (_selectedDrinkSubcat != null &&
              _effectiveCat(dish) != _selectedDrinkSubcat) continue;
        } else {
          if (_effectiveCat(dish) != _selectedCategory) continue;
        }
      }
      // Gorditas / Menudo / Lo dulce: no aparecen como tarjetas en el cuerpo.
      // Solo se acceden tocando el chip respectivo (abre el diálogo).
      if (dish.category == 'gorditas' ||
          dish.category == 'menudo' ||
          dish.category == 'lo_dulce' ||
          dish.category == 'dessert') continue;
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
    // Consolidar todas las categorías de bebidas en un solo chip 'drink'.
    // El submenú vertical (Aguas/Jugos/Refrescos/Cafés) aparece al tocarlo.
    if (rawCats.any(_allDrinkCats.contains)) {
      rawCats.removeAll(_allDrinkCats);
      rawCats.add('drink');
    }
    rawCats.removeWhere(_isPlatillosCategory);
    const pinned = [
      'drink',
      'gorditas',
      'chilaquiles',
      'huevos',
      'molletes',
      'enchiladas',
      'huaraches',
      'arrachera',
    ];
    final rest = rawCats.where((c) => !pinned.contains(c)).toList()..sort();
    final ordered = [...pinned.where(rawCats.contains), ...rest];
    return [...ordered];
  }

  String _translateCategory(String c) => Globals.translateCategory(c);

  /// Abre el diálogo directo si la categoría produce exactamente 1 tarjeta.
  /// Devuelve true si se abrió el diálogo (no hace falta filtrar).
  bool _triggerSingleCardAction(BuildContext context, String label) {
    final items = widget.dishes
        .where((d) => _effectiveCat(d) == label)
        .toList();
    if (items.isEmpty) return false;

    // Bebidas (subcategoría como chip).
    if (_isDrinkCategory(label)) {
      // Refrescos, Jugos y Aguas tienen diálogo dedicado con SABORES y TAMAÑOS
      // (cargados de la BD) — abrirlo vía addDishToCart con un platillo
      // representativo de la subcategoría.
      const dialogSubcats = {'refrescos', 'jugos', 'aguas', 'choco', 'te', 'leche'};
      if (dialogSubcats.contains(label)) {
        Dish rep = items.first;
        if (label == 'aguas') {
          // Preferir "Agua Fresca" (su diálogo incluye la opción "Natural").
          rep = items.firstWhere((d) {
            final n = d.name.toLowerCase();
            return n.contains('agua fresca') ||
                (n.startsWith('agua') && !n.contains('natural'));
          }, orElse: () => items.first);
        }
        addDishToCart(context, rep);
        return true;
      }
      // Cafés, Alcohol y demás: diálogo consolidado para elegir el tipo.
      final displayName = _translateCategory(label);
      addMultiFlavorVariantToCart(context, items, displayName, displayName);
      return true;
    }

    // Menudo: abrir diálogo consolidado con todas las opciones.
    if (label == 'menudo') {
      final displayName = _translateCategory(label);
      addMultiFlavorVariantToCart(context, items, displayName, displayName);
      return true;
    }
    // Lo dulce: bottom sheet con Molletes / Hot Cakes / Churros (cada uno
    // con su selector apropiado).
    if (label == 'lo_dulce' || label == 'dessert') {
      showLoDulcePickerSheet(context, items);
      return true;
    }

    // Gorditas: abrir el diálogo canónico directo (con selector de BASE
    // Maíz/Harina adentro). No mostrar tarjetas separadas en el cuerpo.
    if (label == 'gorditas') {
      Dish? canonica;
      for (final d in items) {
        final n = d.name.toLowerCase().trim();
        if (n == 'gordita de maíz' || n == 'gordita de maiz') {
          canonica = d;
          break;
        }
      }
      canonica ??= items.first;
      addDishToCart(context, canonica.copyWith(name: 'Gordita'));
      return true;
    }

    const skipMultiFlavor = {
      'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol', 'choco', 'te', 'leche', 'gorditas',
      'menudo',   // needs separate Menudo + Cuajadilla cards
      'lo_dulce', // needs separate Molletes / Churros+HotCakes cards
      'dessert',  // same items sometimes stored as 'dessert'
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
    if (label == 'drink') {
      _showDrinkPickerSheet(context);
      return;
    }
    if (label != 'Todos') {
      if (_triggerSingleCardAction(context, label)) return;
    }
    setState(() {
      // Tocar la categoría activa la deselecciona (muestra todo)
      _selectedCategory = (_selectedCategory == label) ? 'Todos' : label;
      _selectedDrinkSubcat = null;
    });
  }

  void _showDrinkPickerSheet(BuildContext context) {
    const subcats = [
      ('aguas', 'Aguas', Icons.water_drop),
      ('jugos', 'Jugos', Icons.local_drink),
      ('refrescos', 'Refrescos', Icons.sports_bar),
      ('cafes', 'Cafés', Icons.coffee),
      ('choco', 'Choco', Icons.icecream),
      ('te', 'Té', Icons.emoji_food_beverage),
      ('leche', 'Leche', Icons.local_cafe),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFAF1DE),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5DCC4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'Bebidas',
                  style: TextStyle(
                    color: Color(0xFFE07A30),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final s in subcats) ...[
                InkWell(
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _triggerSingleCardAction(context, s.$1);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF1DE),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFE5DCC4), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(s.$3, size: 28, color: const Color(0xFFFF6D00)),
                        const SizedBox(width: 16),
                        Text(
                          s.$2,
                          style: const TextStyle(
                            color: Color(0xFFA08F70),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right,
                            color: Color(0xFFA08F70), size: 22),
                      ],
                    ),
                  ),
                ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBlock(String label) {
    final bool selected = _selectedCategory == label;
    const orange = Color(0xFFFF6D00);
    const cream = Color(0xFFFAF1DE);
    return GestureDetector(
      onTap: () => _onCategoryTap(label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? orange : cream,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Globals.categoryIcon(label),
              size: 32,
              color: selected ? cream : orange,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _translateCategory(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: selected ? cream : orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Devuelve true para cualquier categoría que represente "Platillos generales"
  /// y que no debe mostrarse en el menú de comandas.
  static bool _isPlatillosCategory(String cat) {
    final c = cat.toLowerCase().trim();
    if (c == 'platillos' || c == 'maincourse' || c == 'main_course' ||
        c == 'main course') return true;
    final translated = Globals.translateCategory(cat).toLowerCase();
    return translated == 'platillos' || translated.contains('platillo');
  }

  /// Categorías que mantienen tarjetas individuales (lógica especial)
  static const _skipMultiFlavor = {
    'drink', 'bebidas', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol', 'choco', 'te', 'leche',
    'gorditas',
    'menudo',             // tarjetas separadas: Menudo + Cuajadillas
    'lo_dulce', 'dessert', // tarjetas separadas: Molletes vs Churros+HotCakes
  };

  /// Categorías donde se puede elegir MÁS DE UN sabor/producto a la vez
  // Categorías con multi-selección de sabor en el diálogo. Vacío = todas
  // las categorías son single-select (solo se puede elegir 1 sabor a la vez).
  static const _multiSelectCategories = <String>{};

  List<Widget> _buildCategoryCards(List<Dish> items) {
    if (items.isEmpty) return [];
    final cat = items.first.category.toLowerCase();

    // Bebidas: UNA sola tarjeta consolidada por subcategoría (Aguas, Cafés,
    // Refrescos, Jugos) que abre el diálogo para elegir la bebida. Sin DishCards
    // individuales.
    if (_isDrinkCategory(cat)) {
      final sub = _effectiveCat(items.first);
      final displayName = _translateCategory(sub);
      return [
        MultiFlavorVariantCard(
          dishes: items,
          displayName: displayName,
          categoryPrefix: displayName,
        ),
      ];
    }

    // Menudo: variantes de tamaño separadas de las Cuajadillas (complemento independiente)
    if (cat == 'menudo' && items.length > 1) {
      final menudos = items.where((d) => d.name.toLowerCase().contains('menudo')).toList();
      final cuajadillas = items.where((d) => d.name.toLowerCase().contains('cuajadilla')).toList();
      final others = items.where((d) =>
          !d.name.toLowerCase().contains('menudo') &&
          !d.name.toLowerCase().contains('cuajadilla')).toList();
      final cards = <Widget>[];
      if (menudos.length > 1) {
        cards.add(MultiFlavorVariantCard(
          dishes: menudos,
          displayName: 'Menudo',
          categoryPrefix: 'Menudo',
          multiSelectFlavors: false,
          overrideIcon: Icons.soup_kitchen,
          subtitle: 'Sáb · Dom',
        ));
      } else {
        for (final d in menudos) cards.add(DishCard(dish: d));
      }
      if (cuajadillas.length > 1) {
        cards.add(MultiFlavorVariantCard(
          dishes: cuajadillas,
          displayName: 'Cuajadilla',
          categoryPrefix: 'Cuajadilla',
          multiSelectFlavors: false,
          overrideIcon: Icons.lunch_dining,
        ));
      } else {
        for (final d in cuajadillas) cards.add(DishCard(dish: d));
      }
      for (final d in others) cards.add(DishCard(dish: d));
      return cards;
    }

    // Lo dulce / dessert: Molletes Dulces por orden; Churros y Hot Cakes por cantidad
    if ((cat == 'lo_dulce' || cat == 'dessert') && items.length > 1) {
      final molletes = items.where((d) => d.name.toLowerCase().contains('mollete')).toList();
      // Excluir cualquier variante "1/2" del grupo de piezas para que no aparezca el selector de tamaño
      final piezas = items.where((d) =>
          !d.name.toLowerCase().contains('mollete') &&
          !d.name.toLowerCase().contains('1/2')).toList();
      final mediaOtros = items.where((d) =>
          !d.name.toLowerCase().contains('mollete') &&
          d.name.toLowerCase().contains('1/2')).toList();
      final cards = <Widget>[];
      for (final d in molletes) {
        cards.add(DishCard(dish: d));
      }
      for (final d in mediaOtros) {
        cards.add(DishCard(dish: d));
      }
      if (piezas.isNotEmpty) {
        final displayName = _translateCategory(cat);
        cards.add(MultiFlavorVariantCard(
          dishes: piezas,
          displayName: displayName,
          categoryPrefix: displayName,
          multiSelectFlavors: _multiSelectCategories.contains(cat),
        ));
      }
      return cards;
    }

    // Para categorías con 2+ platillos, colapsar a una sola tarjeta multi-sabor
    if (items.length > 1 && !_skipMultiFlavor.contains(cat)) {
      final displayName = _translateCategory(cat);
      return [
        MultiFlavorVariantCard(
          dishes: items,
          displayName: displayName,
          categoryPrefix: displayName,
          multiSelectFlavors: _multiSelectCategories.contains(cat),
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
      final initial = _selectedCategory == 'Todos' && _searchQuery.isEmpty;
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Center(
              child: Text(
                initial
                    ? 'Selecciona una categoría'
                    : 'No hay coincidencias',
                style: const TextStyle(color: Colors.grey),
              ),
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
                    color: Color(0xFFFF6D00),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${cards.length})',
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFFA08F70)),
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
                  isMobile ? (crossAxisCount == 2 ? 1.45 : 1.6) : (isTablet ? 1.7 : 1.8),
              crossAxisSpacing: isMobile ? 8 : (isTablet ? 8 : 12),
              mainAxisSpacing: isMobile ? 8 : (isTablet ? 8 : 12),
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fondo: foto de gorditas (sin overlay — visible al 100%).
        Image.asset(
          'assets/images/gordita.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        Column(
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
        // Categorías: cuadrícula de 3 columnas con scroll dentro de su Expanded,
        // igual que el menú de Comandas (mesero). Cuando no hay categoría
        // seleccionada ni búsqueda, ocupa toda la pantalla.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Builder(builder: (_) {
                  const cols = 3;
                  final realCount = _availableCategories.length;
                  final paddedCount =
                      ((realCount + cols - 1) ~/ cols) * cols;
                  return GridView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 96,
                    ),
                    itemCount: paddedCount,
                    itemBuilder: (_, i) {
                      if (i >= realCount) {
                        // Placeholder sólido (mismo look que los demás cards)
                        // para rellenar la última fila sin huecos.
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF1DE),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        );
                      }
                      return _buildCategoryBlock(_availableCategories[i]);
                    },
                  );
                }),
              ),
            ),
          ),
        ),
        if (!(_selectedCategory == 'Todos' && _searchQuery.isEmpty))
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final realWidth = constraints.maxWidth;
                int cols;
                if (isPhone) {
                  cols = realWidth < 400 ? 2 : 3;
                } else if (isTablet) {
                  cols = (realWidth / 150).floor().clamp(2, 5);
                } else {
                  cols = (realWidth / 180).floor().clamp(4, 8);
                }
                return CustomScrollView(
                  slivers: [
                    ..._buildGroupedMenu(filteredDishes, cols, isPhone,
                        isTablet: isTablet),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                );
              },
            ),
          ),
          ],
        ),
      ],
    );
  }
}
