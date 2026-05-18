// ─────────────────────────────────────────────
// home_screen_search_patch.dart — FoodFeast
// Patch file — replace _FoodItemSearchDelegate, _RestaurantCard,
// FoodResultTile in home_screen.dart with these updated versions.
//
// Changes vs previous patch:
//   • Search also matches RESTAURANT NAMES and shows restaurant cards
//     above food item results when the query matches a restaurant name.
//   • Food item search logic is UNCHANGED.
//   • RestaurantSearchResult model added (internal to this file).
//   • _searchFoodItems returns a record: (restaurants, items).
//   • _buildBody renders a "Restaurants" section first, then "Dishes".
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_provider.dart';
import 'portion_sheet.dart';
import 'restaurant_detail_screen.dart';

// ─────────────────────────────────────────────
// Restaurant search result model
// ─────────────────────────────────────────────
class RestaurantSearchResult {
  final String id;
  final String name;
  final String cuisine;
  final String deliveryTime;
  final String imageUrl;
  final double rating;
  final bool isPromoted;
  final bool isActive;

  const RestaurantSearchResult({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.deliveryTime,
    required this.imageUrl,
    required this.rating,
    required this.isPromoted,
    required this.isActive,
  });
}

// ─────────────────────────────────────────────
// FoodSearchResult — unchanged from previous patch
// ─────────────────────────────────────────────
class FoodSearchResult {
  final String itemName;
  final String restaurantId;
  final String restaurantName;
  final double price;
  final bool isVeg;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final String imageUrl;
  final String description;
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;
  final bool isRestaurantActive;
  final bool isItemAvailable;

  const FoodSearchResult({
    required this.itemName,
    required this.restaurantId,
    required this.restaurantName,
    required this.price,
    required this.isVeg,
    required this.calories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    required this.imageUrl,
    required this.description,
    this.portionPrices = const {},
    this.portionNutrition = const {},
    this.isRestaurantActive = true,
    this.isItemAvailable = true,
  });

  bool get canOrder => isRestaurantActive && isItemAvailable;
}

// ─────────────────────────────────────────────
// Combined search result holder
// ─────────────────────────────────────────────
class _SearchData {
  final List<RestaurantSearchResult> restaurants;
  final List<FoodSearchResult> items;
  const _SearchData(this.restaurants, this.items);
}

// ─────────────────────────────────────────────
// Updated Food search delegate
// ─────────────────────────────────────────────
class FoodItemSearchDelegate extends SearchDelegate<String> {
  static const _red = Color(0xFFE23744);
  FoodFilter _filter;
  FoodItemSearchDelegate({FoodFilter initialFilter = const FoodFilter()})
      : _filter = initialFilter;

  @override
  String get searchFieldLabel => 'Search dishes, restaurants...';

