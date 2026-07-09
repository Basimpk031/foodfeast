// ─────────────────────────────────────────────────────────────────────────────
// dynamic_island_overlay.dart — FoodFeast  (COMPLETELY FIXED)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'order_tracking_screen.dart';

enum CutoutType {
  punchHoleCentered,
  punchHoleSide,
  notch,
  none,
}

class CutoutInfo {
  final CutoutType type;
  final double centerX;
  final double screenW;
  final double cutoutH;
  final double cutoutTop;

  const CutoutInfo({
    required this.type,
    required this.centerX,
    required this.screenW,
    required this.cutoutH,
    this.cutoutTop = 0,
  });

  bool get isCentered {
    if (screenW <= 0) return false;
    final deviation = (centerX - screenW / 2).abs() / screenW;
    return deviation < 0.10;
  }
}

class CutoutDetector {
  static const _channel = MethodChannel('com.foodfeast.app/display_cutout');

  static Future<CutoutInfo?> detect() async {
    try {
      final result = await _channel.invokeMethod<Map>('getCutoutInfo');
      debugPrint('[DynamicIsland] raw result: $result');
      if (result == null) return null;

      final typeStr   = result['type']      as String? ?? 'none';
      final centerX   = (result['centerX']  as num?)?.toDouble() ?? 0;
      final screenW   = (result['screenW']  as num?)?.toDouble() ?? 0;
      final cutoutH   = (result['cutoutH']  as num?)?.toDouble() ?? 0;
      final cutoutTop = (result['cutoutTop'] as num?)?.toDouble() ?? 0;

      CutoutType cutoutType;
      switch (typeStr) {
        case 'punch_hole':
          cutoutType = CutoutType.punchHoleCentered;
          break;
        case 'notch':
          cutoutType = CutoutType.notch;
          break;
        default:
          cutoutType = CutoutType.none;
      }

      final info = CutoutInfo(
        type: cutoutType,
        centerX: centerX,
        screenW: screenW,
        cutoutH: cutoutH,
        cutoutTop: cutoutTop,
      );

      if (cutoutType == CutoutType.punchHoleCentered && !info.isCentered) {
        return CutoutInfo(
          type: CutoutType.punchHoleSide,
          centerX: centerX,
          screenW: screenW,
          cutoutH: cutoutH,
          cutoutTop: cutoutTop,
        );
      }

      return info;
    } on PlatformException {
      return null;
    }
  }
}

class _StatusMeta {
  final String emoji;
  final String label;
  final String sublabel;
  final Color color;
  final bool pulse;

  const _StatusMeta({
    required this.emoji,
    required this.label,
    required this.sublabel,
    required this.color,
    this.pulse = false,
  });

  static const _blue   = Color(0xFF0EA5E9);
  static const _green  = Color(0xFF22C55E);
  static const _orange = Color(0xFFF97316);
  static const _red    = Color(0xFFEF4444);

  static _StatusMeta from(String status) {
    switch (status) {
      case 'confirmed':
        return const _StatusMeta(emoji: '✅', label: 'Confirmed',  sublabel: 'Order accepted',         color: _blue);
      case 'preparing':
        return const _StatusMeta(emoji: '👨‍🍳', label: 'Preparing',  sublabel: 'Kitchen is cooking',     color: _orange, pulse: true);
      case 'ready_for_pickup':
        return const _StatusMeta(emoji: '🛵', label: 'Ready!',     sublabel: 'Finding agent',          color: _orange, pulse: true);
      case 'picked_up':
        return const _StatusMeta(emoji: '📦', label: 'Picked Up',  sublabel: 'Agent has your order',   color: _blue,   pulse: true);
      case 'out_for_delivery':
        return const _StatusMeta(emoji: '🚀', label: 'On the Way', sublabel: 'Heading to you!',        color: _blue,   pulse: true);
      case 'delivered':
        return const _StatusMeta(emoji: '🎉', label: 'Delivered!', sublabel: 'Enjoy your meal 😋',     color: _green);
      case 'cancelled':
        return const _StatusMeta(emoji: '❌', label: 'Cancelled',  sublabel: 'Order was cancelled',    color: _red);
      default:
        return const _StatusMeta(emoji: '🕐', label: 'Placed',     sublabel: 'Waiting for restaurant', color: _orange, pulse: true);
    }
  }
}

