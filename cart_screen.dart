// ─────────────────────────────────────────────
// cart_screen.dart — FoodFeast
// Fixed: full Firestore order write
//        addOrderNutrition (calories + protein + carbs + fat)
//        success dialog shows full nutrition breakdown
//        CartItemTile preserves protein/carbs/fat on +
//        admin orders view gets item-level nutrition
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_provider.dart';
import 'calorie_tracker.dart';
import 'ai_recommendation_engine.dart'; // ✅ AI Recommendation Engine
import 'checkout_screen.dart';
import 'favorites_ratings_service.dart';
import 'reviews_sheet.dart';

class CartScreen extends StatefulWidget {
  final VoidCallback? onBrowseFoodItems;
  const CartScreen({super.key, this.onBrowseFoodItems});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  bool _isPlacingOrder = false;

  // ── Go to Checkout ─────────────────────────────────────────────────────────
  void _goToCheckout(BuildContext context, CartProvider cart) {
    if (cart.items.isEmpty) return;

    final payload = CheckoutPayload(
      items: cart.items.map((item) => {
        'name':           item.name,
        'restaurantId':   item.restaurantId,
        'restaurantName': item.restaurantName,
        'price':          item.effectivePrice,
        'quantity':       item.quantity,
        'imageUrl':       item.imageUrl,
        'isVeg':          item.isVeg,
        'portion':        item.portion?.label ?? '',
        'calories':       item.calories,
        'protein':        item.protein,
        'carbs':          item.carbs,
        'fat':            item.fat,
      }).toList(),
      totalPrice:     cart.totalPrice,
      totalCalories:  cart.totalCalories,
      totalProtein:   cart.totalProtein,
      totalCarbs:     cart.totalCarbs,
      totalFat:       cart.totalFat,
      restaurantName: cart.items.first.restaurantName,
      source:         'cart',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(payload: payload),
      ),
    );
  }

  // ── Legacy _placeOrder (kept for reference, no longer called) ──────────────
  Future<void> _placeOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Please log in to place an order', _red);
      return;
    }

    final cart = CartProvider.instance;
    if (cart.items.isEmpty) return;

    setState(() => _isPlacingOrder = true);

    try {
      // 1. Fetch user name
      final userDoc  = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final userName = (userData['name'] as String?)?.isNotEmpty == true
          ? userData['name'] as String
          : (user.displayName ?? 'Customer');

      // 2. Build item list — carry ALL nutrition fields
      final List<Map<String, dynamic>> orderItems = cart.items.map((item) => {
        'name':           item.name,
        'restaurantId':   item.restaurantId,
        'restaurantName': item.restaurantName,
        'price':          item.effectivePrice,
        'quantity':       item.quantity,
        'imageUrl':       item.imageUrl,
        'isVeg':          item.isVeg,
        'portion':        item.portion?.label ?? '',
        // per-item nutrition (already portion-resolved in CartItem)
        'calories': item.calories,
        'protein':  item.protein,
        'carbs':    item.carbs,
        'fat':      item.fat,
      }).toList();

      // 3. Order-level totals
      final totalPrice    = cart.totalPrice;
      final totalCalories = cart.totalCalories;
      final totalProtein  = cart.totalProtein;
      final totalCarbs    = cart.totalCarbs;
      final totalFat      = cart.totalFat;
      final restaurantName = cart.items.first.restaurantName;

      // 4. Write to Firestore orders collection
      final orderRef = await FirebaseFirestore.instance.collection('orders').add({
        'userId':         user.uid,
        'userName':       userName,
        'restaurantName': restaurantName,
        'items':          orderItems,
        'total':          totalPrice,
        'status':         'pending',
        // Order-level nutrition — used by profile history & stats screen
        'totalCalories':  totalCalories,
        'totalProtein':   totalProtein,
        'totalCarbs':     totalCarbs,
        'totalFat':       totalFat,
        'createdAt':      FieldValue.serverTimestamp(),
      });

      // 5. Update CalorieTracker → stats screen + profile ring + weekly data
      await CalorieTracker.instance.addOrderNutrition(
        calories: totalCalories,
        protein:  totalProtein,
        carbs:    totalCarbs,
        fat:      totalFat,
      );
      // ✅ AI: refresh recommendations after order — collaborative signal updated
      FoodRecommendationEngine.instance.invalidateCache();
      FoodRecommendationEngine.instance.getRecommendations();

      // 6. Clear cart
      cart.clearCart();

      // 7. Show success dialog
      if (mounted) {
        _showSuccessDialog(
          orderId:  orderRef.id,
          calories: totalCalories,
          protein:  totalProtein,
          carbs:    totalCarbs,
          fat:      totalFat,
          total:    totalPrice,
        );
      }
    } catch (e) {
      debugPrint('CartScreen._placeOrder error: $e');
      if (mounted) _snack('Failed to place order. Please try again.', _red);
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  // ── Success Dialog ─────────────────────────────────────────────────────────
  void _showSuccessDialog({
    required String orderId,
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // Tick icon
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: _green.withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: _green, size: 44),
            ),
            const SizedBox(height: 16),
            const Text('Order Placed! 🎉',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
            const SizedBox(height: 4),
            Text('Order #${orderId.substring(0, 8).toUpperCase()}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF6E6E73))),
            const SizedBox(height: 20),

            // Nutrition banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF9F0),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFE0B2))),
              child: Column(children: [
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF9500), size: 15),
                  SizedBox(width: 5),
                  Text("Added to Today's Nutrition Log",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                ]),
                const SizedBox(height: 12),

                // Big calorie number
                if (calories > 0)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$calories',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
                            color: _red)),
                    const SizedBox(width: 5),
                    const Text('kcal',
                        style: TextStyle(fontSize: 15, color: Color(0xFF6E6E73))),
                  ]),

                const SizedBox(height: 12),

                // Macro trio
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _macroCell('💪', 'Protein', '${protein.toStringAsFixed(1)}g',
                      const Color(0xFF007AFF)),
                  _vertDivider(),
                  _macroCell('🌾', 'Carbs', '${carbs.toStringAsFixed(1)}g',
                      const Color(0xFF34C759)),
                  _vertDivider(),
                  _macroCell('🥑', 'Fat', '${fat.toStringAsFixed(1)}g',
                      const Color(0xFFFF9500)),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // Total paid
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Amount Paid',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
                Text('₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E))),
              ]),
            ),
            const SizedBox(height: 20),

            // Button
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: () => Navigator.pop(context),
                child: const Text('Great, Thanks! 🙌',
                    style: TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Small helpers ──────────────────────────────────────────────────────────
  Widget _macroCell(String emoji, String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      Text(label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF6E6E73))),
    ]);
  }

  Widget _vertDivider() =>
      Container(height: 40, width: 1, color: const Color(0xFFE5E5EA));

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating));
  }

  Widget _bannerMacro(String value, String label, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      Text(label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6E6E73))),
    ]);
  }

  Widget _summaryRow(String left, String right, Color lColor, Color rColor,
      {bool boldLeft = false, bool boldRight = false, bool largeRight = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(left,
          style: TextStyle(
              fontSize: 14,
              fontWeight: boldLeft ? FontWeight.w700 : FontWeight.w400,
              color: lColor)),
      Text(right,
          style: TextStyle(
              fontSize: largeRight ? 18 : 14,
              fontWeight: boldRight ? FontWeight.w800 : FontWeight.w600,
              color: rColor)),
    ]);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Your Cart',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
        actions: [
          AnimatedBuilder(
            animation: CartProvider.instance,
            builder: (_, __) => CartProvider.instance.items.isNotEmpty
                ? TextButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        title: const Text('Clear Cart?',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                        content: const Text('Remove all items from cart?',
                            style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73))),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel',
                                  style: TextStyle(color: Color(0xFF6E6E73)))),
                          TextButton(
                              onPressed: () {
                                CartProvider.instance.clearCart();
                                Navigator.pop(context);
                              },
                              child: const Text('Clear',
                                  style: TextStyle(
                                      color: _red, fontWeight: FontWeight.w700))),
                        ],
                      ),
                    ),
                    child: const Text('Clear All',
                        style: TextStyle(color: _red, fontWeight: FontWeight.w600)),
                  )
                : const SizedBox(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: CartProvider.instance,
        builder: (context, _) {
          final cart = CartProvider.instance;

          // ── Empty state ──────────────────────────────────────────────────
          if (cart.items.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 100, height: 100,
                  decoration: const BoxDecoration(
                      color: Color(0xFFF5F5F5), shape: BoxShape.circle),
                  child: const Icon(Icons.shopping_bag_outlined,
                      size: 50, color: Color(0xFFAEAEB2)),
                ),
                const SizedBox(height: 20),
                const Text('Your cart is empty',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E))),
                const SizedBox(height: 8),
                const Text('Search and add food items to get started!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF6E6E73))),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: widget.onBrowseFoodItems,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                        color: _red, borderRadius: BorderRadius.circular(24)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Browse Food Items',
                          style: TextStyle(color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            );
          }

          // ── Filled cart ──────────────────────────────────────────────────
          final grouped       = cart.itemsByRestaurant;
          final restaurantIds = grouped.keys.toList();
          final totalCalories = cart.totalCalories;
          final totalProtein  = cart.totalProtein;
          final totalCarbs    = cart.totalCarbs;
          final totalFat      = cart.totalFat;

          return Column(children: [

            // Nutrition banner
            if (totalCalories > 0 || totalProtein > 0)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                    color: _red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _red.withOpacity(0.18))),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: _red, size: 16),
                    const SizedBox(width: 6),
                    Text('$totalCalories kcal in cart',
                        style: const TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w700, color: _red)),
                    const Spacer(),
                    AnimatedBuilder(
                      animation: CalorieTracker.instance,
                      builder: (_, __) {
                        final t     = CalorieTracker.instance;
                        final after = t.consumedCalories + totalCalories;
                        final over  = after > t.goalCalories;
                        return Text(
                          over
                              ? '⚠️ ${after - t.goalCalories} kcal over goal'
                              : '✅ ${t.goalCalories - after} kcal under goal',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: over ? Colors.orange : _green),
                        );
                      },
                    ),
                  ]),
                  if (totalProtein > 0 || totalCarbs > 0 || totalFat > 0) ...[
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _bannerMacro('💪 ${totalProtein.toStringAsFixed(0)}g',
                          'Protein', const Color(0xFF007AFF)),
                      _bannerMacro('🌾 ${totalCarbs.toStringAsFixed(0)}g',
                          'Carbs', const Color(0xFF34C759)),
                      _bannerMacro('🥑 ${totalFat.toStringAsFixed(0)}g',
                          'Fat', const Color(0xFFFF9500)),
                    ]),
                  ],
                ]),
              ),

            // Item list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: restaurantIds.length,
                itemBuilder: (_, ri) {
                  final restId    = restaurantIds[ri];
                  final restItems = grouped[restId]!;
                  final restName  = restItems.first.restaurantName;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Row(children: [
                        const Icon(Icons.store_rounded, size: 15, color: _red),
                        const SizedBox(width: 6),
                        Text(restName,
                            style: const TextStyle(fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E))),
                      ]),
                    ),
                    ...restItems.map((item) => _CartItemTile(item: item)),
                    if (ri < restaurantIds.length - 1)
                      const Divider(height: 24, color: Color(0xFFE5E5EA)),
                  ]);
                },
              ),
            ),

            // Checkout panel
            // Checkout panel
            Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20,
                  20 + MediaQuery.of(context).padding.bottom + 0),
              decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -4))]),
              child: Column(children: [
                _summaryRow(
                    '${cart.totalItems} item${cart.totalItems > 1 ? 's' : ''}',
                    '₹${cart.totalPrice.toStringAsFixed(0)}',
                    const Color(0xFF6E6E73), const Color(0xFF6E6E73)),
                const SizedBox(height: 4),
                if (totalCalories > 0)
                  _summaryRow('Total calories', '$totalCalories kcal',
                      const Color(0xFF6E6E73), const Color(0xFFFF9500)),
                const SizedBox(height: 4),
                _summaryRow('Delivery', 'FREE',
                    const Color(0xFF6E6E73), _green),
                const Divider(height: 18, color: Color(0xFFE5E5EA)),
                _summaryRow('Total Amount',
                    '₹${cart.totalPrice.toStringAsFixed(0)}',
                    const Color(0xFF1C1C1E), _red,
                    boldLeft: true, boldRight: true, largeRight: true),
                const SizedBox(height: 16),

                // Place Order button
                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0),
                    onPressed: () => _goToCheckout(context, cart),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        const Text('Proceed to Checkout',
                            style: TextStyle(color: Colors.white,
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Text('₹${cart.totalPrice.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.white70,
                                fontSize: 14)),
                      ]),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