  @override
  ThemeData appBarTheme(BuildContext context) =>
      Theme.of(context).copyWith(
        appBarTheme:
            const AppBarTheme(backgroundColor: Colors.white, elevation: 0),
        inputDecorationTheme:
            const InputDecorationTheme(border: InputBorder.none),
      );

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.clear_rounded, color: Color(0xFF6E6E73)),
              onPressed: () => query = ''),
        StatefulBuilder(
          builder: (ctx, setS) =>
              Stack(alignment: Alignment.topRight, children: [
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: Color(0xFF1C1C1E)),
              onPressed: () async {
                await showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => FilterSheet(
                    current: _filter,
                    onApply: (f) {
                      _filter = f;
                      Navigator.pop(ctx);
                      final current = query;
                      query = '';
                      query = current.isEmpty ? ' ' : current;
                      if (current.isEmpty) {
                        Future.microtask(() => query = '');
                      }
                      setS(() {});
                    },
                  ),
                );
              },
            ),
            if (_filter.isActive)
              Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: _red, shape: BoxShape.circle))),
          ]),
        ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
      icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1C1C1E)),
      onPressed: () => close(context, ''));

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.trim().isEmpty && !_filter.isActive) {
      return const Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Text('🍔', style: TextStyle(fontSize: 52)),
            SizedBox(height: 12),
            Text('Search for dishes or restaurants...',
                style: TextStyle(fontSize: 15, color: Color(0xFF6E6E73))),
            SizedBox(height: 6),
            Text('Results come from all restaurants',
                style: TextStyle(fontSize: 13, color: Color(0xFFAEAEB2))),
          ]));
    }

    return FutureBuilder<_SearchData>(
      future: _runSearch(query.trim().toLowerCase()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _red));
        }

        final data = snapshot.data ?? const _SearchData([], []);
        final restaurants = data.restaurants;
        final items = data.items;

        if (restaurants.isEmpty && items.isEmpty) {
          return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                const Text('😕', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('No results for "$query"',
                    style: const TextStyle(
                        fontSize: 15, color: Color(0xFF6E6E73))),
                const SizedBox(height: 6),
                const Text('Try different keywords',
                    style:
                        TextStyle(fontSize: 13, color: Color(0xFFAEAEB2))),
              ]));
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            if (_filter.isActive) _buildActiveFilterBar(),

            // ── Restaurant section ──────────────────
            if (restaurants.isNotEmpty) ...[
              _sectionHeader('🏪 Restaurants', restaurants.length),
              ...restaurants.map((r) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: _RestaurantSearchCard(
                      result: r,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RestaurantDetailScreen(
                            restaurantId: r.id,
                            restaurantName: r.name,
                          ),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 4),
            ],

            // ── Food items section ──────────────────
            if (items.isNotEmpty) ...[
              _sectionHeader('🍽️ Dishes', items.length),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                    child: FoodResultTile(result: item),
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
        child: Row(children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: _red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _red)),
          ),
        ]),
      );

  Widget _buildActiveFilterBar() {
    final chips = <String>[];
    if (_filter.vegOnly) chips.add('🌿 Veg only');
    if (_filter.sort == SortOption.priceLow) chips.add('💰 Price: Low→High');
    if (_filter.sort == SortOption.priceHigh) chips.add('💎 Price: High→Low');
    if (_filter.sort == SortOption.caloriesLow) chips.add('🥗 Cal: Lowest first');
    if (_filter.sort == SortOption.caloriesHigh)
      chips.add('🔥 Cal: Highest first');
    if (_filter.maxCalories != null) chips.add('≤ ${_filter.maxCalories} kcal');
    return Container(
      height: 40,
      color: const Color(0xFFF7F7F7),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: chips
            .map((c) => Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: _red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _red.withOpacity(0.3))),
                  child: Text(c,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _red,
                          fontWeight: FontWeight.w600)),
                ))
            .toList(),
      ),
    );
  }

  // ── Main search — queries restaurants + food items in parallel ──────────
  Future<_SearchData> _runSearch(String q) async {
    final restaurantsSnap =
        await FirebaseFirestore.instance.collection('restaurants').get();

    final List<RestaurantSearchResult> matchedRestaurants = [];
    final List<FoodSearchResult> matchedItems = [];

    for (final restDoc in restaurantsSnap.docs) {
      final restData = restDoc.data();
      final restName = (restData['name'] ?? '').toString();
      final isRestActive = restData['isActive'] ?? true;

      // ── Restaurant name match (does not affect food item search) ──────
      if (q.isNotEmpty &&
          restName.toLowerCase().contains(q)) {
        matchedRestaurants.add(RestaurantSearchResult(
          id: restDoc.id,
          name: restName,
          cuisine: restData['cuisine'] ?? '',
          deliveryTime: restData['deliveryTime'] ?? '30–40 min',
          imageUrl: restData['imageUrl'] ?? '',
          rating: (restData['rating'] ?? 0.0).toDouble(),
          isPromoted: restData['isPromoted'] ?? false,
          isActive: isRestActive,
        ));
      }

      // ── Food item search — UNCHANGED logic ──────────────────────────
      final menuSnap = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restDoc.id)
          .collection('menuItems')
          .get();

      for (final itemDoc in menuSnap.docs) {
        final item = itemDoc.data();
        final itemName = (item['name'] ?? '').toString().toLowerCase();
        final description = (item['description'] ?? '').toString().toLowerCase();
        final category = (item['category'] ?? '').toString().toLowerCase();
        final matchesQuery = q.isEmpty ||
            itemName.contains(q) ||
            description.contains(q) ||
            category.contains(q);
        if (!matchesQuery) continue;

        final isVeg = item['isVeg'] ?? false;
        final calories = (item['calories'] ?? 0) as int;
        final price = (item['price'] ?? 0).toDouble();
        final protein = (item['protein'] ?? 0).toDouble();
        final carbs = (item['carbs'] ?? 0).toDouble();
        final fat = (item['fat'] ?? 0).toDouble();
        final isItemAvailable = item['isAvailable'] ?? true;

        if (_filter.vegOnly && !isVeg) continue;
        if (_filter.maxCalories != null && calories > _filter.maxCalories!)
          continue;

        final Map<String, double> portionPrices = {};
        final qp = item['quarterPrice'];
        final hp = item['halfPrice'];
        final fp = item['fullPrice'];
        if (qp != null && (qp as num) > 0)
          portionPrices['quarter'] = (qp as num).toDouble();
        if (hp != null && (hp as num) > 0)
          portionPrices['half'] = (hp as num).toDouble();
        if (fp != null && (fp as num) > 0)
          portionPrices['full'] = (fp as num).toDouble();

        final Map<String, PortionNutrition> portionNutrition = {};
        if (portionPrices.isNotEmpty) {
          portionNutrition['quarter'] = PortionNutrition(
              calories: (item['quarterCalories'] ?? 0) as int,
              protein: (item['quarterProtein'] ?? 0).toDouble(),
              carbs: (item['quarterCarbs'] ?? 0).toDouble(),
              fat: (item['quarterFat'] ?? 0).toDouble());
          portionNutrition['half'] = PortionNutrition(
              calories: (item['halfCalories'] ?? 0) as int,
              protein: (item['halfProtein'] ?? 0).toDouble(),
              carbs: (item['halfCarbs'] ?? 0).toDouble(),
              fat: (item['halfFat'] ?? 0).toDouble());
          portionNutrition['full'] = PortionNutrition(
              calories: (item['fullCalories'] ?? 0) as int,
              protein: (item['fullProtein'] ?? 0).toDouble(),
              carbs: (item['fullCarbs'] ?? 0).toDouble(),
              fat: (item['fullFat'] ?? 0).toDouble());
        }

        matchedItems.add(FoodSearchResult(
          itemName: item['name'] ?? '',
          restaurantId: restDoc.id,
          restaurantName: restName,
          price: price,
          isVeg: isVeg,
          calories: calories,
          protein: protein,
          carbs: carbs,
          fat: fat,
          imageUrl: item['imageUrl'] ?? '',
          description: item['description'] ?? '',
          portionPrices: portionPrices,
          portionNutrition: portionNutrition,
          isRestaurantActive: isRestActive,
          isItemAvailable: isItemAvailable,
        ));
      }
    }

    // Sort food items only (restaurant order is search-rank by name)
    switch (_filter.sort) {
      case SortOption.priceLow:
        matchedItems.sort((a, b) => a.price.compareTo(b.price));
        break;
      case SortOption.priceHigh:
        matchedItems.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortOption.caloriesLow:
        matchedItems.sort((a, b) => a.calories.compareTo(b.calories));
        break;
      case SortOption.caloriesHigh:
        matchedItems.sort((a, b) => b.calories.compareTo(a.calories));
        break;
      case SortOption.none:
        break;
    }

    return _SearchData(matchedRestaurants, matchedItems);
  }
}

