// ─────────────────────────────────────────────
// portion_sheet.dart — FoodFeast
// Updated: passes per-portion nutrition (calories, protein, carbs, fat)
//          displays calorie + macro info on each portion card
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'cart_provider.dart';

class PortionNutrition {
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  const PortionNutrition({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });
}

class PortionSheet {
  static const _red = Color(0xFF0077B6);

  static void show({
    required BuildContext context,
    required String name,
    required String restaurantId,
    required String restaurantName,
    required String imageUrl,
    required bool isVeg,
    required Map<String, double> portionPrices,
    required CartProvider cart,
    // Nutrition per portion
    Map<String, PortionNutrition> portionNutrition = const {},
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PortionBottomSheet(
        name: name,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        imageUrl: imageUrl,
        isVeg: isVeg,
        portionPrices: portionPrices,
        portionNutrition: portionNutrition,
        cart: cart,
      ),
    );
  }
}

class _PortionBottomSheet extends StatefulWidget {
  final String name, restaurantId, restaurantName, imageUrl;
  final bool isVeg;
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;
  final CartProvider cart;

  const _PortionBottomSheet({
    required this.name,
    required this.restaurantId,
    required this.restaurantName,
    required this.imageUrl,
    required this.isVeg,
    required this.portionPrices,
    required this.portionNutrition,
    required this.cart,
  });

  @override
  State<_PortionBottomSheet> createState() => _PortionBottomSheetState();
}

class _PortionBottomSheetState extends State<_PortionBottomSheet> {
  static const _red = Color(0xFF0077B6);
  Portion? _selected;

  final _portionOrder = [Portion.quarter, Portion.half, Portion.full];
  final _portionKeys  = ['quarter', 'half', 'full'];
  final _portionEmojis = ['🍗', '🍖', '🫕'];

  @override
  Widget build(BuildContext context) {
    final selectedNutrition = _selected != null
        ? widget.portionNutrition[_portionKeys[_portionOrder.indexOf(_selected!)]]
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),

        // Title row
        Row(children: [
          if (widget.imageUrl.isNotEmpty)
            ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Image.network(widget.imageUrl, width: 52, height: 52, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _imgPlaceholder()))
          else
            _imgPlaceholder(),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
            const Text('Choose your portion', style: TextStyle(fontSize: 12.5, color: Color(0xFF6E6E73))),
          ])),
        ]),
        const SizedBox(height: 20),

        // Portion cards
        Row(children: List.generate(_portionOrder.length, (i) {
          final portion   = _portionOrder[i];
          final key       = _portionKeys[i];
          final price     = widget.portionPrices[key];
          if (price == null || price <= 0) return const SizedBox.shrink();

          final nutrition = widget.portionNutrition[key];
          final isSelected = _selected == portion;
          final qty = widget.cart.getPortionQuantity(widget.name, widget.restaurantId, portion);

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selected = portion),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                decoration: BoxDecoration(
                  color: isSelected ? _red.withOpacity(0.07) : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? _red : const Color(0xFFE5E5EA),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_portionEmojis[i], style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 5),
                  Text(portion.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isSelected ? _red : const Color(0xFF1C1C1E))),
                  const SizedBox(height: 3),
                  Text('₹${price.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isSelected ? _red : const Color(0xFF6E6E73))),
                  if (nutrition != null && nutrition.calories > 0) ...[
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('🔥 ${nutrition.calories}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFF9500))),
                    ),
                  ],
                  if (nutrition != null && (nutrition.protein > 0 || nutrition.carbs > 0 || nutrition.fat > 0)) ...[
                    const SizedBox(height: 4),
                    _macroMiniRow('P', nutrition.protein, const Color(0xFF007AFF)),
                    _macroMiniRow('C', nutrition.carbs, const Color(0xFF34C759)),
                    _macroMiniRow('F', nutrition.fat, const Color(0xFFFF9500)),
                  ],
                  if (qty > 0) ...[
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(10)),
                      child: Text('$qty in cart', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
            ),
          );
        })),

        // Nutrition summary for selected portion
        if (selectedNutrition != null && _selected != null && selectedNutrition.calories > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9F0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFE0B2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _nutritionPill('🔥 Calories', '${selectedNutrition.calories}', 'kcal', const Color(0xFFFF9500)),
              _nutritionPill('💪 Protein',  '${selectedNutrition.protein.toStringAsFixed(1)}', 'g', const Color(0xFF007AFF)),
              _nutritionPill('🌾 Carbs',    '${selectedNutrition.carbs.toStringAsFixed(1)}', 'g', const Color(0xFF34C759)),
              _nutritionPill('🥑 Fat',      '${selectedNutrition.fat.toStringAsFixed(1)}', 'g', const Color(0xFF0077B6)),
            ]),
          ),
        ],

        const SizedBox(height: 20),

        // Add to cart button
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selected != null ? _red : const Color(0xFFE5E5EA),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: _selected == null ? null : () {
              final idx   = _portionOrder.indexOf(_selected!);
              final key   = _portionKeys[idx];
              final price = widget.portionPrices[key]!;
              final nutr  = widget.portionNutrition[key] ?? const PortionNutrition();

              widget.cart.addItem(CartItem(
                name:           widget.name,
                restaurantId:   widget.restaurantId,
                restaurantName: widget.restaurantName,
                price:          widget.portionPrices['full'] ?? price,
                portionPrice:   price,
                imageUrl:       widget.imageUrl,
                isVeg:          widget.isVeg,
                portion:        _selected,
                calories:       nutr.calories,
                protein:        nutr.protein,
                carbs:          nutr.carbs,
                fat:            nutr.fat,
              ));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${_selected!.label} ${widget.name} added to cart 🛒'),
                backgroundColor: const Color(0xFF34C759),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ));
            },
            child: Text(
              _selected != null
                  ? 'Add ${_selected!.label} to Cart — ₹${widget.portionPrices[_portionKeys[_portionOrder.indexOf(_selected!)]]?.toStringAsFixed(0)}'
                  : 'Select a Portion',
              style: TextStyle(
                color: _selected != null ? Colors.white : const Color(0xFF6E6E73),
                fontSize: 14, fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _macroMiniRow(String label, double value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
      Text('$label:', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(width: 2),
      Text('${value.toStringAsFixed(0)}g', style: TextStyle(fontSize: 9, color: color)),
    ]);
  }

  Widget _nutritionPill(String label, String value, String unit, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      Text(unit, style: const TextStyle(fontSize: 10, color: Color(0xFF6E6E73))),
    ]);
  }

  Widget _imgPlaceholder() => Container(
    width: 52, height: 52,
    decoration: BoxDecoration(color: _red.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
    child: const Icon(Icons.fastfood_rounded, color: _red, size: 22),
  );
}