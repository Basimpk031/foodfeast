// ─────────────────────────────────────────────
// restaurant_detail_screen.dart — FoodFeast
// Updated:
//   • Inactive restaurant → grayscale image + overlay banner
//     → blocks add-to-cart / order for ALL items
//   • Inactive food item → "Item Unavailable" badge
//     → blocks add-to-cart for that item
//   • Tap anywhere on item card (not just ADD) → rich detail popup
//     with full image, description, nutrition, portions, rating
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'cart_provider.dart';
import 'portion_sheet.dart';
import 'favorites_ratings_service.dart';
import 'reviews_sheet.dart';
import 'location_service.dart';

/// Parses the restaurant's stored `deliveryTime` string (e.g. "30 min",
/// "25-35 min") to extract an approximate preparation time in minutes.
int _parsePrepMinutes(String deliveryTimeStr) {
  final match = RegExp(r'(\d+)').firstMatch(deliveryTimeStr);
  if (match != null) return int.tryParse(match.group(1)!) ?? 25;
  return 25;
}

class RestaurantDetailScreen extends StatefulWidget {
  final String restaurantId;
  final String restaurantName;
  final String restaurantImageUrl;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantImageUrl,
  });

  @override
  State<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends State<RestaurantDetailScreen> {
  static const _red = Color(0xFF0077B6);
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Veg', 'Non-Veg'];
  final cart = CartProvider.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: StreamBuilder<DocumentSnapshot>(
        // ✅ Listen to restaurant doc to detect isActive changes live
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .snapshots(),
        builder: (context, restSnap) {
          final restData = restSnap.hasData && restSnap.data!.exists
              ? (restSnap.data!.data() as Map<String, dynamic>? ?? {})
              : <String, dynamic>{};
          final isRestActive = restData['isActive'] ?? true;

          return CustomScrollView(
            slivers: [
              // ── App bar with hero image ────────────
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                backgroundColor: _red,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white, size: 18),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                      fit: StackFit.expand,
                      children: [
                    // ✅ Greyscale image when restaurant is inactive
                    ColorFiltered(
                      colorFilter: isRestActive
                          ? const ColorFilter.mode(
                              Colors.transparent, BlendMode.saturation)
                          : const ColorFilter.matrix(<double>[
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0,      0,      0,      1, 0,
                            ]),
                      child: widget.restaurantImageUrl.isNotEmpty
                          ? Image.network(widget.restaurantImageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _gradientPlaceholder())
                          : _gradientPlaceholder(),
                    ),
                    // Dark gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(
                                isRestActive ? 0.6 : 0.75)
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    // ✅ "Restaurant Unavailable" banner over image
                    if (!isRestActive)
                      Positioned(
                        bottom: 60,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.3))),
                            child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Icon(Icons.store_mall_directory_outlined,
                                  color: Colors.white70, size: 18),
                              SizedBox(width: 8),
                              Text('Restaurant Unavailable',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                  title: Text(widget.restaurantName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18)),
                  centerTitle: true,
                ),
              ),

              // ── Restaurant info strip ────────────
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      GestureDetector(
                        onTap: () async {
                          final hasOrdered = await FavoritesRatingsService.instance
                              .hasOrderedFromRestaurant(widget.restaurantId);
                          if (!context.mounted) return;
                          ReviewsSheet.showRestaurant(
                            context,
                            restaurantId: widget.restaurantId,
                            restaurantName: widget.restaurantName,
                            hasOrdered: hasOrdered,
                          );
                        },
                        child: StreamBuilder<double>(
                          stream: FavoritesRatingsService.instance
                              .restaurantAverageRatingStream(widget.restaurantId),
                          builder: (_, snap) {
                            final _sv = snap.data;
                            final avg = (_sv != null && _sv > 0)
                                ? _sv
                                : (restData['rating'] ?? 4.0).toDouble();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF34C759),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(avg.toStringAsFixed(1),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                const Icon(Icons.star_rounded,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 3),
                                const Icon(Icons.chevron_right_rounded,
                                    color: Colors.white70, size: 13),
                              ]),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time_rounded,
                          size: 16, color: Color(0xFF6E6E73)),
                      const SizedBox(width: 4),
                      Builder(builder: (_) {
                        // Compute distance to derive delivery ETA
                        final locMap = restData['location'] as Map<String, dynamic>?;
                        double? distKm;
                        if (locMap != null) {
                          final restLat = (locMap['lat'] as num?)?.toDouble();
                          final restLng = (locMap['lng'] as num?)?.toDouble();
                          if (restLat != null && restLng != null) {
                            final userLoc = LocationService.instance.current;
                            if (userLoc != null) {
                              const R = 6371.0;
                              final dLat = (restLat - userLoc.lat) * (math.pi / 180);
                              final dLng = (restLng - userLoc.lng) * (math.pi / 180);
                              final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
                                  math.cos(userLoc.lat * (math.pi / 180)) *
                                      math.cos(restLat * (math.pi / 180)) *
                                      math.sin(dLng / 2) * math.sin(dLng / 2);
                              distKm = R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
                            }
                          }
                        }
                        final rawDelivery = restData['deliveryTime'] as String? ?? '30 min';
                        final prepMins = _parsePrepMinutes(rawDelivery);
                        String etaLabel;
                        if (distKm != null) {
                          final travelMins = (distKm / 30.0 * 60).ceil();
                          final total = prepMins + travelMins;
                          etaLabel = '${(total - 5).clamp(5, 999)}–${total + 5} min';
                        } else {
                          etaLabel = '~$prepMins min';
                        }
                        return Text(etaLabel,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF6E6E73)));
                      }),
                      const SizedBox(width: 12),
                      const Icon(Icons.delivery_dining_rounded,
                          size: 16, color: Color(0xFF34C759)),
                      const SizedBox(width: 4),
                      const Text('Free delivery',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF34C759))),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        (restData['categories'] as List?)?.join(' • ') ?? '',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF6E6E73))),
                    // ── Location / distance row ─────────────────────
                    Builder(builder: (_) {
                      final locMap = restData['location'] as Map<String, dynamic>?;
                      if (locMap == null) return const SizedBox.shrink();
                      final restLat = (locMap['lat'] as num?)?.toDouble();
                      final restLng = (locMap['lng'] as num?)?.toDouble();
                      final shortName = (locMap['shortName'] as String?) ?? '';
                      final address   = (locMap['address'] as String?) ?? '';
                      // Compute distance if user location is known
                      double? distKm;
                      if (restLat != null && restLng != null) {
                        final userLoc = LocationService.instance.current;
                        if (userLoc != null) {
                          const R = 6371.0;
                          final dLat = (restLat - userLoc.lat) * (math.pi / 180);
                          final dLng = (restLng - userLoc.lng) * (math.pi / 180);
                          final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
                              math.cos(userLoc.lat * (math.pi / 180)) *
                                  math.cos(restLat * (math.pi / 180)) *
                                  math.sin(dLng / 2) * math.sin(dLng / 2);
                          distKm = 6371.0 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
                        }
                      }
                      final distLabel = distKm != null
                          ? (distKm < 1 ? '${(distKm * 1000).round()} m' : '${distKm.toStringAsFixed(1)} km')
                          : null;
                      // Motorcycle travel time for this distance
                      final travelLabel = distKm != null
                          ? '~${(distKm / 30.0 * 60).ceil()} min ride'
                          : null;
                      final displayAddr = shortName.isNotEmpty ? shortName : address;
                      if (displayAddr.isEmpty && distLabel == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0077B6).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF0077B6).withOpacity(0.15)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFF0077B6)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              displayAddr.isNotEmpty ? displayAddr : '',
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1C1C1E), fontWeight: FontWeight.w500),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            )),
                            if (distLabel != null) ...[
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0077B6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(distLabel!,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  if (travelLabel != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(travelLabel,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF6E6E73),
                                              fontWeight: FontWeight.w500)),
                                    ),
                                ],
                              ),
                            ],
                          ]),
                        ),
                      );
                    }),
                    // ✅ Inline unavailable notice
                    if (!isRestActive) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: _red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _red.withOpacity(0.25))),
                        child: const Row(children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: _red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                'This restaurant is currently unavailable. '
                                'You cannot order from here right now.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _red,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ),

              // ── Menu header + filter pills ───────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Menu',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1C1E))),
                      Row(
                          children: _filters.map((f) {
                        final isSelected = _selectedFilter == f;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedFilter = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? _red : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: isSelected
                                      ? _red
                                      : const Color(0xFFE5E5EA)),
                            ),
                            child: Text(f,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF6E6E73))),
                          ),
                        );
                      }).toList()),
                    ],
                  ),
                ),
              ),

              // ── Menu items ───────────────────────
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('restaurants')
                    .doc(widget.restaurantId)
                    .collection('menuItems')
                    .orderBy('name')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                          ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const SliverToBoxAdapter(
                        child: Center(
                            child: Padding(
                                padding: EdgeInsets.all(40),
                                child: CircularProgressIndicator(
                                    color: _red))));
                  }

                  if (!snapshot.hasData ||
                      snapshot.data!.docs.isEmpty) {
                    return const SliverToBoxAdapter(
                        child: Center(
                            child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Column(children: [
                                  Text('🍽️',
                                      style: TextStyle(fontSize: 48)),
                                  SizedBox(height: 12),
                                  Text('No menu items yet',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6E6E73))),
                                ]))));
                  }

                  // ✅ Include ALL items (available & unavailable)
                  // and show unavailable items greyed out
                  var items = snapshot.data!.docs;

                  if (_selectedFilter == 'Veg') {
                    items = items
                        .where((doc) =>
                            (doc.data() as Map)['isVeg'] == true)
                        .toList();
                  } else if (_selectedFilter == 'Non-Veg') {
                    items = items
                        .where((doc) =>
                            (doc.data() as Map)['isVeg'] != true)
                        .toList();
                  }

                  if (items.isEmpty) {
                    return const SliverToBoxAdapter(
                        child: Center(
                            child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                    'No items in this category',
                                    style: TextStyle(
                                        fontSize: 15,
                                        color: Color(0xFF6E6E73))))));
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _MenuItemCard(
                        data: items[index].data()
                            as Map<String, dynamic>,
                        cart: cart,
                        restaurantId: widget.restaurantId,
                        restaurantName: widget.restaurantName,
                        restaurantRating:
                            (restData['rating'] ?? 4.0).toDouble(),
                        // ✅ Pass restaurant active state down
                        isRestaurantActive: isRestActive,
                      ),
                      childCount: items.length,
                    ),
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      // ── View cart bar ────────────────────────
      bottomNavigationBar: AnimatedBuilder(
        animation: cart,
        builder: (context, _) {
          if (cart.totalItems == 0) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -4))
                ]),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  minimumSize: const Size(double.infinity, 54),
                  elevation: 0),
              onPressed: () => Navigator.pop(context, 'go_to_cart'),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      '${cart.totalItems} item${cart.totalItems > 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
                const Text('View Cart',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(
                    '₹${cart.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _gradientPlaceholder() => Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [
              Color(0xFF023E8A),
              Color(0xFF0077B6),
              Color(0xFF00B4D8)
            ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: const Center(
            child: Icon(Icons.restaurant_rounded,
                color: Colors.white54, size: 80)),
      );
}

