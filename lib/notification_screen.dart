// ─────────────────────────────────────────────
// notification_screen.dart — FoodFeast
// • Reads notifications from Firestore 'notifications' collection
// • Marks notifications as read per-user in 'notificationReads/{uid}'
// • Unread badge count is exposed via NotificationService
// • Tap a notification → rich detail bottom sheet
// • Coupon/promo notifications: icon replaced by a mini offer card
//   thumbnail that plays the same animation as the offers_section card
// • Order status / delivery notifications: animated mini icon cards
// ─────────────────────────────────────────────
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'help_support_screen.dart';

// ─────────────────────────────────────────────
// NotificationService  (singleton)
// ─────────────────────────────────────────────
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final instance = NotificationService._();

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  void updateCount(int count) {
    if (_unreadCount != count) {
      _unreadCount = count;
      notifyListeners();
    }
  }

  void startListening(String uid) {
    FirebaseFirestore.instance
        .collection('notificationReads')
        .doc(uid)
        .snapshots()
        .listen((_) => _refreshCount(uid));
    FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((_) => _refreshCount(uid));
    _refreshCount(uid);
  }

  Future<void> _refreshCount(String uid) async {
    try {
      final readsSnap = await FirebaseFirestore.instance
          .collection('notificationReads').doc(uid).get();
      final readData = (readsSnap.data() as Map<String, dynamic>?) ?? {};
      final notifSnap = await FirebaseFirestore.instance
          .collection('notifications')
          .orderBy('sentAt', descending: true)
          .limit(50)
          .get();
      final relevant = notifSnap.docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        final target = data['targetUid'] as String?;
        return target == null || target.isEmpty || target == uid;
      });
      final unread = relevant.where((d) => readData[d.id] != true).length;
      updateCount(unread);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────
// Offer visual theme (mirrors offers_section.dart)
// ─────────────────────────────────────────────
enum _OfferAnimType { bike, piggy, fire, lightning, gift, birthday, bounce }

class _OfferVisual {
  final List<Color> gradient;
  final String badgeLabel;
  final _OfferAnimType animType;
  const _OfferVisual({
    required this.gradient,
    required this.badgeLabel,
    required this.animType,
  });
}

const _offerVisuals = <String, _OfferVisual>{
  'welcome':  _OfferVisual(gradient: [Color(0xFF7B2FBE), Color(0xFFD63AF9)], badgeLabel: 'WELCOME',  animType: _OfferAnimType.gift),
  'birthday': _OfferVisual(gradient: [Color(0xFFFF6B6B), Color(0xFFFFD93D)], badgeLabel: 'BIRTHDAY', animType: _OfferAnimType.birthday),
  'percent':  _OfferVisual(gradient: [Color(0xFFE8321A), Color(0xFFFF8C42)], badgeLabel: 'HOT DEAL', animType: _OfferAnimType.fire),
  'flat':     _OfferVisual(gradient: [Color(0xFF00796B), Color(0xFF26C6DA)], badgeLabel: 'FLAT OFF', animType: _OfferAnimType.piggy),
  'flash':    _OfferVisual(gradient: [Color(0xFF1A237E), Color(0xFF3949AB)], badgeLabel: 'FLASH',    animType: _OfferAnimType.lightning),
  'free':     _OfferVisual(gradient: [Color(0xFF2E7D32), Color(0xFF43A047)], badgeLabel: 'FREE SHIP',animType: _OfferAnimType.bike),
};

_OfferVisual _offerVisualFor(String? visualType) =>
    _offerVisuals[(visualType ?? '').toLowerCase()] ??
    const _OfferVisual(
      gradient: [Color(0xFFE85D04), Color(0xFFFF8C42)],
      badgeLabel: 'OFFER',
      animType: _OfferAnimType.bounce,
    );

// ─────────────────────────────────────────────
// _MiniOfferCard — looks like the left panel of
// the offer card in offers_section, 46×56 px
// ─────────────────────────────────────────────
class _MiniOfferCard extends StatefulWidget {
  final String? visualType;
  const _MiniOfferCard({required this.visualType});

  @override
  State<_MiniOfferCard> createState() => _MiniOfferCardState();
}