class DynamicIslandService with WidgetsBindingObserver {
  DynamicIslandService._();
  static final instance = DynamicIslandService._();

  static const _nativeOverlayChannel = MethodChannel('com.foodfeast.app/native_overlay');
  static const _prefKey              = 'dynamic_island_active_order';

  GlobalKey<NavigatorState>? _navKey;
  OverlayEntry? _entry;
  StreamSubscription<DocumentSnapshot>? _orderSub;
  String? _currentOrderId;
  CutoutInfo? _cutoutInfo;

  final _statusNotifier  = ValueNotifier<String>('pending');
  final _visibleNotifier = ValueNotifier<bool>(false);

  Future<void> init(GlobalKey<NavigatorState> navKey) async {
    _navKey     = navKey;
    _cutoutInfo = await CutoutDetector.detect();
    WidgetsBinding.instance.addObserver(this);

    final prefs   = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefKey);
    if (savedId != null && savedId.isNotEmpty) {
      debugPrint('[DynamicIsland] Restoring island for order $savedId after app restart');
      WidgetsBinding.instance.addPostFrameCallback((_) { show(orderId: savedId); });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _dismissNativeOverlay();
      final orderId = _currentOrderId;
      if (orderId != null && _entry == null) {
        debugPrint('[DynamicIsland] Resumed — re-inserting Flutter overlay for $orderId');
        Future.delayed(const Duration(milliseconds: 350), () {
          if (_currentOrderId != null && _entry == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) { _insertOverlay(orderId); });
          }
        });
      }
    } else if (state == AppLifecycleState.paused) {
      final orderId = _currentOrderId;
      if (orderId != null) _showNativeOverlay(orderId, _statusNotifier.value);
      final entryToRemove = _entry;
      _entry = null;
      _visibleNotifier.value = false;
      Future.delayed(const Duration(milliseconds: 300), () {
        try { entryToRemove?.remove(); } catch (_) {}
      });
    }
  }

  Future<void> _showNativeOverlay(String orderId, String status) async {
    try {
      await _nativeOverlayChannel.invokeMethod('showOverlay', {'orderId': orderId, 'status': status});
    } on PlatformException catch (e) {
      debugPrint('[DynamicIsland] _showNativeOverlay failed: $e');
    }
  }

  Future<void> _dismissNativeOverlay() async {
    try {
      await _nativeOverlayChannel.invokeMethod('dismissOverlay');
    } on PlatformException catch (e) {
      debugPrint('[DynamicIsland] _dismissNativeOverlay failed: $e');
    }
  }

  void _handleNativeTap() => _openTracking();

  Future<void> show({required String orderId}) async {
    _cutoutInfo ??= await CutoutDetector.detect();
    final info = _cutoutInfo;

    debugPrint('[DynamicIsland] show() called for $orderId, type=${info?.type}');

    if (info == null ||
        info.type == CutoutType.none ||
        info.type == CutoutType.notch ||
        info.type == CutoutType.punchHoleSide) {
      debugPrint('[DynamicIsland] BLOCKED type=${info?.type}');
      return;
    }

    if (_currentOrderId == orderId) return;
    dismiss(permanent: true);

    _currentOrderId       = orderId;
    _statusNotifier.value = 'pending';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, orderId);

    _orderSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final status = (snap.data()?['status'] as String?) ?? 'pending';
      _statusNotifier.value = status;
      _showNativeOverlay(orderId, status);
      if (status == 'delivered' || status == 'cancelled') {
        Future.delayed(const Duration(seconds: 4), () => dismiss(permanent: true));
      }
    });

    _insertOverlay(orderId);

    _nativeOverlayChannel.setMethodCallHandler((call) async {
      if (call.method == 'onOverlayTapped') _handleNativeTap();
    });
  }

  void _insertOverlay(String orderId) {
    final overlayState = _navKey?.currentState?.overlay;
    if (overlayState == null) {
      debugPrint('[DynamicIsland] overlay is null — skipping insert');
      return;
    }
    final old = _entry;
    _entry = null;
    try { old?.remove(); } catch (_) {}

    _entry = OverlayEntry(
      builder: (_) => _DynamicIslandWidget(
        orderId: orderId,
        statusNotifier: _statusNotifier,
        visibleNotifier: _visibleNotifier,
        cutoutInfo: _cutoutInfo,
        onTap: _openTracking,
        onDismiss: () => dismiss(permanent: true),
      ),
    );
    overlayState.insert(_entry!);
    _visibleNotifier.value = true;
  }

  void dismiss({bool permanent = true}) {
    _visibleNotifier.value = false;
    final entryToRemove = _entry;
    _entry = null;
    Future.delayed(const Duration(milliseconds: 500), () {
      try { entryToRemove?.remove(); } catch (_) {}
    });
    if (permanent) {
      _dismissNativeOverlay();
      _orderSub?.cancel();
      _orderSub       = null;
      _currentOrderId = null;
      SharedPreferences.getInstance().then((p) => p.remove(_prefKey));
    }
  }

  void _openTracking() {
    final id = _currentOrderId;
    if (id == null) return;
    _navKey?.currentState?.push(
      MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: id)),
    );
  }
}

