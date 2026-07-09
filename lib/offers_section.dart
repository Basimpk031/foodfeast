// ─────────────────────────────────────────────────────────────────────────────
// offers_section.dart — FoodFeast  (ANIMATED EDITION)
//
// Each coupon type has a unique looping animation:
//   free      → delivery bike dashing right
//   flat      → piggy bank with coin inserting
//   percent   → fire burning / flame pulse
//   flash     → lightning bolt striking
//   welcome   → gift box opening / confetti pop
//   birthday  → birthday cake candle popping
//   (default) → food items bouncing
//
// ── INTEGRATION (unchanged) ──────────────────────────────────────────────────
//  1. import 'offers_section.dart'; in home_screen.dart
//  2. SliverToBoxAdapter(child: const OffersSection())  in _buildHomeContent
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'checkout_screen.dart';
import 'cart_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Theme + animation type
// ─────────────────────────────────────────────────────────────────────────────
enum _AnimType { bike, piggy, fire, lightning, gift, birthday, bounce }

class _OfferTheme {
  final List<Color> gradient;
  final IconData icon;
  final String badgeLabel;
  final _AnimType animType;

  const _OfferTheme({
    required this.gradient,
    required this.icon,
    required this.badgeLabel,
    required this.animType,
  });
}

const Map<String, _OfferTheme> _themes = {
  'welcome': _OfferTheme(
    gradient: [Color(0xFF7B2FBE), Color(0xFFD63AF9)],
    icon: Icons.card_giftcard_rounded,
    badgeLabel: 'WELCOME',
    animType: _AnimType.gift,
  ),
  'birthday': _OfferTheme(
    gradient: [Color(0xFFFF6B6B), Color(0xFFFFD93D)],
    icon: Icons.cake_rounded,
    badgeLabel: 'BIRTHDAY',
    animType: _AnimType.birthday,
  ),
  'percent': _OfferTheme(
    gradient: [Color(0xFFE8321A), Color(0xFFFF8C42)],
    icon: Icons.local_fire_department_rounded,
    badgeLabel: 'HOT DEAL',
    animType: _AnimType.fire,
  ),
  'flat': _OfferTheme(
    gradient: [Color(0xFF00796B), Color(0xFF26C6DA)],
    icon: Icons.savings_rounded,
    badgeLabel: 'FLAT OFF',
    animType: _AnimType.piggy,
  ),
  'flash': _OfferTheme(
    gradient: [Color(0xFF1A237E), Color(0xFF3949AB)],
    icon: Icons.bolt_rounded,
    badgeLabel: 'FLASH',
    animType: _AnimType.lightning,
  ),
  'free': _OfferTheme(
    gradient: [Color(0xFF2E7D32), Color(0xFF43A047)],
    icon: Icons.local_shipping_rounded,
    badgeLabel: 'FREE SHIP',
    animType: _AnimType.bike,
  ),
};

