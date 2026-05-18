import 'package:flutter/material.dart';

/// FoodFeast Splash Screen — butter-smooth YouTube-style
///
/// [onAnimationDone] is called the moment the bar finishes sliding.
/// FoodFeastBootstrap uses this to know the animation is complete.
/// The app opens only when BOTH this fires AND Firebase is ready.

class SplashScreen extends StatefulWidget {
  final VoidCallback? onAnimationDone;
  const SplashScreen({super.key, this.onAnimationDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _logoCtrl;
  late final Animation<double>   _logoOpacity;
  late final Animation<double>   _logoScale;

  late final AnimationController _barCtrl;
  late final Animation<double>   _barProgress;
  late final Animation<double>   _barOpacity;

  // Butter-smooth cubic bezier curves
  static const _easeOut   = Cubic(0.16, 1.00, 0.30, 1.0);
  static const _easeInOut = Cubic(0.45, 0.00, 0.55, 1.0);

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: _easeOut),
    );
    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: _easeOut),
    );

    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _barProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _barCtrl, curve: _easeInOut),
    );
    _barOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _barCtrl,
        curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
      ),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Phase 1: logo fades in
    await _logoCtrl.forward();

    // Brief pause
    await Future.delayed(const Duration(milliseconds: 120));

    // Phase 2: bar slides across
    await _barCtrl.forward();

    // Bar is done — tell Bootstrap we're ready
    widget.onAnimationDone?.call();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _barCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_logoCtrl, _barCtrl]),
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Logo ──────────────────────────────────────────────────
                Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      width: 110,
                      height: 110,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Progress bar ──────────────────────────────────────────
                SizedBox(
                  width: 110,
                  height: 3,
                  child: Opacity(
                    opacity: _barOpacity.value,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Stack(
                        children: [
                          // Dark track
                          Container(color: const Color(0xFF1A0000)),
                          // Red fill sliding from left
                          FractionallySizedBox(
                            widthFactor: _barProgress.value,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF0000),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(99),
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
            );
          },
        ),
      ),
    );
  }
}