class _DynamicIslandWidget extends StatefulWidget {
  final String orderId;
  final ValueNotifier<String> statusNotifier;
  final ValueNotifier<bool> visibleNotifier;
  final CutoutInfo? cutoutInfo;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _DynamicIslandWidget({
    required this.orderId,
    required this.statusNotifier,
    required this.visibleNotifier,
    required this.onTap,
    required this.onDismiss,
    this.cutoutInfo,
  });

  @override
  State<_DynamicIslandWidget> createState() => _DynamicIslandWidgetState();
}

class _DynamicIslandWidgetState extends State<_DynamicIslandWidget>
    with TickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _entryCtrl;
  late final AnimationController _statusCtrl;

  late final Animation<double> _expandAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _entryAnim;
  late final Animation<double> _statusAnim;

  bool   _expanded        = false;
  String _displayedStatus = 'pending';
  bool _tapLocked = false;

  static const double _pillH     = 34.0;
  static const double _pillWColl = 126.0;
  static const double _pillWExp  = 300.0;
  static const double _pillHExp  = 128.0; // ← FIXED: Increased to 128.0 safely
  static const double _pillR     = 20.0;

  @override
  void initState() {
    super.initState();

    _expandCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _pulseCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _entryCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _statusCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutBack,   reverseCurve: Curves.easeInCubic);
    _pulseAnim  = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl,  curve: Curves.easeInOut));
    _entryAnim  = CurvedAnimation(parent: _entryCtrl,  curve: Curves.easeOutBack);
    _statusAnim = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _statusCtrl, curve: Curves.easeInOut));

    _entryCtrl.forward();
    _statusCtrl.value  = 1.0;
    _displayedStatus   = widget.statusNotifier.value;

    widget.statusNotifier.addListener(_onStatusChanged);
    widget.visibleNotifier.addListener(_onVisibilityChanged);
  }

  void _onStatusChanged() {
    final s = widget.statusNotifier.value;
    if (s == _displayedStatus) return;
    _statusCtrl.reverse().then((_) {
      if (mounted) {
        setState(() => _displayedStatus = s);
        _statusCtrl.forward();
      }
    });
  }

  void _onVisibilityChanged() {
    if (!widget.visibleNotifier.value && mounted) _entryCtrl.reverse();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    _statusCtrl.dispose();
    widget.statusNotifier.removeListener(_onStatusChanged);
    widget.visibleNotifier.removeListener(_onVisibilityChanged);
    super.dispose();
  }

  void _toggleExpand() {
    if (_tapLocked) return;
    _tapLocked = true;
    Future.delayed(const Duration(milliseconds: 350), () => _tapLocked = false);

    setState(() => _expanded = !_expanded);
    if (_expanded) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _expandCtrl.forward();
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted && _expanded) _collapse();
      });
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _expandCtrl.reverse();
    }
  }

  void _collapse() {
    if (!mounted) return;
    setState(() => _expanded = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _expandCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final dpr        = MediaQuery.of(context).devicePixelRatio;
    final screenW    = MediaQuery.of(context).size.width;
    final statusBarH = MediaQuery.of(context).padding.top;
    final info       = widget.cutoutInfo;

    double pillTop;
    const double minGap = 8.0;

    if (info != null && info.cutoutH > 0) {
      double holeCenterY;
      if (info.cutoutTop > 0) {
        holeCenterY = (info.cutoutTop + (info.cutoutH / 2)) / dpr;
      } else {
        holeCenterY = statusBarH / 2;
      }
      pillTop = holeCenterY - (_pillH / 2);
    } else {
      pillTop = (statusBarH - _pillH) / 2;
    }

    if (pillTop < minGap) pillTop = minGap;

    final cameraCenter = info != null && info.centerX > 0
        ? info.centerX / dpr
        : screenW / 2;

    const double touchPadding = 24.0;

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (_, __) {
        final t     = _expandAnim.value;
        final pillW = _pillWColl + (_pillWExp - _pillWColl) * t;

        final rawLeft    = cameraCenter - pillW / 2;
        final visualLeft = rawLeft.clamp(8.0, screenW - pillW - 8.0);

        return Positioned(
          top:  pillTop - touchPadding,
          left: visualLeft - touchPadding,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -2),
              end: Offset.zero,
            ).animate(_entryAnim),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleExpand,
              onLongPress: _toggleExpand,
              child: Container(
                color: Colors.transparent, 
                padding: const EdgeInsets.all(touchPadding),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulseAnim, _statusAnim]),
                  builder: (_, __) {
                    final meta   = _StatusMeta.from(_displayedStatus);
                    final height = _pillH + (_pillHExp - _pillH) * t;

                    return Container(
                      width: pillW,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(_pillR),
                        boxShadow: [
                          BoxShadow(
                            color: meta.color.withOpacity(0.4 * (0.3 + 0.7 * t)),
                            blurRadius: 20 + 14 * t,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_pillR),
                        child: Stack(children: [
                          if (t > 0.01)
                            Positioned.fill(
                              child: Opacity(
                                opacity: t * 0.15,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment.topCenter,
                                      radius: 1.2,
                                      colors: [meta.color, Colors.transparent],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Opacity(
                            opacity: (1 - t * 2).clamp(0.0, 1.0),
                            child: _CollapsedPill(
                              meta: meta,
                              pulseAnim: _pulseAnim,
                              pillW: pillW,
                              pillH: height,
                            ),
                          ),
                          if (t > 0.3)
                            // ── FIX: Positioned block isolates layout constraints from animation frame changes ──
                            Positioned(
                              top: 0,
                              left: 0,
                              width: pillW,
                              height: _pillHExp,
                              child: Opacity(
                                opacity: ((t - 0.3) / 0.7).clamp(0.0, 1.0) * _statusAnim.value,
                                child: _ExpandedCard(
                                  meta: meta,
                                  orderId: widget.orderId,
                                  onTrack: widget.onTap,
                                  onClose: _collapse,
                                ),
                              ),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CollapsedPill extends StatelessWidget {
  final _StatusMeta meta;
  final Animation<double> pulseAnim;
  final double pillW;
  final double pillH;

  const _CollapsedPill({
    required this.meta,
    required this.pulseAnim,
    required this.pillW,
    required this.pillH,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: pillW,
        height: pillH,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                meta.emoji,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.0,
                  decoration: TextDecoration.none,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFFF97316),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ExpandedCard extends StatelessWidget {
  final _StatusMeta meta;
  final String orderId;
  final VoidCallback onTrack;
  final VoidCallback onClose;

  const _ExpandedCard({
    required this.meta,
    required this.orderId,
    required this.onTrack,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Safety check: protect against substring range crashes if orderId is short
    final shortId = orderId.length >= 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Keep column from stretching out
        children: [
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: meta.color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: meta.color.withOpacity(0.35), width: 1),
              ),
              child: Center(
                child: Text(meta.emoji, style: const TextStyle(fontSize: 17, decoration: TextDecoration.none)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.label, style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800,
                    letterSpacing: 0.1, decoration: TextDecoration.none, height: 1.1,
                  )),
                  const SizedBox(height: 2),
                  Text(meta.sublabel, style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 10.5,
                    fontWeight: FontWeight.w500, decoration: TextDecoration.none, height: 1.2,
                  )),
                ],
              ),
            ),
            GestureDetector(
              onTap: onClose,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white54, size: 13),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Text('#$shortId', style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 9.5,
                  fontWeight: FontWeight.w700, letterSpacing: 1.0, decoration: TextDecoration.none,
                )),
              ),
              GestureDetector(
                onTap: onTrack,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: meta.color,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: meta.color.withOpacity(0.45), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation_rounded, color: Colors.white, size: 11),
                      SizedBox(width: 5),
                      Text('Track', style: TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800,
                        letterSpacing: 0.2, decoration: TextDecoration.none,
                      )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}