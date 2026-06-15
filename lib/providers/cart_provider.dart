import 'package:flutter/foundation.dart';
import '../models/dish.dart';

class CartItem {
  final Dish dish;
  int quantity;
  String clientLabel;
  List<String> guisados;

  CartItem({
    required this.dish,
    this.quantity = 1,
    this.clientLabel = 'Cliente 1',
    this.guisados = const [],
  });
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  /// Id sintético del artículo "Envío FLASH". Se inserta como CartItem para
  /// que el carrito y el ticket lo muestren como un renglón más. Al guardar
  /// la orden, se mapea a `dish_id: null` para no violar la FK.
  static const String deliveryFeeId = '__delivery_fee__';
  static const String deliveryFeeKey = '__delivery_fee__';

  String currentClient = 'Cliente 1';
  List<String> clients = ['Cliente 1'];

  Map<String, CartItem> get items => {..._items};

  int get itemCount => _items.values.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount {
    return _items.values.fold(
      0.0,
      (sum, item) => sum + (item.dish.price * item.quantity),
    );
  }

  /// Precio actual del artículo de envío en el carrito (0 si no hay).
  double get deliveryFee {
    final item = _items[deliveryFeeKey];
    if (item == null) return 0.0;
    return item.dish.price * item.quantity;
  }

  /// Inserta/actualiza un CartItem sintético "Envío FLASH" con el monto
  /// recibido. Si `fee <= 0`, lo elimina.
  void setDeliveryFee(double fee) {
    if (fee <= 0) {
      if (_items.remove(deliveryFeeKey) != null) notifyListeners();
      return;
    }
    final feeDish = Dish(
      id: deliveryFeeId,
      name: 'Envío FLASH',
      description: 'Cuota de servicio a domicilio',
      price: fee,
      imageUrl: '',
      category: 'Envío',
      isSale: true,
    );
    _items[deliveryFeeKey] = CartItem(
      dish: feeDish,
      quantity: 1,
      clientLabel: currentClient,
    );
    notifyListeners();
  }

  /// Elimina el artículo de envío del carrito.
  void clearDeliveryFee() {
    if (_items.remove(deliveryFeeKey) != null) notifyListeners();
  }

  void addClient(String name) {
    if (!clients.contains(name)) {
      clients = [...clients, name];
      notifyListeners();
    }
  }

  void removeClient(String name) {
    if (name == 'Cliente 1' && clients.length == 1) return;
    // Remove all items for this client
    _items.removeWhere((key, item) => item.clientLabel == name);
    clients = clients.where((c) => c != name).toList();
    if (currentClient == name) {
      currentClient = clients.first;
    }
    notifyListeners();
  }

  void renameClient(String oldName, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == oldName || clients.contains(trimmed)) return;
    // Update items
    final entries = _items.entries.toList();
    _items.clear();
    for (final entry in entries) {
      if (entry.value.clientLabel == oldName) {
        final newKey = entry.key.replaceFirst('_$oldName', '_$trimmed');
        entry.value.clientLabel = trimmed;
        _items[newKey] = entry.value;
      } else {
        _items[entry.key] = entry.value;
      }
    }
    // Update list
    clients = clients.map((c) => c == oldName ? trimmed : c).toList();
    if (currentClient == oldName) currentClient = trimmed;
    notifyListeners();
  }

  void setCurrentClient(String name) {
    if (clients.contains(name)) {
      currentClient = name;
      notifyListeners();
    }
  }

  void addItem(Dish dish) {
    final key = '${dish.id}_$currentClient';
    if (_items.containsKey(key)) {
      _items[key]!.quantity += 1;
    } else {
      _items[key] = CartItem(dish: dish, clientLabel: currentClient);
    }
    notifyListeners();
  }

  /// Adds a dish with specific guisados. Each call creates a unique entry
  /// (uses a timestamp suffix so multiple guisado combos can coexist).
  void addItemWithGuisados(Dish dish, List<String> guisados, {int quantity = 1}) {
    final key = '${dish.id}_${currentClient}_${DateTime.now().millisecondsSinceEpoch}';
    _items[key] = CartItem(
      dish: dish,
      clientLabel: currentClient,
      guisados: List<String>.from(guisados),
      quantity: quantity,
    );
    notifyListeners();
  }

  void incrementQuantity(String itemKey) {
    // El envío es un artículo fijo (cantidad 1, monto calculado).
    if (itemKey == deliveryFeeKey) return;
    if (_items.containsKey(itemKey)) {
      _items[itemKey]!.quantity += 1;
      notifyListeners();
    }
  }

  void decrementQuantity(String itemKey) {
    if (itemKey == deliveryFeeKey) return;
    if (!_items.containsKey(itemKey)) return;

    if (_items[itemKey]!.quantity > 1) {
      _items[itemKey]!.quantity -= 1;
    } else {
      _items.remove(itemKey);
    }
    notifyListeners();
  }

  void removeItem(String itemKey) {
    _items.remove(itemKey);
    notifyListeners();
  }

  /// Limpia el carrito. Por defecto preserva el artículo de envío FLASH
  /// (la cuota se setea ANTES de entrar al menú; si la borráramos aquí,
  /// la perdemos al inicializar la vista del menú).
  /// Para borrar absolutamente todo (incluyendo envío), pasa
  /// `keepDeliveryFee: false` — útil al cerrar/terminar la orden.
  void clearCart({bool keepDeliveryFee = true}) {
    final preservedFee =
        keepDeliveryFee ? _items[deliveryFeeKey] : null;
    _items.clear();
    if (preservedFee != null) {
      _items[deliveryFeeKey] = preservedFee;
    }
    clients = ['Cliente 1'];
    currentClient = 'Cliente 1';
    notifyListeners();
  }
}
