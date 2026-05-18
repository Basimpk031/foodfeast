// ─────────────────────────────────────────────
// cart_provider.dart — FoodFeast
// AI Integration: CartItem nutrition fields (calories, protein, carbs, fat)
// are passed directly to FoodRecommendationEngine via cart_screen.dart.
// Updated: full nutrition fields (calories, protein, carbs, fat)
//          per-portion nutrition support
//          NutritionTotals getter for stats
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';

enum Portion { quarter, half, full }

extension PortionLabel on Portion {
  String get label {
    switch (this) {
      case Portion.quarter: return 'Quarter';
      case Portion.half:    return 'Half';
      case Portion.full:    return 'Full';
    }
  }

  String get shortLabel {
    switch (this) {
      case Portion.quarter: return '¼';
      case Portion.half:    return '½';
      case Portion.full:    return 'Full';
    }
  }
}

class CartItem {
  final String name;
  final String restaurantId;
  final String restaurantName;
  final double price;
  final String imageUrl;
  final bool isVeg;

  // Portion fields — null means regular item
  final Portion? portion;
  final double? portionPrice;

  // Nutrition per serving
  final int calories;
  final double protein; // grams
  final double carbs;   // grams
  final double fat;     // grams

  int quantity;

  CartItem({
    required this.name,
    required this.restaurantId,
    required this.restaurantName,
    required this.price,
    required this.imageUrl,
    required this.isVeg,
    this.portion,
    this.portionPrice,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.quantity = 1,
  });

  double get effectivePrice => portionPrice ?? price;

  String get key {
    final portionSuffix = portion != null ? '__${portion!.name}' : '';
    return '${restaurantId}__$name$portionSuffix';
  }
}

class NutritionTotals {
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  const NutritionTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  NutritionTotals operator +(NutritionTotals other) => NutritionTotals(
    calories: calories + other.calories,
    protein: protein + other.protein,
    carbs: carbs + other.carbs,
    fat: fat + other.fat,
  );
}

class CartProvider extends ChangeNotifier {
  static final CartProvider instance = CartProvider._internal();
  CartProvider._internal();

  final Map<String, CartItem> _items = {};

  List<CartItem> get items => _items.values.toList();

  int get totalItems =>
      _items.values.fold(0, (sum, i) => sum + i.quantity);

  double get totalPrice =>
      _items.values.fold(0.0, (sum, i) => sum + i.effectivePrice * i.quantity);

  int get totalCalories =>
      _items.values.fold(0, (sum, i) => sum + (i.calories * i.quantity));

  double get totalProtein =>
      _items.values.fold(0.0, (sum, i) => sum + (i.protein * i.quantity));

  double get totalCarbs =>
      _items.values.fold(0.0, (sum, i) => sum + (i.carbs * i.quantity));

  double get totalFat =>
      _items.values.fold(0.0, (sum, i) => sum + (i.fat * i.quantity));

  NutritionTotals get nutritionTotals => NutritionTotals(
    calories: totalCalories,
    protein: totalProtein,
    carbs: totalCarbs,
    fat: totalFat,
  );

  int getQuantity(String name, String restaurantId) {
    int total = 0;
    for (final item in _items.values) {
      if (item.name == name && item.restaurantId == restaurantId) {
        total += item.quantity;
      }
    }
    return total;
  }

  int getPortionQuantity(String name, String restaurantId, Portion? portion) {
    final portionSuffix = portion != null ? '__${portion.name}' : '';
    final key = '${restaurantId}__$name$portionSuffix';
    return _items[key]?.quantity ?? 0;
  }

  bool isInCart(String name, String restaurantId) {
    return _items.keys.any((k) => k.startsWith('${restaurantId}__$name'));
  }

  List<String> get restaurantNames =>
      _items.values.map((i) => i.restaurantName).toSet().toList();

  Map<String, List<CartItem>> get itemsByRestaurant {
    final Map<String, List<CartItem>> grouped = {};
    for (final item in _items.values) {
      grouped.putIfAbsent(item.restaurantId, () => []);
      grouped[item.restaurantId]!.add(item);
    }
    return grouped;
  }

  void addItem(CartItem newItem) {
    final key = newItem.key;
    if (_items.containsKey(key)) {
      _items[key]!.quantity++;
    } else {
      _items[key] = newItem;
    }
    notifyListeners();
  }

  void removeItem(String name, String restaurantId, {Portion? portion}) {
    final portionSuffix = portion != null ? '__${portion.name}' : '';
    final key = '${restaurantId}__$name$portionSuffix';
    if (_items.containsKey(key)) {
      if (_items[key]!.quantity > 1) {
        _items[key]!.quantity--;
      } else {
        _items.remove(key);
      }
    }
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}