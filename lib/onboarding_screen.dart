// ─────────────────────────────────────────────────────────────────
// onboarding_screen.dart — FoodFeast
// Fully animated full-screen onboarding for new customers.
// Shown ONCE right after signup. Never shown again (SharedPreferences).
// ─────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show AuthGate;
import 'package:firebase_auth/firebase_auth.dart';

// ─── Onboarding gate helpers ──────────────────────────────────────

String _onboardingKey(String uid) => 'onboarding_done_$uid';

Future<bool> needsOnboarding(String uid) async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(_onboardingKey(uid)) ?? false);
}

Future<void> markOnboardingDone(String uid) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingKey(uid), true);
}

// ─── Data model ───────────────────────────────────────────────────

class _PageData {
  final String emoji;
  final String title;
  final String subtitle;
  final String body;
  final Color bg1;
  final Color bg2;
  final Color accentLight;
  final List<_Tip> tips;
  const _PageData({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.bg1,
    required this.bg2,
    required this.accentLight,
    required this.tips,
  });
}

class _Tip {
  final IconData icon;
  final String label;
  const _Tip(this.icon, this.label);
}

// ─── Slide content ────────────────────────────────────────────────

const List<_PageData> _pages = [
  // 1 ── Discover Restaurants
  _PageData(
    emoji: '🍽️',
    title: 'Discover Restaurants',
    subtitle: 'Food near you, always.',
    body:
        'Browse hundreds of restaurants near you, filtered by cuisine, rating,calorie count & distance(7km) — powered by your GPS.',
    bg1: Color(0xFF005F8E),
    bg2: Color(0xFF0096C7),
    accentLight: Color(0xFFE0F4FF),
    tips: [
      _Tip(Icons.search_rounded, 'Search by dish, cuisine or restaurant name'),
      _Tip(Icons.tune_rounded, 'Filter by rating, price & Calorie count'),
      _Tip(Icons.location_on_rounded, 'GPS auto-detects your delivery area'),
    ],
  ),

  // 2 ── Bundle (group order, customize different items into one)
  _PageData(
    emoji: '📦',
    title: 'Bundle & Order Together',
    subtitle: 'One order, everyone happy.',
    body:
        'Build a group order with your friends or family — each person picks their own items from any restaurant and it all comes in a single bundle.',
    bg1: Color(0xFF1A5C2A),
    bg2: Color(0xFF2E8B57),
    accentLight: Color(0xFFE8F5E9),
    tips: [
      _Tip(Icons.group_rounded,
          'Used to enhance your experience'),
      _Tip(Icons.fastfood_rounded,
          'Mix items from different sections into one order'),
      _Tip(Icons.receipt_long_rounded,
          'One checkout, one delivery'),
    ],
  ),

  // 4 ── Live Order Tracking
  _PageData(
    emoji: '📍',
    title: 'Live Order Tracking',
    subtitle: 'Watch your food arrive.',
    body:
        'Follow your order in real time — from the restaurant kitchen to your door — with live map tracking and push alerts at every stage.',
    bg1: Color(0xFF005546),
    bg2: Color(0xFF00897B),
    accentLight: Color(0xFFE0F5F3),
    tips: [
      _Tip(Icons.map_outlined,
          'Live map shows your delivery agent\'s exact location'),
      _Tip(Icons.notifications_outlined,
          'Push alerts when order is confirmed, picked up & nearby'),
      _Tip(Icons.support_agent_rounded,
          'Contact your agent from the tracking screen'),
    ],
  ),

  // 5 ── Offers & Flash Deals (separate from Bundle)
  _PageData(
    emoji: '🎁',
    title: 'Deals Made for You',
    subtitle: 'More food, less money.',
    body:
        'Unlock exclusive flash deals, seasonal discounts and promo codes — freshly curated every day so there\'s always something worth grabbing.',
    bg1: Color(0xFFBF3600),
    bg2: Color(0xFFE65100),
    accentLight: Color(0xFFFFF3E0),
    tips: [
      _Tip(Icons.bolt_rounded,
          'Flash deals refresh daily — check back often'),
      _Tip(Icons.local_offer_rounded,
          'Apply promo codes at checkout for instant savings'),
      _Tip(Icons.celebration_rounded,
          'Seasonal & festival offers drop regularly'),
    ],
  ),

  // 6 ── Calorie Tracker (tracks + shows info, does NOT block)
  _PageData(
    emoji: '🔥',
    title: 'Calorie Tracker',
    subtitle: 'Eat smart, feel great.',
    body:
        'Every order is tracked against your daily calorie goal. See calorie counts per item and review your weekly intake history — all without restricting your choices.',
    bg1: Color(0xFFAD1717),
    bg2: Color(0xFFD32F2F),
    accentLight: Color(0xFFFFEBEE),
    tips: [
      _Tip(Icons.restaurant_menu_rounded,
          'Every menu item shows its calorie count upfront'),
      _Tip(Icons.bar_chart_rounded,
          'Weekly calorie history on your Stats screen'),
      _Tip(Icons.monitor_heart_outlined,
          'Daily goal calculated from your BMI & activity level'),
    ],
  ),

  // 7 ── Profile
  _PageData(
    emoji: '👤',
    title: 'Your Profile',
    subtitle: 'Everything in one place.',
    body:
        'Save delivery addresses, reorder your favourites in a tap, view full order history and keep your health profile up to date anytime.',
    bg1: Color(0xFF0D47A1),
    bg2: Color(0xFF1976D2),
    accentLight: Color(0xFFE3F2FD),
    tips: [
      _Tip(Icons.home_outlined,
          'Save home, work & custom delivery addresses'),
      _Tip(Icons.help_outline,
          'Help and Support For Customer Questions & Complaints'),
      _Tip(Icons.settings_outlined,
          'Update health goals & preferences anytime'),
    ],
  ),
];