// ─────────────────────────────────────────────
// Compact restaurant search card (shown in search results only)
// ─────────────────────────────────────────────
class _RestaurantSearchCard extends StatelessWidget {
  final RestaurantSearchResult result;
  final VoidCallback onTap;
  static const _red = Color(0xFFE23744);

  const _RestaurantSearchCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: result.isActive ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ]),
        child: Row(children: [
          // Thumbnail
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(16)),
            child: ColorFiltered(
              colorFilter: result.isActive
                  ? const ColorFilter.mode(
                      Colors.transparent, BlendMode.saturation)
                  : const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0, 0, 0, 1, 0,
                    ]),
              child: SizedBox(
                width: 88,
                height: 80,
                child: result.imageUrl.isNotEmpty
                    ? Image.network(result.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
            ),
          ),

          // Info
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                    child: Text(result.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: result.isActive
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFF9E9E9E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (result.isActive && result.rating > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFF34C759),
                          borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(result.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const Icon(Icons.star_rounded,
                            color: Colors.white, size: 10),
                      ]),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(result.cuisine,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6E6E73)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                if (!result.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: _red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('Currently Unavailable',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _red)),
                  )
                else
                  Row(children: [
                    const Icon(Icons.access_time_rounded,
                        size: 12, color: Color(0xFF6E6E73)),
                    const SizedBox(width: 3),
                    Text(result.deliveryTime,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF6E6E73))),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 11, color: Color(0xFFAEAEB2)),
                    const SizedBox(width: 2),
                    const Text('View menu',
                        style: TextStyle(
                            fontSize: 11,
                            color: _red,
                            fontWeight: FontWeight.w600)),
                  ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: _red.withOpacity(0.08),
        child: const Center(
            child:
                Icon(Icons.restaurant_rounded, size: 32, color: _red)));
}