class _MiniOfferCardState extends State<_MiniOfferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    final visual = _offerVisualFor(widget.visualType);
    switch (visual.animType) {
      case _OfferAnimType.bike:
        _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
        break;
      case _OfferAnimType.piggy:
        _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
        break;
      case _OfferAnimType.fire:
        _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
        break;
      case _OfferAnimType.lightning:
        _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
        break;
      case _OfferAnimType.gift:
        _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
        break;
      case _OfferAnimType.birthday:
        _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
        break;
      case _OfferAnimType.bounce:
        _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
        break;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = _offerVisualFor(widget.visualType);
    return Container(
      width: 46,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: visual.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: visual.gradient[0].withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned(
              right: -8, top: -8,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 4),
                SizedBox(
                  width: 46,
                  child: Center(child: _buildAnim(visual.animType)),
                ),
                const SizedBox(height: 3),
                Text(
                  visual.badgeLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 5.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnim(_OfferAnimType type) {
    switch (type) {
      case _OfferAnimType.bike:      return _BikeAnimation(ctrl: _ctrl);
      case _OfferAnimType.piggy:     return _PiggyAnimation(ctrl: _ctrl);
      case _OfferAnimType.fire:      return _FireAnimation(ctrl: _ctrl);
      case _OfferAnimType.lightning: return _LightningAnimation(ctrl: _ctrl);
      case _OfferAnimType.gift:      return _GiftAnimation(ctrl: _ctrl);
      case _OfferAnimType.birthday:  return _BirthdayAnimation(ctrl: _ctrl);
      case _OfferAnimType.bounce:    return _BounceAnimation(ctrl: _ctrl);
    }
  }
}

// ─────────────────────────────────────────────
// Exact animation classes from offers_section.dart
// ─────────────────────────────────────────────

// 1. Delivery Bike
class _BikeAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _BikeAnimation({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final slide  = Tween<double>(begin: -8.0, end: 8.0).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final wobble = Tween<double>(begin: -0.06, end: 0.06).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final blur1  = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: ctrl, curve: const Interval(0.0, 0.5)));
    final blur2  = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: ctrl, curve: const Interval(0.3, 0.8)));
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 34, height: 26,
        child: Stack(alignment: Alignment.center, children: [
          Positioned(left: 0, top: 10, child: Opacity(opacity: blur1.value * 0.6,
              child: Container(width: 10, height: 2, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))))),
          Positioned(left: 2, top: 15, child: Opacity(opacity: blur2.value * 0.4,
              child: Container(width: 7, height: 1.5, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))))),
          Transform.translate(
            offset: Offset(slide.value * 0.6, 0),
            child: Transform.rotate(angle: wobble.value,
                child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 22)),
          ),
        ]),
      ),
    );
  }
}

// 2. Piggy Bank + Coin
class _PiggyAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _PiggyAnimation({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final coinY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 3.0).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 3.0, end: 3.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 3.0, end: -10.0), weight: 25),
    ]).animate(ctrl);
    final coinOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 25),
    ]).animate(ctrl);
    final piggyShake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 40),
    ]).animate(ctrl);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 28, height: 32,
        child: Stack(alignment: Alignment.center, children: [
          Transform.translate(
            offset: Offset(math.sin(piggyShake.value * math.pi) * 1.5, 0),
            child: const Padding(padding: EdgeInsets.only(top: 8),
                child: Icon(Icons.savings_rounded, color: Colors.white, size: 20)),
          ),
          Positioned(top: 0, child: Transform.translate(
            offset: Offset(0, coinY.value),
            child: Opacity(opacity: coinOpacity.value,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD700),
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 0.8),
                ),
                child: const Center(child: Text('₹', style: TextStyle(fontSize: 4.5, fontWeight: FontWeight.w900, color: Colors.white))),
              ),
            ),
          )),
        ]),
      ),
    );
  }
}

// 3. Fire Flame
class _FireAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _FireAnimation({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.9, end: 1.18).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final glow  = Tween<double>(begin: 0.3, end: 0.85).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final tilt  = Tween<double>(begin: -0.08, end: 0.08).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 28, height: 28,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: 26 * scale.value, height: 26 * scale.value,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange.withOpacity(glow.value * 0.25)),
          ),
          Transform.rotate(angle: tilt.value,
              child: Transform.scale(scale: scale.value,
                  child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 22))),
        ]),
      ),
    );
  }
}

// 4. Lightning Strike
class _LightningAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _LightningAnimation({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final bright = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.2).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.2, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.5).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
    ]).animate(ctrl);
    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.9).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 50),
    ]).animate(ctrl);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 28, height: 28,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: 26, height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.yellow.withOpacity(bright.value * 0.2))),
          Transform.scale(scale: scale.value,
              child: Opacity(opacity: bright.value.clamp(0.2, 1.0),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 26))),
        ]),
      ),
    );
  }
}