// ─── Main Screen ─────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _current = 0;

  // Content fade + slide in
  late AnimationController _contentCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideUpAnim;

  // Emoji bounce (idle loop)
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceAnim;

  // Emoji scale pop on page change
  late AnimationController _emojiPopCtrl;
  late Animation<double> _emojiPopAnim;

  // Floating orbs (idle loop)
  late AnimationController _orbCtrl;

  // Rotating ring around emoji
  late AnimationController _ringCtrl;

  // Tips stagger
  late AnimationController _tipCtrl;
  late List<Animation<double>> _tipFades;
  late List<Animation<Offset>> _tipSlides;

  // Button pulse
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Shimmer on subtitle pill
  late AnimationController _shimmerCtrl;
  late Animation<double> _shimmerAnim;

  // Particle sparkle loop
  late AnimationController _sparkleCtrl;

  // Background morph (slow scale pulse)
  late AnimationController _bgMorphCtrl;
  late Animation<double> _bgMorphAnim;

  @override
  void initState() {
    super.initState();

    // ── Content fade/slide ──────────────────────────────
    _contentCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim =
        CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut);
    _slideUpAnim =
        Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _contentCtrl, curve: Curves.easeOutQuart));

    // ── Emoji vertical bounce (gentler, slower) ─────────
    _bounceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _bounceAnim = Tween<double>(begin: 0, end: -14).animate(
        CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut));

    // ── Emoji pop scale on page change ─────────────────
    _emojiPopCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _emojiPopAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.18), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.94), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _emojiPopCtrl, curve: Curves.easeOut));

    // ── Floating background orbs ─────────────────────────
    _orbCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 9))
      ..repeat();

    // ── Spinning ring (slower, more elegant) ────────────
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 14))
      ..repeat();

    // ── Tips stagger ─────────────────────────────────────
    _tipCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _tipFades = List.generate(3, (i) {
      final s = i * 0.20;
      return Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: _tipCtrl,
          curve: Interval(s, s + 0.5, curve: Curves.easeOut)));
    });
    _tipSlides = List.generate(3, (i) {
      final s = i * 0.20;
      return Tween<Offset>(begin: const Offset(0.30, 0), end: Offset.zero)
          .animate(CurvedAnimation(
              parent: _tipCtrl,
              curve: Interval(s, s + 0.5, curve: Curves.easeOutCubic)));
    });

    // ── Button pulse (subtle) ─────────────────────────────
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.038).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // ── Shimmer sweep ────────────────────────────────────
    _shimmerCtrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
          ..repeat();
    _shimmerAnim = Tween<double>(begin: -1, end: 2)
        .animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.linear));

    // ── Sparkle particles ────────────────────────────────
    _sparkleCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();

    // ── Background slow morph ────────────────────────────
    _bgMorphCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _bgMorphAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _bgMorphCtrl, curve: Curves.easeInOut));

    _playPageIn(pop: false);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _contentCtrl.dispose();
    _bounceCtrl.dispose();
    _emojiPopCtrl.dispose();
    _orbCtrl.dispose();
    _ringCtrl.dispose();
    _tipCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _sparkleCtrl.dispose();
    _bgMorphCtrl.dispose();
    super.dispose();
  }

  void _playPageIn({bool pop = true}) {
    _contentCtrl.reset();
    _tipCtrl.reset();
    if (pop) {
      _emojiPopCtrl.reset();
      _emojiPopCtrl.forward();
    }
    Future.delayed(const Duration(milliseconds: 40), () {
      if (!mounted) return;
      _contentCtrl.forward();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        _tipCtrl.forward();
      });
    });
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    _playPageIn();
  }

  void _next() {
    if (_current < _pages.length - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInOutCubic);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) await markOnboardingDone(user.uid);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            AuthGate(initialUser: FirebaseAuth.instance.currentUser),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_current];
    final size = MediaQuery.of(context).size;
    final isLast = _current == _pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          // ── Animated gradient background ──────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [page.bg1, page.bg2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // ── Slow-morphing radial overlay for depth ────
          AnimatedBuilder(
            animation: _bgMorphAnim,
            builder: (_, __) {
              return Positioned.fill(
                child: CustomPaint(
                  painter: _RadialOverlayPainter(
                      t: _bgMorphAnim.value, color: page.bg2),
                ),
              );
            },
          ),

          // ── Floating orbs ─────────────────────────────
          _FloatingOrbs(ctrl: _orbCtrl, size: size),

          // ── Sparkle particles ─────────────────────────
          _SparkleLayer(ctrl: _sparkleCtrl, size: size),

          // ── Wave divider into white card ──────────────
          Positioned(
            bottom: size.height * 0.365,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(size.width, 64),
              painter: _WavePainter(),
            ),
          ),

          // ── White bottom card ─────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: size.height * 0.415,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(36)),
                boxShadow: [
                  BoxShadow(
                      color: page.bg1.withOpacity(0.18),
                      blurRadius: 40,
                      offset: const Offset(0, -6)),
                  const BoxShadow(
                      color: Colors.black12,
                      blurRadius: 20,
                      offset: Offset(0, -2)),
                ],
              ),
            ),
          ),

          // ── Actual page content ───────────────────────
          PageView.builder(
            controller: _pageCtrl,
            itemCount: _pages.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, i) => _SlideContent(
              page: _pages[i],
              fadeAnim: _fadeAnim,
              slideUpAnim: _slideUpAnim,
              bounceAnim: _bounceAnim,
              emojiPopAnim: _emojiPopAnim,
              ringCtrl: _ringCtrl,
              shimmerAnim: _shimmerAnim,
              tipFades: _tipFades,
              tipSlides: _tipSlides,
              size: size,
            ),
          ),

          // ── Top bar: logo + skip ──────────────────────
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(22),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.50)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12),
                      ],
                    ),
                    child: const Row(children: [
                      Text('🍕', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 7),
                      Text('FoodFeast',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              letterSpacing: -0.2,
                              shadows: [
                                Shadow(
                                    color: Colors.black38,
                                    blurRadius: 4,
                                    offset: Offset(0, 1))
                              ])),
                    ]),
                  ),
                  // Skip
                  AnimatedOpacity(
                    opacity: isLast ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    child: GestureDetector(
                      onTap: _finish,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.50)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 12),
                          ],
                        ),
                        child: const Text('Skip',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                      color: Colors.black38,
                                      blurRadius: 4,
                                      offset: Offset(0, 1))
                                ])),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom controls ───────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dot indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pages.length, (i) {
                        final active = i == _current;
                        return GestureDetector(
                          onTap: () => _pageCtrl.animateToPage(i,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 30 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? page.bg1
                                  : const Color(0xFFCCCCCC),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                          color: page.bg1.withOpacity(0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ]
                                  : [],
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    // Next / Get Started button
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: GestureDetector(
                        onTap: _next,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          width: double.infinity,
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [page.bg1, page.bg2],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: page.bg1.withOpacity(0.50),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10)),
                              BoxShadow(
                                  color: page.bg1.withOpacity(0.20),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            child: Row(
                              key: ValueKey(isLast),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isLast ? "Let's Eat! 🎉" : 'Next',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black26,
                                            blurRadius: 6,
                                            offset: Offset(0, 1))
                                      ]),
                                ),
                                if (!isLast) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded,
                                      color: Colors.white, size: 20),
                                ]
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Slide content per page ───────────────────────────────────────