// ─────────────────────────────────────────────
// Food Result Tile — unchanged from previous patch
// ─────────────────────────────────────────────
class FoodResultTile extends StatelessWidget {
  final FoodSearchResult result;
  static const _red = Color(0xFFE23744);
  const FoodResultTile({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CartProvider.instance,
      builder: (_, __) {
        final cart = CartProvider.instance;
        final qty =
            cart.getQuantity(result.itemName, result.restaurantId);
        final hasPortions = result.portionPrices.isNotEmpty;
        final canOrder = result.canOrder;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 4))
              ]),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              // Image
              Stack(children: [
                ColorFiltered(
                  colorFilter: canOrder
                      ? const ColorFilter.mode(
                          Colors.transparent, BlendMode.saturation)
                      : const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: result.imageUrl.isNotEmpty
                        ? Image.network(result.imageUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder())
                        : _placeholder(),
                  ),
                ),
                if (!canOrder)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12))),
                      child: Text(
                          !result.isRestaurantActive
                              ? 'Restaurant\nUnavailable'
                              : 'Item\nUnavailable',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
              const SizedBox(width: 12),

              // Info
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Row(children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: result.isVeg
                                ? const Color(0xFF34C759)
                                : _red,
                            width: 1.5),
                        borderRadius: BorderRadius.circular(2)),
                    child: Center(
                        child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: result.isVeg
                                    ? const Color(0xFF34C759)
                                    : _red,
                                shape: BoxShape.circle))),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(result.itemName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: canOrder
                                  ? const Color(0xFF1C1C1E)
                                  : const Color(0xFF9E9E9E)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.store_rounded,
                      size: 12, color: Color(0xFF6E6E73)),
                  const SizedBox(width: 3),
                  Flexible(
                      child: Text(result.restaurantName,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6E6E73)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 5),

                if (!canOrder) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: _red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _red.withOpacity(0.3))),
                    child: Text(
                        !result.isRestaurantActive
                            ? 'Restaurant Unavailable'
                            : 'Item Unavailable',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _red)),
                  ),
                ] else ...[
                  hasPortions
                      ? Text(
                          '₹${_minP(result.portionPrices).toStringAsFixed(0)} – ₹${_maxP(result.portionPrices).toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _red))
                      : Text('₹${result.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _red)),
                ],
              ])),

              const SizedBox(width: 8),

              // ADD / disabled button
              if (!canOrder)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('N/A',
                      style: TextStyle(
                          color: Color(0xFF9E9E9E),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                )
              else
                qty == 0
                    ? GestureDetector(
                        onTap: () => _addToCart(cart, context),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                                color: _red,
                                borderRadius: BorderRadius.circular(10)),
                            child: const Text('ADD',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800))))
                    : Container(
                        decoration: BoxDecoration(
                            border: Border.all(color: _red, width: 1.5),
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          InkWell(
                              onTap: () => cart.removeItem(
                                  result.itemName, result.restaurantId),
                              child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 7),
                                  child: Icon(Icons.remove_rounded,
                                      size: 16, color: _red))),
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text('$qty',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1C1C1E)))),
                          InkWell(
                              onTap: () => _addToCart(cart, context),
                              child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 7),
                                  child: Icon(Icons.add_rounded,
                                      size: 16, color: _red))),
                        ])),
            ]),

            // Nutrition chips
            if (canOrder &&
                !hasPortions &&
                (result.calories > 0 || result.protein > 0)) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (result.calories > 0)
                  _chip('🔥', '${result.calories}kcal',
                      const Color(0xFFFF9500)),
                if (result.protein > 0)
                  _chip('💪', '${result.protein.toStringAsFixed(0)}g P',
                      const Color(0xFF007AFF)),
                if (result.carbs > 0)
                  _chip('🌾', '${result.carbs.toStringAsFixed(0)}g C',
                      const Color(0xFF34C759)),
                if (result.fat > 0)
                  _chip(
                      '🥑', '${result.fat.toStringAsFixed(0)}g F', _red),
              ]),
            ],
            if (canOrder && hasPortions) ...[
              const SizedBox(height: 8),
              _portionNutrRow(result.portionNutrition),
            ],
          ]),
        );
      },
    );
  }

  Widget _portionNutrRow(Map<String, PortionNutrition> nutr) {
    const keys = ['quarter', 'half', 'full'];
    const labels = ['¼', '½', 'Full'];
    final valid = <int>[];
    for (int i = 0; i < keys.length; i++) {
      final n = nutr[keys[i]];
      if (n != null && (result.portionPrices[keys[i]] ?? 0) > 0) {
        valid.add(i);
      }
    }
    if (valid.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF9F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE0B2))),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: valid.map((i) {
            final n = nutr[keys[i]]!;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Text(labels[i],
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6E6E73))),
              if (n.calories > 0)
                Text('🔥${n.calories}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFFF9500),
                        fontWeight: FontWeight.w700)),
              if (n.protein > 0)
                Text('P:${n.protein.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF007AFF))),
              if (n.carbs > 0)
                Text('C:${n.carbs.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF34C759))),
              if (n.fat > 0)
                Text('F:${n.fat.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFFE23744))),
            ]);
          }).toList()),
    );
  }

  Widget _chip(String e, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Text('$e $label',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  double _minP(Map<String, double> p) {
    final v = p.values.where((x) => x > 0);
    return v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b);
  }

  double _maxP(Map<String, double> p) {
    final v = p.values.where((x) => x > 0);
    return v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
  }

  void _addToCart(CartProvider cart, BuildContext context) {
    if (!result.canOrder) return;
    if (result.portionPrices.isNotEmpty) {
      PortionSheet.show(
          context: context,
          name: result.itemName,
          restaurantId: result.restaurantId,
          restaurantName: result.restaurantName,
          imageUrl: result.imageUrl,
          isVeg: result.isVeg,
          portionPrices: result.portionPrices,
          portionNutrition: result.portionNutrition,
          cart: cart);
      return;
    }
    cart.addItem(CartItem(
        name: result.itemName,
        restaurantId: result.restaurantId,
        restaurantName: result.restaurantName,
        price: result.price,
        imageUrl: result.imageUrl,
        isVeg: result.isVeg,
        calories: result.calories,
        protein: result.protein,
        carbs: result.carbs,
        fat: result.fat));
  }

  Widget _placeholder() => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
            color: _red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.fastfood_rounded, color: _red, size: 30),
      );
}