// ─────────────────────────────────────────────
// Menu Item Card
// ─────────────────────────────────────────────
class _MenuItemCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final CartProvider cart;
  final String restaurantId;
  final String restaurantName;
  final double restaurantRating;
  final bool isRestaurantActive;

  const _MenuItemCard({
    required this.data,
    required this.cart,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantRating,
    required this.isRestaurantActive,
  });

  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final name            = data['name'] ?? '';
    final price           = (data['price'] ?? 0).toDouble();
    final originalPrice   = (data['originalPrice'] ?? 0).toDouble();
    final calories        = (data['calories'] ?? 0) as int;
    final protein         = (data['protein'] ?? 0).toDouble();
    final carbs           = (data['carbs'] ?? 0).toDouble();
    final fat             = (data['fat'] ?? 0).toDouble();
    final imageUrl        = data['imageUrl'] ?? '';
    final description     = data['description'] ?? '';
    final isVeg           = data['isVeg'] ?? false;
    final hasDiscount     = originalPrice > 0 && originalPrice > price;
    final portionsEnabled = data['portionsEnabled'] == true;
    // ✅ Item-level availability
    final isItemAvailable = data['isAvailable'] ?? true;
    // Combined: item is orderable only if both restaurant & item are active
    final canOrder        = isRestaurantActive && isItemAvailable;

    final portionPrices = portionsEnabled
        ? <String, double>{
            'quarter': (data['quarterPrice'] ?? 0.0).toDouble(),
            'half':    (data['halfPrice'] ?? 0.0).toDouble(),
            'full':    (data['fullPrice'] ?? 0.0).toDouble(),
          }
        : <String, double>{};

    final portionNutrition = portionsEnabled
        ? <String, PortionNutrition>{
            'quarter': PortionNutrition(
              calories: (data['quarterCalories'] ?? 0) as int,
              protein:  (data['quarterProtein'] ?? 0).toDouble(),
              carbs:    (data['quarterCarbs'] ?? 0).toDouble(),
              fat:      (data['quarterFat'] ?? 0).toDouble(),
            ),
            'half': PortionNutrition(
              calories: (data['halfCalories'] ?? 0) as int,
              protein:  (data['halfProtein'] ?? 0).toDouble(),
              carbs:    (data['halfCarbs'] ?? 0).toDouble(),
              fat:      (data['halfFat'] ?? 0).toDouble(),
            ),
            'full': PortionNutrition(
              calories: (data['fullCalories'] ?? 0) as int,
              protein:  (data['fullProtein'] ?? 0).toDouble(),
              carbs:    (data['fullCarbs'] ?? 0).toDouble(),
              fat:      (data['fullFat'] ?? 0).toDouble(),
            ),
          }
        : <String, PortionNutrition>{};

    return AnimatedBuilder(
      animation: cart,
      builder: (context, _) {
        final qty = cart.getQuantity(name, restaurantId);
        return GestureDetector(
          // ✅ Tap anywhere on card → detail popup
          onTap: () => _showItemDetailPopup(context,
              name: name,
              price: price,
              originalPrice: originalPrice,
              calories: calories,
              protein: protein,
              carbs: carbs,
              fat: fat,
              imageUrl: imageUrl,
              description: description,
              isVeg: isVeg,
              portionsEnabled: portionsEnabled,
              portionPrices: portionPrices,
              portionNutrition: portionNutrition,
              rating: restaurantRating,
              canOrder: canOrder,
              isItemAvailable: isItemAvailable),
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ]),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // ── Image with badges ──────────────
              Stack(children: [
                ColorFiltered(
                  colorFilter: canOrder
                      ? const ColorFilter.mode(
                          Colors.transparent, BlendMode.saturation)
                      : const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl.isNotEmpty
                        ? Image.network(imageUrl,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _placeholder())
                        : _placeholder(),
                  ),
                ),
                // Veg/Non-Veg dot
                Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                              color: isVeg
                                  ? const Color(0xFF34C759)
                                  : _red,
                              width: 1.5),
                          borderRadius: BorderRadius.circular(3)),
                      child: Center(
                          child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: isVeg
                                      ? const Color(0xFF34C759)
                                      : _red,
                                  shape: BoxShape.circle))),
                    )),
                if (portionsEnabled)
                  Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFF007AFF),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('Portions',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w800)),
                      )),
                // ✅ Unavailable overlay on image
                if (!canOrder)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12))),
                      child: Text(
                          !isRestaurantActive
                              ? 'Unavailable'
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

              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: canOrder
                            ? const Color(0xFF1C1C1E)
                            : const Color(0xFF9E9E9E))),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12,
                          color: canOrder
                              ? const Color(0xFF6E6E73)
                              : const Color(0xFFBDBDBD)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],

                // ✅ Item unavailable chip
                if (!isItemAvailable && isRestaurantActive) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: _red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _red.withOpacity(0.3))),
                    child: const Text('Item Unavailable',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _red)),
                  ),
                ],

                const SizedBox(height: 6),

                // Nutrition chips
                if (!portionsEnabled && calories > 0)
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _macroChip('🔥', '${calories}kcal',
                        const Color(0xFFFF9500)),
                    if (protein > 0)
                      _macroChip('💪',
                          '${protein.toStringAsFixed(0)}g P',
                          const Color(0xFF007AFF)),
                    if (carbs > 0)
                      _macroChip('🌾',
                          '${carbs.toStringAsFixed(0)}g C',
                          const Color(0xFF34C759)),
                    if (fat > 0)
                      _macroChip('🥑',
                          '${fat.toStringAsFixed(0)}g F',
                          const Color(0xFF0077B6)),
                  ]),

                if (portionsEnabled)
                  Row(children: const [
                    Icon(Icons.info_outline_rounded,
                        size: 12, color: Color(0xFF007AFF)),
                    SizedBox(width: 3),
                    Text('See nutrition per portion',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF007AFF))),
                  ]),

                const SizedBox(height: 6),

                Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                  // Price
                  Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                    portionsEnabled
                        ? Text(
                            '₹${_minP(portionPrices).toStringAsFixed(0)} – ₹${_maxP(portionPrices).toStringAsFixed(0)}',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: canOrder
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFF9E9E9E)),
                          )
                        : Text('₹${price.toStringAsFixed(0)}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: canOrder
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFF9E9E9E))),
                    if (!portionsEnabled && hasDiscount)
                      Row(children: [
                        Text(
                            '₹${originalPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFAEAEB2),
                                decoration:
                                    TextDecoration.lineThrough)),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: const Color(0xFFE8F8EF),
                              borderRadius:
                                  BorderRadius.circular(4)),
                          child: Text(
                              '${(((originalPrice - price) / originalPrice) * 100).toStringAsFixed(0)}% OFF',
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF34C759))),
                        ),
                      ]),
                  ]),

                  // ✅ Rating chip + Heart + ADD button
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StreamBuilder<double>(
                        stream: FavoritesRatingsService.instance
                            .itemAverageRatingStream(restaurantId, name),
                        builder: (_, snap) {
                          final avg = snap.data ?? 0.0;
                          if (avg <= 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF34C759),
                                  borderRadius: BorderRadius.circular(7)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.star_rounded,
                                    color: Colors.white, size: 11),
                                const SizedBox(width: 3),
                                Text(avg.toStringAsFixed(1),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          );
                        },
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                      FavoriteHeartButton(
                        restaurantId: restaurantId,
                        restaurantName: restaurantName,
                        itemName: name,
                        imageUrl: imageUrl,
                        isVeg: isVeg,
                        price: price,
                        size: 20,
                      ),
                  const SizedBox(width: 8),
                  // ✅ ADD button — disabled if not orderable
                  if (!canOrder)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE5E5EA),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('Unavailable',
                          style: TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    )
                  else if (portionsEnabled)
                    GestureDetector(
                      onTap: () => PortionSheet.show(
                        context: context,
                        name: name,
                        restaurantId: restaurantId,
                        restaurantName: restaurantName,
                        imageUrl: imageUrl,
                        isVeg: isVeg,
                        portionPrices: portionPrices,
                        portionNutrition: portionNutrition,
                        cart: cart,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: qty > 0 ? _red : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: _red, width: 1.5)),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text('ADD',
                              style: TextStyle(
                                  color: qty > 0
                                      ? Colors.white
                                      : _red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
                          if (qty > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: Colors.white
                                      .withOpacity(0.25),
                                  borderRadius:
                                      BorderRadius.circular(6)),
                              child: Text('$qty',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight:
                                          FontWeight.w700)),
                            ),
                          ],
                        ]),
                      ),
                    )
                  else
                    qty == 0
                        ? GestureDetector(
                            onTap: () => cart.addItem(CartItem(
                              name: name,
                              restaurantId: restaurantId,
                              restaurantName: restaurantName,
                              price: price,
                              imageUrl: imageUrl,
                              isVeg: isVeg,
                              calories: calories,
                              protein: protein,
                              carbs: carbs,
                              fat: fat,
                            )),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                  color: _red,
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              child: const Text('ADD',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5)),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: _red, width: 1.5),
                                borderRadius:
                                    BorderRadius.circular(10)),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              GestureDetector(
                                  onTap: () => cart.removeItem(
                                      name, restaurantId),
                                  child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6),
                                      child: Icon(
                                          Icons.remove_rounded,
                                          size: 16,
                                          color: _red))),
                              Text('$qty',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1C1C1E))),
                              GestureDetector(
                                  onTap: () => cart.addItem(CartItem(
                                    name: name,
                                    restaurantId: restaurantId,
                                    restaurantName: restaurantName,
                                    price: price,
                                    imageUrl: imageUrl,
                                    isVeg: isVeg,
                                    calories: calories,
                                    protein: protein,
                                    carbs: carbs,
                                    fat: fat,
                                  )),
                                  child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6),
                                      child: Icon(Icons.add_rounded,
                                          size: 16,
                                          color: _red))),
                            ]),
                          ),
                      ]), // end heart+ADD Row
                    ], // end Column children
                  ), // end Column
                ]),
              ])),
            ]),
          ),
        );
      },
    );
  }

  // ✅ Rich food item detail popup
  void _showItemDetailPopup(
    BuildContext context, {
    required String name,
    required double price,
    required double originalPrice,
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
    required String imageUrl,
    required String description,
    required bool isVeg,
    required bool portionsEnabled,
    required Map<String, double> portionPrices,
    required Map<String, PortionNutrition> portionNutrition,
    required double rating,
    required bool canOrder,
    required bool isItemAvailable,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemDetailSheet(
        name: name,
        price: price,
        originalPrice: originalPrice,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        imageUrl: imageUrl,
        description: description,
        isVeg: isVeg,
        portionsEnabled: portionsEnabled,
        portionPrices: portionPrices,
        portionNutrition: portionNutrition,
        rating: rating,
        canOrder: canOrder,
        isItemAvailable: isItemAvailable,
        isRestaurantActive: isRestaurantActive,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        cart: cart,
      ),
    );
  }

  Widget _macroChip(String emoji, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text('$emoji $label',
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }

  double _minP(Map<String, double> p) {
    final v = p.values.where((x) => x > 0);
    return v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b);
  }

  double _maxP(Map<String, double> p) {
    final v = p.values.where((x) => x > 0);
    return v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
  }

  Widget _placeholder() => Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
            color: _red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.fastfood_rounded, color: _red, size: 36),
      );
}