class _SlideContent extends StatelessWidget {
  final _PageData page;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideUpAnim;
  final Animation<double> bounceAnim;
  final Animation<double> emojiPopAnim;
  final AnimationController ringCtrl;
  final Animation<double> shimmerAnim;
  final List<Animation<double>> tipFades;
  final List<Animation<Offset>> tipSlides;
  final Size size;

  const _SlideContent({
    required this.page,
    required this.fadeAnim,
    required this.slideUpAnim,
    required this.bounceAnim,
    required this.emojiPopAnim,
    required this.ringCtrl,
    required this.shimmerAnim,
    required this.tipFades,
    required this.tipSlides,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Gradient hero area ───────────────────────────
        SizedBox(
          height: size.height * 0.415,
          child: Padding(
            // Bottom padding keeps content away from the wave edge
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: FadeTransition(
                opacity: fadeAnim,
                child: SlideTransition(
                  position: slideUpAnim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Spinning ring + bouncing emoji ──
                      // Scale the ring relative to screen height so it
                      // never pushes out of the hero area on small screens.
                      LayoutBuilder(builder: (_, constraints) {
                        final ringSize =
                            (size.height * 0.415 * 0.50).clamp(120.0, 160.0);
                        final innerRing = ringSize * 0.76;
                        final glowSize  = ringSize * 0.675;
                        final emojiFz   = (ringSize * 0.36).clamp(44.0, 58.0);
                        return SizedBox(
                          width: ringSize + 10,
                          height: ringSize + 10,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer glow halo
                              Container(
                                width: ringSize,
                                height: ringSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.white.withOpacity(0.15),
                                        blurRadius: 50,
                                        spreadRadius: 20),
                                  ],
                                ),
                              ),
                              // Outer spinning dashed ring
                              AnimatedBuilder(
                                animation: ringCtrl,
                                builder: (_, __) => Transform.rotate(
                                  angle: ringCtrl.value * 2 * math.pi,
                                  child: CustomPaint(
                                    size: Size(ringSize, ringSize),
                                    painter: _DashedCirclePainter(
                                        color: Colors.white.withOpacity(0.40),
                                        dashCount: 14),
                                  ),
                                ),
                              ),
                              // Counter-rotating inner ring
                              AnimatedBuilder(
                                animation: ringCtrl,
                                builder: (_, __) => Transform.rotate(
                                  angle:
                                      -ringCtrl.value * 2 * math.pi * 0.65,
                                  child: CustomPaint(
                                    size: Size(innerRing, innerRing),
                                    painter: _DashedCirclePainter(
                                        color:
                                            Colors.white.withOpacity(0.25),
                                        dashCount: 8),
                                  ),
                                ),
                              ),
                              // Glow circle
                              Container(
                                width: glowSize,
                                height: glowSize,
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.30),
                                      Colors.white.withOpacity(0.10),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        color:
                                            Colors.white.withOpacity(0.35),
                                        blurRadius: 40,
                                        spreadRadius: 10),
                                  ],
                                ),
                              ),
                              // Bouncing + pop emoji
                              AnimatedBuilder(
                                animation: bounceAnim,
                                builder: (_, __) => Transform.translate(
                                  offset: Offset(0, bounceAnim.value),
                                  child: ScaleTransition(
                                    scale: emojiPopAnim,
                                    child: Text(page.emoji,
                                        style: TextStyle(
                                            fontSize: emojiFz)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      SizedBox(height: size.height * 0.018),
                      // Title — strong white with text shadow
                      Text(
                        page.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize:
                              (size.height * 0.033).clamp(20.0, 27.0),
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                          height: 1.1,
                          shadows: const [
                            Shadow(
                                color: Colors.black45,
                                blurRadius: 12,
                                offset: Offset(0, 2)),
                            Shadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 1)),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: size.height * 0.010),
                      // Shimmer subtitle pill
                      _ShimmerPill(
                          text: page.subtitle,
                          shimmerAnim: shimmerAnim),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── White card content ───────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 4, 26, 0),
            child: FadeTransition(
              opacity: fadeAnim,
              child: SlideTransition(
                position: slideUpAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    // Body text — darker, better contrast
                    Text(
                      page.body,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Color(0xFF2A2A2A),
                        height: 1.65,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...List.generate(page.tips.length, (i) {
                      return SlideTransition(
                        position: tipSlides[i],
                        child: FadeTransition(
                          opacity: tipFades[i],
                          child: _TipRow(
                              tip: page.tips[i],
                              color: page.bg1,
                              accentLight: page.accentLight,
                              isLast: i == page.tips.length - 1),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Shimmer pill ─────────────────────────────────────────────────

class _ShimmerPill extends StatelessWidget {
  final String text;
  final Animation<double> shimmerAnim;
  const _ShimmerPill({required this.text, required this.shimmerAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerAnim,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              stops: const [0.0, 0.4, 0.6, 1.0],
              colors: [
                Colors.white.withOpacity(0.22),
                Colors.white.withOpacity(
                    0.22 + 0.22 * _shimmerAlpha(shimmerAnim.value, 0)),
                Colors.white.withOpacity(
                    0.22 + 0.22 * _shimmerAlpha(shimmerAnim.value, 0.2)),
                Colors.white.withOpacity(0.22),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.55), width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: Colors.white.withOpacity(0.20),
                  blurRadius: 12,
                  spreadRadius: 1),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
                shadows: [
                  Shadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 1))
                ]),
          ),
        );
      },
    );
  }

  double _shimmerAlpha(double t, double offset) {
    final v = ((t + offset) % 1.0);
    return (1 - (v - 0.5).abs() * 2).clamp(0.0, 1.0);
  }
}

// ─── Tip row ─────────────────────────────────────────────────────

class _TipRow extends StatelessWidget {
  final _Tip tip;
  final Color color;
  final Color accentLight;
  final bool isLast;
  const _TipRow(
      {required this.tip,
      required this.color,
      required this.accentLight,
      required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 11),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentLight,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(tip.icon, color: color, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              tip.label,
              style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  letterSpacing: 0.05),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Floating background orbs ─────────────────────────────────────

class _FloatingOrbs extends StatelessWidget {
  final AnimationController ctrl;
  final Size size;
  const _FloatingOrbs({required this.ctrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = ctrl.value * 2 * math.pi;
        return Stack(children: [
          _orb(size.width * 0.76 + math.cos(t) * 18,
              size.height * 0.04 + math.sin(t) * 14, 88, 0.12),
          _orb(-30 + math.sin(t * 0.65) * 16,
              size.height * 0.13 + math.cos(t * 0.65) * 22, 110, 0.09),
          _orb(size.width * 0.40 + math.cos(t * 1.2) * 12,
              size.height * 0.00 + math.sin(t * 1.2) * 10, 60, 0.10),
          _orb(size.width * 0.07 + math.sin(t * 0.45) * 20,
              size.height * 0.26 + math.cos(t * 0.45) * 16, 48, 0.08),
          _orb(size.width * 0.62 + math.sin(t * 0.9) * 14,
              size.height * 0.21 + math.cos(t * 0.9) * 11, 36, 0.08),
          // Extra large blurry orb far back
          _orb(size.width * 0.15 + math.sin(t * 0.3) * 24,
              size.height * 0.05 + math.cos(t * 0.3) * 18, 180, 0.05),
        ]);
      },
    );
  }

  Widget _orb(double l, double t, double r, double opacity) => Positioned(
        left: l,
        top: t,
        child: Container(
          width: r,
          height: r,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(opacity)),
        ),
      );
}

// ─── Sparkle particle layer ───────────────────────────────────────

class _SparkleLayer extends StatelessWidget {
  final AnimationController ctrl;
  final Size size;
  const _SparkleLayer({required this.ctrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        size: size,
        painter: _SparklePainter(t: ctrl.value, size: size),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final double t;
  final Size size;
  static final _rng = math.Random(42);
  static late final List<_SparkleParticle> _particles =
      List.generate(18, (i) => _SparkleParticle(_rng, i));

  const _SparklePainter({required this.t, required this.size});

  @override
  void paint(Canvas canvas, Size sz) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in _particles) {
      final life = ((t + p.phase) % 1.0);
      if (life > 0.6) continue;
      final alpha = (life < 0.15
              ? life / 0.15
              : life < 0.45
                  ? 1.0
                  : 1.0 - (life - 0.45) / 0.15)
          .clamp(0.0, 1.0);
      final y = p.y * sz.height - life * 60;
      paint.color = Colors.white.withOpacity(alpha * 0.55);
      final r = p.r * (1 - life * 0.4);
      canvas.drawCircle(Offset(p.x * sz.width, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

class _SparkleParticle {
  final double x, y, r, phase;
  _SparkleParticle(math.Random rng, int seed)
      : x = rng.nextDouble(),
        y = rng.nextDouble() * 0.55,
        r = 1.5 + rng.nextDouble() * 2.5,
        phase = rng.nextDouble();
}

// ─── Radial overlay painter for background depth ──────────────────

class _RadialOverlayPainter extends CustomPainter {
  final double t;
  final Color color;
  const _RadialOverlayPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * (0.3 + t * 0.4);
    final cy = size.height * (0.1 + t * 0.15);
    final radius = size.width * (0.8 + t * 0.3);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(0.18),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius));
    canvas.drawCircle(Offset(cx, cy), radius, paint);
  }

  @override
  bool shouldRepaint(_RadialOverlayPainter old) =>
      old.t != t || old.color != color;
}

// ─── Dashed circle painter ────────────────────────────────────────

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final int dashCount;
  const _DashedCirclePainter({required this.color, this.dashCount = 12});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final step = 2 * math.pi / dashCount;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * step;
      final endAngle = startAngle + step * 0.44;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle - startAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => false;
}

// ─── Wave divider painter ─────────────────────────────────────────

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 44)
      ..cubicTo(size.width * 0.15, 10, size.width * 0.35, 6, size.width * 0.5, 24)
      ..cubicTo(size.width * 0.65, 42, size.width * 0.82, 38, size.width, 14)
      ..lineTo(size.width, 64)
      ..lineTo(0, 64)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}