// ─────────────────────────────────────────────
// RestaurantCard (home screen list) — unchanged from previous patch
// ─────────────────────────────────────────────
class RestaurantCard extends StatelessWidget {
  final String id, name, cuisine, deliveryTime, imageUrl;
  final double rating;
  final bool isPromoted;
  final bool isActive;
  final VoidCallback onTap;
  static const _red = Color(0xFFE23744);

  const RestaurantCard({
    super.key,
    required this.id,
    required this.name,
    required this.cuisine,
    required this.rating,
    required this.deliveryTime,
    required this.imageUrl,
    required this.isPromoted,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 4))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: ColorFiltered(
                  colorFilter: isActive
                      ? const ColorFilter.mode(
                          Colors.transparent, BlendMode.saturation)
                      : const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),
              ),
            ),
            if (isPromoted)
              Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('Promoted',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6E6E73))))),
            if (isActive)
              Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFF34C759),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(rating.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const Icon(Icons.star_rounded,
                            color: Colors.white, size: 12)
                      ]))),
            if (!isActive)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18))),
                  child: const Center(
                    child: Text('Currently Unavailable',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3)),
                  ),
                ),
              ),
          ]),
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text(name,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFF9E9E9E)))),
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(cuisine,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6E6E73)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                const Icon(Icons.access_time_rounded,
                    size: 14, color: Color(0xFF6E6E73)),
                const SizedBox(width: 4),
                Text(deliveryTime,
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF6E6E73))),
                const Spacer(),
                if (isActive) ...[
                  const Icon(Icons.delivery_dining_rounded,
                      size: 14, color: Color(0xFF34C759)),
                  const SizedBox(width: 4),
                  const Text('Free delivery',
                      style: TextStyle(
                          fontSize: 12.5, color: Color(0xFF34C759))),
                ] else ...[
                  const Icon(Icons.block_rounded,
                      size: 14, color: Color(0xFF9E9E9E)),
                  const SizedBox(width: 4),
                  const Text('Not accepting orders',
                      style: TextStyle(
                          fontSize: 12.5, color: Color(0xFF9E9E9E))),
                ],
              ])),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
        decoration: BoxDecoration(color: _red.withOpacity(0.08)),
        child: const Center(
            child:
                Icon(Icons.restaurant_rounded, size: 60, color: _red)));
}