_OfferTheme _themeFor(Map<String, dynamic> data) {
  final visual = (data['visualType'] as String? ?? '').toLowerCase();
  if (_themes.containsKey(visual)) return _themes[visual]!;
  final category = (data['category'] as String? ?? '').toLowerCase();
  if (category == 'welcome' || category == 'first_order') return _themes['welcome']!;
  if (category == 'birthday') return _themes['birthday']!;
  final type = (data['type'] as String? ?? 'percent').toLowerCase();
  return type == 'flat' ? _themes['flat']! : _themes['percent']!;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────
class OffersSection extends StatelessWidget {
  const OffersSection({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('coupons')
          .where('isActive', isEqualTo: true)
          .limit(12)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const _ShimmerRow();
        if (snap.hasError) return const SizedBox.shrink();

        final now  = DateTime.now();
        final docs = (snap.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final expiryTs = data['expiryDate'];
          if (expiryTs != null) {
            final expiry = (expiryTs as Timestamp).toDate();
            if (now.isAfter(expiry)) return false;
          }
          return true;
        }).toList();

        docs.sort((a, b) {
          final aTs = (a.data() as Map<String, dynamic>)['createdAt'];
          final bTs = (b.data() as Map<String, dynamic>)['createdAt'];
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return (bTs as Timestamp).compareTo(aTs as Timestamp);
        });

        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 22, 16, 12),
              child: Text(
                '🎉 Offers for you',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E), letterSpacing: -0.3),
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: _CouponCard(data: data, uid: uid),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coupon card
// ─────────────────────────────────────────────────────────────────────────────
class _CouponCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String? uid;
  const _CouponCard({required this.data, required this.uid});

  @override
  State<_CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends State<_CouponCard>
    with TickerProviderStateMixin {
  // Press scale
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  // Per-type animation controller
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 110));
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));

    final theme = _themeFor(widget.data);
    switch (theme.animType) {
      case _AnimType.bike:
        _animCtrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1400))
          ..repeat();
        break;
      case _AnimType.piggy:
        _animCtrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1800))
          ..repeat();
        break;
      case _AnimType.fire:
        _animCtrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 900))
          ..repeat(reverse: true);
        break;
      case _AnimType.lightning:
        _animCtrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 700))
          ..repeat(reverse: true);
        break;
      case _AnimType.gift:
        _animCtrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 2000))
          ..repeat();
        break;
      case _AnimType.birthday:
        _animCtrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1600))
          ..repeat();
        break;
      case _AnimType.bounce:
        _animCtrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 800))
          ..repeat(reverse: true);
        break;
    }
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  bool get _alreadyUsed {
    final uid = widget.uid;
    if (uid == null) return false;
    final usedBy = List<String>.from(widget.data['usedBy'] as List? ?? []);
    return usedBy.contains(uid);
  }

  String _discountLabel() {
    final type  = (widget.data['type'] as String? ?? 'percent').toLowerCase();
    final value = (widget.data['value'] as num? ?? 0).toDouble();
    return type == 'percent'
        ? '${value.toStringAsFixed(0)}% OFF'
        : '₹${value.toStringAsFixed(0)} OFF';
  }

  String? _expiryText() {
    final ts = widget.data['expiryDate'];
    if (ts == null) return null;
    final expiry = (ts as Timestamp).toDate();
    final diff   = expiry.difference(DateTime.now());
    if (diff.inDays > 1) return 'Expires in ${diff.inDays}d';
    if (diff.inHours > 0) return 'Expires in ${diff.inHours}h';
    return 'Expires soon!';
  }

  String? _minOrderText() {
    final min = (widget.data['minOrder'] as num? ?? 0).toDouble();
    return min > 0 ? 'Min ₹${min.toStringAsFixed(0)}' : null;
  }

  void _goToCheckout(BuildContext context, String code) {
    final cart = CartProvider.instance;
    final payload = CheckoutPayload(
      items: cart.items.map((i) => {
        'name':           i.name,
        'price':          i.effectivePrice,
        'quantity':       i.quantity,
        'calories':       i.calories,
        'protein':        i.protein,
        'carbs':          i.carbs,
        'fat':            i.fat,
        'restaurantId':   i.restaurantId,
        'restaurantName': i.restaurantName,
        'imageUrl':       i.imageUrl,
        'isVeg':          i.isVeg,
        if (i.portion != null) 'portion': i.portion!.name,
      }).toList(),
      totalPrice:     cart.totalPrice,
      totalCalories:  cart.totalCalories,
      totalProtein:   cart.totalProtein,
      totalCarbs:     cart.totalCarbs,
      totalFat:       cart.totalFat,
      restaurantName: cart.items.isNotEmpty ? cart.items.first.restaurantName : '',
      restaurantId:   cart.items.isNotEmpty ? cart.items.first.restaurantId : null,
      source: 'cart',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(payload: payload, initialPromoCode: code),
      ),
    );
  }

  void _showUsedSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.block_rounded,
                color: Color(0xFFFF3B30), size: 32),
          ),
          const SizedBox(height: 16),
          Text(widget.data['code'] ?? '',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900,
                  letterSpacing: 2, color: Color(0xFF1C1C1E))),
          const SizedBox(height: 8),
          const Text('You\'ve already used this coupon.',
              style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73))),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it',
                  style: TextStyle(
                      color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showOfferSheet(BuildContext context) {
    final theme   = _themeFor(widget.data);
    final code    = widget.data['code'] as String? ?? '';
    final desc    = widget.data['description'] as String? ?? '';
    final minText = _minOrderText();
    final expText = _expiryText();
    final isSoon  = expText != null && expText.contains('soon');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: theme.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 18),
              Row(children: [
                Icon(theme.icon, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Text(_discountLabel(),
                    style: const TextStyle(
                        fontSize: 30, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: -0.5)),
              ]),
              const SizedBox(height: 6),
              Text(
                desc.isNotEmpty ? desc : 'Apply this code at checkout',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85)),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(context).padding.bottom + 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.gradient[0].withOpacity(0.3), width: 1.5),
                ),
                child: Row(children: [
                  Icon(Icons.confirmation_number_rounded,
                      size: 20, color: theme.gradient[0]),
                  const SizedBox(width: 10),
                  Text(code,
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900,
                          color: theme.gradient[0], letterSpacing: 2.5)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied!'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                    child: Icon(Icons.copy_rounded, size: 18, color: theme.gradient[0]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (minText != null) _chip(Icons.shopping_bag_outlined, minText),
                if (expText != null)
                  _chip(Icons.schedule_rounded, expText,
                      color: isSoon
                          ? const Color(0xFFFF3B30)
                          : const Color(0xFF6E6E73)),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.gradient[0],
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 18),
                  label: const Text('Go to Checkout — Auto Apply',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  onPressed: () {
                    Navigator.pop(context);
                    _goToCheckout(context, code);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Code copied! Paste it at checkout.'),
                          duration: Duration(seconds: 2)),
                    );
                  },
                  child: const Text('Just copy the code',
                      style: TextStyle(color: Color(0xFF6E6E73))),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label,
      {Color color = const Color(0xFF6E6E73)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme   = _themeFor(widget.data);
    final code    = widget.data['code'] as String? ?? '';
    final expText = _expiryText();
    final used    = _alreadyUsed;

    return GestureDetector(
      onTapDown:   (_) => _pressCtrl.forward(),
      onTapUp:     (_) => _pressCtrl.reverse(),
      onTapCancel: () => _pressCtrl.reverse(),
      onTap: () => used ? _showUsedSheet(context) : _showOfferSheet(context),
      child: ScaleTransition(
        scale: _scale,
        child: SizedBox(
          width: 245,
          child: Stack(
            children: [
              // ── Main card ──────────────────────────────────────────────────
              Container(
                width: 245,
                height: 152,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: used
                        ? [const Color(0xFFBDBDBD), const Color(0xFF9E9E9E)]
                        : theme.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: used ? [] : [
                    BoxShadow(
                      color: theme.gradient[0].withOpacity(0.38),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      // Background decorative circles
                      Positioned(
                        right: -20, top: -20,
                        child: Container(
                          width: 110, height: 110,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.07)),
                        ),
                      ),
                      Positioned(
                        right: 26, bottom: -30,
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.05)),
                        ),
                      ),

                      // Perforation dots (dashed divider)
                      Positioned(
                        left: 72, top: 10, bottom: 10,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(7, (_) => Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.28),
                            ),
                          )),
                        ),
                      ),

                      // ── Left: animated icon area ───────────────────────────
                      Positioned(
                        left: 0, top: 0, bottom: 0, width: 72,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildAnimatedIcon(theme, used),
                            const SizedBox(height: 5),
                            Text(
                              theme.badgeLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white.withOpacity(0.85),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Right: content ─────────────────────────────────────
                      Positioned(
                        left: 86, right: 12, top: 14, bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _discountLabel(),
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                            Text(
                              (widget.data['description'] as String? ?? '').isNotEmpty
                                  ? widget.data['description']
                                  : 'Apply at checkout',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white.withOpacity(0.85),
                                  height: 1.35),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Code badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.4),
                                        width: 0.8),
                                  ),
                                  child: Text(
                                    code,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 1.5),
                                  ),
                                ),
                                if (expText != null) ...[
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    Icon(Icons.schedule_rounded,
                                        size: 9,
                                        color: Colors.white.withOpacity(0.75)),
                                    const SizedBox(width: 3),
                                    Text(expText,
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            color: Colors.white.withOpacity(0.82),
                                            fontWeight: FontWeight.w600)),
                                  ]),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── "Already Used" overlay ─────────────────────────────────────
              if (used)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.38),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '✓ Already Used',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800,
                              color: Color(0xFF6E6E73)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build per-type animated icon ───────────────────────────────────────────
  Widget _buildAnimatedIcon(_OfferTheme theme, bool used) {
    if (used) {
      return Icon(theme.icon, color: Colors.white70, size: 28);
    }

    switch (theme.animType) {
      case _AnimType.bike:
        return _BikeAnimation(ctrl: _animCtrl);
      case _AnimType.piggy:
        return _PiggyAnimation(ctrl: _animCtrl);
      case _AnimType.fire:
        return _FireAnimation(ctrl: _animCtrl);
      case _AnimType.lightning:
        return _LightningAnimation(ctrl: _animCtrl);
      case _AnimType.gift:
        return _GiftAnimation(ctrl: _animCtrl);
      case _AnimType.birthday:
        return _BirthdayAnimation(ctrl: _animCtrl);
      case _AnimType.bounce:
        return _BounceAnimation(ctrl: _animCtrl);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Delivery Bike Dashing (free shipping)
// ─────────────────────────────────────────────────────────────────────────────
class _BikeAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _BikeAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final slide = Tween<double>(begin: -8.0, end: 8.0)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final wobble = Tween<double>(begin: -0.06, end: 0.06)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));

    // Motion blur lines
    final blur1 = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(
            parent: ctrl, curve: const Interval(0.0, 0.5)));
    final blur2 = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(
            parent: ctrl, curve: const Interval(0.3, 0.8)));

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 50, height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Speed lines
              Positioned(
                left: 0, top: 14,
                child: Opacity(
                  opacity: blur1.value * 0.6,
                  child: Container(
                    width: 14, height: 2,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 2, top: 20,
                child: Opacity(
                  opacity: blur2.value * 0.4,
                  child: Container(
                    width: 10, height: 1.5,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
              // Bike icon with slide + wobble
              Transform.translate(
                offset: Offset(slide.value, 0),
                child: Transform.rotate(
                  angle: wobble.value,
                  child: const Icon(Icons.delivery_dining_rounded,
                      color: Colors.white, size: 30),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Piggy Bank with Coin Inserting (flat off)
// ─────────────────────────────────────────────────────────────────────────────
class _PiggyAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _PiggyAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Coin drops from top at 0→0.6 of cycle, then resets
    final coinY = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: -12.0, end: 4.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 60),
      TweenSequenceItem(
          tween: Tween(begin: 4.0, end: 4.0),
          weight: 15),
      TweenSequenceItem(
          tween: Tween(begin: 4.0, end: -12.0),
          weight: 25),
    ]).animate(ctrl);

    final coinOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0)
          .chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 25),
    ]).animate(ctrl);

    // Piggy shake when coin hits
    final piggyShake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.elasticOut)), weight: 40),
    ]).animate(ctrl);

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 40, height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Piggy with shake
              Transform.translate(
                offset: Offset(math.sin(piggyShake.value * math.pi) * 2, 0),
                child: const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Icon(Icons.savings_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
              // Coin falling
              Positioned(
                top: 0,
                child: Transform.translate(
                  offset: Offset(0, coinY.value),
                  child: Opacity(
                    opacity: coinOpacity.value,
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFD700),
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
                      ),
                      child: const Center(
                        child: Text('₹',
                            style: TextStyle(
                                fontSize: 6, fontWeight: FontWeight.w900,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Fire Burning / Flame Pulse (percent off)
// ─────────────────────────────────────────────────────────────────────────────
class _FireAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _FireAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.9, end: 1.18)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final glow  = Tween<double>(begin: 0.3, end: 0.85)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final tilt  = Tween<double>(begin: -0.08, end: 0.08)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 40, height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow ring
              Container(
                width: 36 * scale.value,
                height: 36 * scale.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withOpacity(glow.value * 0.25),
                ),
              ),
              Transform.rotate(
                angle: tilt.value,
                child: Transform.scale(
                  scale: scale.value,
                  child: const Icon(Icons.local_fire_department_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Lightning Strike (flash deal)
// ─────────────────────────────────────────────────────────────────────────────
class _LightningAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _LightningAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Flash: bright → dim → bright rapidly
    final bright = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.2)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 0.2, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.5)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50),
    ]).animate(ctrl);

    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4)
          .chain(CurveTween(curve: Curves.easeOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.9)
          .chain(CurveTween(curve: Curves.easeIn)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 50),
    ]).animate(ctrl);

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 40, height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow halo
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.yellow.withOpacity(bright.value * 0.2),
                ),
              ),
              Transform.scale(
                scale: scale.value,
                child: Opacity(
                  opacity: bright.value.clamp(0.2, 1.0),
                  child: const Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 32),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Gift Box Opening / Confetti Pop (welcome)
// ─────────────────────────────────────────────────────────────────────────────
class _GiftAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _GiftAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Lid lifts then drops back
    final lidY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0)
          .chain(CurveTween(curve: Curves.easeOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: -8.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 0.0)
          .chain(CurveTween(curve: Curves.bounceOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 25),
    ]).animate(ctrl);

    // Confetti particles
    final confettiOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0)
          .chain(CurveTween(curve: Curves.easeIn)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 50),
    ]).animate(ctrl);

    final confettiY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -16.0)
          .chain(CurveTween(curve: Curves.easeOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: -16.0, end: -16.0), weight: 50),
    ]).animate(ctrl);

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 44, height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Gift box base
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(Icons.card_giftcard_rounded,
                    color: Colors.white, size: 28),
              ),
              // Lid lifting (small rectangle)
              Positioned(
                top: 0,
                child: Transform.translate(
                  offset: Offset(0, lidY.value),
                  child: Container(
                    width: 20, height: 7,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              // Confetti: 3 small stars
              ...[
                const Offset(-10, 0),
                const Offset(0, -4),
                const Offset(10, 0),
              ].asMap().entries.map((e) {
                final colors = [Colors.yellowAccent, Colors.pinkAccent, Colors.cyanAccent];
                return Positioned(
                  top: 2,
                  child: Transform.translate(
                    offset: Offset(e.value.dx,
                        confettiY.value + e.value.dy),
                    child: Opacity(
                      opacity: confettiOpacity.value,
                      child: Icon(Icons.star_rounded,
                          color: colors[e.key], size: 8),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Birthday Candle / Confetti Pop (birthday)
// ─────────────────────────────────────────────────────────────────────────────
class _BirthdayAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _BirthdayAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Flame flicker
    final flicker = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.8)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.1)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 40),
    ]).animate(ctrl);

    // Confetti pop particles
    final popProgress = CurvedAnimation(parent: ctrl, curve: Curves.easeOut);
    final popOpacity  = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 40),
    ]).animate(ctrl);

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 44, height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Cake icon
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(Icons.cake_rounded, color: Colors.white, size: 26),
              ),
              // Flame above cake
              Positioned(
                top: 0,
                child: Transform.scale(
                  scale: flicker.value,
                  child: const Icon(Icons.local_fire_department_rounded,
                      color: Colors.orangeAccent, size: 14),
                ),
              ),
              // Pop particles
              ...[
                const Offset(-12, -12),
                const Offset(12, -12),
                const Offset(0, -18),
              ].asMap().entries.map((e) {
                final dist = popProgress.value * 16;
                final angle = (e.key * 2.4) + 0.8;
                final pColors = [Colors.yellowAccent, Colors.pinkAccent, Colors.lightBlueAccent];
                return Positioned(
                  top: 6,
                  child: Transform.translate(
                    offset: Offset(
                      math.cos(angle) * dist,
                      math.sin(angle) * dist - 8,
                    ),
                    child: Opacity(
                      opacity: popOpacity.value,
                      child: Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: pColors[e.key],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Bouncing Food (default / fallback)
// ─────────────────────────────────────────────────────────────────────────────
class _BounceAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _BounceAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final bounce = Tween<double>(begin: 0.0, end: -8.0)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final squash = Tween<double>(begin: 1.0, end: 1.15)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final squeez = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return Transform.translate(
          offset: Offset(0, bounce.value),
          child: Transform.scale(
            scaleX: squash.value,
            scaleY: squeez.value,
            child: const Text('🍔', style: TextStyle(fontSize: 28)),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer skeleton
// ─────────────────────────────────────────────────────────────────────────────
class _ShimmerRow extends StatefulWidget {
  const _ShimmerRow();
  @override
  State<_ShimmerRow> createState() => _ShimmerRowState();
}

class _ShimmerRowState extends State<_ShimmerRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>    _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 22, 16, 12),
        child: Text('🎉 Offers for you',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
      ),
      SizedBox(
        height: 152,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(right: 14),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Container(
                width: 245, height: 152,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color.lerp(const Color(0xFFE0E0E0),
                        const Color(0xFFF5F5F5), _anim.value)!,
                    Color.lerp(const Color(0xFFF5F5F5),
                        const Color(0xFFE0E0E0), _anim.value)!,
                  ]),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}