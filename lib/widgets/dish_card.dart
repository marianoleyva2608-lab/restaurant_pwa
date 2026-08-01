import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dish.dart';
import '../providers/cart_provider.dart';
import '../globals.dart';

/// Categorías de bebida (no preparadas en cocina). El resto se considera
/// "preparado" y permite comentarios adicionales (ej. "sin lechuga, sin chile").
const _drinkCategories = {
  'drink',
  'bebidas',
  'jugos',
  'cafes',
  'refrescos',
  'aguas',
  'alcohol',
};

bool _isPreparedDishes(Iterable<Dish> dishes) =>
    dishes.any((d) => !_drinkCategories.contains(d.category.toLowerCase()));

/// Fila de 🌶 según spice_level (1..3). Devuelve un widget vacío si es 0.
Widget _chileRow(int level) {
  if (level <= 0) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      '🌶' * level.clamp(0, 3),
      style: const TextStyle(fontSize: 9, height: 1),
    ),
  );
}

/// Emoji que representa el tipo de carne de un guisado.
/// Si no hay meat_type, devuelve string vacío.
String meatEmoji(String? meatType) {
  switch (meatType) {
    case 'res':
      return '🐄';
    case 'cerdo':
      return '🐷';
    case 'pollo':
      return '🐔';
    case 'sin_carne':
      return '🌽';
    default:
      return '';
  }
}

/// Área scrollable de altura fija que muestra una flecha animada hacia abajo
/// mientras quede contenido por debajo del viewport. La flecha desaparece al
/// llegar al final.
class _ScrollableWithDownHint extends StatefulWidget {
  final double height;
  final Color hintColor;
  final Color fadeColor;
  final Widget child;
  const _ScrollableWithDownHint({
    required this.height,
    required this.hintColor,
    required this.fadeColor,
    required this.child,
  });
  @override
  State<_ScrollableWithDownHint> createState() =>
      _ScrollableWithDownHintState();
}

class _ScrollableWithDownHintState extends State<_ScrollableWithDownHint>
    with SingleTickerProviderStateMixin {
  final ScrollController _ctrl = ScrollController();
  late final AnimationController _anim;
  // Asumir overflow al inicio para que la flecha esté visible mientras se
  // mide el contenido. Si después se detecta que cabe sin scrollear, se
  // oculta.
  bool _hasOverflow = true;
  bool _atBottom = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _ctrl.addListener(_onScroll);
    // Reintentar varias veces porque el Wrap puede tardar 1-2 frames en
    // calcular su altura final.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), _onScroll);
      Future.delayed(const Duration(milliseconds: 200), _onScroll);
    });
  }

  void _onScroll() {
    if (!mounted || !_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final overflow = pos.maxScrollExtent > 0;
    final atBottom = overflow && pos.pixels >= pos.maxScrollExtent - 4;
    if (overflow != _hasOverflow || atBottom != _atBottom) {
      setState(() {
        _hasOverflow = overflow;
        _atBottom = atBottom;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onScroll);
    _ctrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showHint = _hasOverflow && !_atBottom;
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _onScroll());
              return false;
            },
            child: SingleChildScrollView(
              controller: _ctrl,
              physics: const ClampingScrollPhysics(),
              child: widget.child,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: showHint ? 1 : 0,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.fadeColor.withValues(alpha: 0),
                        widget.fadeColor,
                      ],
                    ),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: FadeTransition(
                    opacity: Tween<double>(begin: 0.45, end: 1.0)
                        .animate(_anim),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: widget.hintColor,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sección reutilizable de comentarios libres para los diálogos de preparación.
Widget _buildCommentField(TextEditingController controller) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 12),
      const Divider(color: Color(0xFFE5DCC4)),
      const SizedBox(height: 8),
      const Text('COMENTARIOS',
          style: TextStyle(
              color: const Color(0xFF7A6E5A),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1)),
      const SizedBox(height: 10),
      TextField(
        controller: controller,
        style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 14, fontWeight: FontWeight.w600),
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Ej. sin lechuga, sin chile',
          hintStyle: const TextStyle(color: Color(0xFFA08F70), fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFFAF1DE),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5DCC4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5DCC4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFF6D00)),
          ),
        ),
      ),
    ],
  );
}

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

const _chocoFallback = ['Fresa', 'Chocolate', 'Vainilla'];
const _teFallback = ['Manzanilla', 'Limón', 'Negro', 'Verde'];

Future<List<String>> _loadDrinkFlavors(String type) async {
  try {
    final supabase = Supabase.instance.client;
    List<String> types;
    if (type == 'refresco') {
      types = ['refresco', 'refresco_355', 'refresco_600'];
    } else if (type == 'refresco_355') {
      types = ['refresco_355', 'refresco'];
    } else if (type == 'refresco_600') {
      // Un sabor guardado como "Refresco" genérico (sin tamaño específico)
      // debe verse también en 600 ml, igual que ya pasa con 355.
      types = ['refresco_600', 'refresco'];
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
        .order('name', ascending: true);
    final list = (rows as List)
        .map((r) => r['name'] as String)
        .toSet()
        .toList()..sort();
    if (list.isNotEmpty) return list;
    if (type.startsWith('refresco')) return _refrescoFallback;
    if (type.startsWith('jugo')) return _jugoFallback;
    if (type.startsWith('choco')) return _chocoFallback;
    if (type.startsWith('te')) return _teFallback;
    return _aguaFallback;
  } catch (_) {
    if (type.startsWith('refresco')) return _refrescoFallback;
    if (type.startsWith('jugo')) return _jugoFallback;
    if (type.startsWith('choco')) return _chocoFallback;
    if (type.startsWith('te')) return _teFallback;
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

/// Nombre a mostrar/imprimir para una bebida (refresco/agua/jugo) según
/// el TAMAÑO elegido en el diálogo. Se arma directo del `type` (ej.
/// 'refresco_600', 'agua_1litro') en vez de usar el nombre del dish que
/// se tocó originalmente en el menú — si no, al cambiar el TAMAÑO en el
/// diálogo (ej. tocar "Agua Fresca 1 litro" pero elegir 600 ml), el
/// título se quedaba con el tamaño viejo mientras el sabor/tamaño real
/// se mostraba aparte, contradictorio.
String _drinkDisplayName(String type) {
  if (type.startsWith('refresco')) {
    final suffix = type.replaceFirst(RegExp(r'^refresco_'), '');
    if (suffix.contains('355')) return 'Refresco de vidrio';
    if (suffix.contains('600')) return 'Refresco no retornable';
    return 'Refresco';
  }
  if (type.startsWith('jugo')) return 'Jugo';
  return 'Agua Fresca';
}

/// Diálogo mínimo para platillos preparados que se agregan directo (sin
/// opciones de sabor/guisado, ej. arrachera, sopes, enchiladas): permite
/// cantidad y un comentario libre antes de agregar a la orden.
Future<void> _addPreparedDishWithComment(
    BuildContext context, Dish dish, {String? replaceKey}) async {
  final cart = context.read<CartProvider>();
  final commentController = TextEditingController();
  int dialogQty = 1;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFFFAF1DE),
        title: Text(dish.name,
            style: TextStyle(
                color: const Color(0xFF3D2E1A),
                fontWeight: FontWeight.w700,
                fontSize: MediaQuery.of(ctx).size.width < 380 ? 14 : 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCommentField(commentController),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFE5DCC4)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('CANTIDAD',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => setDialogState(
                              () { if (dialogQty > 1) dialogQty--; }),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF1DE),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE5DCC4)),
                            ),
                            child: const Icon(Icons.remove,
                                color: const Color(0xFF7A6E5A), size: 18),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text('$dialogQty',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFFF6D00),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                        ),
                        InkWell(
                          onTap: () => setDialogState(() => dialogQty++),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6D00)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFFF6D00)),
                            ),
                            child: const Icon(Icons.add,
                                color: Color(0xFFFF6D00), size: 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: const Color(0xFFA08F70))),
          ),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final comment = commentController.text.trim();
                cart.addItemWithGuisados(
                  dish,
                  [if (comment.isNotEmpty) comment],
                  quantity: dialogQty,
                );
                if (replaceKey != null) cart.removeItem(replaceKey);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '${dialogQty > 1 ? '$dialogQty × ' : ''}${dish.name} agregado'),
                    duration: const Duration(milliseconds: 500),
                    behavior: SnackBarBehavior.floating,
                    width: 220,
                  ));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                foregroundColor: Color(0xFFFAF1DE),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Agregar a la orden',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    ),
  );
  commentController.dispose();
}

