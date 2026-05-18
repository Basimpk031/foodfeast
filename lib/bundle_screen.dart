// ─────────────────────────────────────────────
// bundle_screen.dart — FoodFeast
// Feature: Bundle Creation
//   • Browse all food items across all restaurants
//   • Select multiple items to group into a named bundle
//   • See live totals: price, calories, protein, carbs, fat
//   • Save bundle to Firestore → users/{uid}/bundles
//   • View & manage saved bundles (order / delete)
//   • Order a bundle → writes to 'orders' + updates CalorieTracker
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'calorie_tracker.dart';
import 'cart_provider.dart';
import 'portion_sheet.dart';
import 'checkout_screen.dart';
import 'favorites_ratings_service.dart';
import 'location_service.dart';
import 'location_filter.dart';

// ── Delivery-time helpers (shared with home_screen) ──────────────────────────
double? _bundleCalcDistanceKm(Map<String, dynamic>? locMap) {
  if (locMap == null) return null;
  final restLat = (locMap['lat'] as num?)?.toDouble();
  final restLng = (locMap['lng'] as num?)?.toDouble();
  if (restLat == null || restLng == null) return null;
  final userLoc = LocationService.instance.current;
  if (userLoc == null) return null;
  const R = 6371.0;
  final dLat = (restLat - userLoc.lat) * (math.pi / 180);
  final dLng = (restLng - userLoc.lng) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(userLoc.lat * (math.pi / 180)) *
          math.cos(restLat * (math.pi / 180)) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

int _bundleParsePrepMins(String deliveryTimeStr) {
  final match = RegExp(r'(\d+)').firstMatch(deliveryTimeStr);
  return match != null ? (int.tryParse(match.group(1)!) ?? 25) : 25;
}

String _bundleCalcDelivery({required String deliveryTimeStr, required double? distanceKm}) {
  final prepMins = _bundleParsePrepMins(deliveryTimeStr);
  if (distanceKm == null) return '~$prepMins min';
  final travelMins = (distanceKm / 30.0 * 60).ceil();
  final total = prepMins + travelMins;
  return '${(total - 5).clamp(5, 999)}–${total + 5} min';
}

String _bundleFmtDistance(double km) =>
    km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

// ─────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────
class BundleItem {
  final String name;
  final String restaurantId;
  final String restaurantName;
  final double price;
  final String imageUrl;
  final bool isVeg;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  int quantity;

  // ── Availability ──────────────────────────────
  final bool isItemAvailable;
  final bool isRestaurantActive;

  // ── Portion support ───────────────────────────
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;
  /// When this item uses portions, records which portion was chosen.
  /// null = no portion chosen yet (or item has no portions).
  Portion? selectedPortion;
  /// The per-portion price actually selected (used for display & order total).
  double portionPrice;

  BundleItem({
    required this.name,
    required this.restaurantId,
    required this.restaurantName,
    required this.price,
    required this.imageUrl,
    required this.isVeg,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.quantity = 1,
    this.isItemAvailable = true,
    this.isRestaurantActive = true,
    this.portionPrices = const {},
    this.portionNutrition = const {},
    this.selectedPortion,
    double? portionPrice,
  }) : portionPrice = portionPrice ?? price;

  bool get isAvailable => isItemAvailable && isRestaurantActive;
  bool get hasPortion => portionPrices.isNotEmpty;

  /// Effective price used for bundle totals and display.
  /// Keys off selectedPortion (not hasPortion) so it works correctly after
  /// reload from Firestore, where portionPrices map is not persisted.
  double get effectivePrice => selectedPortion != null ? portionPrice : price;

  Map<String, dynamic> toMap() => {
        'name': name,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'price': price,
        'portionPrice': portionPrice,
        'selectedPortion': selectedPortion?.name,
        'imageUrl': imageUrl,
        'isVeg': isVeg,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'quantity': quantity,
      };

  factory BundleItem.fromMap(Map<String, dynamic> m) {
    Portion? sp;
    final spStr = m['selectedPortion'] as String?;
    if (spStr != null) {
      sp = Portion.values.where((p) => p.name == spStr).firstOrNull;
    }
    return BundleItem(
      name: m['name'] ?? '',
      restaurantId: m['restaurantId'] ?? '',
      restaurantName: m['restaurantName'] ?? '',
      price: (m['price'] ?? 0).toDouble(),
      portionPrice: (() {
        final pp = m['portionPrice'];
        if (pp != null && (pp as num) > 0) return (pp as num).toDouble();
        return (m['price'] ?? 0).toDouble();
      })(),
      imageUrl: m['imageUrl'] ?? '',
      isVeg: m['isVeg'] ?? false,
      calories: (m['calories'] ?? 0).toInt(),
      protein: (m['protein'] ?? 0).toDouble(),
      carbs: (m['carbs'] ?? 0).toDouble(),
      fat: (m['fat'] ?? 0).toDouble(),
      quantity: (m['quantity'] ?? 1).toInt(),
      selectedPortion: sp,
    );
  }

  String get key => '${restaurantId}__$name';
}

class SavedBundle {
  final String id;
  final String name;
  final List<BundleItem> items;
  final DateTime createdAt;

  const SavedBundle({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
  });

  double get totalPrice =>
      items.fold(0.0, (s, i) => s + i.effectivePrice * i.quantity);
  int get totalCalories =>
      items.fold(0, (s, i) => s + i.calories * i.quantity);
  double get totalProtein =>
      items.fold(0.0, (s, i) => s + i.protein * i.quantity);
  double get totalCarbs =>
      items.fold(0.0, (s, i) => s + i.carbs * i.quantity);
  double get totalFat =>
      items.fold(0.0, (s, i) => s + i.fat * i.quantity);
  int get totalItems => items.fold(0, (s, i) => s + i.quantity);

  /// True when at least one item in this bundle is currently unavailable
  /// (admin deactivated item OR restaurant deactivated).
  bool get hasUnavailableItems => items.any((i) => !i.isAvailable);

  factory SavedBundle.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = (d['items'] as List?) ?? [];
    return SavedBundle(
      id: doc.id,
      name: d['name'] ?? 'My Bundle',
      items: rawItems
          .map((e) => BundleItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

// ─────────────────────────────────────────────
// BundleScreen
// ─────────────────────────────────────────────
class BundleScreen extends StatefulWidget {
  const BundleScreen({super.key});

  @override
  State<BundleScreen> createState() => _BundleScreenState();
}

class _BundleScreenState extends State<BundleScreen>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFF0077B6);
  static const _purple = Color(0xFF8B5CF6);
  static const _blue = Color(0xFF007AFF);
  static const _green = Color(0xFF34C759);
  static const _orange = Color(0xFFFF9500);

  late TabController _tabCtrl;

  // Builder state
  final Map<String, BundleItem> _selectedItems = {};
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _filterRestaurant = 'All';
  bool _vegOnly = false;
  bool _isSaving = false;
  final Set<String> _orderingBundleIds = {};

  // All food items from Firestore
  List<Map<String, dynamic>> _allItems = [];
  List<String> _restaurantNames = ['All'];
  bool _loadingItems = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadAllFoodItems();
    // Re-fetch whenever user changes location
    LocationService.instance.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onLocationChanged);
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    _loadAllFoodItems();
  }

  // ── Load all food items across restaurants ──
  Future<void> _loadAllFoodItems() async {
    setState(() => _loadingItems = true);
    try {
      final restaurantsSnap = await FirebaseFirestore.instance
          .collection('restaurants')
          .get();

      final List<Map<String, dynamic>> items = [];
      final Set<String> rNames = {};

      for (final rDoc in restaurantsSnap.docs) {
        final rData = rDoc.data();
        // Skip restaurants outside user's radius
        if (!isRestaurantNearby(rData)) continue;
        final rName = (rData['name'] as String?)?.isNotEmpty == true
            ? rData['name'] as String
            : 'Restaurant';
        // ✅ Track whether the whole restaurant is active
        final isRestaurantActive = rData['isActive'] ?? true;
        final restaurantDeliveryTime = (rData['deliveryTime'] as String?) ?? '30 min';
        final restaurantLocation = rData['location'] as Map<String, dynamic>?;
        rNames.add(rName);

        try {
          final menuSnap = await FirebaseFirestore.instance
              .collection('restaurants')
              .doc(rDoc.id)
              .collection('menuItems')
              .orderBy('name')
              .get();

          for (final mDoc in menuSnap.docs) {
            final mData = mDoc.data();
            final name = (mData['name'] as String?) ?? '';
            if (name.isEmpty) continue;

            // ✅ Keep ALL items — but record availability flags
            final isItemAvailable = mData['isAvailable'] != false;

            // ── Portion prices ──────────────────────────
            final Map<String, double> portionPrices = {};
            final qp = mData['quarterPrice'];
            final hp = mData['halfPrice'];
            final fp = mData['fullPrice'];
            if (qp != null && (qp as num) > 0) portionPrices['quarter'] = (qp as num).toDouble();
            if (hp != null && (hp as num) > 0) portionPrices['half']    = (hp as num).toDouble();
            if (fp != null && (fp as num) > 0) portionPrices['full']    = (fp as num).toDouble();

            // ── Portion nutrition ───────────────────────
            final Map<String, PortionNutrition> portionNutrition = {};
            if (portionPrices.isNotEmpty) {
              portionNutrition['quarter'] = PortionNutrition(
                calories: (mData['quarterCalories'] ?? 0) as int,
                protein:  (mData['quarterProtein']  ?? 0).toDouble(),
                carbs:    (mData['quarterCarbs']    ?? 0).toDouble(),
                fat:      (mData['quarterFat']      ?? 0).toDouble(),
              );
              portionNutrition['half'] = PortionNutrition(
                calories: (mData['halfCalories'] ?? 0) as int,
                protein:  (mData['halfProtein']  ?? 0).toDouble(),
                carbs:    (mData['halfCarbs']    ?? 0).toDouble(),
                fat:      (mData['halfFat']      ?? 0).toDouble(),
              );
              portionNutrition['full'] = PortionNutrition(
                calories: (mData['fullCalories'] ?? 0) as int,
                protein:  (mData['fullProtein']  ?? 0).toDouble(),
                carbs:    (mData['fullCarbs']    ?? 0).toDouble(),
                fat:      (mData['fullFat']      ?? 0).toDouble(),
              );
            }

            items.add({
              'name':                name,
              'restaurantId':        rDoc.id,
              'restaurantName':      rName,
              'price':               (mData['price'] ?? 0).toDouble(),
              'imageUrl':            mData['imageUrl'] ?? '',
              'isVeg':               mData['isVeg'] ?? false,
              'calories':            (mData['calories'] ?? 0).toInt(),
              'protein':             (mData['protein']  ?? 0).toDouble(),
              'carbs':               (mData['carbs']    ?? 0).toDouble(),
              'fat':                 (mData['fat']      ?? 0).toDouble(),
              // ✅ Availability flags
              'isItemAvailable':     isItemAvailable,
              'isRestaurantActive':  isRestaurantActive,
              // ✅ Restaurant location & delivery info (for per-item ETA)
              'restaurantDeliveryTime': restaurantDeliveryTime,
              'restaurantLocation':  restaurantLocation,
              // ✅ Portion data
              'portionPrices':       portionPrices,
              'portionNutrition':    portionNutrition,
            });
          }
        } catch (menuErr) {
          debugPrint(
              'BundleScreen: failed to load menu for ${rDoc.id}: $menuErr');
        }
      }

      if (mounted) {
        setState(() {
          _allItems = items;
          _restaurantNames = ['All', ...rNames.toList()..sort()];
          _loadingItems = false;
        });
      }
    } catch (e) {
      debugPrint('BundleScreen._loadAllFoodItems error: $e');
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  // ── Computed totals ─────────────────────────
  double get _totalPrice =>
      _selectedItems.values.fold(0.0, (s, i) => s + i.effectivePrice * i.quantity);
  int get _totalCalories =>
      _selectedItems.values.fold(0, (s, i) => s + i.calories * i.quantity);
  double get _totalProtein =>
      _selectedItems.values.fold(0.0, (s, i) => s + i.protein * i.quantity);
  double get _totalCarbs =>
      _selectedItems.values.fold(0.0, (s, i) => s + i.carbs * i.quantity);
  double get _totalFat =>
      _selectedItems.values.fold(0.0, (s, i) => s + i.fat * i.quantity);
  int get _totalItemCount =>
      _selectedItems.values.fold(0, (s, i) => s + i.quantity);

  // ── Filtered items ──────────────────────────
  List<Map<String, dynamic>> get _filteredItems {
    return _allItems.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          (item['name'] as String)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          (item['restaurantName'] as String)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      final matchesRestaurant = _filterRestaurant == 'All' ||
          item['restaurantName'] == _filterRestaurant;
      final matchesVeg = !_vegOnly || (item['isVeg'] as bool);
      return matchesSearch && matchesRestaurant && matchesVeg;
    }).toList();
  }

  // ── Add / remove from bundle ────────────────
  void _toggleItem(Map<String, dynamic> itemData) {
    final key = '${itemData['restaurantId']}__${itemData['name']}';
    final portionPrices = (itemData['portionPrices'] as Map<String, double>?) ?? {};

    if (_selectedItems.containsKey(key)) {
      setState(() => _selectedItems.remove(key));
      return;
    }

    // ✅ If item has portions, show the bundle portion picker first
    if (portionPrices.isNotEmpty) {
      _showBundlePortionPicker(itemData);
      return;
    }

    setState(() {
      _selectedItems[key] = BundleItem(
        name:               itemData['name'],
        restaurantId:       itemData['restaurantId'],
        restaurantName:     itemData['restaurantName'],
        price:              itemData['price'],
        imageUrl:           itemData['imageUrl'],
        isVeg:              itemData['isVeg'],
        calories:           itemData['calories'],
        protein:            itemData['protein'],
        carbs:              itemData['carbs'],
        fat:                itemData['fat'],
        isItemAvailable:    itemData['isItemAvailable'] ?? true,
        isRestaurantActive: itemData['isRestaurantActive'] ?? true,
        portionPrices:      portionPrices,
        portionNutrition:   (itemData['portionNutrition'] as Map<String, PortionNutrition>?) ?? {},
      );
    });
  }

  // ── Bundle portion picker ───────────────────
  void _showBundlePortionPicker(Map<String, dynamic> itemData) {
    final portionPrices =
        (itemData['portionPrices'] as Map<String, double>?) ?? {};
    final portionNutrition =
        (itemData['portionNutrition'] as Map<String, PortionNutrition>?) ?? {};

    const portionOrder = [Portion.quarter, Portion.half, Portion.full];
    const portionKeys  = ['quarter', 'half', 'full'];
    const portionEmojis = ['🍗', '🍖', '🫕'];

    Portion? selected;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Handle
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              // Title
              Row(children: [
                const Text('📦', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(itemData['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                  const Text('Choose a portion to add to bundle', style: TextStyle(fontSize: 12.5, color: Color(0xFF6E6E73))),
                ])),
              ]),
              const SizedBox(height: 20),
              // Portion cards
              Row(children: List.generate(portionOrder.length, (i) {
                final portion   = portionOrder[i];
                final key       = portionKeys[i];
                final price     = portionPrices[key];
                if (price == null || price <= 0) return const SizedBox.shrink();
                final nutrition = portionNutrition[key];
                final isSel     = selected == portion;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setModalState(() => selected = portion),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                      decoration: BoxDecoration(
                        color: isSel ? _purple.withOpacity(0.07) : const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isSel ? _purple : const Color(0xFFE5E5EA), width: isSel ? 2 : 1),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(portionEmojis[i], style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 5),
                        Text(portion.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isSel ? _purple : const Color(0xFF1C1C1E))),
                        const SizedBox(height: 3),
                        Text('₹${price.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isSel ? _purple : const Color(0xFF6E6E73))),
                        if (nutrition != null && nutrition.calories > 0) ...[
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: _orange.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                            child: Text('🔥 ${nutrition.calories}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _orange)),
                          ),
                          if (nutrition.protein > 0 || nutrition.carbs > 0 || nutrition.fat > 0) ...[
                            const SizedBox(height: 3),
                            Text('P:${nutrition.protein.toStringAsFixed(0)}g', style: TextStyle(fontSize: 9, color: _blue)),
                            Text('C:${nutrition.carbs.toStringAsFixed(0)}g', style: TextStyle(fontSize: 9, color: _green)),
                            Text('F:${nutrition.fat.toStringAsFixed(0)}g', style: TextStyle(fontSize: 9, color: _orange)),
                          ],
                        ],
                      ]),
                    ),
                  ),
                );
              })),
              const SizedBox(height: 20),
              // Add button
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selected != null ? _purple : const Color(0xFFE5E5EA),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: selected == null ? null : () {
                    final idx   = portionOrder.indexOf(selected!);
                    final pKey  = portionKeys[idx];
                    final pPrice = portionPrices[pKey]!;
                    final nutr  = portionNutrition[pKey] ?? const PortionNutrition();
                    final itemKey = '${itemData['restaurantId']}__${itemData['name']}';
                    setState(() {
                      _selectedItems[itemKey] = BundleItem(
                        name:               itemData['name'],
                        restaurantId:       itemData['restaurantId'],
                        restaurantName:     itemData['restaurantName'],
                        price:              itemData['price'],
                        portionPrice:       pPrice,
                        imageUrl:           itemData['imageUrl'],
                        isVeg:              itemData['isVeg'],
                        calories:           nutr.calories,
                        protein:            nutr.protein,
                        carbs:              nutr.carbs,
                        fat:                nutr.fat,
                        isItemAvailable:    itemData['isItemAvailable'] ?? true,
                        isRestaurantActive: itemData['isRestaurantActive'] ?? true,
                        portionPrices:      portionPrices,
                        portionNutrition:   portionNutrition,
                        selectedPortion:    selected,
                      );
                    });
                    Navigator.pop(ctx);
                    _snack('${selected!.label} ${itemData['name']} added to bundle 📦', _purple);
                  },
                  child: Text(
                    selected != null
                        ? 'Add ${selected!.label} to Bundle — ₹${portionPrices[portionKeys[portionOrder.indexOf(selected!)]]?.toStringAsFixed(0)}'
                        : 'Select a Portion',
                    style: TextStyle(
                      color: selected != null ? Colors.white : const Color(0xFF6E6E73),
                      fontSize: 14, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _incrementItem(String key) {
    setState(() {
      if (_selectedItems.containsKey(key)) {
        _selectedItems[key]!.quantity++;
      }
    });
  }

  void _decrementItem(String key) {
    setState(() {
      if (_selectedItems.containsKey(key)) {
        if (_selectedItems[key]!.quantity > 1) {
          _selectedItems[key]!.quantity--;
        } else {
          _selectedItems.remove(key);
        }
      }
    });
  }

  // ── Save bundle ─────────────────────────────
  Future<void> _saveBundle() async {
    if (_selectedItems.isEmpty) {
      _snack('Add at least one item to your bundle', _red);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Please log in to save a bundle', _red);
      return;
    }

    String bundleName = 'My Bundle ${DateTime.now().day}/${DateTime.now().month}';
    final nameCtrl = TextEditingController(text: bundleName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('📦', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          const Text('Name Your Bundle',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Weekend Feast',
              filled: true,
              fillColor: const Color(0xFFF7F7F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow('Items', '$_totalItemCount items', _purple),
          _summaryRow(
              'Total', '₹${_totalPrice.toStringAsFixed(0)}', _green),
          _summaryRow('Calories', '$_totalCalories kcal', _orange),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6E6E73))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Bundle',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    bundleName = nameCtrl.text.trim().isEmpty ? 'My Bundle' : nameCtrl.text.trim();

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bundles')
          .add({
        'name': bundleName,
        'items': _selectedItems.values.map((i) => i.toMap()).toList(),
        'totalPrice': _totalPrice,
        'totalCalories': _totalCalories,
        'totalProtein': _totalProtein,
        'totalCarbs': _totalCarbs,
        'totalFat': _totalFat,
        'itemCount': _totalItemCount,
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() => _selectedItems.clear());
      if (mounted) {
        _snack('Bundle "$bundleName" saved! 📦', _green);
        _tabCtrl.animateTo(1); // Switch to saved bundles tab
      }
    } catch (e) {
      debugPrint('BundleScreen._saveBundle error: $e');
      _snack('Failed to save bundle. Try again.', _red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Order a saved bundle ────────────────────
  Future<void> _orderBundle(SavedBundle bundle) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Please log in to place an order', _red);
      return;
    }
    if (bundle.items.isEmpty) {
      _snack('Bundle has no items', _red);
      return;
    }

    // ✅ Block order if any item is unavailable
    if (bundle.hasUnavailableItems) {
      final unavailableNames = bundle.items
          .where((i) => !i.isAvailable)
          .map((i) => i.name)
          .join(', ');
      _snack('Cannot order — unavailable items: $unavailableNames', _red);
      return;
    }

    // Collect unique restaurant names for display
    final uniqueRestaurants =
        bundle.items.map((i) => i.restaurantName).toSet().toList();
    final restaurantLabel = uniqueRestaurants.length == 1
        ? uniqueRestaurants.first
        : uniqueRestaurants.join(', ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Text('📦 ', style: TextStyle(fontSize: 18)),
          const Text('Order Bundle?',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bundle.name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _purple)),
              const SizedBox(height: 4),
              // Show all restaurant names
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.storefront_rounded,
                    size: 13, color: Color(0xFF6E6E73)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(restaurantLabel,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF6E6E73))),
                ),
              ]),
              const SizedBox(height: 10),
              _summaryRow('Items', '${bundle.totalItems} items', _purple),
              _summaryRow(
                  'Total', '₹${bundle.totalPrice.toStringAsFixed(0)}', _green),
              _summaryRow(
                  'Calories', '${bundle.totalCalories} kcal', _orange),
            ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6E6E73))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Place Order',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // ── Navigate to Checkout instead of placing directly ──────────────────
    final items = bundle.items.map((i) => i.toMap()).toList();

    final payload = CheckoutPayload(
      items:          items,
      totalPrice:     bundle.totalPrice,
      totalCalories:  bundle.totalCalories,
      totalProtein:   bundle.totalProtein,
      totalCarbs:     bundle.totalCarbs,
      totalFat:       bundle.totalFat,
      restaurantName: restaurantLabel,
      source:         'bundle',
      bundleId:       bundle.id,
      bundleName:     bundle.name,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckoutScreen(payload: payload),
        ),
      );
    }
  }

  // ── Order success dialog ────────────────────
  void _showOrderSuccessDialog({
    required String orderId,
    required String bundleName,
    required String restaurantLabel,
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
    required double total,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            // ✅ tick
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: _green.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded,
                  color: _green, size: 44),
            ),
            const SizedBox(height: 16),
            const Text('Order Placed! 🎉',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 4),
            Text('Order #${orderId.substring(0, 8).toUpperCase()}',
                style: const TextStyle(
                    fontSize: 12.5, color: Color(0xFF6E6E73))),
            const SizedBox(height: 6),

            // ✅ Bundle name pill
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('📦 ',
                    style: TextStyle(fontSize: 12)),
                Text(bundleName,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _purple)),
              ]),
            ),
            const SizedBox(height: 6),

            // ✅ Restaurant name(s)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.storefront_rounded,
                  size: 13, color: Color(0xFF6E6E73)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(restaurantLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF6E6E73))),
              ),
            ]),
            const SizedBox(height: 18),

            // ✅ Nutrition banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF9F0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFE0B2))),
              child: Column(children: [
                const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: Color(0xFFFF9500), size: 15),
                  SizedBox(width: 5),
                  Text("Added to Today's Nutrition Log",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                ]),
                const SizedBox(height: 12),
                if (calories > 0)
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text('$calories',
                        style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: _red)),
                    const SizedBox(width: 5),
                    const Text('kcal',
                        style: TextStyle(
                            fontSize: 15, color: Color(0xFF6E6E73))),
                  ]),
                const SizedBox(height: 12),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                  _macroCell('💪', 'Protein',
                      '${protein.toStringAsFixed(1)}g', _blue),
                  _vertDivider(),
                  _macroCell('🌾', 'Carbs',
                      '${carbs.toStringAsFixed(1)}g', _green),
                  _vertDivider(),
                  _macroCell('🥑', 'Fat',
                      '${fat.toStringAsFixed(1)}g', _orange),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // ✅ Amount paid
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                const Text('Amount Paid',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF6E6E73))),
                Text('₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E))),
              ]),
            ),
            const SizedBox(height: 20),

            // ✅ Done button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
                onPressed: () => Navigator.pop(context),
                child: const Text('Great, Thanks! 🙌',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Macro cell helper ───────────────────────
  Widget _macroCell(
      String emoji, String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      Text(label,
          style: const TextStyle(
              fontSize: 10.5, color: Color(0xFF6E6E73))),
    ]);
  }

  Widget _vertDivider() =>
      Container(height: 40, width: 1, color: const Color(0xFFE5E5EA));

  // ── Delete saved bundle ─────────────────────
  Future<void> _deleteBundle(String bundleId, String bundleName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Bundle?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete "$bundleName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6E6E73))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bundles')
          .doc(bundleId)
          .delete();
      _snack('Bundle deleted', _red);
    } catch (e) {
      _snack('Failed to delete', _red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildCreatorTab(),
                _buildSavedBundlesTab(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Header ──────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF0077B6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _purple.withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
              child: Text('📦', style: TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bundle Creator',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E))),
            Text('Group items into your perfect meal',
                style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
          ]),
        ),
        if (_selectedItems.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _selectedItems.clear()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Clear',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _red)),
            ),
          ),
      ]),
    );
  }

  // ── TabBar ──────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabCtrl,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        labelColor: _purple,
        unselectedLabelColor: const Color(0xFF6E6E73),
        labelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: '🛠️  Build Bundle'),
          Tab(text: '📋  My Bundles'),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TAB 1: Bundle Creator
  // ─────────────────────────────────────────────
  Widget _buildCreatorTab() {
    return Column(children: [
      _buildSearchAndFilter(),
      if (_selectedItems.isNotEmpty) _buildLiveSummaryBar(),
      Expanded(child: _loadingItems ? _buildLoadingState() : _buildItemGrid()),
      if (_selectedItems.isNotEmpty) _buildSaveButton(),
    ]);
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(children: [
        // Search bar
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E5EA)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: const InputDecoration(
              hintText: 'Search items or restaurants...',
              hintStyle:
                  TextStyle(fontSize: 13, color: Color(0xFFAEAEB2)),
              prefixIcon: Icon(Icons.search_rounded,
                  color: Color(0xFF6E6E73), size: 20),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Filter row
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            // Veg toggle
            GestureDetector(
              onTap: () => setState(() => _vegOnly = !_vegOnly),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _vegOnly ? _green : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _vegOnly ? _green : const Color(0xFFE5E5EA)),
                ),
                child: Row(children: [
                  const Text('🥦', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text('Veg',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _vegOnly ? Colors.white : const Color(0xFF6E6E73))),
                ]),
              ),
            ),
            // Restaurant filters
            ..._restaurantNames.map((r) {
              final isSelected = _filterRestaurant == r;
              return GestureDetector(
                onTap: () => setState(() => _filterRestaurant = r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _purple : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isSelected
                            ? _purple
                            : const Color(0xFFE5E5EA)),
                  ),
                  child: Center(
                    child: Text(r,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF6E6E73))),
                  ),
                ),
              );
            }),
          ]),
        ),
      ]),
    );
  }

  // Live summary bar (shows when items are selected)
  Widget _buildLiveSummaryBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: _purple.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        const Text('📦', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text('$_totalItemCount items',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        _livePill('🔥', '$_totalCalories', 'kcal', const Color(0xFFFFD700)),
        const SizedBox(width: 8),
        _livePill('💰', '₹${_totalPrice.toStringAsFixed(0)}', '', Colors.white),
      ]),
    );
  }

  Widget _livePill(String emoji, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Text('$value$unit',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: _purple),
        SizedBox(height: 12),
        Text('Loading food items...',
            style: TextStyle(color: Color(0xFF6E6E73))),
      ]),
    );
  }

  Widget _buildItemGrid() {
    // ListenableBuilder ensures distances recalculate whenever the user's
    // location becomes available (LocationService is a ChangeNotifier).
    return ListenableBuilder(
      listenable: LocationService.instance,
      builder: (_, __) {
    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🍽️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
              _allItems.isEmpty
                  ? 'No food items available'
                  : 'No items match your filter',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6E6E73))),
          if (_allItems.isEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _loadAllFoodItems,
              child: const Text('Tap to retry',
                  style: TextStyle(
                      fontSize: 13,
                      color: _purple,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildFoodItemCard(items[i]),
    );
      }, // ListenableBuilder builder
    );  // ListenableBuilder
  }

  Widget _buildFoodItemCard(Map<String, dynamic> item) {
    final key = '${item['restaurantId']}__${item['name']}';
    final isSelected = _selectedItems.containsKey(key);
    final qty = _selectedItems[key]?.quantity ?? 0;
    final isVeg = item['isVeg'] as bool;
    final calories = (item['calories'] as int);

    // ✅ Availability
    final isItemAvailable    = item['isItemAvailable'] as bool? ?? true;
    final isRestaurantActive = item['isRestaurantActive'] as bool? ?? true;
    final canOrder = isItemAvailable && isRestaurantActive;

    // ✅ Portions
    final portionPrices = (item['portionPrices'] as Map<String, double>?) ?? {};
    final hasPortion = portionPrices.isNotEmpty;
    final selectedItem = _selectedItems[key];
    final portionLabel = selectedItem?.selectedPortion?.label;

    return Opacity(
      opacity: canOrder ? 1.0 : 0.75,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? (canOrder ? _purple : const Color(0xFF9E9E9E))
                : const Color(0xFFF0F0F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: isSelected
                    ? (canOrder ? _purple.withOpacity(0.12) : Colors.black.withOpacity(0.04))
                    : Colors.black.withOpacity(0.04),
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          // Image — greyscale when unavailable
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(13)),
            child: ColorFiltered(
              colorFilter: canOrder
                  ? const ColorFilter.mode(Colors.transparent, BlendMode.saturation)
                  : const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0,      0,      0,      1, 0,
                    ]),
              child: SizedBox(
                width: 80, height: 80,
                child: (item['imageUrl'] as String).isNotEmpty
                    ? Image.network(item['imageUrl'],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imgPlaceholder())
                    : _imgPlaceholder(),
              ),
            ),
          ),
          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  // Veg / Non-veg dot
                  Container(
                    width: 13, height: 13,
                    decoration: BoxDecoration(
                      border: Border.all(color: isVeg ? _green : _red, width: 1.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(child: Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(color: isVeg ? _green : _red, shape: BoxShape.circle),
                    )),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(item['name'],
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: canOrder ? const Color(0xFF1C1C1E) : const Color(0xFF9E9E9E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 4),
                  // ⭐ Live rating badge
                  StreamBuilder<double>(
                    stream: FavoritesRatingsService.instance
                        .itemAverageRatingStream(
                            item['restaurantId'] as String,
                            item['name'] as String),
                    builder: (_, snap) {
                      final avg = snap.data ?? 0.0;
                      if (avg <= 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(avg.toStringAsFixed(1),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          const Icon(Icons.star_rounded, color: Colors.white, size: 10),
                        ]),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 3),
                Text(item['restaurantName'],
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73))),
                // ── ETA · Location · Distance ──────────────────────────────
                Builder(builder: (_) {
                  final locMap = item['restaurantLocation'] as Map<String, dynamic>?;
                  final shortName = (locMap?['shortName'] as String?) ?? '';
                  final distKm = _bundleCalcDistanceKm(locMap);
                  final deliveryStr = (item['restaurantDeliveryTime'] as String?) ?? '30 min';
                  final etaLabel = _bundleCalcDelivery(
                      deliveryTimeStr: deliveryStr, distanceKm: distKm);
                  return Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      // ETA
                      const Icon(Icons.access_time_rounded, size: 11, color: Color(0xFF6E6E73)),
                      const SizedBox(width: 3),
                      Text(etaLabel,
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF6E6E73))),
                      // Location name
                      if (shortName.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        const Text('·', style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2))),
                        const SizedBox(width: 4),
                        const Icon(Icons.location_on_rounded, size: 11, color: Color(0xFF0077B6)),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(shortName,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF0077B6),
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      // Distance
                      if (distKm != null) ...[
                        const SizedBox(width: 4),
                        const Text('·', style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2))),
                        const SizedBox(width: 4),
                        Text(_bundleFmtDistance(distKm),
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF0077B6),
                                fontWeight: FontWeight.w600)),
                      ],
                    ]),
                  );
                }),
                const SizedBox(height: 4),

                // ✅ Unavailability badges (same style as home_screen)
                if (!isRestaurantActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFF9E9E9E).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('Restaurant Unavailable',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9E9E9E))),
                  )
                else if (!isItemAvailable)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: _red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _red.withOpacity(0.25))),
                    child: const Text('Item Unavailable',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _red)),
                  ),

                const SizedBox(height: 4),
                // Price: show range for portion items
                if (hasPortion)
                  Row(children: [
                    Text(
                      '₹${_minP(portionPrices).toStringAsFixed(0)} – ₹${_maxP(portionPrices).toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                          color: canOrder ? _purple : const Color(0xFF9E9E9E)),
                    ),
                    if (portionLabel != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(portionLabel,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _purple)),
                      ),
                    ],
                  ])
                else
                  Row(children: [
                    Text('₹${(item['price'] as double).toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: canOrder ? const Color(0xFF1C1C1E) : const Color(0xFF9E9E9E))),
                    if (calories > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('🔥 $calories kcal',
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600, color: _orange)),
                      ),
                    ],
                  ]),
              ]),
            ),
          ),
          // ✅ Add / qty control — N/A when unavailable
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: !canOrder && !isSelected
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text('N/A',
                        style: TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  )
                : isSelected
                    ? _qtyControl(key, qty, canOrder: canOrder)
                    : GestureDetector(
                        onTap: () => _toggleItem(item),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: _purple,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                  color: _purple.withOpacity(0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  double _minP(Map<String, double> p) { final v = p.values.where((x) => x > 0); return v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b); }
  double _maxP(Map<String, double> p) { final v = p.values.where((x) => x > 0); return v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b); }

  Widget _qtyControl(String key, int qty, {bool canOrder = true}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: () => _decrementItem(key),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: qty == 1
                ? _red.withOpacity(0.1)
                : _purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
              qty == 1
                  ? Icons.delete_outline_rounded
                  : Icons.remove_rounded,
              size: 16,
              color: qty == 1 ? _red : _purple),
        ),
      ),
      SizedBox(
        width: 28,
        child: Text('$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
      ),
      GestureDetector(
        onTap: () => _incrementItem(key),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.add_rounded, size: 16, color: _purple),
        ),
      ),
    ]);
  }

  Widget _buildSaveButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: Column(children: [
        // Nutrition breakdown strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F3FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
            _macroChip('💪', '${_totalProtein.toStringAsFixed(1)}g',
                'Protein', _blue),
            _macroChip('🌾', '${_totalCarbs.toStringAsFixed(1)}g',
                'Carbs', _green),
            _macroChip(
                '🥑', '${_totalFat.toStringAsFixed(1)}g', 'Fat', _orange),
            _macroChip('🔥', '$_totalCalories', 'kcal', _red),
          ]),
        ),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: _isSaving ? null : _saveBundle,
            child: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('📦  Save Bundle',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('₹${_totalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
          ),
        ),
      ]),
    );
  }

  Widget _macroChip(
      String emoji, String value, String label, Color color) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      Text(label,
          style: const TextStyle(fontSize: 9, color: Color(0xFF6E6E73))),
    ]);
  }

  // ─────────────────────────────────────────────
  // TAB 2: Saved Bundles
  // ─────────────────────────────────────────────
  Widget _buildSavedBundlesTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🔒', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Login to view your bundles',
              style: TextStyle(
                  fontSize: 15, color: Color(0xFF6E6E73))),
        ]),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bundles')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _purple));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📦', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              const Text('No bundles yet',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 6),
              const Text('Build your first bundle in the Builder tab!',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF6E6E73))),
              const SizedBox(height: 18),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => _tabCtrl.animateTo(0),
                child: const Text('  🛠️  Build a Bundle  ',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          );
        }

        final bundles = snapshot.data!.docs
            .map((d) => _hydrateBundleAvailability(SavedBundle.fromFirestore(d)))
            .toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          itemCount: bundles.length,
          itemBuilder: (_, i) => _buildSavedBundleCard(bundles[i]),
        );
      },
    );
  }

  // ── Live availability hydration for saved bundles ──────────────────────────
  /// Cross-references each saved bundle item against the freshly loaded
  /// _allItems list so the "Unavailable" badge and order-block reflect the
  /// admin's current settings, even for previously-saved bundles.
  SavedBundle _hydrateBundleAvailability(SavedBundle bundle) {
    if (_allItems.isEmpty) return bundle; // still loading — leave as-is

    final hydratedItems = bundle.items.map((item) {
      // Find matching live item by restaurantId + name
      final live = _allItems.firstWhere(
        (a) => a['restaurantId'] == item.restaurantId && a['name'] == item.name,
        orElse: () => {},
      );
      if (live.isEmpty) {
        // Item no longer exists in Firestore → treat as unavailable
        return BundleItem(
          name:               item.name,
          restaurantId:       item.restaurantId,
          restaurantName:     item.restaurantName,
          price:              item.price,
          portionPrice:       item.portionPrice,
          imageUrl:           item.imageUrl,
          isVeg:              item.isVeg,
          calories:           item.calories,
          protein:            item.protein,
          carbs:              item.carbs,
          fat:                item.fat,
          quantity:           item.quantity,
          selectedPortion:    item.selectedPortion,
          isItemAvailable:    false,
          isRestaurantActive: false,
        );
      }
      return BundleItem(
        name:               item.name,
        restaurantId:       item.restaurantId,
        restaurantName:     item.restaurantName,
        price:              item.price,
        portionPrice:       item.portionPrice,
        imageUrl:           item.imageUrl,
        isVeg:              item.isVeg,
        calories:           item.calories,
        protein:            item.protein,
        carbs:              item.carbs,
        fat:                item.fat,
        quantity:           item.quantity,
        selectedPortion:    item.selectedPortion,
        isItemAvailable:    live['isItemAvailable'] as bool? ?? true,
        isRestaurantActive: live['isRestaurantActive'] as bool? ?? true,
      );
    }).toList();

    return SavedBundle(
      id:        bundle.id,
      name:      bundle.name,
      items:     hydratedItems,
      createdAt: bundle.createdAt,
    );
  }

  // ── Edit saved bundle (rename + add/remove items) ──────────────────────────
  void _showEditBundleSheet(SavedBundle bundle) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nameCtrl   = TextEditingController(text: bundle.name);
    final searchCtrl = TextEditingController();

    // Working copy of selected items (keyed by restaurantId__name)
    final Map<String, BundleItem> editItems = {
      for (final i in bundle.items) i.key: i,
    };

    bool   isSaving     = false;
    String editSearch   = '';
    bool   editVegOnly  = false;
    String editRestFilter = 'All';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModal) {
          // ── Totals ──────────────────────────────────────────────────────
          double totalPrice() =>
              editItems.values.fold(0.0, (s, i) => s + i.effectivePrice * i.quantity);
          int totalCal() =>
              editItems.values.fold(0, (s, i) => s + i.calories * i.quantity);

          // ── Filtered catalogue (exclude already-added & unavailable) ───
          final catalogue = _allItems.where((a) {
            final key = '${a['restaurantId']}__${a['name']}';
            if (editItems.containsKey(key)) return false;
            if (!(a['isItemAvailable'] as bool? ?? true)) return false;
            if (!(a['isRestaurantActive'] as bool? ?? true)) return false;
            if (editVegOnly && !(a['isVeg'] as bool)) return false;
            if (editRestFilter != 'All' &&
                a['restaurantName'] != editRestFilter) return false;
            if (editSearch.isNotEmpty) {
              final q = editSearch.toLowerCase();
              final nameMatch =
                  (a['name'] as String).toLowerCase().contains(q);
              final restMatch =
                  (a['restaurantName'] as String).toLowerCase().contains(q);
              if (!nameMatch && !restMatch) return false;
            }
            return true;
          }).toList();

          // Unique restaurant names for filter chips
          final restNames = [
            'All',
            ..._allItems
                .where((a) =>
                    (a['isItemAvailable'] as bool? ?? true) &&
                    (a['isRestaurantActive'] as bool? ?? true))
                .map((a) => a['restaurantName'] as String)
                .toSet()
                .toList()
              ..sort(),
          ];

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.92,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                // ── Handle ────────────────────────────────────────────────
                const SizedBox(height: 12),
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: const Color(0xFFE5E5EA),
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),

                // ── Header ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: _purple.withOpacity(0.1),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.edit_rounded,
                          color: _purple, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Edit Bundle',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1C1E))),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),

                // ── Bundle name field ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: nameCtrl,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF1C1C1E)),
                    decoration: InputDecoration(
                      labelText: 'Bundle Name',
                      labelStyle: const TextStyle(
                          fontSize: 13, color: Color(0xFF6E6E73)),
                      prefixIcon: const Icon(Icons.label_outline_rounded,
                          size: 18, color: _purple),
                      filled: true,
                      fillColor: _purple.withOpacity(0.04),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: _purple.withOpacity(0.25))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: _purple.withOpacity(0.25))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: _purple, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Live summary strip ─────────────────────────────────────
                if (editItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        const Text('📦', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                            '${editItems.values.fold(0, (s, i) => s + i.quantity)} items',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('🔥 ${totalCal()} kcal',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 10),
                        Text('₹${totalPrice().toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),

                const Divider(height: 1),

                // ── Scrollable content ────────────────────────────────────
                Expanded(
                  child: _loadingItems
                      ? const Center(
                          child: CircularProgressIndicator(color: _purple))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                          children: [
                            // ── Current bundle items ─────────────────────
                            if (editItems.isNotEmpty) ...[
                              const Text('In your bundle',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6E6E73))),
                              const SizedBox(height: 8),
                              ...editItems.values.map((bi) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _purple.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: _purple.withOpacity(0.3),
                                        width: 1.5),
                                  ),
                                  child: Row(children: [
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                          '${bi.name}${bi.selectedPortion != null ? ' (${bi.selectedPortion!.label})' : ''}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1C1C1E)),
                                        ),
                                        Text(bi.restaurantName,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF6E6E73))),
                                        // ── Distance + ETA ──────────────
                                        Builder(builder: (_) {
                                          // Find matching item from _allItems for location data
                                          final srcItem = _allItems.firstWhere(
                                            (a) => a['restaurantId'] == bi.restaurantId && a['name'] == bi.name,
                                            orElse: () => <String, dynamic>{},
                                          );
                                          final locMap = srcItem['restaurantLocation'] as Map<String, dynamic>?;
                                          final distKm = _bundleCalcDistanceKm(locMap);
                                          final deliveryStr = (srcItem['restaurantDeliveryTime'] as String?) ?? '30 min';
                                          final etaLabel = _bundleCalcDelivery(
                                              deliveryTimeStr: deliveryStr, distanceKm: distKm);
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Row(children: [
                                              const Icon(Icons.access_time_rounded, size: 10, color: Color(0xFF6E6E73)),
                                              const SizedBox(width: 3),
                                              Text(etaLabel,
                                                  style: const TextStyle(fontSize: 10, color: Color(0xFF6E6E73))),
                                              if (distKm != null) ...[
                                                const SizedBox(width: 4),
                                                const Icon(Icons.delivery_dining_rounded, size: 10, color: Color(0xFF0077B6)),
                                                const SizedBox(width: 2),
                                                Text(_bundleFmtDistance(distKm),
                                                    style: const TextStyle(fontSize: 10, color: Color(0xFF0077B6), fontWeight: FontWeight.w600)),
                                              ],
                                            ]),
                                          );
                                        }),
                                        Text(
                                          '₹${bi.effectivePrice.toStringAsFixed(0)} each',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _purple),
                                        ),
                                      ]),
                                    ),
                                    // Qty control
                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                      GestureDetector(
                                        onTap: () => setModal(() {
                                          if (bi.quantity > 1) {
                                            bi.quantity--;
                                          } else {
                                            editItems.remove(bi.key);
                                          }
                                        }),
                                        child: Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                              color: bi.quantity == 1
                                                  ? _red.withOpacity(0.1)
                                                  : _purple.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(7)),
                                          child: Icon(
                                              bi.quantity == 1
                                                  ? Icons.delete_outline_rounded
                                                  : Icons.remove_rounded,
                                              size: 14,
                                              color: bi.quantity == 1
                                                  ? _red
                                                  : _purple),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 28,
                                        child: Text('${bi.quantity}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1C1C1E))),
                                      ),
                                      GestureDetector(
                                        onTap: () =>
                                            setModal(() => bi.quantity++),
                                        child: Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                              color:
                                                  _purple.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(7)),
                                          child: const Icon(Icons.add_rounded,
                                              size: 14, color: _purple),
                                        ),
                                      ),
                                    ]),
                                  ]),
                                );
                              }),
                              const SizedBox(height: 6),
                              const Divider(color: Color(0xFFE5E5EA)),
                              const SizedBox(height: 4),
                            ],

                            // ── Add items section ────────────────────────
                            const Text('Add items',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6E6E73))),
                            const SizedBox(height: 10),

                            // Search bar
                            Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                    color: const Color(0xFFE5E5EA)),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2))
                                ],
                              ),
                              child: TextField(
                                controller: searchCtrl,
                                onChanged: (v) =>
                                    setModal(() => editSearch = v.trim()),
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF1C1C1E)),
                                decoration: const InputDecoration(
                                  hintText: 'Search items or restaurants...',
                                  hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFAEAEB2)),
                                  prefixIcon: Icon(Icons.search_rounded,
                                      color: Color(0xFF6E6E73), size: 19),
                                  border: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Filter chips row
                            SizedBox(
                              height: 32,
                              child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                // Veg toggle
                                GestureDetector(
                                  onTap: () => setModal(
                                      () => editVegOnly = !editVegOnly),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: editVegOnly
                                          ? _green
                                          : Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                          color: editVegOnly
                                              ? _green
                                              : const Color(0xFFE5E5EA)),
                                    ),
                                    child: Row(children: [
                                      const Text('🥦',
                                          style: TextStyle(fontSize: 12)),
                                      const SizedBox(width: 4),
                                      Text('Veg',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: editVegOnly
                                                  ? Colors.white
                                                  : const Color(
                                                      0xFF6E6E73))),
                                    ]),
                                  ),
                                ),
                                // Restaurant chips
                                ...restNames.map((r) {
                                  final isSel = editRestFilter == r;
                                  return GestureDetector(
                                    onTap: () => setModal(
                                        () => editRestFilter = r),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 150),
                                      margin:
                                          const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? _purple
                                            : Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: isSel
                                                ? _purple
                                                : const Color(
                                                    0xFFE5E5EA)),
                                      ),
                                      child: Center(
                                        child: Text(r,
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color: isSel
                                                    ? Colors.white
                                                    : const Color(
                                                        0xFF6E6E73))),
                                      ),
                                    ),
                                  );
                                }),
                              ]),
                            ),
                            const SizedBox(height: 10),

                            // Catalogue results
                            if (catalogue.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                    const Text('🍽️',
                                        style: TextStyle(fontSize: 36)),
                                    const SizedBox(height: 8),
                                    Text(
                                        editSearch.isNotEmpty
                                            ? 'No items match "$editSearch"'
                                            : 'All available items are already in your bundle',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF6E6E73))),
                                  ]),
                                ),
                              )
                            else
                              ...catalogue.map((itemData) {
                                final portionPrices =
                                    (itemData['portionPrices']
                                            as Map<String, double>?) ??
                                        {};
                                final isVeg = itemData['isVeg'] as bool;
                                final calories =
                                    itemData['calories'] as int;
                                return Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F7F7),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE5E5EA)),
                                  ),
                                  child: Row(children: [
                                    // Veg/non-veg dot
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(
                                          right: 8, top: 2),
                                      decoration: BoxDecoration(
                                          color:
                                              isVeg ? _green : _red,
                                          shape: BoxShape.circle),
                                    ),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(itemData['name'],
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color:
                                                    Color(0xFF1C1C1E))),
                                        Text(
                                            itemData['restaurantName'],
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color:
                                                    Color(0xFF6E6E73))),
                                        Row(children: [
                                          Text(
                                            portionPrices.isNotEmpty
                                                ? '₹${_minP(portionPrices).toStringAsFixed(0)} – ₹${_maxP(portionPrices).toStringAsFixed(0)}'
                                                : '₹${(itemData['price'] as double).toStringAsFixed(0)}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: portionPrices
                                                        .isNotEmpty
                                                    ? _purple
                                                    : const Color(
                                                        0xFF1C1C1E)),
                                          ),
                                          if (calories > 0) ...[
                                            const SizedBox(width: 6),
                                            Text('🔥 $calories kcal',
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(
                                                        0xFFFF9500))),
                                          ],
                                        ]),
                                      ]),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        if (portionPrices.isNotEmpty) {
                                          Navigator.pop(ctx);
                                          _showBundlePortionPickerForEdit(
                                            itemData,
                                            bundle,
                                            editItems,
                                            nameCtrl.text.trim(),
                                            user,
                                          );
                                        } else {
                                          setModal(() {
                                            final key =
                                                '${itemData['restaurantId']}__${itemData['name']}';
                                            editItems[key] = BundleItem(
                                              name: itemData['name'],
                                              restaurantId:
                                                  itemData['restaurantId'],
                                              restaurantName:
                                                  itemData['restaurantName'],
                                              price: itemData['price'],
                                              imageUrl:
                                                  itemData['imageUrl'],
                                              isVeg: itemData['isVeg'],
                                              calories:
                                                  itemData['calories'],
                                              protein: itemData['protein'],
                                              carbs: itemData['carbs'],
                                              fat: itemData['fat'],
                                              isItemAvailable: true,
                                              isRestaurantActive: true,
                                            );
                                          });
                                        }
                                      },
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: _purple,
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                        child: const Icon(
                                            Icons.add_rounded,
                                            color: Colors.white,
                                            size: 20),
                                      ),
                                    ),
                                  ]),
                                );
                              }),
                          ],
                        ),
                ),

                // ── Save button ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (editItems.isEmpty) {
                                _snack(
                                    'Bundle must have at least one item',
                                    _red);
                                return;
                              }
                              setModal(() => isSaving = true);
                              try {
                                final newName =
                                    nameCtrl.text.trim().isEmpty
                                        ? bundle.name
                                        : nameCtrl.text.trim();
                                final items = editItems.values
                                    .map((i) => i.toMap())
                                    .toList();
                                final tp = editItems.values.fold(
                                    0.0,
                                    (s, i) =>
                                        s + i.effectivePrice * i.quantity);
                                final tc = editItems.values.fold(
                                    0,
                                    (s, i) =>
                                        s + i.calories * i.quantity);
                                final tpro = editItems.values.fold(
                                    0.0,
                                    (s, i) =>
                                        s + i.protein * i.quantity);
                                final tcarb = editItems.values.fold(
                                    0.0,
                                    (s, i) => s + i.carbs * i.quantity);
                                final tfat = editItems.values.fold(
                                    0.0,
                                    (s, i) => s + i.fat * i.quantity);
                                final tic = editItems.values
                                    .fold(0, (s, i) => s + i.quantity);

                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .collection('bundles')
                                    .doc(bundle.id)
                                    .update({
                                  'name': newName,
                                  'items': items,
                                  'totalPrice': tp,
                                  'totalCalories': tc,
                                  'totalProtein': tpro,
                                  'totalCarbs': tcarb,
                                  'totalFat': tfat,
                                  'itemCount': tic,
                                  'updatedAt':
                                      FieldValue.serverTimestamp(),
                                });
                                if (ctx.mounted) Navigator.pop(ctx);
                                _snack('Bundle updated! ✅', _purple);
                              } catch (e) {
                                _snack('Failed to save changes', _red);
                              } finally {
                                setModal(() => isSaving = false);
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Save Changes',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }


  // ── Portion picker for items added during edit ──────────────────────────────
  void _showBundlePortionPickerForEdit(
    Map<String, dynamic> itemData,
    SavedBundle bundle,
    Map<String, BundleItem> editItems,
    String currentBundleName,
    User user,
  ) {
    final portionPrices =
        (itemData['portionPrices'] as Map<String, double>?) ?? {};
    final portionNutrition =
        (itemData['portionNutrition'] as Map<String, PortionNutrition>?) ?? {};

    const portionOrder = [Portion.quarter, Portion.half, Portion.full];
    const portionKeys = ['quarter', 'half', 'full'];
    const portionEmojis = ['🍗', '🍖', '🫕'];

    Portion? selected;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Text('📦', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Text(itemData['name'],
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E))),
                const Text('Choose a portion to add to bundle',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF6E6E73))),
              ])),
            ]),
            const SizedBox(height: 20),
            Row(
                children: List.generate(portionOrder.length, (i) {
              final portion = portionOrder[i];
              final key = portionKeys[i];
              final price = portionPrices[key];
              if (price == null || price <= 0) return const SizedBox.shrink();
              final nutrition = portionNutrition[key];
              final isSel = selected == portion;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setModalState(() => selected = portion),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSel
                          ? _purple.withOpacity(0.07)
                          : const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: isSel ? _purple : const Color(0xFFE5E5EA),
                          width: isSel ? 2 : 1),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(portionEmojis[i],
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 5),
                      Text(portion.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSel ? _purple : const Color(0xFF1C1C1E))),
                      const SizedBox(height: 3),
                      Text('₹${price.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isSel ? _purple : const Color(0xFF6E6E73))),
                      if (nutrition != null && nutrition.calories > 0) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: _orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text('🔥 ${nutrition.calories}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _orange)),
                        ),
                      ],
                    ]),
                  ),
                ),
              );
            })),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      selected != null ? _purple : const Color(0xFFE5E5EA),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: selected == null
                    ? null
                    : () {
                        final idx = portionOrder.indexOf(selected!);
                        final pKey = portionKeys[idx];
                        final pPrice = portionPrices[pKey]!;
                        final nutr = portionNutrition[pKey] ??
                            const PortionNutrition();
                        final itemKey =
                            '${itemData['restaurantId']}__${itemData['name']}';
                        editItems[itemKey] = BundleItem(
                          name: itemData['name'],
                          restaurantId: itemData['restaurantId'],
                          restaurantName: itemData['restaurantName'],
                          price: itemData['price'],
                          portionPrice: pPrice,
                          imageUrl: itemData['imageUrl'],
                          isVeg: itemData['isVeg'],
                          calories: nutr.calories,
                          protein: nutr.protein,
                          carbs: nutr.carbs,
                          fat: nutr.fat,
                          isItemAvailable: true,
                          isRestaurantActive: true,
                          portionPrices: portionPrices,
                          portionNutrition: portionNutrition,
                          selectedPortion: selected,
                        );
                        Navigator.pop(ctx);
                        // Re-open the edit sheet with the updated items
                        final updatedBundle = SavedBundle(
                          id: bundle.id,
                          name: currentBundleName.isEmpty
                              ? bundle.name
                              : currentBundleName,
                          items: editItems.values.toList(),
                          createdAt: bundle.createdAt,
                        );
                        _showEditBundleSheet(updatedBundle);
                        _snack(
                            '${selected!.label} ${itemData['name']} added 📦',
                            _purple);
                      },
                child: Text(
                  selected != null
                      ? 'Add ${selected!.label} to Bundle'
                      : 'Select a Portion',
                  style: TextStyle(
                    color: selected != null
                        ? Colors.white
                        : const Color(0xFF6E6E73),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSavedBundleCard(SavedBundle bundle) {
    final hasUnavailable = bundle.hasUnavailableItems;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Card header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_purple.withOpacity(0.08), Colors.transparent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Text('📦', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bundle.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E))),
                Text('${bundle.totalItems} items · ${bundle.items.map((i) => i.restaurantName).toSet().length} restaurant(s)',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6E6E73))),
              ]),
            ),
            // ── Edit button ──────────────────────────
            GestureDetector(
              onTap: () => _showEditBundleSheet(bundle),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_rounded,
                    color: _purple, size: 18),
              ),
            ),
            // ── Delete button ────────────────────────
            GestureDetector(
              onTap: () => _deleteBundle(bundle.id, bundle.name),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: _red, size: 18),
              ),
            ),
          ]),
        ),

        // ✅ Unavailable warning banner
        if (hasUnavailable)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _red.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: _red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Some items are currently unavailable. Ordering is disabled until they become available again.',
                  style: TextStyle(fontSize: 11, color: _red, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),

        // Items preview
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: bundle.items
                .take(3)
                .map((item) {
                  final itemUnavailable = !item.isAvailable;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                        width: 6, height: 6,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: itemUnavailable
                              ? const Color(0xFF9E9E9E)
                              : (item.isVeg ? _green : _red),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Row(children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.name}${item.selectedPortion != null ? ' (${item.selectedPortion!.label})' : ''} × ${item.quantity}',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: itemUnavailable
                                          ? const Color(0xFF9E9E9E)
                                          : const Color(0xFF3C3C3E)),
                                ),
                                // ── Per-item distance + ETA ─────────────
                                Builder(builder: (_) {
                                  final srcItem = _allItems.firstWhere(
                                    (a) => a['restaurantId'] == item.restaurantId && a['name'] == item.name,
                                    orElse: () => <String, dynamic>{},
                                  );
                                  final locMap = srcItem['restaurantLocation'] as Map<String, dynamic>?;
                                  final distKm = _bundleCalcDistanceKm(locMap);
                                  final deliveryStr = (srcItem['restaurantDeliveryTime'] as String?) ?? '30 min';
                                  final eta = _bundleCalcDelivery(deliveryTimeStr: deliveryStr, distanceKm: distKm);
                                  return Row(children: [
                                    const Icon(Icons.access_time_rounded, size: 10, color: Color(0xFF6E6E73)),
                                    const SizedBox(width: 2),
                                    Text(eta, style: const TextStyle(fontSize: 10, color: Color(0xFF6E6E73))),
                                    if (distKm != null) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.delivery_dining_rounded, size: 10, color: Color(0xFF0077B6)),
                                      const SizedBox(width: 2),
                                      Text(_bundleFmtDistance(distKm),
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF0077B6), fontWeight: FontWeight.w600)),
                                    ],
                                  ]);
                                }),
                              ],
                            ),
                          ),
                          if (itemUnavailable) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: !item.isRestaurantActive
                                    ? const Color(0xFF9E9E9E).withOpacity(0.12)
                                    : _red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: !item.isRestaurantActive
                                      ? const Color(0xFF9E9E9E).withOpacity(0.3)
                                      : _red.withOpacity(0.25),
                                ),
                              ),
                              child: Text(
                                !item.isRestaurantActive ? 'Rest. unavailable' : 'Unavailable',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: !item.isRestaurantActive
                                      ? const Color(0xFF9E9E9E)
                                      : _red,
                                ),
                              ),
                            ),
                          ],
                        ]),
                      ),
                      Text(
                          '₹${(item.effectivePrice * item.quantity).toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: itemUnavailable
                                  ? const Color(0xFF9E9E9E)
                                  : const Color(0xFF6E6E73))),
                    ]),
                  );
                })
                .toList(),
          ),
        ),
        if (bundle.items.length > 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text('+${bundle.items.length - 3} more items',
                style: const TextStyle(
                    fontSize: 11,
                    color: _purple,
                    fontWeight: FontWeight.w600)),
          ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(height: 16, color: Color(0xFFF0F0F0)),
        ),

        // Nutrition row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            _bundleNutritionChip('🔥', '${bundle.totalCalories}',
                'kcal', _orange),
            _bundleNutritionChip(
                '💪', '${bundle.totalProtein.toStringAsFixed(0)}g',
                'Protein', _blue),
            _bundleNutritionChip(
                '🌾', '${bundle.totalCarbs.toStringAsFixed(0)}g',
                'Carbs', _green),
            _bundleNutritionChip(
                '🥑', '${bundle.totalFat.toStringAsFixed(0)}g',
                'Fat', _orange.withOpacity(0.8)),
          ]),
        ),

        // ✅ Order button — disabled when bundle has unavailable items or ordering in progress
        Builder(builder: (context) {
          final isOrdering = _orderingBundleIds.contains(bundle.id);
          final isDisabled = hasUnavailable || isOrdering;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDisabled ? const Color(0xFFE5E5EA) : _red,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: isDisabled ? null : () => _orderBundle(bundle),
                child: isOrdering
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            hasUnavailable
                                ? '🚫  Unavailable Items'
                                : '🛒  Order Bundle',
                            style: TextStyle(
                                color: hasUnavailable
                                    ? const Color(0xFF9E9E9E)
                                    : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text('₹${bundle.totalPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: hasUnavailable
                                      ? const Color(0xFF9E9E9E)
                                      : Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                        ]),
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget _bundleNutritionChip(
      String emoji, String value, String label, Color color) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 13)),
      Text(value,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      Text(label,
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6E6E73))),
    ]);
  }

  Widget _imgPlaceholder() => Container(
        color: _purple.withOpacity(0.08),
        child: const Center(
            child: Icon(Icons.fastfood_rounded, color: _purple, size: 26)),
      );

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text('$label: ',
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF6E6E73))),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor)),
      ]),
    );
  }
}