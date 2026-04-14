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
  void addItemWithGuisados(Dish dish, List<String> guisados) {
    final key = '${dish.id}_${currentClient}_${DateTime.now().millisecondsSinceEpoch}';
    _items[key] = CartItem(
      dish: dish,
      clientLabel: currentClient,
      guisados: List<String>.from(guisados),
    );
    notifyListeners();
  }

  void incrementQuantity(String itemKey) {
    if (_items.containsKey(itemKey)) {
      _items[itemKey]!.quantity += 1;
      notifyListeners();
    }
  }

  void decrementQuantity(String itemKey) {
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

  void clearCart() {
    _items.clear();
    clients = ['Cliente 1'];
    currentClient = 'Cliente 1';
    notifyListeners();
  }
}