/// Bottom sheet para "Lo dulce": separa Molletes / Hot Cakes / Churros en
/// 3 opciones, cada una con su selector apropiado.
void showLoDulcePickerSheet(BuildContext context, List<Dish> items, {String? replaceKey}) {
  Dish? findFirst(bool Function(Dish) test) {
    for (final d in items) {
      if (test(d)) return d;
    }
    return null;
  }

  final molletes = findFirst((d) => d.name.toLowerCase().contains('mollete'));
  final hotCakes = items.where((d) => d.name.toLowerCase().contains('hot cake')).toList();
  final churros = findFirst((d) => d.name.toLowerCase().contains('churro'));

  // Cualquier otro platillo de "Lo dulce" que no sea Molletes/Hot Cakes/Churros
  // (por ejemplo Galletas u otros postres nuevos) se muestra también, uno por uno,
  // para que no quede invisible en el picker.
  final otros = items.where((d) =>
      d != molletes &&
      !hotCakes.contains(d) &&
      d != churros).toList();

  final options = <(String, IconData, VoidCallback)>[
    if (molletes != null)
      ('Molletes Dulces', Icons.breakfast_dining, () {
        _showMolletesDulcesDialog(context, molletes, replaceKey: replaceKey);
      }),
    if (hotCakes.isNotEmpty)
      ('Hot Cakes', Icons.cake, () {
        addMultiFlavorVariantToCart(context, hotCakes, 'Hot Cakes', 'Hot Cakes', replaceKey: replaceKey);
      }),
    if (churros != null)
      ('Churros', Icons.bakery_dining, () {
        _addPreparedDishWithComment(context, churros, replaceKey: replaceKey);
      }),
    for (final dish in otros)
      (dish.name, Icons.cookie, () {
        _addPreparedDishWithComment(context, dish, replaceKey: replaceKey);
      }),
  ];

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFFFAF1DE),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
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
              child: Text('Lo dulce',
                  style: TextStyle(
                      color: Color(0xFFE07A30),
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            for (final opt in options) ...[
              InkWell(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  opt.$3();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF1DE),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5DCC4), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(opt.$2, size: 28, color: const Color(0xFFFF6D00)),
                      const SizedBox(width: 16),
                      Text(opt.$1,
                          style: const TextStyle(
                              color: Color(0xFFA08F70),
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: const Color(0xFFA08F70), size: 22),
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
  );
}

/// Diálogo específico para Molletes Dulces con selector de "1 Orden" /
/// "1/2 Orden" (la 1/2 orden se calcula a la mitad del precio base).
Future<void> _showMolletesDulcesDialog(BuildContext context, Dish dish, {String? replaceKey}) async {
  final cart = context.read<CartProvider>();
  final commentController = TextEditingController();
  String selectedSize = 'orden'; // 'orden' o 'media'
  int dialogQty = 1;
  final double precioOrden = dish.price;
  final double precioMedia = (dish.price / 2).roundToDouble();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final unitPrice = selectedSize == 'orden' ? precioOrden : precioMedia;
        final total = unitPrice * dialogQty;
        return AlertDialog(
          backgroundColor: const Color(0xFFFAF1DE),
          title: const Text('Molletes Dulces',
              style: TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TAMAÑO',
                      style: TextStyle(
                          color: const Color(0xFF7A6E5A),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    _ToggleOption(
                      icon: Icons.restaurant,
                      label: '1 Orden',
                      price: '\$${precioOrden.toStringAsFixed(0)}',
                      value: selectedSize == 'orden',
                      onChanged: (v) =>
                          setDialogState(() => selectedSize = 'orden'),
                    ),
                    _ToggleOption(
                      icon: Icons.content_cut,
                      label: '1/2 Orden',
                      price: '\$${precioMedia.toStringAsFixed(0)}',
                      value: selectedSize == 'media',
                      onChanged: (v) =>
                          setDialogState(() => selectedSize = 'media'),
                    ),
                  ]),
                  _buildCommentField(commentController),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE5DCC4)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('CANTIDAD',
                          style: TextStyle(
                              color: const Color(0xFF7A6E5A),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1)),
                      Row(children: [
                        InkWell(
                          onTap: () => setDialogState(
                              () { if (dialogQty > 1) dialogQty--; }),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF1DE),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5DCC4)),
                            ),
                            child: const Icon(Icons.remove,
                                color: const Color(0xFF7A6E5A), size: 18),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text('$dialogQty',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFFF6D00),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                        ),
                        InkWell(
                          onTap: () => setDialogState(() => dialogQty++),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFF6D00)),
                            ),
                            child: const Icon(Icons.add,
                                color: Color(0xFFFF6D00), size: 18),
                          ),
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Total: \$${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Color(0xFFFF6D00),
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: const Color(0xFFA08F70))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final comment = commentController.text.trim();
                final isMedia = selectedSize == 'media';
                final dishToAdd = isMedia
                    ? dish.copyWith(
                        price: precioMedia,
                        name: '${dish.name} (1/2 Orden)',
                      )
                    : dish;
                cart.addItemWithGuisados(
                  dishToAdd,
                  [if (comment.isNotEmpty) comment],
                  quantity: dialogQty,
                );
                if (replaceKey != null) cart.removeItem(replaceKey);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        '${dialogQty > 1 ? '$dialogQty × ' : ''}${dishToAdd.name} agregado'),
                    duration: const Duration(milliseconds: 600),
                    behavior: SnackBarBehavior.floating,
                    width: 260,
                  ));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                foregroundColor: Color(0xFFFAF1DE),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Agregar a la orden',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    ),
  );
  commentController.dispose();
}

/// Carga los items de la categoría "extras" (Órdenes Extras) desde Supabase.
/// Se usan como toggles en los diálogos de chilaquiles / huevos / enchiladas
/// para agregar acompañamientos como tocino, huevo extra, bolillo, etc.
Future<List<Dish>> _loadExtras() async {
  try {
    final supabase = Supabase.instance.client;
    final rows = await supabase
        .from('dishes')
        .select()
        .eq('category', 'extras')
        .order('name', ascending: true);
    final all = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Dish.fromJson)
        .where((d) => d.isSale)
        .toList();
    // Deduplicar: en la BD hay variantes del mismo extra (p.ej. "Tocino o
    // Jamón" y "Orden Extra - Tocino o jamón"). Las colapsamos a una sola
    // entrada por nombre normalizado, prefiriendo la versión más limpia
    // (sin el prefijo "Orden Extra -" / sufijo " Extra").
    String normalize(String s) {
      var n = s.toLowerCase().trim();
      n = n.replaceAll(RegExp(r'^orden\s+extra\s*-\s*'), '');
      n = n.replaceAll(RegExp(r'\s+extra$'), '');
      n = n.replaceAll(RegExp(r'\s+'), ' ');
      return n;
    }
    bool isPrefixed(String s) {
      final n = s.toLowerCase().trim();
      return n.startsWith('orden extra') || n.endsWith(' extra');
    }
    final Map<String, Dish> byKey = {};
    for (final d in all) {
      final key = normalize(d.name);
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = d;
      } else {
        // Si la nueva es "limpia" y la existente está prefijada, reemplazar.
        if (isPrefixed(existing.name) && !isPrefixed(d.name)) {
          byKey[key] = d;
        }
      }
    }
    final deduped = byKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return deduped;
  } catch (_) {
    return [];
  }
}