// ── Cart Item Tile ──────────────────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final CartItem item;
  const _CartItemTile({required this.item});
  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final cart       = CartProvider.instance;
    final hasPortion = item.portion != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 4))]),
      child: Row(children: [

        // Image
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: item.imageUrl.isNotEmpty
              ? Image.network(item.imageUrl, width: 60, height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder())
              : _placeholder(),
        ),
        const SizedBox(width: 12),

        // Info column
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Veg dot + name
          Row(children: [
            Container(width: 12, height: 12,
                decoration: BoxDecoration(
                    border: Border.all(
                        color: item.isVeg
                            ? const Color(0xFF34C759) : _red, width: 1.5),
                    borderRadius: BorderRadius.circular(2)),
                child: Center(child: Container(width: 5, height: 5,
                    decoration: BoxDecoration(
                        color: item.isVeg ? const Color(0xFF34C759) : _red,
                        shape: BoxShape.circle)))),
            const SizedBox(width: 6),
            Flexible(child: Text(item.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E)),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            // ⭐ Live rating badge
            StreamBuilder<double>(
              stream: FavoritesRatingsService.instance
                  .itemAverageRatingStream(item.restaurantId, item.name),
              builder: (_, snap) {
                final avg = snap.data ?? 0.0;
                if (avg <= 0) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () async {
                    final hasOrdered = await FavoritesRatingsService.instance
                        .hasOrderedFromRestaurant(item.restaurantId);
                    if (!context.mounted) return;
                    ReviewsSheet.showItem(
                      context,
                      restaurantId: item.restaurantId,
                      itemName: item.name,
                      restaurantName: item.restaurantName,
                      hasOrdered: hasOrdered,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFF34C759),
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(avg.toStringAsFixed(1),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      const Icon(Icons.star_rounded, color: Colors.white, size: 10),
                    ]),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 5),

          // Portion badge + price + calories
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
            if (hasPortion)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF007AFF).withOpacity(0.3),
                        width: 1)),
                child: Text(
                    '${item.portion!.shortLabel} ${item.portion!.label}',
                    style: const TextStyle(fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007AFF))),
              ),
            Text('₹${item.effectivePrice.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, color: _red,
                    fontWeight: FontWeight.w700)),
            if (item.calories > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_fire_department_rounded,
                    size: 11, color: Color(0xFFFF9500)),
                Text(' ${item.calories * item.quantity} kcal',
                    style: const TextStyle(fontSize: 11,
                        color: Color(0xFF6E6E73))),
              ]),
          ]),

          // Macro chips
          if (item.protein > 0 || item.carbs > 0 || item.fat > 0) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: [
              if (item.protein > 0)
                _macroChip('P:${item.protein.toStringAsFixed(0)}g',
                    const Color(0xFF007AFF)),
              if (item.carbs > 0)
                _macroChip('C:${item.carbs.toStringAsFixed(0)}g',
                    const Color(0xFF34C759)),
              if (item.fat > 0)
                _macroChip('F:${item.fat.toStringAsFixed(0)}g',
                    const Color(0xFFFF9500)),
            ]),
          ],
        ])),

        // Qty control — ✅ ALL nutrition fields passed when re-adding
        Container(
          decoration: BoxDecoration(
              border: Border.all(color: _red, width: 1.5),
              borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => cart.removeItem(item.name, item.restaurantId,
                  portion: item.portion),
              child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Icon(Icons.remove_rounded, size: 16, color: _red)),
            ),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.quantity}',
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E)))),
            InkWell(
              onTap: () => cart.addItem(CartItem(
                name:           item.name,
                restaurantId:   item.restaurantId,
                restaurantName: item.restaurantName,
                price:          item.price,
                portionPrice:   item.portionPrice,
                imageUrl:       item.imageUrl,
                isVeg:          item.isVeg,
                portion:        item.portion,
                // ✅ All macros preserved — previously lost here
                calories:       item.calories,
                protein:        item.protein,
                carbs:          item.carbs,
                fat:            item.fat,
              )),
              child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Icon(Icons.add_rounded, size: 16, color: _red)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _macroChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
    child: Text(label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _placeholder() => Container(
    width: 60, height: 60,
    decoration: BoxDecoration(
        color: _red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10)),
    child: const Icon(Icons.fastfood_rounded, color: _red, size: 28),
  );
}