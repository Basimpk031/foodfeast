// ═══════════════════════════════════════════════════════════════════════════
// liquid_glass_widgets.dart  — FoodFeast
//
// iOS 26 "Liquid Glass" style:
//   • _LiquidGlassSearchBar  → drop-in for _buildSearchBar()
//   • _LiquidGlassNavBar     → drop-in for _LiquidNavBar (bottom nav)
//
// HOW TO USE
// ──────────────────────────────────────────────────────────────────────────
// 1. Add this file to your lib/ folder.
// 2. In home_screen.dart:
//
//    a) Replace _buildSearchBar() body with:
//         return _LiquidGlassSearchBar(
//           onTap:        () => _openFoodSearch(),
//           onFilterTap:  () => _showFilterSheet(const FoodFilter()),
//         );
//
//    b) Replace the _LiquidNavBar(...) call in _buildBottomNav() with:
//         return _LiquidGlassNavBar(
//           selectedIndex: _selectedIndex,
//           navKeys:       _navKeys,
//           onTabSelected: (i) {
//             _goToTab(i);
//             if (i == 0) _loadPhotoUrl();
//           },
//         );
//
// 3. The old _LiquidNavBar class and _Spring class can stay — they won't
//    conflict.  Or remove them to clean up.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cart_provider.dart';

// ───────────────────────────────────────────────────────────────────────────
// Shared constants
// ───────────────────────────────────────────────────────────────────────────
const _kBlue        = Color(0xFF0077B6);
const _kGlassWhite  = Colors.white;
const _kGlassBorder = Color(0xFFFFFFFF);

// ───────────────────────────────────────────────────────────────────────────
// Liquid Glass helper  (used by both widgets)
// ───────────────────────────────────────────────────────────────────────────
class _GlassBox extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color tintColor;
  final double tintOpacity;
  final Color borderColor;
  final double borderWidth;
  final List<BoxShadow>? shadows;
  final Gradient? gradient;

  const _GlassBox({
    required this.child,
    required this.borderRadius,
    this.blurSigma   = 28,
    this.tintColor   = Colors.white,
    this.tintOpacity = 0.18,
    this.borderColor = const Color(0xFFFFFFFF),
    this.borderWidth = 1.0,
    this.shadows,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient ?? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tintColor.withOpacity(tintOpacity + 0.06),
                tintColor.withOpacity(tintOpacity),
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: borderColor.withOpacity(0.55),
              width: borderWidth,
            ),
            boxShadow: shadows ?? [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 24,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.60),
                blurRadius: 0,
                spreadRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ① LIQUID GLASS SEARCH BAR
// ═══════════════════════════════════════════════════════════════════════════
class _LiquidGlassSearchBar extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onFilterTap;

  const _LiquidGlassSearchBar({
    required this.onTap,
    required this.onFilterTap,
  });

  @override
  State<_LiquidGlassSearchBar> createState() =>
      _LiquidGlassSearchBarState();
}