/// Widget reutilizable que muestra una sección "ÓRDENES EXTRAS" con los
/// items toggleables. Recibe la lista de extras y el set de ids seleccionados.
Widget _buildExtrasSection({
  required List<Dish> extras,
  required Set<String> selectedIds,
  required void Function(String id) onToggle,
}) {
  if (extras.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 12),
      const Divider(color: Color(0xFFE5DCC4)),
      const SizedBox(height: 8),
      const Text('ÓRDENES EXTRAS',
          style: TextStyle(
              color: const Color(0xFF7A6E5A),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: extras.map((e) {
          final selected = selectedIds.contains(e.id);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onToggle(e.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFFF6D00).withValues(alpha: 0.18)
                    : const Color(0xFFFAF1DE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFF6D00)
                      : const Color(0xFFE5DCC4),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.add_circle_outline,
                    size: 16,
                    color: selected
                        ? const Color(0xFFFF6D00)
                        : Color(0xFFA08F70),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${e.name}  \$${e.price.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: selected ? Color(0xFFFAF1DE) : Color(0xFF7A6E5A),
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ],
  );
}

Future<void> addDishToCart(BuildContext context, Dish dish, {String? replaceKey}) async {
  final cart = context.read<CartProvider>();
  final nameLower = dish.name.toLowerCase();
  final bool isRefresco = nameLower.contains('refresco');
  final bool isAguaFresca = (nameLower.contains('agua fresca') || nameLower.startsWith('agua')) &&
      !nameLower.contains('natural');
  final bool isJugo = dish.category == 'jugos' || nameLower.contains('jugo');
  final bool isChoco = nameLower.contains('choco');
  final bool isTe = nameLower.startsWith('té') || nameLower.startsWith('te ') || nameLower == 'te';

  if (isRefresco || isAguaFresca || isJugo || isChoco || isTe) {
    final categoryPrefix = isTe ? 'te' : isChoco ? 'choco' : isJugo ? 'jugo' : isRefresco ? 'refresco' : 'agua';
    final drinkIcon = isTe ? Icons.emoji_food_beverage : isChoco ? Icons.icecream : isJugo ? Icons.blender : isRefresco ? Icons.sports_bar : Icons.local_drink;

    // Cargar tamaños desde drink_type_prices
    List<Map<String, dynamic>> drinkSizes = [];
    try {
      final supabase = Supabase.instance.client;
      final rows = await supabase.from('drink_type_prices').select('type, price').order('price', ascending: true);
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

    // Para Agua Fresca: buscar también el dish "Agua Natural" para ofrecerlo
    // como un sabor más ("Natural") sin que el usuario tenga que volver al menú.
    Dish? aguaNaturalDish;
    if (isAguaFresca) {
      try {
        final supabase = Supabase.instance.client;
        final rows = await supabase
            .from('dishes')
            .select()
            .ilike('name', '%agua natural%');
        final list = (rows as List)
            .cast<Map<String, dynamic>>()
            .map(Dish.fromJson)
            .toList();
        if (list.isNotEmpty) aguaNaturalDish = list.first;
      } catch (_) {}
    }

    String? selectedSizeType; // e.g. 'refresco_600', 'agua_500ml'
    String? selectedSabor;
    int dialogQty = 1;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Sabores según el tamaño seleccionado. Si no hay NINGÚN
            // tamaño configurado (ej. Choco/Té, de tamaño fijo),
            // flavorsByType queda vacío — hay que caer directo a
            // genericFlavors (el respaldo), si no la lista de sabores
            // se queda vacía por completo.
            final List<String> baseSabores = selectedSizeType != null
                ? (flavorsByType[selectedSizeType!] ?? genericFlavors)
                : (flavorsByType.isEmpty
                    ? genericFlavors
                    : (flavorsByType.values.fold<Set<String>>({}, (s, l) => s..addAll(l)).toList()..sort()));
            // Para Agua Fresca, agregar "Natural" como un sabor extra
            // (mapea al dish de Agua Natural).
            final bool hasAguaNatural = aguaNaturalDish != null;
            final currentSabores = [
              ...baseSabores.where((s) {
                final n = s.toLowerCase().trim();
                if (n == 'natural') return false;
                // Evita el duplicado: si existe el dish dedicado de Agua
                // Natural, no mostramos también el sabor "Agua Natural".
                if (n == 'agua natural' && hasAguaNatural) return false;
                return true;
              }),
              if (hasAguaNatural) 'Agua Natural',
            ];
            // Cuando se elige "Agua Natural", el tamaño no aplica (es de
            // tamaño fijo). Ocultamos el selector de TAMAÑO en ese caso.
            final bool isNaturalSelected = selectedSabor == 'Agua Natural';

            return AlertDialog(
              backgroundColor: const Color(0xFFFAF1DE),
              title: Text(
                isRefresco ? '¿De qué sabor/marca?' : isJugo ? '¿Qué jugo?' : '¿De qué sabor?',
                style: TextStyle(color: const Color(0xFF3D2E1A), fontWeight: FontWeight.w700, fontSize: MediaQuery.of(ctx).size.width < 380 ? 14 : 16),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (drinkSizes.isNotEmpty && !isNaturalSelected) ...[
                        const Text('TAMAÑO',
                            style: TextStyle(color: const Color(0xFF7A6E5A), fontSize: 11,
                                fontWeight: FontWeight.w600, letterSpacing: 1)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: drinkSizes.map((s) {
                            final type = s['type'] as String;
                            final label = _formatDrinkSizeLabel(type);
                            final priceNum = s['price'];
                            final priceStr = priceNum != null
                                ? '\$${(priceNum as num).toStringAsFixed(0)}'
                                : null;
                            return _ToggleOption(
                              icon: drinkIcon,
                              label: label,
                              price: priceStr,
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
                        const Divider(color: Color(0xFFE5DCC4)),
                        const SizedBox(height: 8),
                      ],
                      const Text('SABOR',
                          style: TextStyle(color: const Color(0xFF7A6E5A), fontSize: 11,
                              fontWeight: FontWeight.w600, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: MediaQuery.of(ctx).size.width < 400 ? 2 : 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 6,
                          mainAxisExtent: 46,
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
                                    : const Color(0xFFFAF1DE),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 14,
                                    color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      sabor,
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFF7A6E5A),
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
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFFE5DCC4)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('CANTIDAD',
                              style: TextStyle(color: const Color(0xFF7A6E5A), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                          Row(
                            children: [
                              InkWell(
                                onTap: () => setDialogState(() { if (dialogQty > 1) dialogQty--; }),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAF1DE),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5DCC4)),
                                  ),
                                  child: const Icon(Icons.remove, color: const Color(0xFF7A6E5A), size: 18),
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                child: Text(
                                  '$dialogQty',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                              ),
                              InkWell(
                                onTap: () => setDialogState(() => dialogQty++),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFF6D00)),
                                  ),
                                  child: const Icon(Icons.add, color: Color(0xFFFF6D00), size: 18),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: const Color(0xFFA08F70))),
                ),
                TextButton(
                  onPressed: (selectedSabor == null ||
                          (drinkSizes.isNotEmpty &&
                              !isNaturalSelected &&
                              selectedSizeType == null))
                      ? null
                      : () async {
                    Navigator.pop(ctx);
                    // Caso especial: si el sabor elegido es "Natural" y
                    // existe el dish de Agua Natural, usamos ese (precio y
                    // nombre vienen de la BD).
                    if (isNaturalSelected && aguaNaturalDish != null) {
                      cart.addItemWithGuisados(aguaNaturalDish!, [], quantity: dialogQty);
                      if (replaceKey != null) cart.removeItem(replaceKey);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${dialogQty > 1 ? '$dialogQty × ' : ''}${aguaNaturalDish!.name} agregado'),
                            duration: const Duration(milliseconds: 500),
                            behavior: SnackBarBehavior.floating,
                            width: 280,
                          ),
                        );
                      }
                      return;
                    }
                    // Agua Fresca no tiene variantes de tamaño configuradas
                    // en drink_type_prices (siempre es de 600 ml), así que
                    // el selector de TAMAÑO no aparece. Para que igual
                    // salga "600 ml" en la comanda impresa (como ya pasa
                    // con refrescos), lo agregamos por defecto aquí.
                    final sizeLabel = selectedSizeType != null
                        ? _formatDrinkSizeLabel(selectedSizeType!)
                        : (isAguaFresca && !isNaturalSelected ? '600 ml' : null);
                    final extras = [
                      if (sizeLabel != null) sizeLabel,
                      selectedSabor!,
                    ];
                    Dish finalDish = dish;
                    if (selectedSizeType != null) {
                      final price = await _loadDrinkPrice(selectedSizeType!);
                      finalDish = dish.copyWith(
                        price: price,
                        name: _drinkDisplayName(selectedSizeType!),
                      );
                    }
                    cart.addItemWithGuisados(finalDish, extras, quantity: dialogQty);
                    if (replaceKey != null) cart.removeItem(replaceKey);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${dialogQty > 1 ? '$dialogQty × ' : ''}${finalDish.name} ($selectedSabor) agregado'),
                          duration: const Duration(milliseconds: 500),
                          behavior: SnackBarBehavior.floating,
                          width: 280,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00),
                    foregroundColor: Color(0xFFFAF1DE),
                    disabledBackgroundColor: const Color(0xFFE5DCC4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Agregar a la orden', style: TextStyle(fontWeight: FontWeight.bold)),
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
    if (replaceKey != null) cart.removeItem(replaceKey);
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
    await _addPreparedDishWithComment(context, dish, replaceKey: replaceKey);
    return;
  }


  if (!dish.requiresGuisado && !isChilaquil) {
    // Platillos preparados que se agregan directo → permitir comentario.
    // Bebidas (alcohol, etc.) se agregan sin diálogo.
    if (_isPreparedDishes([dish])) {
      await _addPreparedDishWithComment(context, dish, replaceKey: replaceKey);
      return;
    }
    cart.addItem(dish);
    if (replaceKey != null) cart.removeItem(replaceKey);
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
        .order('name', ascending: true);
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
  // Filtro CON CARNE / SIN CARNE para el selector de guisado del
  // diálogo single-dish.
  bool guisadoMeatFilter = true;
  final bool isGordita = dish.category == 'gorditas' ||
      dish.name.toLowerCase().contains('gordita');
  final bool isTapa = dish.category == 'tapas' ||
      dish.name.toLowerCase().contains('tapa');
  final bool showOptions = isGordita || isTapa || isChilaquil;

  // Cargar ÓRDENES EXTRAS si aplica (chilaquiles, huevos, enchiladas).
  // Los seleccionados se agregan al carrito como items independientes.
  List<Dish> extrasDisponibles = [];
  final bool showExtras = isChilaquil;
  if (showExtras) {
    extrasDisponibles = await _loadExtras();
    if (!context.mounted) return;
  }
  final Set<String> selectedExtraIds = {};
  // Sub-selector cuando el extra es "Orden Extra - Guisado": el usuario debe
  // elegir cuál guisado lleva el extra.
  bool isGuisadoExtra(Dish d) =>
      d.name.toLowerCase().contains('guisado');
  final bool hasGuisadoExtra = extrasDisponibles.any(isGuisadoExtra);
  String? selectedGuisadoForExtra;
  bool guisadoExtraMeatFilter = true;

  // Cargar ambas variantes de gordita (Maíz / Harina) si aplica, para que el
  // diálogo permita cambiar la base sin cerrarse.
  Dish? gorditaMaizDish;
  Dish? gorditaHarinaDish;
  if (isGordita) {
    try {
      final rows = await supabase
          .from('dishes')
          .select()
          .eq('category', 'gorditas');
      final all = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(Dish.fromJson)
          .toList();
      for (final d in all) {
        final n = d.name.toLowerCase().trim();
        if (n == 'gordita de harina' || n.contains('harina')) {
          gorditaHarinaDish ??= d;
        } else if (n == 'gordita de maíz' ||
            n == 'gordita de maiz' ||
            n.contains('maíz') ||
            n.contains('maiz')) {
          gorditaMaizDish ??= d;
        }
      }
    } catch (e) {
      debugPrint('Error cargando variantes de gordita: $e');
    }
  }
  // Si solo se encontró una variante, no mostramos selector.
  final bool showBaseSelector =
      isGordita && gorditaMaizDish != null && gorditaHarinaDish != null;
  // Estado de la base seleccionada — arranca según la tarjeta que se tocó.
  String selectedBase =
      dish.name.toLowerCase().contains('harina') ? 'harina' : 'maíz';
  Dish currentDish() {
    if (!isGordita) return dish;
    if (selectedBase == 'harina') return gorditaHarinaDish ?? dish;
    return gorditaMaizDish ?? dish;
  }

  bool conQueso = false;
  bool conHuevo = false; // solo para chilaquiles
  bool frita = false;
  final Set<String> selectedSalsas = {}; // multi-selección (máx 2) para chilaquiles
  String? selectedTerminoHuevo; // solo para chilaquiles con huevo
  int dialogQty = 1;
  // Comentarios libres para platillos preparados (chilaquiles, gorditas, tapas, guisados)
  final allowsComment = _isPreparedDishes([dish]);
  final commentController = TextEditingController();

  const salsasChilaquil = ['Roja', 'Verde', 'Ranchera'];
  const terminosHuevo = ['Tierno', 'Cocido', 'Sellados'];

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Recalcula en cada rebuild: la base puede haber cambiado.
          final Dish activeDish = currentDish();
          final bool canBeFrita =
              isGordita && !(selectedBase == 'harina');
          return AlertDialog(
            backgroundColor: const Color(0xFFFAF1DE),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isChilaquil
                      ? '¿Cómo quieres los ${activeDish.name}?'
                      : (isGordita
                          ? '¿Qué Gordita?'
                          : '¿Qué guisado lleva el ${activeDish.name}?'),
                  style: TextStyle(color: const Color(0xFF3D2E1A), fontWeight: FontWeight.w700, fontSize: MediaQuery.of(ctx).size.width < 380 ? 14 : 16),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '\$${activeDish.price.toStringAsFixed(0)}',
                      style: const TextStyle(color: Color(0xFFFF6D00), fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    if ((activeDish.piecesPerOrder ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6D00).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFFF6D00).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          '${activeDish.piecesPerOrder} ${activeDish.piecesPerOrder == 1 ? "pieza" : "piezas"}',
                          style: const TextStyle(
                            color: Color(0xFFFF6D00),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // BASE + Opciones en una sola fila para maximizar el
                  // espacio de los guisados. BASE (Maíz/Harina) a la
                  // izquierda; Opciones (Queso/Frita) a la derecha.
                  if (showBaseSelector || showOptions) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showBaseSelector)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'BASE',
                                  style: TextStyle(
                                      color: Color(0xFF7A6E5A),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _BaseChip(
                                      label: 'Maíz',
                                      price: gorditaMaizDish!.price,
                                      selected: selectedBase == 'maíz',
                                      onTap: () => setDialogState(() {
                                        selectedBase = 'maíz';
                                      }),
                                    ),
                                    const SizedBox(width: 6),
                                    _BaseChip(
                                      label: 'Harina',
                                      price: gorditaHarinaDish!.price,
                                      selected: selectedBase == 'harina',
                                      onTap: () => setDialogState(() {
                                        selectedBase = 'harina';
                                        frita = false;
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (showBaseSelector && showOptions)
                          const SizedBox(width: 10),
                        if (showOptions)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Opciones',
                                  style: TextStyle(
                                      color: Color(0xFF7A6E5A),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1),
                                ),
                                const SizedBox(height: 4),
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
                                        price: isTapa
                                            ? '+\$25'
                                            : (isGordita ? '+\$5' : null),
                                        value: conQueso,
                                        onChanged: (v) =>
                                            setDialogState(() => conQueso = v),
                                      ),
                                    if (isGordita) ...[
                                      const SizedBox(width: 6),
                                      _ToggleOption(
                                        icon: Icons.local_fire_department,
                                        label: 'Frita',
                                        value: frita,
                                        enabled: canBeFrita,
                                        onChanged: canBeFrita
                                            ? (v) =>
                                                setDialogState(() => frita = v)
                                            : (_) {},
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(color: Color(0xFFE5DCC4), height: 4),
                    const SizedBox(height: 4),
                  ],

                  // Término del huevo (solo cuando conHuevo está activo)
                  if (isChilaquil && conHuevo) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'TÉRMINO DEL HUEVO',
                      style: TextStyle(
                          color: const Color(0xFF7A6E5A),
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
                                    : const Color(0xFFFAF1DE),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    termino,
                                    style: TextStyle(
                                      color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
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
                    const Divider(color: Color(0xFFE5DCC4)),
                  ],

                  // Selector de salsa para chilaquiles (multi, máx 2)
                  if (isChilaquil) ...[
                    const Text(
                      'SALSA (máx. 2)',
                      style: TextStyle(
                          color: const Color(0xFF7A6E5A),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: salsasChilaquil.map((salsa) {
                        final isSelected = selectedSalsas.contains(salsa);
                        final canAddMore = selectedSalsas.length < 2;
                        return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setDialogState(() {
                              if (isSelected) {
                                selectedSalsas.remove(salsa);
                              } else if (canAddMore) {
                                selectedSalsas.add(salsa);
                              }
                              // Si no está seleccionado y ya hay 2, se ignora.
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                                    : const Color(0xFFFAF1DE),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFE5DCC4),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    salsa,
                                    style: TextStyle(
                                      color: isSelected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                                ],
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
                      style: TextStyle(color: const Color(0xFF7A6E5A)),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GUISADO',
                          style: TextStyle(
                              color: const Color(0xFF7A6E5A),
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
                                : Color(0xFFB6A88A),
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
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? const Color(0xFFFF6D00).withValues(alpha: 0.18)
                                      : const Color(0xFFFAF1DE),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isChecked
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFFFF6D00).withValues(alpha: 0.35),
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
                                      size: 14,
                                      color: const Color(0xFFFF6D00),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${meatEmoji(g['meat_type'] as String?)} $name'.trim(),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: const Color(0xFFFF6D00),
                                        fontSize: 11,
                                        fontWeight: isChecked ? FontWeight.w700 : FontWeight.w600,
                                      ),
                                    ),
                                    _chileRow(g['spice_level'] as int? ?? 0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        // Mostrar todos los guisados sin filtro CON CARNE /
                        // SIN CARNE (los botones de filtro fueron removidos).
                        final activeList = guisados.toList();
                        Widget filterTab(String label, bool value) {
                          final isActive = guisadoMeatFilter == value;
                          return Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() {
                                guisadoMeatFilter = value;
                              }),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  // Tabs CON CARNE / SIN CARNE: ambos en
                                  // fondo claro con texto naranja/taupe —
                                  // nada de blanco sobre dark navy.
                                  color: isActive
                                      ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                                      : const Color(0xFFFAF1DE),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isActive
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFFE5DCC4),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isActive
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFFA08F70),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ScrollableWithDownHint(
                              height: 480,
                              hintColor: const Color(0xFFFF6D00),
                              fadeColor: const Color(0xFFFAF1DE),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children:
                                    activeList.map(buildItem).toList(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  // Selector de cantidad
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE5DCC4)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('CANTIDAD',
                          style: TextStyle(color: Color(0xFF7A6E5A), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => setDialogState(() { if (dialogQty > 1) dialogQty--; }),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF1DE),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE5DCC4)),
                              ),
                              child: const Icon(Icons.remove, color: Color(0xFF7A6E5A), size: 18),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '$dialogQty',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF3D2E1A), fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          InkWell(
                            onTap: () => setDialogState(() => dialogQty++),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFF6D00)),
                              ),
                              child: const Icon(Icons.add, color: Color(0xFFFF6D00), size: 18),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (allowsComment) _buildCommentField(commentController),
                  if (showExtras)
                    _buildExtrasSection(
                      extras: extrasDisponibles,
                      selectedIds: selectedExtraIds,
                      onToggle: (id) => setDialogState(() {
                        if (selectedExtraIds.contains(id)) {
                          selectedExtraIds.remove(id);
                          final d = extrasDisponibles
                              .firstWhere((e) => e.id == id);
                          if (isGuisadoExtra(d)) {
                            selectedGuisadoForExtra = null;
                          }
                        } else {
                          selectedExtraIds.add(id);
                        }
                      }),
                    ),
                  // Sub-selector: cuando se elige una ÓRDEN EXTRA de guisado,
                  // pedir cuál guisado lleva.
                  if (showExtras &&
                      hasGuisadoExtra &&
                      guisados.isNotEmpty &&
                      extrasDisponibles.any((e) =>
                          isGuisadoExtra(e) &&
                          selectedExtraIds.contains(e.id))) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    const Text('GUISADO DEL EXTRA',
                        style: TextStyle(
                            color: Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    _ScrollableWithDownHint(
                      height: 450,
                      hintColor: const Color(0xFFFF6D00),
                      fadeColor: const Color(0xFFFAF1DE),
                      child: LayoutBuilder(builder: (_, c) {
                        final itemW = (c.maxWidth - 18) / 4;
                        Widget buildItem(Map<String, dynamic> g) {
                          final name = g['name'] as String;
                          final isSel = selectedGuisadoForExtra == name;
                          return SizedBox(
                            width: itemW,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setDialogState(() {
                                selectedGuisadoForExtra = isSel ? null : name;
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? const Color(0xFFFF6D00)
                                          .withValues(alpha: 0.18)
                                      : const Color(0xFFFAF1DE),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSel
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFFFF6D00)
                                            .withValues(alpha: 0.35),
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isSel
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      size: 14,
                                      color: const Color(0xFFFF6D00),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${meatEmoji(g['meat_type'] as String?)} $name'.trim(),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: const Color(0xFFFF6D00),
                                        fontSize: 11,
                                        fontWeight: isSel
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    _chileRow(g['spice_level'] as int? ?? 0),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        final activeList = guisados.toList();
                        Widget filterTab(String label, bool value) {
                          final isActive =
                              guisadoExtraMeatFilter == value;
                          return Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() {
                                guisadoExtraMeatFilter = value;
                              }),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                                decoration: BoxDecoration(
                                  // Tabs CON CARNE / SIN CARNE: ambos en
                                  // fondo claro con texto naranja/taupe —
                                  // nada de blanco sobre dark navy.
                                  color: isActive
                                      ? const Color(0xFFFF6D00).withValues(alpha: 0.15)
                                      : const Color(0xFFFAF1DE),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isActive
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFFE5DCC4),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isActive
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFFA08F70),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: activeList.map(buildItem).toList(),
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                  // Total dinámico
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE5DCC4)),
                  const SizedBox(height: 4),
                  Text(
                    // Precio con queso extra: gordita +$10, tapa +$25.
                    // Otros platillos con queso no aumentan.
                    'Total: \$${((activeDish.price + (conQueso ? (isTapa ? 25 : (isGordita ? 5 : 0)) : 0)) * dialogQty + extrasDisponibles.where((e) => selectedExtraIds.contains(e.id)).fold<double>(0, (s, e) => s + e.price)).toStringAsFixed(0)}${dialogQty > 1 ? ' (×$dialogQty)' : ''}',
                    style: const TextStyle(
                      color: Color(0xFFFF6D00),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar',
                    style: TextStyle(color: const Color(0xFFA08F70))),
              ),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                onPressed: () {
                  // Chilaquiles requieren al menos 1 salsa (máx 2)
                  if (isChilaquil && selectedSalsas.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Selecciona al menos una salsa (máximo 2)'),
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
                  // Si se eligió "Orden Extra - Guisado", exigir guisado.
                  if (showExtras &&
                      hasGuisadoExtra &&
                      extrasDisponibles.any((e) =>
                          isGuisadoExtra(e) &&
                          selectedExtraIds.contains(e.id)) &&
                      selectedGuisadoForExtra == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Selecciona el guisado del extra'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final comment = commentController.text.trim();
                  final extras = [
                    if (isChilaquil && selectedSalsas.isNotEmpty) 'Salsa ${selectedSalsas.join(" + ")}',
                    if (isChilaquil && conHuevo) 'Con huevo ${selectedTerminoHuevo != null ? "(${selectedTerminoHuevo})" : ""}',
                    if (!isChilaquil && conQueso) 'Con queso',
                    if (frita) 'Frita',
                    if (!isChilaquil) ...selected,
                    if (allowsComment && comment.isNotEmpty) comment,
                  ];
                  // Aplicar el extra de queso al precio: gordita +$10,
                  // tapa +$25, resto sin cambio.
                  final quesoExtra = conQueso
                      ? (isTapa ? 25.0 : (isGordita ? 5.0 : 0.0))
                      : 0.0;
                  final finalDish = quesoExtra > 0
                      ? activeDish.copyWith(price: activeDish.price + quesoExtra)
                      : activeDish;
                  cart.addItemWithGuisados(finalDish, extras, quantity: dialogQty);
                  if (replaceKey != null) cart.removeItem(replaceKey);
                  // Agregar las órdenes extras seleccionadas como items
                  // del carrito; usamos addItem para que si el mismo
                  // extra ya existe (mismo cliente) incremente la
                  // cantidad en vez de crear una nueva fila repetida.
                  for (final extraId in selectedExtraIds) {
                    final extra = extrasDisponibles
                        .firstWhere((e) => e.id == extraId);
                    if (isGuisadoExtra(extra) &&
                        selectedGuisadoForExtra != null) {
                      cart.addItemWithGuisados(
                          extra, [selectedGuisadoForExtra!]);
                    } else {
                      cart.addItem(extra);
                    }
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${dialogQty > 1 ? '$dialogQty × ' : ''}${activeDish.name} agregado'),
                        duration: const Duration(milliseconds: 500),
                        behavior: SnackBarBehavior.floating,
                        width: 220,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Color(0xFFFAF1DE),
                  disabledBackgroundColor: const Color(0xFFE5DCC4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Agregar a la orden', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ),
            ],
          );
        },
      );
    },
  );
  commentController.dispose();
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
                  if ((dish.piecesPerOrder ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${dish.piecesPerOrder} ${dish.piecesPerOrder == 1 ? "pieza" : "piezas"} por orden',
                        style: const TextStyle(
                          color: Color(0xFFA08F70),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                            '\$${dish.price.toStringAsFixed(dish.price % 1 == 0 ? 0 : 2)}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
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
                                    minHeight: 36,
                                    minWidth: 36,
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
                                  minHeight: 36,
                                  minWidth: 36,
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
    List<Dish> dishes, String displayName, String categoryPrefix,
    {bool multiSelectFlavors = false, String? replaceKey}) async {
  final cart = context.read<CartProvider>();

  // Deduplicar variantes equivalentes con / sin prefijo 'Orden Extra - '
  // o sufijo ' Extra' (p.ej. 'Tocino o Jamón' y 'Orden Extra - Tocino o
  // jamón' apuntan al mismo producto). Preferimos la versión más limpia.
  String normalizeDishName(String s) {
    var n = s.toLowerCase().trim();
    n = n.replaceAll(RegExp(r'^orden\s+extra\s*-\s*'), '');
    n = n.replaceAll(RegExp(r'\s+extra$'), '');
    n = n.replaceAll(RegExp(r'\s+'), ' ');
    return n;
  }
  bool isPrefixedDishName(String s) {
    final n = s.toLowerCase().trim();
    return n.startsWith('orden extra') || n.endsWith(' extra');
  }
  final Map<String, Dish> dedupByKey = {};
  for (final d in dishes) {
    final key = normalizeDishName(d.name);
    final existing = dedupByKey[key];
    if (existing == null) {
      dedupByKey[key] = d;
    } else if (isPrefixedDishName(existing.name) && !isPrefixedDishName(d.name)) {
      dedupByKey[key] = d;
    }
  }
  dishes = dedupByKey.values.toList();

  // Detectar qué dimensiones tienen variación real
  final sizes = dishes.map((d) => _extractSize(d.name)).toSet();
  final quantities =
      dishes.map((d) => _extractQuantity(d.name)).whereType<int>().toSet();
  final flavors =
      dishes.map((d) => _extractFlavor(d.name, categoryPrefix)).toSet();
  // Orden custom para Menudo: Chico → Mediano → Grande → resto alfabético
  // (p.ej. las cuajadillas quedan al final, no entremezcladas).
  const menudoSizeOrder = ['chico', 'mediano', 'grande'];
  int menudoRank(String s) {
    final n = s.toLowerCase().trim();
    final i = menudoSizeOrder.indexWhere((k) => n == k);
    return i == -1 ? menudoSizeOrder.length : i;
  }
  final isMenudoCategory = categoryPrefix.toLowerCase() == 'menudo';
  final sortedFlavors = flavors.toList()
    ..sort((a, b) {
      if (isMenudoCategory) {
        final ra = menudoRank(a);
        final rb = menudoRank(b);
        if (ra != rb) return ra.compareTo(rb);
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  final sortedQty = quantities.toList()..sort();

  final showSize = sizes.length > 1;
  final showQty = quantities.length > 1;
  final showFlavor = flavors.length > 1;

  String? selectedSize = showSize ? null : (sizes.isNotEmpty ? sizes.first : null);
  int? selectedQty = showQty ? null : (quantities.isNotEmpty ? quantities.first : null);
  // Multi-select: se pueden elegir varios sabores a la vez
  final Set<String> selectedFlavors =
      showFlavor ? {} : (flavors.isNotEmpty ? {flavors.first} : {});
  int? selectedEnmolQty; // cantidad solo para enmoladas (single-flavor)
  int dialogQty = 1;

  // Menudo: tipo de carne (Pata, Libro, Panza, Callo, Pañal, Surtido)
  final isMenudo = categoryPrefix.toLowerCase() == 'menudo';
  final Set<String> selectedTiposCarne = {};
  const menudoTipos = ['Pata', 'Libro', 'Panza', 'Callo', 'Pañal', 'Surtido'];

  // Huevos: selector de término (Tierno, Cocido, Sellados)
  final isHuevoCategory = dishes.any((d) =>
      d.category == 'huevos' ||
      d.name.toLowerCase().contains('huevo'));
  String? selectedTerminoHuevo;
  const terminosHuevo = ['Tierno', 'Cocido', 'Sellados'];

  // Huevo Revuelto: obliga a elegir Jamón o Tocino.
  String? selectedProteinaHuevo;
  const proteinasHuevo = ['Jamón', 'Tocino'];

  // Quesadilla de Maíz: opción "Frita" (de comal por default). Es
  // exclusiva de este platillo — no aplica a los demás sabores del
  // grupo (Burrito, Taco Chico, etc.).
  bool selectedFritaQuesadilla = false;

  // Lo Dulce: selector de piezas (1, 2, 3)
  // Detecta por categoryPrefix (Lo dulce) o por categoría de los platillos
  final isLoDulce = categoryPrefix.toLowerCase() == 'lo dulce' ||
      dishes.any((d) => d.category == 'lo_dulce' || d.category == 'dessert');
  int? selectedPiezasLoDulce;
  const loDulcePiezas = [1, 2, 3];

  // Sabores que tienen variantes de piezas en la BD (e.g. Hot Cakes pero no Churros)
  final flavorsWithQtyVariants = dishes
      .where((d) => _extractQuantity(d.name) != null)
      .map((d) => _extractFlavor(d.name, categoryPrefix))
      .toSet();

  // Cargar guisados si algún platillo de la categoría los requiere o si
  // alguna ÓRDEN EXTRA es de guisado (en ese caso al togglearla el
  // mesero podrá elegir cuál guisado lleva el extra).
  List<Map<String, dynamic>> guisados = [];
  Future<void> loadGuisados() async {
    try {
      final supabase = Supabase.instance.client;
      final rows = await supabase
          .from('guisados')
          .select()
          .eq('available', true)
          .order('name', ascending: true);
      guisados = (rows as List).cast<Map<String, dynamic>>()
          .where((g) {
            final branch = g['branch_name'] as String?;
            return branch == null || branch == Globals.currentBranch;
          })
          .toList();
    } catch (e) {
      debugPrint('Error cargando guisados: $e');
    }
  }
  if (dishes.any((d) => d.requiresGuisado)) {
    await loadGuisados();
    if (!context.mounted) return;
  }
  List<String> selectedGuisados = [];
  // Filtro CON CARNE / SIN CARNE compartido por los selectores de
  // guisado del diálogo mixto y del sub-selector de extra-guisado.
  bool mixedGuisadoMeatFilter = true;
  // Guisado asociado a la ÓRDEN EXTRA de guisado (al toggle aparece el
  // sub-selector). Sólo un guisado por extra.
  String? selectedGuisadoForExtra;

  // Salsa para chilaquiles (también aplica cuando el sabor "Chilaquiles" se
  // selecciona dentro de un mixto, p.ej. Molletes → Chilaquiles).
  final Set<String> selectedSalsasChilaquil = {};
  const salsasChilaquilOptions = ['Roja', 'Verde', 'Ranchera'];
  bool conQuesoExtra = false;
  const quesoExtraPrecio = 5.0;

  // Comentarios libres (ej. "sin lechuga, sin chile") para platillos preparados
  final allowsComment = _isPreparedDishes(dishes);
  final commentController = TextEditingController();

  // ÓRDENES EXTRAS: solo aplica para huevos y enchiladas.
  final bool showExtras = dishes.any((d) {
        final c = d.category.toLowerCase();
        return c == 'huevos' || c == 'enchiladas';
      }) ||
      categoryPrefix.toLowerCase() == 'huevos' ||
      categoryPrefix.toLowerCase() == 'enchiladas';
  List<Dish> extrasDisponibles = [];
  if (showExtras) {
    extrasDisponibles = await _loadExtras();
    if (!context.mounted) return;
  }
  final Set<String> selectedExtraIds = {};
  // Detecta si un dish-extra es del tipo "guisado" (Orden Extra - Guisado,
  // Guisado Extra, etc.) — al togglearlo se abre el sub-selector de guisados.
  bool isGuisadoExtra(Dish d) =>
      d.name.toLowerCase().contains('guisado');
  final bool hasGuisadoExtra =
      extrasDisponibles.any(isGuisadoExtra);
  if (hasGuisadoExtra && guisados.isEmpty) {
    await loadGuisados();
    if (!context.mounted) return;
  }

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        // Encontrar el platillo que coincide con cada sabor seleccionado.
        // Para isLoDulce con variantes de piezas (Hot Cakes), usar selectedPiezasLoDulce
        // para el matching en lugar de selectedQty (que se controla con otro picker).
        final Map<String, Dish> matchedByFlavor = {};
        for (final fl in selectedFlavors) {
          final flHasQtyVariants = flavorsWithQtyVariants.contains(fl);
          for (final d in dishes) {
            final dSize = _extractSize(d.name);
            final dQty = _extractQuantity(d.name);
            final dFlavor = _extractFlavor(d.name, categoryPrefix);
            if (showFlavor && dFlavor != fl) continue;
            if (showSize && dSize != selectedSize) continue;
            if (flHasQtyVariants) {
              // Lo dulce: las piezas se controlan con selectedPiezasLoDulce
              final matchQty = isLoDulce ? selectedPiezasLoDulce : selectedQty;
              if (dQty != matchQty) continue;
            } else {
              if (dQty != null) continue; // solo la versión base (sin sufijo pzas.)
            }
            if (!showSize && sizes.isNotEmpty && dSize != sizes.first) continue;
            if (!showFlavor && flavors.isNotEmpty && dFlavor != flavors.first) continue;
            matchedByFlavor[fl] = d;
            break;
          }
        }

        // Para isLoDulce el selector de piezas lo maneja su propia sección;
        // no mostrar el picker genérico de qty para evitar doble selector.
        final anySelectedHasQtyVariants = selectedFlavors.any(
            (fl) => flavorsWithQtyVariants.contains(fl));
        final effectiveShowQty = showQty && anySelectedHasQtyVariants && !isLoDulce;

        // Enmoladas: solo cuando hay exactamente ese sabor seleccionado
        final selectedIsEnmolada = selectedFlavors.length == 1 &&
            selectedFlavors.first.toLowerCase().contains('enmolad');
        // La sección GUISADO se muestra cuando el sabor seleccionado lo
        // requiere. Usamos dos rutas para detectarlo:
        //   1) El dish ya emparejado por sabor+tamaño (matchedByFlavor).
        //   2) Si aún no hay tamaño elegido, comparar por nombre del sabor
        //      contra los dishes — así aparece desde que se elige el sabor.
        // Para sabores que no llevan guisado (Naturales, Chilaquiles,
        // Arrachera) sigue sin aparecer.
        final selectedRequiresGuisado =
            matchedByFlavor.values.any((d) => d.requiresGuisado) ||
                (selectedFlavors.isNotEmpty &&
                    dishes.any((d) {
                      final dFlavor =
                          _extractFlavor(d.name, categoryPrefix);
                      return d.requiresGuisado &&
                          selectedFlavors.contains(dFlavor);
                    }));
        final anyRequiresGuisado = selectedRequiresGuisado;

        // isHuevoCategory detecta si ALGÚN platillo del grupo es huevo (ej.
        // "Huevo Estrellado o Revuelto" dentro de Órdenes Extras, junto con
        // "Orden Extra - Arrachera", "Pieza de Bolillo", etc.). Pero el
        // TÉRMINO DEL HUEVO solo debe pedirse cuando el platillo
        // REALMENTE seleccionado es huevo — si no, un extra que no es
        // huevo (ej. Arrachera) se quedaba bloqueado sin poder agregarse.
        final selectedIsHuevoFlavor = isHuevoCategory &&
            matchedByFlavor.values.any((d) =>
                d.category == 'huevos' || d.name.toLowerCase().contains('huevo'));

        // Huevo Revuelto: exige elegir Jamón o Tocino (solo cuando el
        // sabor realmente seleccionado es un huevo "revuelto").
        final selectedIsRevueltoHuevo = selectedIsHuevoFlavor &&
            matchedByFlavor.values.any((d) =>
                d.name.toLowerCase().contains('revuelto'));

        // Quesadilla de Maíz: la opción "Frita" solo aparece cuando ese
        // es el sabor realmente seleccionado, no para el resto del grupo.
        final selectedIsQuesadillaMaiz = matchedByFlavor.values
            .any((d) => d.name.toLowerCase() == 'quesadilla de maíz');

        // El sabor "Chilaquiles" (p.ej. dentro de Molletes) exige elegir
        // salsa: 1 obligatoria, máx. 2. También aplica si TODO el grupo ya
        // es de categoría "chilaquiles" (ej. "Chilaquiles" vs "Huevo" como
        // variantes) — ahí el nombre del sabor puede ser solo "Huevo" y no
        // contener la palabra "chilaquil", pero sigue siendo un chilaquil.
        final bool isChilaquilesCategory =
            dishes.any((d) => d.category == 'chilaquiles');
        final hasChilaquilFlavor = isChilaquilesCategory ||
            selectedFlavors.any((f) => f.toLowerCase().contains('chilaquil'));

        // Arrachera: ofrece "Con Queso" igual que Chilaquiles (toggle
        // genérico +$5), ya que la mayoría de sus variantes (Burrito, Taco,
        // Volcán, Gordita...) no tienen una versión "con queso" propia en
        // el menú — solo el Bolillo la tiene como platillo separado.
        final bool isArracheraCategory =
            dishes.any((d) => d.category == 'arrachera');
        final bool showQuesoToggle = hasChilaquilFlavor || isArracheraCategory;

        // Lo dulce: el selector PIEZAS solo aplica a sabores que se venden por
        // unidad (Churros, Hot Cakes). Los Molletes se cobran por orden, así
        // que cuando solo hay Molletes seleccionados ocultamos el selector.
        bool isMolleteFlavor(String f) => f.toLowerCase().contains('mollete');
        final needsPiezas =
            isLoDulce && selectedFlavors.any((f) => !isMolleteFlavor(f));

        final canAdd = matchedByFlavor.isNotEmpty &&
            (!showSize || selectedSize != null) &&
            (!effectiveShowQty || selectedQty != null) &&
            (!showFlavor || selectedFlavors.isNotEmpty) &&
            (!selectedIsEnmolada || selectedEnmolQty != null) &&
            (!isMenudo || selectedTiposCarne.isNotEmpty) &&
            (!selectedIsHuevoFlavor || selectedTerminoHuevo != null) &&
            (!selectedIsRevueltoHuevo || selectedProteinaHuevo != null) &&
            (!needsPiezas || selectedPiezasLoDulce != null) &&
            // En el diálogo MIXTO (multi-sabor) no hay toggle Con Queso, así
            // que la única forma de "no dejar la gordita vacía" es exigir al
            // menos un guisado cuando el sabor lo requiere. La opción "solo
            // con queso" vive en el diálogo simple (individual) y ahí sí se
            // permite sin guisado.
            (!selectedRequiresGuisado || selectedGuisados.isNotEmpty) &&
            (!hasChilaquilFlavor || selectedSalsasChilaquil.isNotEmpty) &&
            // Si seleccionaron un extra de guisado, deben elegir cuál.
            (!extrasDisponibles.any((e) =>
                    isGuisadoExtra(e) && selectedExtraIds.contains(e.id)) ||
                selectedGuisadoForExtra != null);

        // Para lo_dulce: la cantidad efectiva se calcula por-platillo.
        // - Molletes Dulces → 1 (una orden, sin multiplicar)
        // - Variante con piezas en el nombre (Hot Cakes 2 pzas.) → 1
        // - Churros u otro sin variantes → selectedPiezasLoDulce
        int qtyForLoDulceDish(Dish d, String flavor) {
          if (isMolleteFlavor(flavor)) return 1;
          if (_extractQuantity(d.name) != null) return 1;
          return selectedPiezasLoDulce ?? 1;
        }

        // Sumar el subtotal real respetando la cantidad por-platillo.
        // Para lo_dulce: multiplicamos también por dialogQty (cantidad general)
        // para que se pueda pedir N veces el mismo postre.
        final double totalPrice = (isLoDulce
                ? matchedByFlavor.entries.fold<double>(0, (s, e) =>
                    s + e.value.price * qtyForLoDulceDish(e.value, e.key))
                : matchedByFlavor.values
                    .fold<double>(0, (s, d) => s + d.price)) *
                dialogQty +
            (showQuesoToggle && conQuesoExtra
                ? quesoExtraPrecio * dialogQty
                : 0);

        // Piezas por orden: prioriza la variante seleccionada (matchedByFlavor);
        // si no hay selección, usa la primera que tenga un valor > 0. Así el
        // chip aparece cuando aunque sea una variante tiene piezas definidas
        // y se actualiza al cambiar de sabor.
        int? headerPieces;
        for (final d in matchedByFlavor.values) {
          final p = d.piecesPerOrder ?? 0;
          if (p > 0) {
            headerPieces = p;
            break;
          }
        }
        headerPieces ??= () {
          for (final d in dishes) {
            final p = d.piecesPerOrder ?? 0;
            if (p > 0) return p;
          }
          return null;
        }();

        return AlertDialog(
          backgroundColor: const Color(0xFFFAF1DE),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(displayName,
                  style: TextStyle(color: const Color(0xFF3D2E1A), fontWeight: FontWeight.w700, fontSize: MediaQuery.of(ctx).size.width < 380 ? 14 : 16)),
              if (headerPieces != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6D00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFF6D00).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '$headerPieces ${headerPieces == 1 ? "pieza" : "piezas"} por orden',
                    style: const TextStyle(
                      color: Color(0xFFFF6D00),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSize && !isLoDulce) ...[
                    const Text('TAMAÑO',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
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
                            price: () {
                              final firstFl = selectedFlavors.isNotEmpty
                                  ? selectedFlavors.first
                                  : sortedFlavors.firstOrNull;
                              final d = dishes.firstWhere(
                                (d) => _extractSize(d.name) == 'orden' &&
                                    (!showFlavor || _extractFlavor(d.name, categoryPrefix) == firstFl),
                                orElse: () => dishes.firstWhere((d) => _extractSize(d.name) == 'orden', orElse: () => dishes.first),
                              );
                              return '\$${d.price.toStringAsFixed(0)}';
                            }(),
                            value: selectedSize == 'orden',
                            onChanged: (v) => setDialogState(
                                () => selectedSize = v ? 'orden' : null),
                          ),
                        if (sizes.contains('media'))
                          _ToggleOption(
                            icon: Icons.content_cut,
                            label: '1/2 Orden',
                            price: () {
                              final firstFl = selectedFlavors.isNotEmpty
                                  ? selectedFlavors.first
                                  : sortedFlavors.firstOrNull;
                              final d = dishes.firstWhere(
                                (d) => _extractSize(d.name) == 'media' &&
                                    (!showFlavor || _extractFlavor(d.name, categoryPrefix) == firstFl),
                                orElse: () => dishes.firstWhere((d) => _extractSize(d.name) == 'media', orElse: () => dishes.first),
                              );
                              return '\$${d.price.toStringAsFixed(0)}';
                            }(),
                            value: selectedSize == 'media',
                            onChanged: (v) => setDialogState(
                                () => selectedSize = v ? 'media' : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                  ],
                  if (effectiveShowQty) ...[
                    const Text('PIEZAS',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
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
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                  ],
                  if (showFlavor) ...[
                    Text(isMenudo ? 'TAMAÑO' : isHuevoCategory ? 'TIPO DE HUEVO' : 'SABOR',
                        style: const TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: sortedFlavors
                          // En Menudo, las cuajadillas se renderizan abajo en
                          // su propia sección, no aquí en TAMAÑO.
                          .where((fl) =>
                              !(isMenudo &&
                                  fl.toLowerCase().contains('cuajadilla')))
                          .map((fl) {
                        Dish? matchDish;
                        for (final d in dishes) {
                          if (_extractFlavor(d.name, categoryPrefix) != fl) continue;
                          if (showSize && selectedSize != null && _extractSize(d.name) != selectedSize) continue;
                          matchDish = d;
                          break;
                        }
                        final priceStr = matchDish != null
                            ? '\$${matchDish.price.toStringAsFixed(0)}'
                            : null;
                        return _ToggleOption(
                          icon: Icons.local_dining,
                          label: fl.isEmpty ? displayName : fl,
                          price: priceStr,
                          value: selectedFlavors.contains(fl),
                          onChanged: (v) => setDialogState(() {
                            if (!multiSelectFlavors) {
                              // Single-select: radio button behavior
                              selectedFlavors.clear();
                              if (v) selectedFlavors.add(fl);
                            } else {
                              if (v) {
                                selectedFlavors.add(fl);
                              } else {
                                selectedFlavors.remove(fl);
                              }
                            }
                            // Resetear cantidad enmoladas si ya no es selección única
                            if (!(selectedFlavors.length == 1 &&
                                selectedFlavors.first.toLowerCase().contains('enmolad'))) {
                              selectedEnmolQty = null;
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                  // Tipo de carne: solo para Menudo
                  if (isMenudo) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('TIPO DE CARNE',
                            style: TextStyle(
                                color: const Color(0xFF7A6E5A),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1)),
                        const SizedBox(width: 8),
                        Text(
                          selectedTiposCarne.isEmpty
                              ? 'elige uno o más'
                              : selectedTiposCarne.join(', '),
                          style: TextStyle(
                            color: selectedTiposCarne.isEmpty
                                ? const Color(0xFFA08F70)
                                : const Color(0xFFFF6D00),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: menudoTipos.map((tipo) {
                        const tipoIcons = <String, IconData>{
                          'Pata':    Icons.pets,
                          'Libro':   Icons.layers,
                          'Panza':   Icons.circle_outlined,
                          'Callo':   Icons.grid_view,
                          'Pañal':   Icons.texture,
                          'Surtido': Icons.shuffle,
                        };
                        return _ToggleOption(
                          icon: tipoIcons[tipo] ?? Icons.soup_kitchen,
                          label: tipo,
                          value: selectedTiposCarne.contains(tipo),
                          onChanged: (v) => setDialogState(() {
                            if (v) selectedTiposCarne.add(tipo);
                            else selectedTiposCarne.remove(tipo);
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                  // CUAJADILLA: en Menudo, debajo de TIPO DE CARNE.
                  // Es alternativa al TAMAÑO (Chico/Mediano/Grande) — son
                  // mutuamente excluyentes (radio behavior).
                  if (isMenudo) ...[
                    Builder(builder: (_) {
                      final cuajadillaFlavors = sortedFlavors
                          .where((f) => f.toLowerCase().contains('cuajadilla'))
                          .toList();
                      if (cuajadillaFlavors.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          const Divider(color: Color(0xFFE5DCC4)),
                          const SizedBox(height: 8),
                          const Text('CUAJADILLA',
                              style: TextStyle(
                                  color: const Color(0xFF7A6E5A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: cuajadillaFlavors.map((fl) {
                              Dish? matchDish;
                              for (final d in dishes) {
                                if (_extractFlavor(d.name, categoryPrefix) != fl) continue;
                                matchDish = d;
                                break;
                              }
                              final priceStr = matchDish != null
                                  ? '\$${matchDish.price.toStringAsFixed(0)}'
                                  : null;
                              final shortLabel = fl
                                  .replaceAll(RegExp(r'^cuajadilla\s+', caseSensitive: false), '')
                                  .replaceAll(RegExp(r'\s*\(.*\)\s*'), '')
                                  .trim();
                              return _ToggleOption(
                                icon: Icons.local_pizza,
                                label: shortLabel.isEmpty ? fl : shortLabel,
                                price: priceStr,
                                value: selectedFlavors.contains(fl),
                                onChanged: (v) => setDialogState(() {
                                  selectedFlavors.clear();
                                  if (v) selectedFlavors.add(fl);
                                }),
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    }),
                  ],
                  // Término del huevo: solo si el platillo elegido es huevo
                  if (selectedIsHuevoFlavor) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    const Text('TÉRMINO DEL HUEVO',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: terminosHuevo.map((termino) => _ToggleOption(
                        icon: Icons.egg_alt,
                        label: termino,
                        value: selectedTerminoHuevo == termino,
                        onChanged: (v) => setDialogState(() {
                          selectedTerminoHuevo = v ? termino : null;
                        }),
                      )).toList(),
                    ),
                  ],
                  // Con Jamón o Tocino: solo si el sabor elegido es huevo revuelto
                  if (selectedIsRevueltoHuevo) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    const Text('¿CON JAMÓN O TOCINO?',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: proteinasHuevo.map((proteina) => _ToggleOption(
                        icon: proteina == 'Jamón' ? Icons.lunch_dining : Icons.outdoor_grill,
                        label: proteina,
                        value: selectedProteinaHuevo == proteina,
                        onChanged: (v) => setDialogState(() {
                          selectedProteinaHuevo = v ? proteina : null;
                        }),
                      )).toList(),
                    ),
                  ],
                  // Frita: exclusivo de Quesadilla de Maíz.
                  if (selectedIsQuesadillaMaiz) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    const Text('¿DE COMAL O FRITA?',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _ToggleOption(
                      icon: Icons.local_fire_department,
                      label: 'Frita',
                      value: selectedFritaQuesadilla,
                      onChanged: (v) => setDialogState(() {
                        selectedFritaQuesadilla = v;
                      }),
                    ),
                  ],
                  // Piezas: solo para Churros / Hot Cakes (no Molletes Dulces,
                  // que se cobran por orden)
                  if (needsPiezas) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    const Text('PIEZAS',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: loDulcePiezas.map((p) => _ToggleOption(
                        icon: Icons.numbers,
                        label: p == 1 ? '1 pieza' : '$p piezas',
                        value: selectedPiezasLoDulce == p,
                        onChanged: (v) => setDialogState(
                            () => selectedPiezasLoDulce = v ? p : null),
                      )).toList(),
                    ),
                  ],
                  // Salsa para sabor Chilaquiles (mismo selector que el
                  // diálogo de chilaquiles puros): 3 opciones, máx. 2.
                  if (hasChilaquilFlavor) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('SALSA (máx. 2)',
                            style: TextStyle(
                                color: const Color(0xFF7A6E5A),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1)),
                        Text(
                          '${selectedSalsasChilaquil.length}/2',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selectedSalsasChilaquil.length >= 2
                                ? const Color(0xFFFF6D00)
                                : Color(0xFFB6A88A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: salsasChilaquilOptions.map((salsa) {
                        final isSelected =
                            selectedSalsasChilaquil.contains(salsa);
                        final canAddMore =
                            selectedSalsasChilaquil.length < 2;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setDialogState(() {
                            if (isSelected) {
                              selectedSalsasChilaquil.remove(salsa);
                            } else if (canAddMore) {
                              selectedSalsasChilaquil.add(salsa);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFF6D00)
                                      .withValues(alpha: 0.15)
                                  : const Color(0xFFFAF1DE),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFFF6D00)
                                    : const Color(0xFFE5DCC4),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: isSelected
                                      ? const Color(0xFFFF6D00)
                                      : const Color(0xFFA08F70),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  salsa,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Color(0xFFFAF1DE)
                                        : Color(0xFFA08F70),
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  // Con Queso: toggle genérico +$5 para Chilaquiles y
                  // Arrachera (variantes que no tienen ya una versión "con
                  // queso" propia en el menú, como el Bolillo de Arrachera).
                  if (showQuesoToggle) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    _ToggleOption(
                      icon: Icons.egg_alt,
                      label: 'Con Queso',
                      price: '+\$${quesoExtraPrecio.toStringAsFixed(0)}',
                      value: conQuesoExtra,
                      onChanged: (v) =>
                          setDialogState(() => conQuesoExtra = v),
                    ),
                  ],
                  // Guisado: aparece cuando algún platillo seleccionado lo requiere
                  if (anyRequiresGuisado && guisados.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('GUISADO',
                            style: TextStyle(
                                color: const Color(0xFF7A6E5A),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1)),
                        Text(
                          '${selectedGuisados.length}/5',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selectedGuisados.length >= 5
                                ? const Color(0xFFFF6D00)
                                : Color(0xFFB6A88A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ScrollableWithDownHint(
                      height: 500,
                      hintColor: const Color(0xFFFF6D00),
                      fadeColor: const Color(0xFFFAF1DE),
                      child: LayoutBuilder(builder: (innerCtx, c) {
                          final itemW = (c.maxWidth - 18) / 4;
                          Widget buildItem(Map<String, dynamic> g) {
                            final name = g['name'] as String;
                            final isChecked = selectedGuisados.contains(name);
                            return SizedBox(
                              width: itemW,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setDialogState(() {
                                  if (isChecked) {
                                    selectedGuisados.remove(name);
                                  } else if (selectedGuisados.length < 5) {
                                    selectedGuisados.add(name);
                                  }
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isChecked
                                        ? const Color(0xFFFF6D00).withValues(alpha: 0.18)
                                        : const Color(0xFFFAF1DE),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isChecked
                                          ? const Color(0xFFFF6D00)
                                          : const Color(0xFFFF6D00).withValues(alpha: 0.35),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isChecked
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 14,
                                        color: const Color(0xFFFF6D00),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${meatEmoji(g['meat_type'] as String?)} $name'.trim(),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFFF6D00),
                                          fontSize: 11,
                                          fontWeight: isChecked
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      _chileRow(
                                          g['spice_level'] as int? ?? 0),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          // Si el sabor seleccionado ya dice "con carne" o
                          // "sin carne" (p.ej. "½ Litro Guisado con Carne"),
                          // forzamos el filtro y escondemos los tabs — la
                          // decisión ya está tomada arriba en SABOR.
                          bool? forcedMeat;
                          for (final d in matchedByFlavor.values) {
                            final n = d.name.toLowerCase();
                            if (n.contains('sin carne')) {
                              forcedMeat = false;
                              break;
                            }
                            if (n.contains('con carne')) {
                              forcedMeat = true;
                              break;
                            }
                          }
                          // Sincroniza el estado para que GUISADO DEL EXTRA
                          // y la lógica downstream usen el filtro correcto.
                          if (forcedMeat != null &&
                              mixedGuisadoMeatFilter != forcedMeat) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              setDialogState(() {
                                mixedGuisadoMeatFilter = forcedMeat!;
                                // Limpiar selecciones que ya no aplican al
                                // nuevo filtro forzado.
                                final allowed = guisados
                                    .where((g) =>
                                        (g['with_meat'] as bool? ?? true) ==
                                        forcedMeat)
                                    .map((g) => g['name'] as String)
                                    .toSet();
                                selectedGuisados = selectedGuisados
                                    .where(allowed.contains)
                                    .toList();
                                if (selectedGuisadoForExtra != null &&
                                    !allowed
                                        .contains(selectedGuisadoForExtra)) {
                                  selectedGuisadoForExtra = null;
                                }
                              });
                            });
                          }
                          // Si forcedMeat viene del contexto (ej. sección
                          // MENUDO con tipos de carne obligatorios), filtramos
                          // por ese valor. Si no, mostramos todos los guisados
                          // (los tabs CON CARNE / SIN CARNE fueron removidos).
                          final activeList = forcedMeat == null
                              ? guisados.toList()
                              : guisados
                                  .where((g) =>
                                      (g['with_meat'] as bool? ?? true) ==
                                      forcedMeat)
                                  .toList();
                          Widget filterTab(String label, bool value) {
                            final isActive = mixedGuisadoMeatFilter == value;
                            return Expanded(
                              child: InkWell(
                                onTap: () => setDialogState(() {
                                  mixedGuisadoMeatFilter = value;
                                }),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isActive
                                          ? const Color(0xFFFF6D00)
                                          : const Color(0xFF334155),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isActive
                                          ? const Color(0xFFFAF1DE)
                                          : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: activeList.map(buildItem).toList(),
                              ),
                            ],
                          );
                        }),
                    ),
                  ],
                  // Cantidad de piezas: solo para enmoladas seleccionadas en solitario
                  if (selectedIsEnmolada) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    const Text('PIEZAS',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [2, 3].map((q) => _ToggleOption(
                        icon: Icons.numbers,
                        label: '$q pzas',
                        value: selectedEnmolQty == q,
                        onChanged: (v) => setDialogState(
                            () => selectedEnmolQty = v ? q : null),
                      )).toList(),
                    ),
                  ],
                  if (allowsComment) _buildCommentField(commentController),
                  if (showExtras)
                    _buildExtrasSection(
                      extras: extrasDisponibles,
                      selectedIds: selectedExtraIds,
                      onToggle: (id) => setDialogState(() {
                        if (selectedExtraIds.contains(id)) {
                          selectedExtraIds.remove(id);
                          final d = extrasDisponibles
                              .firstWhere((e) => e.id == id);
                          if (isGuisadoExtra(d)) {
                            selectedGuisadoForExtra = null;
                          }
                        } else {
                          selectedExtraIds.add(id);
                        }
                      }),
                    ),
                  // Sub-selector: cuando se elige una ÓRDEN EXTRA de guisado,
                  // pedir cuál guisado lleva.
                  if (showExtras &&
                      hasGuisadoExtra &&
                      guisados.isNotEmpty &&
                      extrasDisponibles.any((e) =>
                          isGuisadoExtra(e) &&
                          selectedExtraIds.contains(e.id))) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE5DCC4)),
                    const SizedBox(height: 8),
                    const Text('GUISADO DEL EXTRA',
                        style: TextStyle(
                            color: const Color(0xFF7A6E5A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    _ScrollableWithDownHint(
                      height: 450,
                      hintColor: const Color(0xFFFF6D00),
                      fadeColor: const Color(0xFFFAF1DE),
                      child: LayoutBuilder(builder: (_, c) {
                          final itemW = (c.maxWidth - 18) / 4;
                          Widget buildItem(Map<String, dynamic> g) {
                            final name = g['name'] as String;
                            final isSel =
                                selectedGuisadoForExtra == name;
                            return SizedBox(
                              width: itemW,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setDialogState(() {
                                  selectedGuisadoForExtra =
                                      isSel ? null : name;
                                }),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? const Color(0xFFFF6D00)
                                            .withValues(alpha: 0.18)
                                        : const Color(0xFFFAF1DE),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSel
                                          ? const Color(0xFFFF6D00)
                                          : const Color(0xFFFF6D00)
                                              .withValues(alpha: 0.35),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSel
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 14,
                                        color: const Color(0xFFFF6D00),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${meatEmoji(g['meat_type'] as String?)} $name'.trim(),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFFF6D00),
                                          fontSize: 11,
                                          fontWeight: isSel
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      _chileRow(
                                          g['spice_level'] as int? ?? 0),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          final activeList = guisados.toList();
                          Widget filterTab(String label, bool value) {
                            final isActive = mixedGuisadoMeatFilter == value;
                            return Expanded(
                              child: InkWell(
                                onTap: () => setDialogState(() {
                                  mixedGuisadoMeatFilter = value;
                                }),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFFFF6D00)
                                        : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isActive
                                          ? const Color(0xFFFF6D00)
                                          : const Color(0xFF334155),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isActive
                                          ? const Color(0xFFFAF1DE)
                                          : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: activeList.map(buildItem).toList(),
                              ),
                            ],
                          );
                        }),
                    ),
                  ],
                  // CANTIDAD: siempre visible (incluyendo lo dulce), igual que
                  // en todos los demás productos.
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE5DCC4)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('CANTIDAD',
                          style: TextStyle(
                              color: const Color(0xFF7A6E5A),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1)),
                      Row(
                        children: [
                          InkWell(
                            onTap: () => setDialogState(
                                () { if (dialogQty > 1) dialogQty--; }),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF1DE),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE5DCC4)),
                              ),
                              child: const Icon(Icons.remove, color: const Color(0xFF7A6E5A), size: 18),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '$dialogQty',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFFF6D00),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          InkWell(
                            onTap: () => setDialogState(() => dialogQty++),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFF6D00)),
                              ),
                              child: const Icon(Icons.add, color: Color(0xFFFF6D00), size: 18),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (canAdd) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Total: \$${totalPrice.toStringAsFixed(0)}',
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
                  style: TextStyle(color: const Color(0xFFA08F70))),
            ),
            SizedBox(
              height: 44,
              child: ElevatedButton(
              onPressed: !canAdd
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      final comment = commentController.text.trim();
                      for (final entry in matchedByFlavor.entries) {
                        final flavor = entry.key;
                        final dish = entry.value;
                        // Cantidad por-platillo:
                        // - Lo dulce: Molletes=1, Hot Cakes (con qty en BD)=1,
                        //   Churros (sin qty)=selectedPiezasLoDulce
                        //   …multiplicado por dialogQty (cantidad general).
                        // - Resto: dialogQty
                        final effectiveQty = isLoDulce
                            ? qtyForLoDulceDish(dish, flavor) * dialogQty
                            : dialogQty;
                        final isChilaquilFl = dish.category == 'chilaquiles' ||
                            flavor.toLowerCase().contains('chilaquil');
                        final extras = [
                          if (dish.requiresGuisado) ...selectedGuisados,
                          if (selectedIsEnmolada && selectedEnmolQty != null)
                            '$selectedEnmolQty piezas',
                          if (isMenudo && selectedTiposCarne.isNotEmpty)
                            selectedTiposCarne.join(', '),
                          if ((dish.category == 'huevos' ||
                                  dish.name.toLowerCase().contains('huevo')) &&
                              selectedTerminoHuevo != null)
                            selectedTerminoHuevo!,
                          if (dish.name.toLowerCase().contains('revuelto') &&
                              selectedProteinaHuevo != null)
                            'Con $selectedProteinaHuevo',
                          if (dish.name.toLowerCase() == 'quesadilla de maíz' &&
                              selectedFritaQuesadilla)
                            'Frita',
                          if (isChilaquilFl &&
                              selectedSalsasChilaquil.isNotEmpty)
                            'Salsa ${selectedSalsasChilaquil.join(" + ")}',
                          if (showQuesoToggle && conQuesoExtra) 'Con queso',
                          if (allowsComment && comment.isNotEmpty) comment,
                        ];
                        final dishToAdd = showQuesoToggle && conQuesoExtra
                            ? dish.copyWith(price: dish.price + quesoExtraPrecio)
                            : dish;
                        cart.addItemWithGuisados(dishToAdd, extras, quantity: effectiveQty);
                      }
                      // Agregar las ÓRDENES EXTRAS seleccionadas; usamos
                      // addItem para consolidar repeticiones del mismo
                      // extra (mismo cliente) en una sola fila con
                      // cantidad incrementada en vez de duplicarlas.
                      // Excepción: el extra de guisado lleva el nombre del
                      // guisado elegido, así que se agrega con
                      // addItemWithGuisados (fila propia).
                      for (final extraId in selectedExtraIds) {
                        final extra = extrasDisponibles
                            .firstWhere((e) => e.id == extraId);
                        if (isGuisadoExtra(extra) &&
                            selectedGuisadoForExtra != null) {
                          cart.addItemWithGuisados(
                              extra, [selectedGuisadoForExtra!]);
                        } else {
                          cart.addItem(extra);
                        }
                      }
                      if (replaceKey != null) cart.removeItem(replaceKey);
                      if (context.mounted) {
                        final names = matchedByFlavor.values
                            .map((d) => d.name)
                            .join(', ');
                        final prefix = dialogQty > 1 ? '$dialogQty × ' : '';
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('$prefix$names agregado${matchedByFlavor.length > 1 ? 's' : ''}'),
                          duration: const Duration(milliseconds: 800),
                          behavior: SnackBarBehavior.floating,
                          width: 300,
                        ));
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6D00),
                foregroundColor: Color(0xFFFAF1DE),
                disabledBackgroundColor: const Color(0xFFE5DCC4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Agregar a la orden',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ),
          ],
        );
      },
    ),
  );
  commentController.dispose();
}

class MultiFlavorVariantCard extends StatelessWidget {
  final List<Dish> dishes;
  final String displayName;
  final String categoryPrefix;
  final bool multiSelectFlavors;
  final IconData? overrideIcon;
  final String? subtitle;

  const MultiFlavorVariantCard({
    super.key,
    required this.dishes,
    required this.displayName,
    required this.categoryPrefix,
    this.multiSelectFlavors = false,
    this.overrideIcon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final minPrice =
        dishes.map((d) => d.price).reduce((a, b) => a < b ? a : b);
    final maxPrice =
        dishes.map((d) => d.price).reduce((a, b) => a > b ? a : b);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => addMultiFlavorVariantToCart(
            context, dishes, displayName, categoryPrefix,
            multiSelectFlavors: multiSelectFlavors),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (overrideIcon != null) ...[
                        Icon(overrideIcon, size: 14, color: const Color(0xFFFF6D00)),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          displayName,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Color(0xFFA08F70),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
                                    categoryPrefix,
                                    multiSelectFlavors: multiSelectFlavors),
                                icon: const Icon(Icons.add, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minHeight: 36, minWidth: 36),
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
    BuildContext context, Dish ordenDish, Dish mediaDish, {String? replaceKey}) async {
  final cart = context.read<CartProvider>();
  Dish? selected;
  final allowsComment = _isPreparedDishes([ordenDish]);
  final commentController = TextEditingController();

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFFFAF1DE),
        title: Text(
          _baseOrdenName(ordenDish.name),
          style: TextStyle(color: const Color(0xFF3D2E1A), fontWeight: FontWeight.w700, fontSize: MediaQuery.of(ctx).size.width < 380 ? 14 : 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TAMAÑO',
                  style: TextStyle(
                      color: const Color(0xFF7A6E5A),
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
                    label: '1 Orden',
                    price: '\$${ordenDish.price.toStringAsFixed(0)}',
                    value: selected?.id == ordenDish.id,
                    onChanged: (v) =>
                        setDialogState(() => selected = v ? ordenDish : null),
                  ),
                  _ToggleOption(
                    icon: Icons.content_cut,
                    label: '1/2 Orden',
                    price: '\$${mediaDish.price.toStringAsFixed(0)}',
                    value: selected?.id == mediaDish.id,
                    onChanged: (v) =>
                        setDialogState(() => selected = v ? mediaDish : null),
                  ),
                ],
              ),
              if (allowsComment) _buildCommentField(commentController),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: const Color(0xFFA08F70))),
          ),
          TextButton(
            onPressed: selected == null
                ? null
                : () {
                    Navigator.pop(ctx);
                    final comment = commentController.text.trim();
                    cart.addItemWithGuisados(
                      selected!,
                      [if (allowsComment && comment.isNotEmpty) comment],
                    );
                    if (replaceKey != null) cart.removeItem(replaceKey);
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6D00),
              foregroundColor: Color(0xFFFAF1DE),
              disabledBackgroundColor: const Color(0xFFE5DCC4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Agregar a la orden', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
  commentController.dispose();
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
                                    color: const Color(0xFFA08F70), fontSize: 10),
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
                                    minHeight: 36, minWidth: 36),
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
  final String? price;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.price,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6D00);
    const cream = Color(0xFFFAF1DE);
    // Texto siempre en colores oscuros / naranja, NUNCA blanco. El estado
    // seleccionado se diferencia con fondo naranja claro (alpha) + border
    // naranja sólido + bold, no con texto cream sobre fondo sólido.
    final effectiveColor = enabled
        ? (value ? orange.withValues(alpha: 0.15) : cream)
        : const Color(0xFFEDE3CE);
    final borderColor = enabled
        ? (value ? orange : orange.withValues(alpha: 0.35))
        : const Color(0xFFCFC7B2);
    final contentColor = enabled
        ? orange
        : const Color(0xFFB0A992);
    final priceColor = enabled
        ? (value ? orange : orange.withValues(alpha: 0.75))
        : const Color(0xFFB0A992);

    return GestureDetector(
      onTap: enabled ? () => onChanged(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: effectiveColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: contentColor),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: value ? FontWeight.w700 : FontWeight.w600,
                    color: contentColor,
                  ),
                ),
                if (price != null)
                  Text(
                    price!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: priceColor,
                    ),
                  ),
              ],
            ),
            if (!enabled) ...[
              const SizedBox(width: 6),
              Icon(Icons.block, size: 14, color: const Color(0xFFB0A992)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip de base de gordita (Maíz / Harina). A diferencia de `_ToggleOption`
/// son mutuamente excluyentes y muestran el precio de cada base.
class _BaseChip extends StatelessWidget {
  final String label;
  final double price;
  final bool selected;
  final VoidCallback onTap;

  const _BaseChip({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFFF6D00);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: 0.15)
                : const Color(0xFFFAF1DE),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? activeColor : const Color(0xFFE5DCC4),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 14,
                color: selected ? activeColor : const Color(0xFFA08F70),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? const Color(0xFFFF6D00) : const Color(0xFFA08F70),
                    ),
                  ),
                  Text(
                    '\$${price.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? const Color(0xFF7A6E5A) : const Color(0xFFA08F70),
                    ),
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
