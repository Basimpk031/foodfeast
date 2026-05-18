// ─────────────────────────────────────────────
// HOW TO WIRE checkout_screen.dart
// into your existing cart_screen.dart
//           and bundle_screen.dart
// ─────────────────────────────────────────────

// ══════════════════════════════════════════════
// 1.  ADD IMPORT to both files
// ══════════════════════════════════════════════
// import 'checkout_screen.dart';


// ══════════════════════════════════════════════
// 2.  CART SCREEN  — replace _placeOrder()
//     with _goToCheckout() below
// ══════════════════════════════════════════════

// In _CartScreenState, replace the existing _placeOrder method
// and the "Place Order" ElevatedButton call with:

void _goToCheckout() {
  final cart = CartProvider.instance;
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
    totalPrice:    cart.totalPrice,
    totalCalories: cart.totalCalories,
    totalProtein:  cart.totalProtein,
    totalCarbs:    cart.totalCarbs,
    totalFat:      cart.totalFat,
    restaurantName: cart.items.first.restaurantName,
    source: 'cart',
  );

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CheckoutScreen(
        payload: payload,
        onOrderSuccess: () {
          // cart is cleared inside CheckoutScreen; nothing extra needed
        },
      ),
    ),
  );
}

// Then change the "Place Order" button's onPressed from:
//   onPressed: _isPlacingOrder ? null : _placeOrder,
// to:
//   onPressed: _goToCheckout,


// ══════════════════════════════════════════════
// 3.  BUNDLE SCREEN  — replace _orderBundle()
//     with _goToBundleCheckout() below
// ══════════════════════════════════════════════

// Find the method that writes to Firestore when a bundle is ordered,
// and replace the Navigator.push (or inline order logic) with:

void _goToBundleCheckout({
  required List<dynamic> bundleItems,   // List<BundleItem> from bundle screen
  required String bundleId,
  required String bundleName,
}) {
  // Build serialised items list
  final items = (bundleItems as List).map((item) => {
    'name':           item.name,
    'restaurantId':   item.restaurantId,
    'restaurantName': item.restaurantName,
    'price':          item.effectivePrice,
    'quantity':       item.quantity,
    'imageUrl':       item.imageUrl,
    'isVeg':          item.isVeg,
    'portion':        item.selectedPortion?.label ?? '',
    'calories':       item.calories,
    'protein':        item.protein,
    'carbs':          item.carbs,
    'fat':            item.fat,
  }).toList();

  final totalPrice = (bundleItems as List)
      .fold<double>(0, (s, i) => s + i.effectivePrice * i.quantity);
  final totalCalories = (bundleItems as List)
      .fold<int>(0, (s, i) => s + (i.calories as int) * (i.quantity as int));
  final totalProtein = (bundleItems as List)
      .fold<double>(0, (s, i) => s + (i.protein as double) * (i.quantity as int));
  final totalCarbs = (bundleItems as List)
      .fold<double>(0, (s, i) => s + (i.carbs as double) * (i.quantity as int));
  final totalFat = (bundleItems as List)
      .fold<double>(0, (s, i) => s + (i.fat as double) * (i.quantity as int));
  final restaurantName =
      (bundleItems as List).first.restaurantName as String;

  final payload = CheckoutPayload(
    items:          items,
    totalPrice:     totalPrice,
    totalCalories:  totalCalories,
    totalProtein:   totalProtein,
    totalCarbs:     totalCarbs,
    totalFat:       totalFat,
    restaurantName: restaurantName,
    source:         'bundle',
    bundleId:       bundleId,
    bundleName:     bundleName,
  );

  Navigator.push(
    context,   // replace with BuildContext available in the calling widget
    MaterialPageRoute(
      builder: (_) => CheckoutScreen(payload: payload),
    ),
  );
}

// Typical call site (inside bundle screen's order button):
//
//   _goToBundleCheckout(
//     bundleItems: _selectedBundle!.items,
//     bundleId:    _selectedBundle!.id,
//     bundleName:  _selectedBundle!.name,
//   );
