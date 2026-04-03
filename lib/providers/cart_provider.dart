import 'package:flutter/foundation.dart';
import '../models/dish.dart';

class CartItem {
  final Dish dish;
  int quantity;

  CartItem({required this.dish, this.quantity = 1});
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => {..._items};

  int get itemCount => _items.values.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount {
    return _items.values.fold(
      0.0,
      (sum, item) => sum + (item.dish.price * item.quantity),
    );
  }

  void addItem(Dish dish) {
    if (_items.containsKey(dish.id)) {
      _items[dish.id]!.quantity += 1;
    } else {
      _items[dish.id] = CartItem(dish: dish);
    }
    notifyListeners();
  }

  void incrementQuantity(String dishId) {
    if (_items.containsKey(dishId)) {
      _items[dishId]!.quantity += 1;
      notifyListeners();
    }
  }

  void decrementQuantity(String dishId) {
    if (!_items.containsKey(dishId)) return;

    if (_items[dishId]!.quantity > 1) {
      _items[dishId]!.quantity -= 1;
    } else {
      _items.remove(dishId);
    }
    notifyListeners();
  }

  void removeItem(String dishId) {
    _items.remove(dishId);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
