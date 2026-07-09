// favorites_screen.dart — FoodFeast
import 'package:flutter/material.dart';
import 'favorites_ratings_service.dart';
import 'cart_provider.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);

  @override
  Widget build(BuildContext context) {
    final svc  = FavoritesRatingsService.instance;
    final cart = CartProvider.instance;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('My Favorites',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<FavoriteItem>>(
        stream: svc.favoritesStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _red));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('🤍', style: TextStyle(fontSize: 64)),
                SizedBox(height: 16),
                Text('No favorites yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                SizedBox(height: 8),
                Text('Tap ❤️ on any food item to save it here',
                    style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73))),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (_, i) => _FavCard(item: items[i], cart: cart),
          );
        },
      ),
    );
  }
}

class _FavCard extends StatelessWidget {
  final FavoriteItem item;
  final CartProvider cart;
  const _FavCard({required this.item, required this.cart});

  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cart,
      builder: (_, __) {
        final qty = cart.getQuantity(item.itemName, item.restaurantId);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))]),
          child: Row(children: [
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.imageUrl.isNotEmpty
                    ? Image.network(item.imageUrl, width: 76, height: 76, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
              Positioned(
                top: 4, left: 4,
                child: Container(
                  width: 13, height: 13,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: item.isVeg ? _green : _red, width: 1.5),
                      borderRadius: BorderRadius.circular(3)),
                  child: Center(child: Container(
                      width: 5, height: 5,
                      decoration: BoxDecoration(color: item.isVeg ? _green : _red, shape: BoxShape.circle))),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.itemName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.store_rounded, size: 12, color: Color(0xFF6E6E73)),
                  const SizedBox(width: 4),
                  Flexible(child: Text(item.restaurantName,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('₹${item.price.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _red)),
                  Row(children: [
                    GestureDetector(
                      onTap: () => FavoritesRatingsService.instance.toggleFavorite(item),
                      child: const Icon(Icons.favorite_rounded, color: Colors.red, size: 20),
                    ),
                    const SizedBox(width: 10),
                    qty == 0
                        ? GestureDetector(
                            onTap: () => cart.addItem(CartItem(
                              name: item.itemName, restaurantId: item.restaurantId,
                              restaurantName: item.restaurantName, price: item.price,
                              imageUrl: item.imageUrl, isVeg: item.isVeg,
                              calories: 0, protein: 0, carbs: 0, fat: 0,
                            )),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(10)),
                              child: const Text('ADD', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(border: Border.all(color: _red, width: 1.5), borderRadius: BorderRadius.circular(10)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              GestureDetector(
                                  onTap: () => cart.removeItem(item.itemName, item.restaurantId),
                                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Icon(Icons.remove_rounded, size: 15, color: _red))),
                              Text('$qty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                              GestureDetector(
                                  onTap: () => cart.addItem(CartItem(
                                    name: item.itemName, restaurantId: item.restaurantId,
                                    restaurantName: item.restaurantName, price: item.price,
                                    imageUrl: item.imageUrl, isVeg: item.isVeg,
                                    calories: 0, protein: 0, carbs: 0, fat: 0,
                                  )),
                                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Icon(Icons.add_rounded, size: 15, color: _red))),
                            ]),
                          ),
                  ]),
                ]),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _placeholder() => Container(
        width: 76, height: 76,
        decoration: BoxDecoration(color: _red.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.fastfood_rounded, color: _red, size: 30),
      );
}