// ─────────────────────────────────────────────
// Item Detail Sheet — rich popup
// ─────────────────────────────────────────────
class _ItemDetailSheet extends StatelessWidget {
  final String name;
  final double price, originalPrice;
  final int calories;
  final double protein, carbs, fat;
  final String imageUrl, description;
  final bool isVeg, portionsEnabled;
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;
  final double rating;
  final bool canOrder, isItemAvailable, isRestaurantActive;
  final String restaurantId, restaurantName;
  final CartProvider cart;

  const _ItemDetailSheet({
    required this.name,
    required this.price,
    required this.originalPrice,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.imageUrl,
    required this.description,
    required this.isVeg,
    required this.portionsEnabled,
    required this.portionPrices,
    required this.portionNutrition,
    required this.rating,
    required this.canOrder,
    required this.isItemAvailable,
    required this.isRestaurantActive,
    required this.restaurantId,
    required this.restaurantName,
    required this.cart,
  });

  static const _red   = Color(0xFF0077B6);
  static const _blue  = Color(0xFF007AFF);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    final hasDiscount = originalPrice > 0 && originalPrice > price;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: ctrl,
          padding: EdgeInsets.zero,
          children: [
            // ── Full image ─────────────────────────
            Stack(children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imgPlaceholder())
                      : _imgPlaceholder(),
                ),
              ),
              // Drag handle
              const Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 40,
                    height: 4,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Colors.white54,
                            borderRadius:
                                BorderRadius.all(Radius.circular(2)))),
                  ),
                ),
              ),
              // Close button
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
              // Veg badge
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: isVeg ? _green : _red, width: 1.5),
                          borderRadius: BorderRadius.circular(2)),
                      child: Center(
                          child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                  color: isVeg ? _green : _red,
                                  shape: BoxShape.circle))),
                    ),
                    const SizedBox(width: 4),
                    Text(isVeg ? 'Veg' : 'Non-Veg',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isVeg ? _green : _red)),
                  ]),
                ),
              ),
              // Unavailable overlay on image
              if (!canOrder)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24))),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3))),
                        child: Text(
                            !isRestaurantActive
                                ? 'Restaurant Unavailable'
                                : 'Item Unavailable',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
            ]),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // ── Name + rating ────────────────────
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1C1E))),
                  ),
                  const SizedBox(width: 12),
                  StreamBuilder<double>(
                    stream: FavoritesRatingsService.instance
                        .itemAverageRatingStream(restaurantId, name),
                    builder: (ctx, snap) {
                      final _sv = snap.data;
                      final avg = (_sv != null && _sv > 0) ? _sv : rating;
                      return GestureDetector(
                        onTap: () async {
                          final hasOrdered = await FavoritesRatingsService.instance
                              .hasOrderedFromRestaurant(restaurantId);
                          if (!ctx.mounted) return;
                          ReviewsSheet.showItem(
                            ctx,
                            restaurantId: restaurantId,
                            itemName: name,
                            restaurantName: restaurantName,
                            hasOrdered: hasOrdered,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: _green,
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(avg.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(width: 3),
                            const Icon(Icons.star_rounded,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 3),
                            const Icon(Icons.chevron_right_rounded,
                                color: Colors.white70, size: 14),
                          ]),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 6),

                // ── Price ────────────────────────────
                if (!portionsEnabled) ...[
                  Row(children: [
                    Text('₹${price.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _red)),
                    if (hasDiscount) ...[
                      const SizedBox(width: 8),
                      Text('₹${originalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFFAEAEB2),
                              decoration: TextDecoration.lineThrough)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE8F8EF),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(
                            '${(((originalPrice - price) / originalPrice) * 100).toStringAsFixed(0)}% OFF',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _green)),
                      ),
                    ],
                  ]),
                ],
                const SizedBox(height: 14),

                // ── Description ──────────────────────
                if (description.isNotEmpty) ...[
                  const Text('Description',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 6),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF6E6E73),
                          height: 1.5)),
                  const SizedBox(height: 16),
                ],

                // ── Nutrition info ───────────────────
                if (calories > 0 ||
                    protein > 0 ||
                    carbs > 0 ||
                    fat > 0) ...[
                  const Text('Nutrition Info',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF9F0),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFFFE0B2))),
                    child: Column(children: [
                      if (calories > 0) ...[
                        Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                          const Icon(
                              Icons.local_fire_department_rounded,
                              color: _orng,
                              size: 16),
                          const SizedBox(width: 6),
                          Text('$calories kcal',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: _orng)),
                          const SizedBox(width: 5),
                          const Text('per serving',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6E6E73))),
                        ]),
                        const SizedBox(height: 12),
                      ],
                      Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceAround,
                          children: [
                        if (protein > 0)
                          _nutrPill('💪', 'Protein',
                              '${protein.toStringAsFixed(1)}g', _blue),
                        if (carbs > 0)
                          _nutrPill('🌾', 'Carbs',
                              '${carbs.toStringAsFixed(1)}g', _green),
                        if (fat > 0)
                          _nutrPill('🥑', 'Fat',
                              '${fat.toStringAsFixed(1)}g', _orng),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Portion prices & nutrition ────────
                if (portionsEnabled &&
                    portionPrices.isNotEmpty) ...[
                  const Text('Portion Sizes & Prices',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 10),
                  _PortionDetailTable(
                      portionPrices: portionPrices,
                      portionNutrition: portionNutrition),
                  const SizedBox(height: 16),
                ],

                // ── Add to cart button ───────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            canOrder ? _red : const Color(0xFFE5E5EA),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14)),
                        elevation: 0),
                    onPressed: canOrder
                        ? () {
                            Navigator.pop(context);
                            if (portionsEnabled) {
                              PortionSheet.show(
                                context: context,
                                name: name,
                                restaurantId: restaurantId,
                                restaurantName: restaurantName,
                                imageUrl: imageUrl,
                                isVeg: isVeg,
                                portionPrices: portionPrices,
                                portionNutrition: portionNutrition,
                                cart: cart,
                              );
                            } else {
                              cart.addItem(CartItem(
                                name: name,
                                restaurantId: restaurantId,
                                restaurantName: restaurantName,
                                price: price,
                                imageUrl: imageUrl,
                                isVeg: isVeg,
                                calories: calories,
                                protein: protein,
                                carbs: carbs,
                                fat: fat,
                              ));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text('$name added to cart 🛒'),
                                backgroundColor: _green,
                                behavior: SnackBarBehavior.floating,
                                duration:
                                    const Duration(seconds: 2),
                              ));
                            }
                          }
                        : null,
                    child: Text(
                        !canOrder
                            ? (!isRestaurantActive
                                ? 'Restaurant Unavailable'
                                : 'Item Unavailable')
                            : (portionsEnabled
                                ? 'Choose Portion & Add'
                                : 'Add to Cart — ₹${price.toStringAsFixed(0)}'),
                        style: TextStyle(
                            color: canOrder
                                ? Colors.white
                                : const Color(0xFF9E9E9E),
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nutrPill(
      String emoji, String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color)),
      Text(label,
          style: const TextStyle(
              fontSize: 10.5, color: Color(0xFF6E6E73))),
    ]);
  }

  Widget _imgPlaceholder() => Container(
        color: _red.withOpacity(0.08),
        child: const Center(
            child: Icon(Icons.fastfood_rounded, color: _red, size: 60)),
      );
}

