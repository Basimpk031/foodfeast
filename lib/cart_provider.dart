// ─────────────────────────────────────────────
// cart_provider.dart — FoodFeast
// AI Integration: CartItem nutrition fields (calories, protein, carbs, fat)
// are passed directly to FoodRecommendationEngine via cart_screen.dart.
// Updated: full nutrition fields (calories, protein, carbs, fat)
//          per-portion nutrition support
//          NutritionTotals getter for stats
//          Cart persistence via SharedPreferences (survives app restarts)
// ─────────────────────────────────────────────
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // ── Serialization ──────────────────────────────────────────────────────────
  String toJson() => name; // 'quarter' | 'half' | 'full'

  static Portion? fromJson(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'quarter': return Portion.quarter;
      case 'half':    return Portion.half;
      case 'full':    return Portion.full;
      default:        return null;
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

  // ── Serialization ──────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'name':           name,
    'restaurantId':   restaurantId,
    'restaurantName': restaurantName,
    'price':          price,
    'imageUrl':       imageUrl,
    'isVeg':          isVeg,
    'portion':        portion?.toJson(),
    'portionPrice':   portionPrice,
    'calories':       calories,
    'protein':        protein,
    'carbs':          carbs,
    'fat':            fat,
    'quantity':       quantity,
  };

  factory CartItem.fromJson(Map<String, dynamic> j) {
    final item = CartItem(
      name:           j['name'] as String,
      restaurantId:   j['restaurantId'] as String,
      restaurantName: j['restaurantName'] as String,
      price:          (j['price'] as num).toDouble(),
      imageUrl:       j['imageUrl'] as String,
      isVeg:          j['isVeg'] as bool,
      portion:        PortionLabel.fromJson(j['portion'] as String?),
      portionPrice:   (j['portionPrice'] as num?)?.toDouble(),
      calories:       (j['calories'] as num?)?.toInt() ?? 0,
      protein:        (j['protein'] as num?)?.toDouble() ?? 0.0,
      carbs:          (j['carbs'] as num?)?.toDouble() ?? 0.0,
      fat:            (j['fat'] as num?)?.toDouble() ?? 0.0,
    );
    item.quantity = (j['quantity'] as num?)?.toInt() ?? 1;
    return item;
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
  CartProvider._internal() {
    _loadCart(); // restore persisted cart on startup
  }

  static const _cartKey = 'foodfeast_cart_v1';

  final Map<String, CartItem> _items = {};

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartKey);
      if (raw == null) return;
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      for (final e in decoded) {
        final item = CartItem.fromJson(e as Map<String, dynamic>);
        _items[item.key] = item;
      }
      notifyListeners();
    } catch (_) {
      // Corrupted cache — silently start with empty cart
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cartKey);
    }
  }

  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _items.values.map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_cartKey, encoded);
    } catch (_) {
      // Ignore save failures — cart still works in-memory
    }
  }

  // ── Getters ────────────────────────────────────────────────────────────────

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

  // ── Mutators (each saves after mutating) ───────────────────────────────────

  void addItem(CartItem newItem) {
    final key = newItem.key;
    if (_items.containsKey(key)) {
      _items[key]!.quantity++;
    } else {
      _items[key] = newItem;
    }
    notifyListeners();
    _saveCart();
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
    _saveCart();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
    _saveCart(); // writes empty list — clears persisted data
  }
}