class _LiquidGlassSearchBarState extends State<_LiquidGlassSearchBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(children: [
        // ── Main glass search pill ─────────────────────────────────────────
        Expanded(
          child: GestureDetector(
            onTap: widget.onTap,
            child: _GlassBox(
              borderRadius: BorderRadius.circular(18),
              blurSigma: 32,
              tintOpacity: 0.20,
              shadows: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.09),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.75),
                  blurRadius: 0,
                  spreadRadius: 0,
                  offset: const Offset(0, 1),
                ),
              ],
              child: SizedBox(
                height: 50,
                child: Row(children: [
                  const SizedBox(width: 14),
                  // Animated shimmer search icon
                  AnimatedBuilder(
                    animation: _shimmerCtrl,
                    builder: (_, __) {
                      final t = (math.sin(_shimmerCtrl.value * 2 * math.pi) + 1) / 2;
                      return Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Color.lerp(
                          const Color(0xFF8E8E93),
                          const Color(0xFF0077B6),
                          t * 0.35,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Search dishes, food items...',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFFAEAEB2),
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.1,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),

        const SizedBox(width: 10),

        // ── Glass filter button ────────────────────────────────────────────
        GestureDetector(
          onTap: widget.onFilterTap,
          child: _GlassBox(
            borderRadius: BorderRadius.circular(16),
            blurSigma: 32,
            tintColor: _kBlue,
            tintOpacity: 0.22,
            borderColor: _kBlue,
            borderWidth: 1.2,
            shadows: [
              BoxShadow(
                color: _kBlue.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.5),
                blurRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Center(
                child: Icon(Icons.tune_rounded,
                    color: _kBlue, size: 22),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ② LIQUID GLASS BOTTOM NAV  (iOS 26 App Store style)
// ═══════════════════════════════════════════════════════════════════════════
class _LiquidGlassNavBar extends StatefulWidget {
  final int selectedIndex;
  final List<GlobalKey> navKeys;
  final ValueChanged<int> onTabSelected;

  const _LiquidGlassNavBar({
    required this.selectedIndex,
    required this.navKeys,
    required this.onTabSelected,
  });

  @override
  State<_LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<_LiquidGlassNavBar>
    with TickerProviderStateMixin {

  // ── Pill slide animation ──────────────────────────────────────────────
  late final AnimationController _pillCtrl;
  late Animation<double> _pillLeft;
  late Animation<double> _pillWidth;

  double _currentLeft  = 0;
  double _currentWidth = 0;
  bool   _initialized  = false;

  // ── Icon pop animations (one per tab) ────────────────────────────────
  late final List<AnimationController> _iconCtrls;

  // ── Shimmer on the glass surface ─────────────────────────────────────
  late final AnimationController _shimCtrl;

  static const _icons  = [
    Icons.home_rounded,
    Icons.shopping_bag_rounded,
    Icons.inventory_2_rounded,
    Icons.bar_chart_rounded,
    Icons.person_rounded,
  ];
  static const _labels = ['Home', 'Cart', 'Bundle', 'Stats', 'Profile'];

  @override
  void initState() {
    super.initState();

    _pillCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _pillLeft  = AlwaysStoppedAnimation(0);
    _pillWidth = AlwaysStoppedAnimation(0);

    _iconCtrls = List.generate(5, (_) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    ));

    _shimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void didUpdateWidget(_LiquidGlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _animatePillTo(widget.selectedIndex);
      _popIcon(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _pillCtrl.dispose();
    for (final c in _iconCtrls) c.dispose();
    _shimCtrl.dispose();
    super.dispose();
  }

  void _init() {
    final rect = _tabRect(widget.selectedIndex);
    if (rect == null) return;
    setState(() {
      _currentLeft  = rect.left;
      _currentWidth = rect.width;
      _initialized  = true;
    });
    _pillLeft  = AlwaysStoppedAnimation(rect.left);
    _pillWidth = AlwaysStoppedAnimation(rect.width);
    _popIcon(widget.selectedIndex);
  }

  void _animatePillTo(int index) {
    final rect = _tabRect(index);
    if (rect == null) return;

    final fromLeft  = _currentLeft;
    final fromWidth = _currentWidth;
    final toLeft    = rect.left;
    final toWidth   = rect.width;

    _pillCtrl.reset();
    _pillLeft  = Tween<double>(begin: fromLeft,  end: toLeft)
        .animate(CurvedAnimation(parent: _pillCtrl, curve: Curves.easeOutExpo));
    _pillWidth = Tween<double>(begin: fromWidth, end: toWidth)
        .animate(CurvedAnimation(parent: _pillCtrl, curve: Curves.easeOutExpo));
    _pillCtrl.forward().then((_) {
      _currentLeft  = toLeft;
      _currentWidth = toWidth;
    });

    HapticFeedback.selectionClick();
  }

  void _popIcon(int index) {
    _iconCtrls[index].forward(from: 0);
  }

  Rect? _tabRect(int index) {
    final key = widget.navKeys[index];
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final navBox = _findNavBox();
    if (navBox == null) return null;
    final offset = box.localToGlobal(Offset.zero, ancestor: navBox);
    return offset & box.size;
  }

  RenderBox? _findNavBox() {
    RenderObject? node =
        widget.navKeys[0].currentContext?.findRenderObject();
    while (node != null) {
      if (node is RenderBox && node.size.width > 200) return node;
      node = node.parent as RenderObject?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: CartProvider.instance,
      builder: (context, _) {
        final cartCount = CartProvider.instance.totalItems;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, math.max(bottom, 12)),
          child: _GlassBox(
            borderRadius: BorderRadius.circular(36),
            blurSigma: 40,
            tintOpacity: 0.16,
            shadows: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 30,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.65),
                blurRadius: 0,
                spreadRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
            child: SizedBox(
              height: 68,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // ── Top highlight shimmer ──────────────────────────────
                  Positioned(
                    top: 0, left: 40, right: 40, height: 1,
                    child: AnimatedBuilder(
                      animation: _shimCtrl,
                      builder: (_, __) {
                        final t = _shimCtrl.value;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(
                                    0.55 + math.sin(t * 2 * math.pi) * 0.25),
                                Colors.transparent,
                              ],
                              stops: [
                                (t - 0.3).clamp(0.0, 1.0),
                                t.clamp(0.0, 1.0),
                                (t + 0.3).clamp(0.0, 1.0),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Floating glass pill ────────────────────────────────
                  if (_initialized)
                    AnimatedBuilder(
                      animation: _pillCtrl,
                      builder: (_, __) {
                        final left  = _pillLeft.value;
                        final width = _pillWidth.value.clamp(48.0, 200.0);
                        return Positioned(
                          left:   left,
                          top:    8,
                          bottom: 8,
                          width:  width,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end:   Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withOpacity(0.72),
                                      Colors.white.withOpacity(0.48),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.80),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.10),
                                      blurRadius: 10,
                                      spreadRadius: -2,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                // Inner top highlight
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 1.5),
                                    child: FractionallySizedBox(
                                      widthFactor: 0.45,
                                      child: Container(
                                        height: 1,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(colors: [
                                            Colors.transparent,
                                            Colors.white.withOpacity(0.9),
                                            Colors.transparent,
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  // ── Tab items ──────────────────────────────────────────
                  Row(
                    children: List.generate(5, (i) =>
                        _buildTab(i, cartCount)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTab(int index, int cartCount) {
    final isActive  = widget.selectedIndex == index;
    final showBadge = index == 1 && cartCount > 0;

    // Icon pop spring: scale 1→1.28→1
    final iconScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.32)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 35),
      TweenSequenceItem(
          tween: Tween(begin: 1.32, end: 0.92)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 0.92, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 35),
    ]).animate(_iconCtrls[index]);

    return Expanded(
      child: GestureDetector(
        key: widget.navKeys[index],
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onTabSelected(index);
          _popIcon(index);
        },
        child: SizedBox(
          height: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _iconCtrls[index],
                    builder: (_, __) {
                      return Transform.scale(
                        scale: iconScale.value,
                        child: Icon(
                          _icons[index],
                          size: 22,
                          color: isActive
                              ? const Color(0xFF1A1A1E)
                              : Colors.white.withOpacity(0.55),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? const Color(0xFF1A1A1E)
                          : Colors.white.withOpacity(0.50),
                      letterSpacing: 0.1,
                    ),
                    child: Text(_labels[index]),
                  ),
                ],
              ),

              // Cart badge
              if (showBadge)
                Positioned(
                  top: 9,
                  right: 8,
                  child: Container(
                    constraints: const BoxConstraints(
                        minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.6),
                          width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3B30).withOpacity(0.45),
                          blurRadius: 6,
                          spreadRadius: -1,
                        ),
                      ],
                    ),
                    child: Text(
                      cartCount > 99 ? '99+' : '$cartCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
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
}