// 5. Gift Box + Confetti
class _GiftAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _GiftAnimation({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final lidY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -7.0).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -7.0, end: -7.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: -7.0, end: 0.0).chain(CurveTween(curve: Curves.bounceOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 25),
    ]).animate(ctrl);
    final confettiOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 50),
    ]).animate(ctrl);
    final confettiY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: -12.0), weight: 50),
    ]).animate(ctrl);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 32, height: 34,
        child: Stack(alignment: Alignment.center, children: [
          const Padding(padding: EdgeInsets.only(top: 4),
              child: Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 22)),
          Positioned(top: 0, child: Transform.translate(
            offset: Offset(0, lidY.value),
            child: Container(width: 14, height: 5,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2))),
          )),
          ...[const Offset(-8, 0), const Offset(0, -3), const Offset(8, 0)].asMap().entries.map((e) {
            final colors = [Colors.yellowAccent, Colors.pinkAccent, Colors.cyanAccent];
            return Positioned(top: 2, child: Transform.translate(
              offset: Offset(e.value.dx, confettiY.value + e.value.dy),
              child: Opacity(opacity: confettiOpacity.value,
                  child: Icon(Icons.star_rounded, color: colors[e.key], size: 6)),
            ));
          }),
        ]),
      ),
    );
  }
}

// 6. Birthday Candle
class _BirthdayAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _BirthdayAnimation({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final flicker = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.8).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.1).chain(CurveTween(curve: Curves.easeInOut)), weight: 40),
    ]).animate(ctrl);
    final popProgress = CurvedAnimation(parent: ctrl, curve: Curves.easeOut);
    final popOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 40),
    ]).animate(ctrl);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 32, height: 34,
        child: Stack(alignment: Alignment.center, children: [
          const Padding(padding: EdgeInsets.only(top: 6),
              child: Icon(Icons.cake_rounded, color: Colors.white, size: 22)),
          Positioned(top: 0, child: Transform.scale(scale: flicker.value,
              child: const Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 11))),
          ...[const Offset(-9, -9), const Offset(9, -9), const Offset(0, -14)].asMap().entries.map((e) {
            final dist = popProgress.value * 12;
            final angle = (e.key * 2.4) + 0.8;
            final pColors = [Colors.yellowAccent, Colors.pinkAccent, Colors.lightBlueAccent];
            return Positioned(top: 4, child: Transform.translate(
              offset: Offset(math.cos(angle) * dist, math.sin(angle) * dist - 6),
              child: Opacity(opacity: popOpacity.value,
                  child: Container(width: 5, height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: pColors[e.key]))),
            ));
          }),
        ]),
      ),
    );
  }
}