// ─── Enums / classes used above ─────────────────────────────────────────────
enum SortOption { none, priceLow, priceHigh, caloriesLow, caloriesHigh }

class FoodFilter {
  final SortOption sort;
  final bool vegOnly;
  final int? maxCalories;

  const FoodFilter({
    this.sort = SortOption.none,
    this.vegOnly = false,
    this.maxCalories,
  });

  FoodFilter copyWith(
      {SortOption? sort,
      bool? vegOnly,
      int? maxCalories,
      bool clearMaxCal = false}) {
    return FoodFilter(
      sort: sort ?? this.sort,
      vegOnly: vegOnly ?? this.vegOnly,
      maxCalories:
          clearMaxCal ? null : (maxCalories ?? this.maxCalories),
    );
  }

  bool get isActive =>
      sort != SortOption.none || vegOnly || maxCalories != null;
}

class FilterSheet extends StatefulWidget {
  final FoodFilter current;
  final ValueChanged<FoodFilter> onApply;
  const FilterSheet(
      {super.key, required this.current, required this.onApply});
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late SortOption _sort;
  late bool _vegOnly;
  late int? _maxCalories;
  static const _red = Color(0xFFE23744);

  @override
  void initState() {
    super.initState();
    _sort = widget.current.sort;
    _vegOnly = widget.current.vegOnly;
    _maxCalories = widget.current.maxCalories;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Filter & Sort',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C1E))),
              TextButton(
                  onPressed: () => setState(() {
                        _sort = SortOption.none;
                        _vegOnly = false;
                        _maxCalories = null;
                      }),
                  child: const Text('Reset',
                      style: TextStyle(
                          color: _red, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 16),
            const Text('Sort by Price',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 10),
            Row(children: [
              _SortChip(
                  label: '💰 Low → High',
                  selected: _sort == SortOption.priceLow,
                  onTap: () => setState(() => _sort =
                      _sort == SortOption.priceLow
                          ? SortOption.none
                          : SortOption.priceLow)),
              const SizedBox(width: 10),
              _SortChip(
                  label: '💎 High → Low',
                  selected: _sort == SortOption.priceHigh,
                  onTap: () => setState(() => _sort =
                      _sort == SortOption.priceHigh
                          ? SortOption.none
                          : SortOption.priceHigh)),
            ]),
            const SizedBox(height: 16),
            const Text('Sort by Calories',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 10),
            Row(children: [
              _SortChip(
                  label: '🥗 Lowest first',
                  selected: _sort == SortOption.caloriesLow,
                  onTap: () => setState(() => _sort =
                      _sort == SortOption.caloriesLow
                          ? SortOption.none
                          : SortOption.caloriesLow)),
              const SizedBox(width: 10),
              _SortChip(
                  label: '🔥 Highest first',
                  selected: _sort == SortOption.caloriesHigh,
                  onTap: () => setState(() => _sort =
                      _sort == SortOption.caloriesHigh
                          ? SortOption.none
                          : SortOption.caloriesHigh)),
            ]),
            const SizedBox(height: 16),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Max Calories',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  Text(
                      _maxCalories != null
                          ? '≤ $_maxCalories kcal'
                          : 'Any',
                      style: TextStyle(
                          fontSize: 13,
                          color: _maxCalories != null
                              ? _red
                              : const Color(0xFF6E6E73),
                          fontWeight: FontWeight.w600)),
                ]),
            Slider(
                value: (_maxCalories ?? 1200).toDouble(),
                min: 100,
                max: 1200,
                divisions: 22,
                activeColor: _red,
                inactiveColor: const Color(0xFFE5E5EA),
                onChanged: (v) =>
                    setState(() => _maxCalories = v.round())),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('100 kcal',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF6E6E73))),
                  if (_maxCalories != null)
                    GestureDetector(
                        onTap: () =>
                            setState(() => _maxCalories = null),
                        child: const Text('Clear',
                            style: TextStyle(
                                fontSize: 11,
                                color: _red,
                                fontWeight: FontWeight.w600))),
                  const Text('1200 kcal',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF6E6E73))),
                ]),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _vegOnly = !_vegOnly),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    color: _vegOnly
                        ? const Color(0xFF34C759).withOpacity(0.08)
                        : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _vegOnly
                            ? const Color(0xFF34C759)
                            : const Color(0xFFE5E5EA),
                        width: 1.5)),
                child: Row(children: [
                  Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFF34C759), width: 2),
                          borderRadius: BorderRadius.circular(3)),
                      child: _vegOnly
                          ? Center(
                              child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFF34C759),
                                      shape: BoxShape.circle)))
                          : null),
                  const SizedBox(width: 12),
                  const Text('Veg Only 🌿',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C1E))),
                  const Spacer(),
                  if (_vegOnly)
                    const Text('ON',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF34C759))),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0),
                onPressed: () => widget.onApply(FoodFilter(
                    sort: _sort,
                    vegOnly: _vegOnly,
                    maxCalories: _maxCalories)),
                child: const Text('Apply Filters',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  static const _red = Color(0xFFE23744);
  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
            color: selected ? _red : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? _red : const Color(0xFFE5E5EA),
                width: 1.5)),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF1C1C1E))),
      ),
    );
  }
}