// ─────────────────────────────────────────────
// Portion detail table inside popup
// ─────────────────────────────────────────────
class _PortionDetailTable extends StatelessWidget {
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;

  static const _keys   = ['quarter', 'half', 'full'];
  static const _labels = ['🍗 Quarter', '🍖 Half', '🫕 Full'];
  static const _blue   = Color(0xFF007AFF);
  static const _green  = Color(0xFF34C759);
  static const _orng   = Color(0xFFFF9500);
  static const _red    = Color(0xFF0077B6);

  const _PortionDetailTable(
      {required this.portionPrices, required this.portionNutrition});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E5EA)),
          borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
              color: Color(0xFFF7F7F7),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(13))),
          child: const Row(children: [
            Expanded(
                flex: 2,
                child: Text('Portion',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
            Expanded(
                child: Text('Price',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
            Expanded(
                child: Text('Cal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
            Expanded(
                child: Text('P/C/F',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
          ]),
        ),
        ...List.generate(_keys.length, (i) {
          final key   = _keys[i];
          final p     = portionPrices[key] ?? 0;
          if (p <= 0) return const SizedBox.shrink();
          final nutr  = portionNutrition[key];
          final isLast = i == _keys.length - 1 ||
              (_keys.sublist(i + 1).every(
                  (k) => (portionPrices[k] ?? 0) <= 0));

          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(
                            color: Color(0xFFE5E5EA)))),
            child: Row(children: [
              Expanded(
                  flex: 2,
                  child: Text(_labels[i],
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C1E)))),
              Expanded(
                  child: Text('₹${p.toStringAsFixed(0)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _red))),
              Expanded(
                  child: Text(
                      nutr != null && nutr.calories > 0
                          ? '${nutr.calories}'
                          : '—',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _orng))),
              Expanded(
                  child: nutr != null &&
                          (nutr.protein > 0 ||
                              nutr.carbs > 0 ||
                              nutr.fat > 0)
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                              if (nutr.protein > 0)
                                _macroMini(
                                    'P:${nutr.protein.toStringAsFixed(0)}g',
                                    _blue),
                              if (nutr.carbs > 0)
                                _macroMini(
                                    'C:${nutr.carbs.toStringAsFixed(0)}g',
                                    _green),
                              if (nutr.fat > 0)
                                _macroMini(
                                    'F:${nutr.fat.toStringAsFixed(0)}g',
                                    _orng),
                            ])
                      : const Text('—',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9E9E9E)))),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _macroMini(String label, Color color) => Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color),
      );
}
// ─── Favorite heart button (local copy — also exported from home_screen.dart) ─
class FavoriteHeartButton extends StatelessWidget {
  final String restaurantId;
  final String restaurantName;
  final String itemName;
  final String imageUrl;
  final bool isVeg;
  final double price;
  final double size;

  const FavoriteHeartButton({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.itemName,
    required this.imageUrl,
    required this.isVeg,
    required this.price,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final svc = FavoritesRatingsService.instance;
    return StreamBuilder<bool>(
      stream: svc.isFavoriteStream(restaurantId, itemName),
      builder: (context, snap) {
        final isFav = snap.data ?? false;
        return GestureDetector(
          onTap: () => svc.toggleFavorite(FavoriteItem(
            itemName: itemName,
            restaurantId: restaurantId,
            restaurantName: restaurantName,
            imageUrl: imageUrl,
            isVeg: isVeg,
            price: price,
          )),
          child: Icon(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFav ? Colors.red : const Color(0xFFAEAEB2),
            size: size,
          ),
        );
      },
    );
  }
}