// 7. Bouncing Food (fallback)
class _BounceAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _BounceAnimation({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final bounce = Tween<double>(begin: 0.0, end: -6.0).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final squash = Tween<double>(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    final squeez = Tween<double>(begin: 1.0, end: 0.88).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, bounce.value),
        child: Transform.scale(scaleX: squash.value, scaleY: squeez.value,
            child: const Text('🍔', style: TextStyle(fontSize: 20))),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 8. Order Status Animation — pulsing checkmark
//    with receipt icon, blue gradient card
// ─────────────────────────────────────────────
class _OrderStatusAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _OrderStatusAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Heartbeat-style pulse on the receipt icon
    final pulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.9).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40), // pause
    ]).animate(ctrl);

    // Checkmark that slides up and fades in, then fades out
    final checkY = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: -3.0).chain(CurveTween(curve: Curves.easeOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -3.0, end: -3.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -3.0, end: -3.0), weight: 40),
    ]).animate(ctrl);

    final checkOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 30),
    ]).animate(ctrl);

    // Ripple ring that expands outward
    final ringScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.4).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.4), weight: 65),
    ]).animate(ctrl);

    final ringOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 65),
    ]).animate(ctrl);

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 30, height: 30,
        child: Stack(alignment: Alignment.center, children: [
          // Ripple ring
          Transform.scale(
            scale: ringScale.value,
            child: Opacity(
              opacity: ringOpacity.value,
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
          // Receipt icon with pulse
          Transform.scale(
            scale: pulse.value,
            child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
          ),
          // Floating checkmark
          Transform.translate(
            offset: Offset(6, checkY.value),
            child: Opacity(
              opacity: checkOpacity.value,
              child: Container(
                width: 11, height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00C853),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 7),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 9. Agent Proximity Animation — bike racing
//    toward a location pin, with ping ripple
// ─────────────────────────────────────────────
class _AgentProximityAnimation extends StatelessWidget {
  final AnimationController ctrl;
  const _AgentProximityAnimation({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    // Bike slides from left toward center-right
    final bikeX = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 4.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: -8.0), weight: 10), // instant reset
      TweenSequenceItem(tween: Tween(begin: -8.0, end: -8.0), weight: 35), // pause before repeat
    ]).animate(ctrl);

    final bikeWobble = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -0.07, end: 0.07).chain(CurveTween(curve: Curves.easeInOut)), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 45),
    ]).animate(ctrl);

    // Speed lines (motion blur streaks)
    final streakOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.7).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 0.7), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 35),
    ]).animate(ctrl);

    // Location pin ping ripple
    final pingScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 0.6), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1.6).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.6, end: 1.6), weight: 25),
    ]).animate(ctrl);

    final pingOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 25),
    ]).animate(ctrl);

    // Pin bounce when bike arrives
    final pinBounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -3.0).chain(CurveTween(curve: Curves.easeOut)), weight: 10),
      TweenSequenceItem(tween: Tween(begin: -3.0, end: 0.0).chain(CurveTween(curve: Curves.bounceOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 25),
    ]).animate(ctrl);

    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => SizedBox(
        width: 36, height: 28,
        child: Stack(alignment: Alignment.center, children: [
          // Speed streak lines
          Positioned(
            left: 0, top: 11,
            child: Opacity(
              opacity: streakOpacity.value * 0.6,
              child: Container(width: 9, height: 1.5,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
            ),
          ),
          Positioned(
            left: 1, top: 15,
            child: Opacity(
              opacity: streakOpacity.value * 0.4,
              child: Container(width: 6, height: 1,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1))),
            ),
          ),
          // Ping ripple around the pin
          Positioned(
            right: 1, top: 0,
            child: Transform.scale(
              scale: pingScale.value,
              child: Opacity(
                opacity: pingOpacity.value,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          // Location pin (right side)
          Positioned(
            right: 3, top: 2,
            child: Transform.translate(
              offset: Offset(0, pinBounce.value),
              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 13),
            ),
          ),
          // Delivery bike (slides left → right)
          Positioned(
            left: 0, top: 5,
            child: Transform.translate(
              offset: Offset(bikeX.value, 0),
              child: Transform.rotate(
                angle: bikeWobble.value,
                child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 19),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _MiniOrderCard — animated card for order_status
// and agent_proximity types (46×56 px, same size
// as _MiniOfferCard)
// ─────────────────────────────────────────────
enum _OrderCardType { orderStatus, agentProximity }

class _MiniOrderCard extends StatefulWidget {
  final _OrderCardType cardType;
  const _MiniOrderCard({required this.cardType});

  @override
  State<_MiniOrderCard> createState() => _MiniOrderCardState();
}

class _MiniOrderCardState extends State<_MiniOrderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    switch (widget.cardType) {
      case _OrderCardType.orderStatus:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1600))
          ..repeat();
        break;
      case _OrderCardType.agentProximity:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1800))
          ..repeat();
        break;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.cardType == _OrderCardType.orderStatus
        ? const [Color(0xFF0055A5), Color(0xFF0099DD)]
        : const [Color(0xFF006B45), Color(0xFF00B07A)];

    final badgeLabel = widget.cardType == _OrderCardType.orderStatus
        ? 'ORDER'
        : 'NEAR YOU';

    final shadow = widget.cardType == _OrderCardType.orderStatus
        ? const Color(0xFF0055A5)
        : const Color(0xFF006B45);

    return Container(
      width: 46,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: shadow.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Background decorative circle
            Positioned(
              right: -8, top: -8,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 4),
                SizedBox(
                  width: 46,
                  child: Center(
                    child: widget.cardType == _OrderCardType.orderStatus
                        ? _OrderStatusAnimation(ctrl: _ctrl)
                        : _AgentProximityAnimation(ctrl: _ctrl),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  badgeLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 5.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _MiniOrderCardHero — larger version for the
// detail sheet hero area (72×88 px)
// ─────────────────────────────────────────────
class _MiniOrderCardHero extends StatefulWidget {
  final _OrderCardType cardType;
  const _MiniOrderCardHero({required this.cardType});

  @override
  State<_MiniOrderCardHero> createState() => _MiniOrderCardHeroState();
}

class _MiniOrderCardHeroState extends State<_MiniOrderCardHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    switch (widget.cardType) {
      case _OrderCardType.orderStatus:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1600))
          ..repeat();
        break;
      case _OrderCardType.agentProximity:
        _ctrl = AnimationController(
            vsync: this, duration: const Duration(milliseconds: 1800))
          ..repeat();
        break;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = widget.cardType == _OrderCardType.orderStatus
        ? const [Color(0xFF0055A5), Color(0xFF0099DD)]
        : const [Color(0xFF006B45), Color(0xFF00B07A)];

    final badgeLabel = widget.cardType == _OrderCardType.orderStatus
        ? 'ORDER UPDATE'
        : 'NEAR YOU';

    final shadow = widget.cardType == _OrderCardType.orderStatus
        ? const Color(0xFF0055A5)
        : const Color(0xFF006B45);

    return Container(
      width: 72,
      height: 88,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: shadow.withOpacity(0.38),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              right: -12, top: -12,
              child: Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                SizedBox(
                  width: 72,
                  child: Center(
                    child: widget.cardType == _OrderCardType.orderStatus
                        ? _OrderStatusAnimation(ctrl: _ctrl)
                        : _AgentProximityAnimation(ctrl: _ctrl),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  badgeLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _NotifStyle — per-type visual config
// ─────────────────────────────────────────────
class _NotifStyle {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String label;
  const _NotifStyle({required this.icon, required this.color, required this.bgColor, required this.label});
}

_NotifStyle _styleFor(String type, {bool isRead = false}) {
  const grey   = Color(0xFF8E8E93);
  const greyBg = Color(0xFFF2F2F7);
  final styles = <String, _NotifStyle>{
    'order_status':    _NotifStyle(icon: Icons.receipt_long_rounded,   color: isRead ? grey : const Color(0xFF0077B6), bgColor: isRead ? greyBg : const Color(0xFFE8F4FB), label: 'Order Update'),
    'agent_proximity': _NotifStyle(icon: Icons.delivery_dining_rounded, color: isRead ? grey : const Color(0xFF00A86B), bgColor: isRead ? greyBg : const Color(0xFFE6F7F1), label: 'Delivery'),
    'admin_reply':     _NotifStyle(icon: Icons.support_agent_rounded,   color: isRead ? grey : const Color(0xFF0077B6), bgColor: isRead ? greyBg : const Color(0xFFE8F4FB), label: 'Support'),
    'coupon':          _NotifStyle(icon: Icons.local_offer_rounded,     color: isRead ? grey : const Color(0xFFCC9000), bgColor: isRead ? greyBg : const Color(0xFFFFF8E1), label: 'Offer'),
    'promo':           _NotifStyle(icon: Icons.celebration_rounded,     color: isRead ? grey : const Color(0xFFE85D04), bgColor: isRead ? greyBg : const Color(0xFFFFF0E8), label: 'Promo'),
    'new_order':       _NotifStyle(icon: Icons.shopping_bag_rounded,    color: isRead ? grey : const Color(0xFF6C63FF), bgColor: isRead ? greyBg : const Color(0xFFF0EEFF), label: 'New Order'),
  };
  return styles[type] ?? _NotifStyle(icon: Icons.campaign_rounded, color: isRead ? grey : const Color(0xFF0077B6), bgColor: isRead ? greyBg : const Color(0xFFE8F4FB), label: 'Notification');
}

// ─────────────────────────────────────────────
// Helper to decide which icon widget to show
// Returns a Widget for the notification list card icon
// ─────────────────────────────────────────────
Widget _buildNotifIcon({
  required String type,
  required bool isRead,
  required _NotifStyle style,
  String? couponVisualType,
}) {
  // Always show animated cards; opacity handles the read/unread visual difference
  if (type == 'coupon' || type == 'promo') {
    return _MiniOfferCard(visualType: couponVisualType);
  }
  if (type == 'order_status') {
    return _MiniOrderCard(cardType: _OrderCardType.orderStatus);
  }
  if (type == 'agent_proximity') {
    return _MiniOrderCard(cardType: _OrderCardType.agentProximity);
  }
  // Other types (admin_reply, new_order, etc.) → plain icon box
  return Container(
    width: 46, height: 46,
    decoration: BoxDecoration(
      color: style.bgColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: style.color.withOpacity(0.2), width: 1),
    ),
    child: Icon(style.icon, size: 22, color: style.color),
  );
}

// Returns hero widget for the detail sheet
Widget _buildNotifHeroIcon({
  required String type,
  required _NotifStyle style,
  String? couponVisualType,
}) {
  if (type == 'coupon' || type == 'promo') {
    return _MiniOfferCardHero(visualType: couponVisualType);
  }
  if (type == 'order_status') {
    return _MiniOrderCardHero(cardType: _OrderCardType.orderStatus);
  }
  if (type == 'agent_proximity') {
    return _MiniOrderCardHero(cardType: _OrderCardType.agentProximity);
  }
  return Container(
    width: 72, height: 72,
    decoration: BoxDecoration(
      color: style.bgColor,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [BoxShadow(color: style.color.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 6))],
    ),
    child: Icon(style.icon, size: 34, color: style.color),
  );
}

// ─────────────────────────────────────────────
// NotificationScreen
// ─────────────────────────────────────────────
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  static const _blue = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFB800);
  late final AnimationController _headerAnim;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  }

  @override
  void dispose() { _headerAnim.dispose(); super.dispose(); }

  Future<void> _markRead(String notifId) async {
    final uid = _uid; if (uid == null) return;
    await FirebaseFirestore.instance.collection('notificationReads').doc(uid)
        .set({notifId: true}, SetOptions(merge: true));
  }

  Future<void> _markAllRead(List<String> ids) async {
    final uid = _uid; if (uid == null) return;
    final Map<String, dynamic> batch = {for (final id in ids) id: true};
    await FirebaseFirestore.instance.collection('notificationReads').doc(uid)
        .set(batch, SetOptions(merge: true));
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _fullDate(DateTime dt) {
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month]} ${dt.day}, ${dt.year}  ·  $h:$m $ampm';
  }

  void _openDetail(BuildContext context, Map<String, dynamic> data, bool isRead) {
    final type          = data['type'] as String? ?? '';
    final style         = _styleFor(type, isRead: false);
    final sentAt        = (data['sentAt'] as Timestamp?)?.toDate();
    final linkedCoupon  = data['linkedCoupon'] as String?;
    final description   = data['description'] as String?;
    final isAdminReply  = type == 'admin_reply';
    final isCouponType  = type == 'coupon' || type == 'promo';
    final isOrderType   = type == 'order_status';
    final isDelivType   = type == 'agent_proximity';
    final couponVisualType = data['couponVisualType'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotifDetailSheet(
        data: data, style: style, sentAt: sentAt,
        linkedCoupon: linkedCoupon, description: description,
        isAdminReply: isAdminReply, isCouponType: isCouponType,
        isOrderType: isOrderType, isDelivType: isDelivType,
        couponVisualType: couponVisualType,
        fullDate: sentAt != null ? _fullDate(sentAt) : '',
        onGoToSupport: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen(initialTab: 5)));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Please log in to view notifications.')));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('notificationReads').doc(uid).snapshots(),
        builder: (context, readSnap) {
          final readData = (readSnap.data?.data() as Map<String, dynamic>?) ?? {};
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('notifications')
                .orderBy('sentAt', descending: true).limit(50).snapshots(),
            builder: (context, notifSnap) {
              if (notifSnap.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator(color: _blue));

              final allDocs = notifSnap.data?.docs ?? [];
              final docs = allDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final target = data['targetUid'] as String?;
                return target == null || target.isEmpty || target == uid;
              }).toList();

              final unread = docs.where((d) => readData[d.id] != true).length;
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => NotificationService.instance.updateCount(unread));

              return CustomScrollView(slivers: [
                // ── Gradient SliverAppBar ──────────────────────────
                SliverAppBar(
                  expandedHeight: 160, pinned: true,
                  backgroundColor: _blue, elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    if (docs.any((d) => readData[d.id] != true))
                      TextButton.icon(
                        onPressed: () => _markAllRead(docs.map((d) => d.id).toList()),
                        icon: const Icon(Icons.done_all_rounded, color: Colors.white70, size: 16),
                        label: const Text('Mark all read', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 4),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.parallax,
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 18),
                    title: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('       Notifications',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: _gold.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Text('$unread new', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ],
                    ]),
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF003E6B), Color(0xFF0077B6), Color(0xFF00B4D8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Large faint bell — top right
                          Positioned(
                            right: -18, top: -18,
                            child: Opacity(
                              opacity: 0.07,
                              child: const Icon(Icons.notifications_rounded, size: 160, color: Colors.white),
                            ),
                          ),
                          // Decorative circles
                          Positioned(
                            left: -30, bottom: -30,
                            child: Container(
                              width: 120, height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 50, bottom: -40,
                            child: Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.04),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 70, top: 28,
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.06),
                              ),
                            ),
                          ),
                          // Bell icon + title row in expanded state
                          Positioned(
                            left: 20, bottom: 54,
                            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 46, height: 46,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                                    ),
                                    child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 26),
                                  ),
                                  if (unread > 0)
                                    Positioned(
                                      right: -6, top: -6,
                                      child: Container(
                                        width: 20, height: 20,
                                        decoration: BoxDecoration(
                                          color: _gold,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFF0077B6), width: 2),
                                          boxShadow: [BoxShadow(color: _gold.withOpacity(0.6), blurRadius: 6)],
                                        ),
                                        child: Center(
                                          child: Text('$unread',
                                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('Notifications',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3)),
                                const SizedBox(height: 3),
                                Text(
                                  unread > 0 ? '$unread unread message${unread > 1 ? 's' : ''}' : 'All caught up!',
                                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w500),
                                ),
                              ]),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Empty state ──
                if (docs.isEmpty)
                  SliverFillRemaining(
                    child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(width: 96, height: 96,
                        decoration: BoxDecoration(color: _blue.withOpacity(0.08), shape: BoxShape.circle),
                        child: const Icon(Icons.notifications_off_outlined, size: 44, color: _blue),
                      ),
                      const SizedBox(height: 20),
                      const Text('All caught up!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                      const SizedBox(height: 6),
                      const Text("No notifications yet.", style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73))),
                    ])),
                  ),

                // ── Notification list ──
                if (docs.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final doc  = docs[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final isRead       = readData[doc.id] == true;
                          final sentAt       = (data['sentAt'] as Timestamp?)?.toDate();
                          final linkedCoupon = data['linkedCoupon'] as String?;
                          final type         = data['type'] as String? ?? '';
                          final isAdminReply = type == 'admin_reply';
                          final isCouponType = type == 'coupon' || type == 'promo';
                          final isOrderType  = type == 'order_status';
                          final isDelivType  = type == 'agent_proximity';
                          final couponVisualType = data['couponVisualType'] as String?;
                          final style        = _styleFor(type, isRead: isRead);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _NotifCard(
                              data: data, isRead: isRead, sentAt: sentAt,
                              linkedCoupon: linkedCoupon, isAdminReply: isAdminReply,
                              style: style, isCouponType: isCouponType,
                              isOrderType: isOrderType, isDelivType: isDelivType,
                              couponVisualType: couponVisualType,
                              timeAgo: sentAt != null ? _timeAgo(sentAt) : '',
                              onTap: () { _markRead(doc.id); _openDetail(context, data, isRead); },
                            ),
                          );
                        },
                        childCount: docs.length,
                      ),
                    ),
                  ),
              ]);
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _NotifCard
// ─────────────────────────────────────────────
class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? sentAt;
  final String? linkedCoupon;
  final bool isAdminReply;
  final _NotifStyle style;
  final String timeAgo;
  final VoidCallback onTap;
  final bool isCouponType;
  final bool isOrderType;
  final bool isDelivType;
  final String? couponVisualType;

  const _NotifCard({
    required this.data, required this.isRead, required this.sentAt,
    required this.linkedCoupon, required this.isAdminReply,
    required this.style, required this.timeAgo, required this.onTap,
    required this.isCouponType, required this.isOrderType,
    required this.isDelivType, required this.couponVisualType,
  });

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : style.bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRead ? const Color(0xFFE5E5EA) : style.color.withOpacity(0.25),
              width: isRead ? 1 : 1.5,
            ),
            boxShadow: [BoxShadow(
              color: isRead ? Colors.black.withOpacity(0.03) : style.color.withOpacity(0.08),
              blurRadius: 12, offset: const Offset(0, 3),
            )],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Icon: animated card OR plain icon ──
            Opacity(
              opacity: isRead ? 0.55 : 1.0,
              child: _buildNotifIcon(
                type: type,
                isRead: isRead,
                style: style,
                couponVisualType: couponVisualType,
              ),
            ),
            const SizedBox(width: 12),

            // ── Content ──
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(data['title'] ?? '',
                      style: TextStyle(fontSize: 14,
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                          color: const Color(0xFF1C1C1E)))),
                  if (!isRead) Container(width: 9, height: 9,
                      margin: const EdgeInsets.only(left: 6, top: 2),
                      decoration: BoxDecoration(color: style.color, shape: BoxShape.circle)),
                ]),
                const SizedBox(height: 4),
                Text(data['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13,
                        color: isRead ? const Color(0xFF8E8E93) : const Color(0xFF3A3A3C),
                        height: 1.45)),
                const SizedBox(height: 8),
                Row(children: [
                  _Chip(label: style.label, color: style.color, bgColor: style.bgColor, icon: style.icon),
                  const SizedBox(width: 6),
                  if (isAdminReply) _Chip(label: 'Tap to view', color: const Color(0xFF0077B6),
                      bgColor: const Color(0xFFE8F4FB), icon: Icons.open_in_new_rounded),
                  if (linkedCoupon != null) ...[
                    if (isAdminReply) const SizedBox(width: 6),
                    _Chip(label: linkedCoupon!, color: const Color(0xFFCC9000),
                        bgColor: const Color(0xFFFFF8E1), icon: Icons.local_offer_rounded),
                  ],
                  const Spacer(),
                  Text(timeAgo, style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _Chip
// ─────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label; final Color color; final Color bgColor; final IconData icon;
  const _Chip({required this.label, required this.color, required this.bgColor, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// _NotifDetailSheet
// ─────────────────────────────────────────────
class _NotifDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final _NotifStyle style;
  final DateTime? sentAt;
  final String? linkedCoupon;
  final String? description;
  final bool isAdminReply;
  final bool isCouponType;
  final bool isOrderType;
  final bool isDelivType;
  final String? couponVisualType;
  final String fullDate;
  final VoidCallback onGoToSupport;

  const _NotifDetailSheet({
    required this.data, required this.style, required this.sentAt,
    required this.linkedCoupon, required this.description,
    required this.isAdminReply, required this.isCouponType,
    required this.isOrderType, required this.isDelivType,
    required this.couponVisualType, required this.fullDate,
    required this.onGoToSupport,
  });

  @override
  Widget build(BuildContext context) {
    final title       = data['title'] as String? ?? '';
    final body        = data['body']  as String? ?? '';
    final orderStatus = data['orderStatus'] as String?;
    final orderId     = data['orderId']     as String?;
    final type        = data['type'] as String? ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.62, minChildSize: 0.4, maxChildSize: 0.92,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Hero icon ──
                Center(child: Column(children: [
                  _buildNotifHeroIcon(
                    type: type,
                    style: style,
                    couponVisualType: couponVisualType,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: style.bgColor, borderRadius: BorderRadius.circular(20)),
                    child: Text(style.label.toUpperCase(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: style.color, letterSpacing: 0.8)),
                  ),
                ])),
                const SizedBox(height: 20),
                Text(title, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E), height: 1.3)),
                const SizedBox(height: 6),
                if (fullDate.isNotEmpty)
                  Center(child: Text(fullDate, style: const TextStyle(fontSize: 12, color: Color(0xFFAEAEB2), fontWeight: FontWeight.w500))),
                const SizedBox(height: 20),
                Container(height: 1, color: const Color(0xFFF2F2F7)),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                  ),
                  child: Text(body, style: const TextStyle(fontSize: 15, color: Color(0xFF1C1C1E), height: 1.6)),
                ),
                const SizedBox(height: 16),
                if (description != null && description!.isNotEmpty) ...[
                  Row(children: [
                    Container(width: 3, height: 18,
                        decoration: BoxDecoration(color: style.color, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 8),
                    const Text('Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3A3A3C))),
                  ]),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [style.bgColor, style.bgColor.withOpacity(0.4)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: style.color.withOpacity(0.15), width: 1),
                    ),
                    child: Text(description!, style: TextStyle(fontSize: 14,
                        color: style.color.withOpacity(isAdminReply ? 0.85 : 0.9), height: 1.65, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 16),
                ],
                if (orderStatus != null) ...[
                  _DetailRow(icon: Icons.local_shipping_rounded, label: 'Status', value: _prettyStatus(orderStatus), color: style.color),
                  const SizedBox(height: 8),
                ],
                if (orderId != null && orderId.isNotEmpty) ...[
                  _DetailRow(icon: Icons.tag_rounded, label: 'Order ID',
                      value: '#${orderId.substring(0, orderId.length.clamp(0, 8)).toUpperCase()}', color: style.color),
                  const SizedBox(height: 8),
                ],
                if (linkedCoupon != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.local_offer_rounded, size: 20, color: Color(0xFFCC9000)),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Coupon Code', style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93), fontWeight: FontWeight.w600)),
                        Text(linkedCoupon!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFCC9000), letterSpacing: 1.2)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                if (isAdminReply) ...[
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: style.color,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: onGoToSupport,
                      icon: const Icon(Icons.help_outline_rounded, size: 18, color: Colors.white),
                      label: const Text('Go to Help & Support',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _prettyStatus(String s) => s.replaceAll('_', ' ').split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
}

// ─────────────────────────────────────────────
// _MiniOfferCardHero — larger version for the
// detail sheet hero area (72×88 px)
// ─────────────────────────────────────────────
class _MiniOfferCardHero extends StatefulWidget {
  final String? visualType;
  const _MiniOfferCardHero({required this.visualType});
  @override
  State<_MiniOfferCardHero> createState() => _MiniOfferCardHeroState();
}

class _MiniOfferCardHeroState extends State<_MiniOfferCardHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    final visual = _offerVisualFor(widget.visualType);
    switch (visual.animType) {
      case _OfferAnimType.bike:      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(); break;
      case _OfferAnimType.piggy:     _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(); break;
      case _OfferAnimType.fire:      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true); break;
      case _OfferAnimType.lightning: _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true); break;
      case _OfferAnimType.gift:      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(); break;
      case _OfferAnimType.birthday:  _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(); break;
      case _OfferAnimType.bounce:    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true); break;
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final visual = _offerVisualFor(widget.visualType);
    return Container(
      width: 72, height: 88,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: visual.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: visual.gradient[0].withOpacity(0.38), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(children: [
          Positioned(right: -12, top: -12,
              child: Container(width: 50, height: 50,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08)))),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(height: 6),
            SizedBox(width: 72, child: Center(child: _buildAnim(visual.animType))),
            const SizedBox(height: 6),
            Text(visual.badgeLabel, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900,
                    color: Colors.white.withOpacity(0.9), letterSpacing: 0.7)),
            const SizedBox(height: 6),
          ]),
        ]),
      ),
    );
  }

  Widget _buildAnim(_OfferAnimType type) {
    switch (type) {
      case _OfferAnimType.bike:      return _BikeAnimation(ctrl: _ctrl);
      case _OfferAnimType.piggy:     return _PiggyAnimation(ctrl: _ctrl);
      case _OfferAnimType.fire:      return _FireAnimation(ctrl: _ctrl);
      case _OfferAnimType.lightning: return _LightningAnimation(ctrl: _ctrl);
      case _OfferAnimType.gift:      return _GiftAnimation(ctrl: _ctrl);
      case _OfferAnimType.birthday:  return _BirthdayAnimation(ctrl: _ctrl);
      case _OfferAnimType.bounce:    return _BounceAnimation(ctrl: _ctrl);
    }
  }
}

// ─────────────────────────────────────────────
// _DetailRow
// ─────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon; final String label; final String value; final Color color;
  const _DetailRow({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93), fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
      ]),
    );
  }
}