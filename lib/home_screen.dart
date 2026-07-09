// ─────────────────────────────────────────────
// home_screen.dart — FoodFeast
// Ultra-smooth spring-physics blob bottom nav
// ─────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'dart:math' as math;
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'login_screen.dart';
import 'liquid_glass_widgets.dart';
import 'restaurant_detail_screen.dart';
import 'profile_screen.dart';
import 'cart_screen.dart';
import 'stats_screen.dart';
import 'cart_provider.dart';
import 'calorie_tracker.dart';
import 'portion_sheet.dart';
import 'bundle_screen.dart';
import 'notification_screen.dart';
import 'favorites_ratings_service.dart';
import 'reviews_sheet.dart';
import 'order_tracking_screen.dart'; // active order banner
import 'location_service.dart';
import 'location_filter.dart';
import 'ai_recommendation_engine.dart'; // ✅ AI Recommendation Engine
import 'offers_section.dart';           // 🎉 Offers banner strip

// ─────────────────────────────────────────────
// FCM background handler — must be top-level
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('BG FCM: ${message.notification?.title}');
}

// ─────────────────────────────────────────────
// NotificationSetup  (singleton)
// ─────────────────────────────────────────────
class NotificationSetup {
  NotificationSetup._();
  static final instance = NotificationSetup._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    _saveFcmToken(token);
    messaging.onTokenRefresh.listen(_saveFcmToken);

    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n != null) _showLocal(n.title ?? 'FoodFeast', n.body ?? '');
    });

    _ready = true;
  }

  void _saveFcmToken(String? token) {
    if (token == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  Future<void> _showLocal(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'foodfeast_channel',
      'FoodFeast Notifications',
      channelDescription: 'Order updates and promotions',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}

// ─────────────────────────────────────────────
// Filter state
// ─────────────────────────────────────────────
enum SortOption { none, priceLow, priceHigh, caloriesLow, caloriesHigh }

class FoodFilter {
  final SortOption sort;
  final bool vegOnly;
  final int? maxCalories;

  const FoodFilter({
    this.sort = SortOption.none,
    this.vegOnly = false,
    this.maxCalories,
  });

  FoodFilter copyWith(
      {SortOption? sort, bool? vegOnly, int? maxCalories, bool clearMaxCal = false}) {
    return FoodFilter(
      sort: sort ?? this.sort,
      vegOnly: vegOnly ?? this.vegOnly,
      maxCalories: clearMaxCal ? null : (maxCalories ?? this.maxCalories),
    );
  }

  bool get isActive => sort != SortOption.none || vegOnly || maxCalories != null;
}

// ─────────────────────────────────────────────
// Food search result model
// ─────────────────────────────────────────────
class FoodSearchResult {
  final String itemName;
  final String restaurantId;
  final String restaurantName;
  final double price;
  final bool isVeg;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final String imageUrl;
  final String description;
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;
  final bool isItemAvailable;
  final bool isRestaurantActive;
  final double? distanceKm;
  final String restaurantAddress;

  const FoodSearchResult({
    required this.itemName,
    required this.restaurantId,
    required this.restaurantName,
    required this.price,
    required this.isVeg,
    required this.calories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    required this.imageUrl,
    required this.description,
    this.portionPrices = const {},
    this.portionNutrition = const {},
    this.isItemAvailable = true,
    this.isRestaurantActive = true,
    this.distanceKm,
    this.restaurantAddress = '',
  });
}

// ── Distance helper ──────────────────────────────────────────────
double? _calcDistanceKm(Map<String, dynamic> restData) {
  final locMap = restData['location'] as Map<String, dynamic>?;
  if (locMap == null) return null;
  final restLat = (locMap['lat'] as num?)?.toDouble();
  final restLng = (locMap['lng'] as num?)?.toDouble();
  if (restLat == null || restLng == null) return null;
  final userLoc = LocationService.instance.current;
  if (userLoc == null) return null;
  const R = 6371.0;
  final dLat = (restLat - userLoc.lat) * (math.pi / 180);
  final dLng = (restLng - userLoc.lng) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(userLoc.lat * (math.pi / 180)) *
          math.cos(restLat * (math.pi / 180)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

String _fmtDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

int _parsePrepMinutes(String deliveryTimeStr) {
  final match = RegExp(r'(\d+)').firstMatch(deliveryTimeStr);
  if (match != null) return int.tryParse(match.group(1)!) ?? 25;
  return 25;
}

String _calcDeliveryTime({
  required String deliveryTimeStr,
  required double? distanceKm,
}) {
  final prepMins = _parsePrepMinutes(deliveryTimeStr);
  if (distanceKm == null) {
    return '~$prepMins min';
  }
  const motorcycleSpeedKmh = 30.0;
  final travelMins = (distanceKm / motorcycleSpeedKmh * 60).ceil();
  final totalMins = prepMins + travelMins;
  return '${(totalMins - 5).clamp(5, 999)}–${totalMins + 5} min';
}

// ─────────────────────────────────────────────
// Spring physics helper
// ─────────────────────────────────────────────
class _Spring {
  double stiffness;
  double damping;
  final double mass;

  double position = 0;
  double velocity = 0;
  double target   = 0;

  _Spring({
    this.stiffness = 320,
    this.damping   = 28,
    this.mass      = 1.0,
  });

  bool tick(double dt) {
    final d = dt.clamp(0.0, 0.032);
    final force    = -stiffness * (position - target);
    final damper   = -damping * velocity;
    final accel    = (force + damper) / mass;
    velocity += accel * d;
    position += velocity * d;

    final atRest = (position - target).abs() < 0.05 &&
        velocity.abs() < 0.05;
    if (atRest) {
      position = target;
      velocity = 0;
    }
    return !atRest;
  }

  void snapTo(double value) {
    position = value;
    target   = value;
    velocity = 0;
  }
}

// ─────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {

  // ── App state ────────────────────────────────
  int _selectedIndex = 0;
  String _selectedCategory = 'All';
  final _searchCtrl = TextEditingController();

  // FIX 1: Persistent ScrollController so position survives tab switches
  final _homeScrollCtrl = ScrollController();

  static const _blue = Color(0xFF0077B6);

  // ── Popular items manual refresh counter ─────
  // Incrementing this forces _FoodItemsGridLoader to re-fetch.
  int _popularItemsRefreshKey = 0;

  // ── Count-up animation ───────────────────────
  late AnimationController _countUpCtrl;
  late Animation<double> _countUpAnim;

  // ── Keys to trigger replay animation on child screens ──
  final _statsKey   = GlobalKey<StatsScreenState>();
  final _profileKey = GlobalKey<ProfileScreenState>();

  // ── Nav keys (one per tab) ──────────────────
  final List<GlobalKey> _navKeys =
      List.generate(5, (_) => GlobalKey());

  // ── User ────────────────────────────────────
  String _photoUrl = '';
  User? get _user => FirebaseAuth.instance.currentUser;
  String get _userName => _user?.displayName ?? 'Foodie';

  String get _userInitials {
    final name = _userName.trim();
    if (name.isEmpty) return 'U';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  final List<Map<String, String>> _categoryIcons = [
    {'label': 'All',      'image': 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=200&q=80'},
    {'label': 'Pizza',    'image': 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=200&q=80'},
    {'label': 'Burger',   'image': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=200&q=80'},
    {'label': 'Indian',   'image': 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=200&q=80'},
    {'label': 'Chinese',  'image': 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=200&q=80'},
    {'label': 'Desserts', 'image': 'https://images.unsplash.com/photo-1551024601-bec78aea704b?w=200&q=80'},
    {'label': 'Biryani',  'image': 'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=200&q=80'},
    {'label': 'Chicken',  'image': 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=200&q=80'},
  ];

  // ────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _countUpCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _countUpAnim = CurvedAnimation(
        parent: _countUpCtrl, curve: Curves.easeOutCubic);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    CalorieTracker.instance.loadTodayData(uid: uid).then((_) {
      if (mounted) _countUpCtrl.forward(from: 0);
    });
    _loadPhotoUrl();
    NotificationSetup.instance.init().then((_) {
      FirebaseMessaging.instance.subscribeToTopic('all_users');
    });
    if (uid != null) NotificationService.instance.startListening(uid);
    LocationService.instance.loadSaved().then((_) {
      if (LocationService.instance.current == null) {
        LocationService.instance.fetchCurrentLocation();
      }
    });
    _listenToActiveOrder();
    FoodRecommendationEngine.instance.invalidateCache();
    FoodRecommendationEngine.instance.getRecommendations();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _orderSub?.cancel();
    _countUpCtrl.dispose();
    _searchCtrl.dispose();
    // FIX 1: dispose the persistent scroll controller
    _homeScrollCtrl.dispose();
    super.dispose();
  }

  // ── Navigation helpers ───────────────────────
  void _goToTab(int index) {
    final wasHome = _selectedIndex == 0;
    setState(() => _selectedIndex = index);
    if (index == 0 && !wasHome) {
      _countUpCtrl.forward(from: 0);
    } else if (index == 3) {
      _statsKey.currentState?.replayAnimation();
    } else if (index == 4) {
      _profileKey.currentState?.replayAnimation();
    }
  }

  void _goToStats() => _goToTab(3);

  Future<void> _loadPhotoUrl() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid).get();
    if (mounted) {
      setState(() => _photoUrl = (doc.data()?['photoUrl'] as String?) ?? '');
    }
  }

  void _openFoodSearch({FoodFilter? initialFilter}) {
    showSearch(
      context: context,
      delegate: _FoodItemSearchDelegate(
          initialFilter: initialFilter ?? const FoodFilter()),
    );
  }

  void _openRestaurant(String id, String name, String imageUrl) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestaurantDetailScreen(
          restaurantId: id,
          restaurantName: name,
          restaurantImageUrl: imageUrl,
        ),
      ),
    );
    if (result == 'go_to_cart' && mounted) _goToTab(1);
  }

  void _showManualLogSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualLogSheet(onSaved: () {}),
    );
  }

  // ── Manual refresh for Popular Items ─────────
  void _refreshPopularItems() {
    // Clear the static cache so the new widget instance actually re-fetches
    _FoodItemsGridLoaderState._cache.clear();
    setState(() => _popularItemsRefreshKey++);
  }

  // ────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────
@override
Scaffold build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFFF2F2F7),
    extendBody: true,
    bottomNavigationBar: _buildBottomNav(),
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [
            Color(0xFFE8F4FD),
            Color(0xFFF2F2F7),
            Color(0xFFE8F4FD),
          ],
        ),
      ),
      child: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeContent(),
          CartScreen(onBrowseFoodItems: _openFoodSearch),
          const BundleScreen(),
          StatsScreen(key: _statsKey),
          ProfileScreen(key: _profileKey, scaffoldMessenger: ScaffoldMessenger.of(context)),
        ],
      ),
    ),
  );
}

  // ────────────────────────────────────────────
  // BOTTOM NAV
  // ────────────────────────────────────────────
  Widget _buildBottomNav() {
  return Material(
    color: Colors.transparent,
    child: _LiquidNavBar(
      selectedIndex: _selectedIndex,
      navKeys: _navKeys,
      onTabSelected: (i) {
        _goToTab(i);
        if (i == 0) _loadPhotoUrl();
      },
    ),
  );
}

  // ────────────────────────────────────────────
  // HOME CONTENT
  // FIX 1: Added PageStorageKey + persistent ScrollController
  // FIX 2: AI Recommendations moved ABOVE Popular Items
  // ────────────────────────────────────────────
  Widget _buildHomeContent() {
    return CustomScrollView(
      key: const PageStorageKey<String>('home_scroll'),
      controller: _homeScrollCtrl,
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(child: _buildActiveOrderBanner()),
        SliverToBoxAdapter(child: _buildSearchBar()),

        // ── Offers banner strip ─────────────────────────────────────
        const SliverToBoxAdapter(child: OffersSection()),

        SliverToBoxAdapter(child: _buildCalorieProgressCard()),
        SliverToBoxAdapter(child: _buildCategories()),

        // ── AI Recommendations above Popular Items ──
        SliverToBoxAdapter(
          child: _buildAiRecommendationSection(),
        ),

        // ── Popular Food Items section ──────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Popular Items',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E))),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Manual refresh button ──────────────────
                    GestureDetector(
                      onTap: _refreshPopularItems,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _blue.withOpacity(0.18), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded,
                                size: 14, color: _blue),
                            const SizedBox(width: 4),
                            Text('Refresh',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _blue,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _openFoodSearch(),
                      child: Text('See all',
                          style: TextStyle(
                              fontSize: 13.5,
                              color: _blue,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Pass refresh key so loader only re-fetches when user taps Refresh
        _buildFoodItemsGrid(),

        // ── Restaurants section ─────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Restaurants Near You',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E))),
                Text('See all',
                    style: TextStyle(
                        fontSize: 13.5,
                        color: _blue,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        _buildRestaurantList(),
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).padding.bottom + 90,
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────
  // AI Recommendation section
  // ────────────────────────────────────────────
  Widget _buildAiRecommendationSection() {
    return AiRecommendationSection(
      onAddToCart: (rec) {
        CartProvider.instance.addItem(CartItem(
          name:           rec.itemName,
          restaurantId:   rec.restaurantId,
          restaurantName: rec.restaurantName,
          price:          rec.price,
          imageUrl:       rec.imageUrl,
          isVeg:          rec.isVeg,
          calories:       rec.calories,
          protein:        rec.protein,
          carbs:          rec.carbs,
          fat:            rec.fat,
        ));
      },
      onItemTap: (rec) {
        _openRestaurant(
          rec.restaurantId,
          rec.restaurantName,
          rec.imageUrl,
        );
      },
    );
  }

  // ── Active order state ─────────────────────
  List<Map<String, String>> _activeOrders = [];
  StreamSubscription<QuerySnapshot>? _orderSub;
  StreamSubscription<User?>? _authSub;

  void _listenToActiveOrder() {
    final uid = _user?.uid;
    if (uid != null) {
      _attachOrderListener(uid);
      return;
    }
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && mounted) {
        _authSub?.cancel();
        _authSub = null;
        _attachOrderListener(user.uid);
      }
    });
  }

  void _attachOrderListener(String uid) {
    _orderSub?.cancel();
    _orderSub = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .where('status', whereIn: [
          'pending', 'confirmed', 'preparing',
          'ready_for_pickup', 'picked_up', 'out_for_delivery',
        ])
        .snapshots()
        .listen((snap) {
      if (!mounted) return;

      const activeStatuses = {
        'pending', 'confirmed', 'preparing',
        'ready_for_pickup', 'picked_up', 'out_for_delivery',
      };
      final activeDocs = snap.docs.where((d) {
        final s = (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
        return activeStatuses.contains(s);
      }).toList()
        ..sort((a, b) {
          final aT = (a.data() as Map<String, dynamic>)['createdAt'];
          final bT = (b.data() as Map<String, dynamic>)['createdAt'];
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return (bT as Timestamp).compareTo(aT as Timestamp);
        });

      final newOrders = activeDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return <String, String>{
          'id':             doc.id,
          'status':         (data['status']         as String? ?? ''),
          'otp':            (data['deliveryOtp']    as String? ?? ''),
          'restaurantName': (data['restaurantName'] as String? ?? 'Your order'),
        };
      }).toList();

      final changed = newOrders.length != _activeOrders.length ||
          List.generate(newOrders.length, (i) =>
            newOrders[i]['id']     != _activeOrders[i]['id']     ||
            newOrders[i]['status'] != _activeOrders[i]['status'] ||
            newOrders[i]['otp']    != _activeOrders[i]['otp']
          ).any((v) => v);

      if (changed) setState(() => _activeOrders = newOrders);
    });
  }

  // ── Active Order Banners ─────────────────────
  Widget _buildActiveOrderBanner() {
    if (_activeOrders.isEmpty) return const SizedBox.shrink();
    return Column(
      children: _activeOrders
          .map((order) => _singleOrderBanner(order))
          .toList(),
    );
  }

  Widget _singleOrderBanner(Map<String, String> order) {
    final orderId  = order['id']!;
    final status   = order['status']!;
    final otp      = order['otp']!;
    final restName = order['restaurantName']!;

    final String emoji;
    final String label;
    final Color  color;
    switch (status) {
      case 'pending':
        emoji = '🕐'; label = 'Waiting for confirmation'; color = const Color(0xFFFF9500);
        break;
      case 'confirmed':
        emoji = '✅'; label = 'Order confirmed!'; color = const Color(0xFF007AFF);
        break;
      case 'preparing':
        emoji = '👨‍🍳'; label = 'Being prepared'; color = const Color(0xFF5856D6);
        break;
      case 'ready_for_pickup':
        emoji = '🛵'; label = 'Ready — finding agent'; color = const Color(0xFFFF6B00);
        break;
      case 'picked_up':
      case 'out_for_delivery':
        emoji = '🚀'; label = 'On the way!'; color = _blue;
        break;
      default:
        emoji = '📦'; label = status; color = _blue;
    }

    final showOtp = otp.isNotEmpty &&
        (status == 'out_for_delivery' || status == 'picked_up');

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: orderId),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.92), color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 5)),
          ],
        ),
        child: Column(children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(restName,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xD9FFFFFF)),
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Track',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white, size: 11),
              ]),
            ),
          ]),

          if (showOtp) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.lock_rounded,
                    color: Colors.white, size: 15),
                const SizedBox(width: 8),
                const Text('OTP: ',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
                Text(
                  otp.split('').join('  '),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.white),
                ),
                const Spacer(),
                const Text('Show to agent',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white70)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildSearchBar() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    child: Row(children: [
      // ── Search pill ───────────────────────────────────────────────
      Expanded(
        child: GestureDetector(
          onTap: () => _openFoodSearch(),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFE5E5EA),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.9),
                  blurRadius: 0,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Top specular sheen line
                Positioned(
                  top: 0, left: 16, right: 16, height: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.95),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(width: 14),
                      Icon(Icons.search_rounded,
                          color: Color(0xFF8E8E93), size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Search dishes, food items...',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFFAEAEB2),
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      const SizedBox(width: 10),

      // ── Filter button ─────────────────────────────────────────────
      GestureDetector(
        onTap: () => _showFilterSheet(const FoodFilter()),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _blue.withOpacity(0.9),
                _blue,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _blue.withOpacity(0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.4),
                blurRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Top specular sheen
              Positioned(
                top: 0, left: 8, right: 8, height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.55),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              const Center(
                child: Icon(Icons.tune_rounded,
                    color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
      ),
    ]),
  );
}

void _showFilterSheet(FoodFilter current) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FilterSheet(
      current: current,
      onApply: (filter) {
        Navigator.pop(context);
        _openFoodSearch(initialFilter: filter);
      },
    ),
  );
}

  // ── Calorie progress card ───────────────────
  Widget _buildCalorieProgressCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: AnimatedBuilder(
        animation: Listenable.merge(
            [CalorieTracker.instance, _countUpAnim]),
        builder: (_, __) {
          final tracker   = CalorieTracker.instance;
          final t         = _countUpAnim.value;

          final consumed  = (tracker.consumedCalories * t).round();
          final goal      = tracker.goalCalories;
          final remaining = (tracker.remainingCalories * t).round();
          final progress  = tracker.progress * t;

          final protein = tracker.consumedProtein * t;
          final carbs   = tracker.consumedCarbs * t;
          final fat     = tracker.consumedFat * t;

          final double rawRatio    = tracker.goalCalories > 0
              ? tracker.consumedCalories / tracker.goalCalories
              : 0.0;
          final bool isNearLimit   = rawRatio >= 0.9 && rawRatio < 1.0;
          final bool isGoalReached = rawRatio == 1.0;
          final bool isExceeded    = rawRatio > 1.0;

          String motivationText = 'Keep going! You\'re doing great 💪';
          if (tracker.consumedCalories == 0) motivationText = 'Start your day healthy! 🥗';
          if (isNearLimit)   motivationText = 'Almost there! 🔥';
          if (isGoalReached) motivationText = 'Daily goal reached! 🎉';
          if (isExceeded)    motivationText = 'Calorie limit exceeded! ⚠️';

          return GestureDetector(
            onTap: _goToStats,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 4))
                  ]),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    Row(children: [
                      const Text("Today's Progress",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E))),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: _blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6)),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.bar_chart_rounded,
                              size: 11,
                              color: _blue.withOpacity(0.7)),
                          const SizedBox(width: 3),
                          Text('View Stats',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _blue.withOpacity(0.7))),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text(motivationText,
                        style: TextStyle(
                            fontSize: 12,
                            color: isExceeded
                                ? Colors.red
                                : isGoalReached
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFF6E6E73))),
                    if (isExceeded) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.warning_rounded,
                            size: 13, color: Colors.red),
                        const SizedBox(width: 4),
                        const Flexible(
                          child: Text(
                            'You have exceeded your calorie limit!',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.red),
                          ),
                        ),
                      ]),
                    ] else if (isGoalReached) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 13, color: Color(0xFF34C759)),
                        const SizedBox(width: 4),
                        const Flexible(
                          child: Text(
                            'You\'ve reached your calorie goal for today!',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF34C759)),
                          ),
                        ),
                      ]),
                    ] else if (isNearLimit) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 13, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        const Flexible(
                          child: Text(
                            'Approaching your daily calorie limit!',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF59E0B)),
                          ),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 14),
                    Row(children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('$consumed',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _blue)),
                        const Text('Consumed',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6E6E73))),
                      ]),
                      Container(
                          height: 36,
                          width: 1,
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16),
                          color: const Color(0xFFE5E5EA)),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('$remaining',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF34C759))),
                        const Text('Remaining',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6E6E73))),
                      ]),
                    ]),
                  ])),
                  GestureDetector(
                    onTap: _goToStats,
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: CustomPaint(
                        painter: _MiniRingPainter(
                            progress: progress,
                            color: isExceeded
                                ? Colors.red
                                : isGoalReached
                                    ? const Color(0xFF34C759)
                                    : isNearLimit
                                        ? const Color(0xFFF59E0B)
                                        : _blue),
                        child: Center(
                            child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                          Text('$consumed',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1C1C1E))),
                          Text('of $goal',
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF6E6E73))),
                        ])),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF0F0F0)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                      _macroMini(
                          '💪',
                          tracker.consumedProtein > 0
                              ? '${protein.toStringAsFixed(1)}g'
                              : '—',
                          'Protein',
                          const Color(0xFF007AFF)),
                      _macroMini(
                          '🌾',
                          tracker.consumedCarbs > 0
                              ? '${carbs.toStringAsFixed(1)}g'
                              : '—',
                          'Carbs',
                          const Color(0xFF34C759)),
                      _macroMini(
                          '🥑',
                          tracker.consumedFat > 0
                              ? '${fat.toStringAsFixed(1)}g'
                              : '—',
                          'Fat',
                          const Color(0xFFFF9500)),
                    ]),
                  ),
                  GestureDetector(
                    onTap: _showManualLogSheet,
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: _blue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: _blue.withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ]),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _macroMini(
      String emoji, String value, String label, Color color) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 1),
      Text(value,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      Text(label,
          style: const TextStyle(
              fontSize: 9, color: Color(0xFF6E6E73))),
    ]);
  }

  // ── Header ──────────────────────────────────
  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 0),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(
              text: TextSpan(children: [
            const TextSpan(
                text: 'Food',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E))),
            TextSpan(
                text: 'Feast',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _blue)),
          ])),
          AnimatedBuilder(
            animation: LocationService.instance,
            builder: (_, __) {
              final svc     = LocationService.instance;
              final current = svc.current;
              final label   = current?.shortName ?? 'Set location';
              return GestureDetector(
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => LocationSheet(
                    onLocationSet: (loc) => setState(() {}),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    current != null
                        ? Icons.location_on_rounded
                        : Icons.location_searching_rounded,
                    color: _blue,
                    size: 14,
                  ),
                  const SizedBox(width: 3),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C1E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: current != null
                        ? const Color(0xFF1C1C1E)
                        : _blue,
                    size: 16,
                  ),
                ]),
              );
            },
          ),
        ]),
        Row(children: [
          AnimatedBuilder(
            animation: NotificationService.instance,
            builder: (_, __) {
              final count = NotificationService.instance.unreadCount;
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationScreen()),
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.07),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: const Icon(Icons.notifications_outlined,
                        color: Color(0xFF1C1C1E), size: 22),
                  ),
                  if (count > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        constraints: const BoxConstraints(
                            minWidth: 18, minHeight: 18),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                            color: _blue,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white, width: 1.5)),
                        child: Center(
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                ]),
              );
            },
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _goToTab(4),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _blue.withOpacity(0.15),
                  boxShadow: [
                    BoxShadow(
                        color: _blue.withOpacity(0.2),
                        blurRadius: 6)
                  ]),
              child: ClipOval(
                child: _photoUrl.isNotEmpty
                    ? Image.network(_photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(_userInitials,
                                style: TextStyle(
                                    color: _blue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13))))
                    : Center(
                        child: Text(_userInitials,
                            style: TextStyle(
                                color: _blue,
                                fontWeight: FontWeight.w700,
                                fontSize: 13))),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Categories ──────────────────────────────
  Widget _buildCategories() {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _categoryIcons.length,
        itemBuilder: (_, i) {
          final cat        = _categoryIcons[i];
          final isSelected = _selectedCategory == cat['label'];
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat['label']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              child: Column(children: [
                // ── Square tile ────────────────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? _blue : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: _blue.withOpacity(0.35),
                              blurRadius: 10,
                              spreadRadius: 1,
                            )
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 6,
                            )
                          ],
                  ),
                  child: AnimatedScale(
                    scale: isSelected ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            cat['image']!,
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: _blue.withOpacity(0.08),
                              child: Icon(
                                Icons.fastfood_rounded,
                                size: 26,
                                color: isSelected ? Colors.white : _blue,
                              ),
                            ),
                          ),
                          // Blue tint overlay when selected
                          if (isSelected)
                            Container(
                              color: _blue.withOpacity(0.22),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // ── Label ──────────────────────────────────────────────────
                Text(
                  cat['label']!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? _blue : const Color(0xFF6E6E73),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Food Items Grid ─────────────────────────
  // FIX: Pass _popularItemsRefreshKey as part of the ValueKey so the
  // loader widget is only replaced (and re-fetches) when the user
  // explicitly taps Refresh — NOT on every tab switch.
  Widget _buildFoodItemsGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator(color: _blue)),
            ),
          );
        }
        final allDocs = snapshot.data?.docs ?? [];
        if (allDocs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return AnimatedBuilder(
          animation: LocationService.instance,
          builder: (_, __) {
            final nearbyDocs = filterNearbyRestaurants(allDocs);
            if (nearbyDocs.isEmpty) {
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }
            return SliverToBoxAdapter(
              child: _FoodItemsGridLoader(
                // KEY CHANGE: embedding refreshKey means Flutter replaces
                // the widget (and triggers initState) only when the user
                // taps Refresh. Tab switches do NOT change this key.
                key: ValueKey('${_selectedCategory}_$_popularItemsRefreshKey'),
                restaurantDocs: nearbyDocs,
                selectedCategory: _selectedCategory,
              ),
            );
          },
        );
      },
    );
  }

  // ── Restaurant list ─────────────────────────
  Widget _buildRestaurantList() {
    final stream = _selectedCategory == 'All'
        ? FirebaseFirestore.instance
            .collection('restaurants')
            .snapshots()
        : FirebaseFirestore.instance
            .collection('restaurants')
            .where('categories', arrayContains: _selectedCategory)
            .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverToBoxAdapter(
              child: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: _blue))));
        }

        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Color(0xFFAEAEB2), size: 48),
                  const SizedBox(height: 12),
                  const Text('Could not load restaurants',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6E6E73))),
                  const SizedBox(height: 6),
                  Text('${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFAEAEB2))),
                ]),
              ),
            ),
          );
        }

        final allDocs = <QueryDocumentSnapshot>[...?snapshot.data?.docs];

        return AnimatedBuilder(
          animation: LocationService.instance,
          builder: (_, __) {
            final docs = filterNearbyRestaurants(allDocs);

            docs.sort((a, b) {
              final rA = ((a.data() as Map)['rating'] ?? 0.0) as num;
              final rB = ((b.data() as Map)['rating'] ?? 0.0) as num;
              return rB.compareTo(rA);
            });

            if (docs.isEmpty) {
              final userHasLocation = LocationService.instance.current != null;
              return SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(children: [
                      Text(
                        userHasLocation ? '📍' : '🍽️',
                        style: const TextStyle(fontSize: 48),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        userHasLocation
                            ? 'No restaurants within ${kDefaultRadiusKm.toStringAsFixed(0)} km'
                            : 'No restaurants found',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6E6E73)),
                      ),
                      if (userHasLocation) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'We\'re expanding! Check back soon.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFFAEAEB2)),
                        ),
                      ],
                    ]),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final doc  = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final distKm = distanceToRestaurant(data);
                  final locMap = data['location'] as Map<String, dynamic>?;
                  final shortAddr = (locMap?['shortName'] as String?) ?? '';
                  return _RestaurantCard(
                    id:           doc.id,
                    name:         data['name'] ?? 'Restaurant',
                    cuisine:      (data['categories'] as List?)?.join(', ') ?? '',
                    rating:       (data['rating'] ?? 4.0).toDouble(),
                    deliveryTime: data['deliveryTime'] ?? '30 min',
                    imageUrl:     data['imageUrl'] ?? '',
                    isPromoted:   data['isPromoted'] ?? false,
                    isActive:     data['isActive'] ?? true,
                    distanceKm:   distKm,
                    shortAddress: shortAddr,
                    onTap: () => _openRestaurant(
                        doc.id, data['name'] ?? '', data['imageUrl'] ?? ''),
                  );
                },
                childCount: docs.length,
              ),
            );
          },
        );
      },
    );
  }
}
// _LiquidNavBar — fully isolated spring widget
// ─────────────────────────────────────────────
class _LiquidNavBar extends StatefulWidget {
  final int selectedIndex;
  final List<GlobalKey> navKeys;
  final ValueChanged<int> onTabSelected;

  const _LiquidNavBar({
    required this.selectedIndex,
    required this.navKeys,
    required this.onTabSelected,
  });

  @override
  State<_LiquidNavBar> createState() => _LiquidNavBarState();
}

class _LiquidNavBarState extends State<_LiquidNavBar>
    with SingleTickerProviderStateMixin {

  final _springLeft  = _Spring(stiffness: 320, damping: 28, mass: 1.0);
  final _springWidth = _Spring(stiffness: 260, damping: 24, mass: 1.0);

  Ticker? _ticker;
  Duration _lastTick  = Duration.zero;
  bool _initialized   = false;
  bool _isDragging    = false;
  int  _dragIndex     = 0;

  static const _icons  = [
    Icons.home_rounded,
    Icons.shopping_cart_outlined,
    Icons.inventory_2_outlined,
    Icons.bar_chart_rounded,
    Icons.person_outline_rounded,
  ];
  static const _labels = ['Home', 'Cart', 'Bundle', 'Stats', 'Profile'];

  @override
  void initState() {
    super.initState();
    _dragIndex = widget.selectedIndex;
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBlob());
  }

  @override
  void didUpdateWidget(_LiquidNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _animateTo(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_lastTick == Duration.zero) { _lastTick = elapsed; return; }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final mL = _springLeft.tick(dt);
    final mW = _springWidth.tick(dt);
    if (mL || mW) setState(() {});
  }

  void _initBlob() {
    final rect = _tabRect(widget.selectedIndex);
    if (rect == null) return;
    _springLeft.snapTo(rect.left);
    _springWidth.snapTo(rect.width);
    setState(() => _initialized = true);
  }

  void _animateTo(int index, {bool instant = false}) {
    final rect = _tabRect(index);
    if (rect == null) return;
    if (instant) {
      _springLeft.snapTo(rect.left);
      _springWidth.snapTo(rect.width);
    } else {
      final dir = (rect.left > _springLeft.position) ? 1.0 : -1.0;
      _springLeft.target  = rect.left;
      _springWidth.target = rect.width;
      _springWidth.velocity += dir * 14;
    }
  }

  Rect? _tabRect(int index) {
    final key = widget.navKeys[index];
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final navBox = _navBox();
    if (navBox == null) return null;
    final offset = box.localToGlobal(Offset.zero, ancestor: navBox);
    return offset & box.size;
  }

  RenderBox? _navBox() {
    RenderObject? node =
        widget.navKeys[0].currentContext?.findRenderObject();
    while (node != null) {
      if (node is RenderBox && node.size.width > 200) return node;
      node = node.parent as RenderObject?;
    }
    return null;
  }

  void _blobFromGlobalX(double globalX) {
    final nb = _navBox();
    if (nb == null) return;
    final origin = nb.localToGlobal(Offset.zero);
    final frac   = ((globalX - origin.dx) / nb.size.width).clamp(0.0, 1.0);
    final idx    = (frac * 5).floor().clamp(0, 4);
    final rect   = _tabRect(idx);
    if (rect == null) return;
    _springLeft.target   = rect.left;
    _springWidth.target  = rect.width;
    _springLeft.velocity += (_springLeft.target - _springLeft.position) * 0.55;
    if (idx != _dragIndex) setState(() => _dragIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CartProvider.instance,
      builder: (context, _) {
        final cartCount = CartProvider.instance.totalItems;
        return Container(
          color: Colors.transparent,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              _isDragging = true;
              _dragIndex  = widget.selectedIndex;
              _springLeft.stiffness  = 560;
              _springWidth.stiffness = 440;
              _springLeft.damping    = 38;
              _springWidth.damping   = 34;
              _blobFromGlobalX(d.globalPosition.dx);
            },
            onHorizontalDragUpdate: (d) => _blobFromGlobalX(d.globalPosition.dx),
            onHorizontalDragEnd: (d) {
              _isDragging = false;
              _springLeft.stiffness  = 320;
              _springWidth.stiffness = 260;
              _springLeft.damping    = 28;
              _springWidth.damping   = 24;
              _springLeft.velocity  += d.velocity.pixelsPerSecond.dx * 0.022;
              widget.onTabSelected(_dragIndex);
            },
            onHorizontalDragCancel: () {
              _isDragging = false;
              _springLeft.stiffness  = 320;
              _springWidth.stiffness = 260;
              _springLeft.damping    = 28;
              _springWidth.damping   = 24;
              _animateTo(widget.selectedIndex);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                  height: 66,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.22),
                        Colors.white.withOpacity(0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.36),
                      width: 0.9,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.16),
                        blurRadius: 24,
                        spreadRadius: -2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        top: 0, left: 40, right: 40, height: 0.8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.85),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),

                      if (_initialized)
                        Positioned(
                          left:   _springLeft.position,
                          top:    7,
                          bottom: 7,
                          width:  _springWidth.position.clamp(48.0, 200.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withOpacity(0.90),
                                  Colors.white.withOpacity(0.62),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 8,
                                  spreadRadius: -1,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: FractionallySizedBox(
                                  widthFactor: 0.55,
                                  child: Container(
                                    height: 0.8,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          Colors.white,
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      Row(
                        children: List.generate(5, (i) => _navItem(i, cartCount)),
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _navItem(int index, int cartCount) {
    final isActive  = widget.selectedIndex == index;
    final isHovered = _isDragging && _dragIndex == index;
    final showBadge = index == 1 && cartCount > 0;

    final Color iconColor = isActive
        ? const Color(0xFF1A1A1E)
        : isHovered
            ? Colors.white.withOpacity(0.96)
            : Colors.white.withOpacity(0.52);

    final Color labelColor = isActive
        ? const Color(0xFF1A1A1E)
        : isHovered
            ? Colors.white.withOpacity(0.90)
            : Colors.white.withOpacity(0.46);

    return Expanded(
      child: GestureDetector(
        key: widget.navKeys[index],
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTabSelected(index),
        child: SizedBox(
          height: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: isActive ? 1.08 : 1.0,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    child: Icon(_icons[index], size: 22, color: iconColor),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: labelColor,
                      letterSpacing: 0.2,
                    ),
                    child: Text(_labels[index]),
                  ),
                ],
              ),
              if (showBadge)
                Positioned(
                  top: 7,
                  right: 5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3B30).withOpacity(0.40),
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

// ─────────────────────────────────────────────
// Manual Log Sheet
// ─────────────────────────────────────────────
class _ManualLogSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _ManualLogSheet({required this.onSaved});
  @override
  State<_ManualLogSheet> createState() => _ManualLogSheetState();
}

class _ManualLogSheetState extends State<_ManualLogSheet> {
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);
  static const _sky   = Color(0xFF007AFF);

  final _labelCtrl    = TextEditingController(text: 'Home food');
  final _caloriesCtrl = TextEditingController();
  final _proteinCtrl  = TextEditingController();
  final _carbsCtrl    = TextEditingController();
  final _fatCtrl      = TextEditingController();

  bool _showMacros = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _caloriesCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cal = int.tryParse(_caloriesCtrl.text.trim());
    if (cal == null || cal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid calorie amount'),
          backgroundColor: _blue,
          behavior: SnackBarBehavior.floating));
      return;
    }

    final protein = double.tryParse(_proteinCtrl.text.trim()) ?? 0;
    final carbs   = double.tryParse(_carbsCtrl.text.trim())   ?? 0;
    final fat     = double.tryParse(_fatCtrl.text.trim())     ?? 0;
    final label   = _labelCtrl.text.trim().isEmpty
        ? 'Home food'
        : _labelCtrl.text.trim();

    // ── 1. Update tracker in-memory instantly so the home screen
    //       ring/numbers refresh immediately with no waiting. ──────
    CalorieTracker.instance.editTodayNutritionLocally(
      calories: CalorieTracker.instance.consumedCalories + cal,
      protein:  CalorieTracker.instance.consumedProtein  + protein,
      carbs:    CalorieTracker.instance.consumedCarbs    + carbs,
      fat:      CalorieTracker.instance.consumedFat      + fat,
    );

    // ── 2. Pop the sheet and show the success snackbar right away ──
    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();

      // Build a rich message showing what was logged
      final macroStr = (protein > 0 || carbs > 0 || fat > 0)
          ? ' • ${protein.toStringAsFixed(0)}g P  '
            '${carbs.toStringAsFixed(0)}g C  '
            '${fat.toStringAsFixed(0)}g F'
          : '';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Text('🔥', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Home food logged  +$cal kcal$macroStr',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    }

    // ── 3. Persist to Firestore in the background (no spinner) ─────
    // NOTE: we do NOT call addManualLog here because _addNutrition
    // inside it would add the values a second time. The in-memory
    // totals were already updated in step 1 via editTodayNutritionLocally.
    // We only need the Firestore write here.
    CalorieTracker.instance.persistManualLogOnly(
      calories: cal,
      protein:  protein,
      carbs:    carbs,
      fat:      fat,
      label:    label,
    ).catchError((e) {
      debugPrint('_ManualLogSheet background save error: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: _blue.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.add_circle_outline_rounded,
                      color: _blue, size: 20)),
              const SizedBox(width: 12),
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Log Home Food',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E))),
                Text('Track what you eat outside the app',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF6E6E73))),
              ]),
            ]),
            const SizedBox(height: 20),
            _inputField(_labelCtrl, 'Description (optional)',
                Icons.label_outline_rounded, null),
            const SizedBox(height: 12),
            _inputField(
              _caloriesCtrl,
              'Calories (kcal) *',
              Icons.local_fire_department_rounded,
              TextInputType.number,
              color: _blue,
              hint: 'e.g. 350',
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _showMacros = !_showMacros),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: _showMacros
                        ? _sky.withOpacity(0.06)
                        : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _showMacros
                            ? _sky.withOpacity(0.3)
                            : const Color(0xFFE5E5EA))),
                child: Row(children: [
                  Icon(Icons.science_outlined,
                      size: 18,
                      color: _showMacros
                          ? _sky
                          : const Color(0xFF6E6E73)),
                  const SizedBox(width: 10),
                  Text(
                      _showMacros
                          ? 'Hide Macros (optional)'
                          : 'Add Macros — Protein / Carbs / Fat (optional)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _showMacros
                              ? _sky
                              : const Color(0xFF6E6E73))),
                  const Spacer(),
                  Icon(
                      _showMacros
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _showMacros
                          ? _sky
                          : const Color(0xFF6E6E73),
                      size: 20),
                ]),
              ),
            ),
            if (_showMacros) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _macroField(
                        _proteinCtrl, '💪 Protein (g)', _sky)),
                const SizedBox(width: 8),
                Expanded(
                    child: _macroField(
                        _carbsCtrl, '🌾 Carbs (g)', _green)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        _macroField(_fatCtrl, '🥑 Fat (g)', _orng)),
              ]),
            ],
            const SizedBox(height: 24),
            const Text('Quick Add',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6E6E73))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _preset('☕ Tea/Coffee', 30),
              _preset('🍎 Fruit', 80),
              _preset('🥗 Salad', 150),
              _preset('🍚 Rice bowl', 300),
              _preset('🥛 Milk', 120),
              _preset('🥜 Snack', 200),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
                onPressed: _save,
                child: const Text('Log Food',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _preset(String label, int kcal) {
    return GestureDetector(
      onTap: () =>
          setState(() => _caloriesCtrl.text = kcal.toString()),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E5EA)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6)
            ]),
        child: Text('$label  $kcal kcal',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E))),
      ),
    );
  }

  Widget _inputField(
    TextEditingController ctrl,
    String label,
    IconData icon,
    TextInputType? type, {
    Color color = const Color(0xFF6E6E73),
    String? hint,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle:
              TextStyle(fontSize: 13, color: color.withOpacity(0.8)),
          prefixIcon: Icon(icon, size: 20, color: color),
          filled: true,
          fillColor: const Color(0xFFF7F7F7),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E5EA))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E5EA))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 13, horizontal: 13)),
    );
  }

  Widget _macroField(
      TextEditingController ctrl, String label, Color color) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 11, color: color),
          filled: true,
          fillColor: color.withOpacity(0.05),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: color.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: color.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 10, horizontal: 10)),
    );
  }
}

// ─────────────────────────────────────────────
// Filter sheet
// ─────────────────────────────────────────────
class _FilterSheet extends StatefulWidget {
  final FoodFilter current;
  final ValueChanged<FoodFilter> onApply;
  const _FilterSheet({required this.current, required this.onApply});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SortOption _sort;
  late bool _vegOnly;
  late int? _maxCalories;
  static const _blue = Color(0xFF0077B6);

  @override
  void initState() {
    super.initState();
    _sort        = widget.current.sort;
    _vegOnly     = widget.current.vegOnly;
    _maxCalories = widget.current.maxCalories;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          const Text('Filter & Sort',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          TextButton(
              onPressed: () => setState(() {
                    _sort        = SortOption.none;
                    _vegOnly     = false;
                    _maxCalories = null;
                  }),
              child: const Text('Reset',
                  style: TextStyle(
                      color: _blue, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 16),
        const Text('Sort by Price',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E))),
        const SizedBox(height: 10),
        Row(children: [
          _SortChip(
              label: '💰 Low → High',
              selected: _sort == SortOption.priceLow,
              onTap: () => setState(() => _sort =
                  _sort == SortOption.priceLow
                      ? SortOption.none
                      : SortOption.priceLow)),
          const SizedBox(width: 10),
          _SortChip(
              label: '💎 High → Low',
              selected: _sort == SortOption.priceHigh,
              onTap: () => setState(() => _sort =
                  _sort == SortOption.priceHigh
                      ? SortOption.none
                      : SortOption.priceHigh)),
        ]),
        const SizedBox(height: 16),
        const Text('Sort by Calories',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E))),
        const SizedBox(height: 10),
        Row(children: [
          _SortChip(
              label: '🥗 Lowest first',
              selected: _sort == SortOption.caloriesLow,
              onTap: () => setState(() => _sort =
                  _sort == SortOption.caloriesLow
                      ? SortOption.none
                      : SortOption.caloriesLow)),
          const SizedBox(width: 10),
          _SortChip(
              label: '🔥 Highest first',
              selected: _sort == SortOption.caloriesHigh,
              onTap: () => setState(() => _sort =
                  _sort == SortOption.caloriesHigh
                      ? SortOption.none
                      : SortOption.caloriesHigh)),
        ]),
        const SizedBox(height: 16),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          const Text('Max Calories',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E))),
          Text(
              _maxCalories != null
                  ? '≤ $_maxCalories kcal'
                  : 'Any',
              style: TextStyle(
                  fontSize: 13,
                  color: _maxCalories != null
                      ? _blue
                      : const Color(0xFF6E6E73),
                  fontWeight: FontWeight.w600)),
        ]),
        Slider(
            value: (_maxCalories ?? 1200).toDouble(),
            min: 100,
            max: 1200,
            divisions: 22,
            activeColor: _blue,
            inactiveColor: const Color(0xFFE5E5EA),
            onChanged: (v) =>
                setState(() => _maxCalories = v.round())),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          const Text('100 kcal',
              style: TextStyle(
                  fontSize: 11, color: Color(0xFF6E6E73))),
          if (_maxCalories != null)
            GestureDetector(
                onTap: () =>
                    setState(() => _maxCalories = null),
                child: const Text('Clear',
                    style: TextStyle(
                        fontSize: 11,
                        color: _blue,
                        fontWeight: FontWeight.w600))),
          const Text('1200 kcal',
              style: TextStyle(
                  fontSize: 11, color: Color(0xFF6E6E73))),
        ]),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => setState(() => _vegOnly = !_vegOnly),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: _vegOnly
                    ? const Color(0xFF34C759).withOpacity(0.08)
                    : const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _vegOnly
                        ? const Color(0xFF34C759)
                        : const Color(0xFFE5E5EA),
                    width: 1.5)),
            child: Row(children: [
              Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: const Color(0xFF34C759),
                          width: 2),
                      borderRadius: BorderRadius.circular(3)),
                  child: _vegOnly
                      ? Center(
                          child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle)))
                      : null),
              const SizedBox(width: 12),
              const Text('Veg Only 🌿',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E))),
              const Spacer(),
              if (_vegOnly)
                const Text('ON',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF34C759))),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0),
            onPressed: () => widget.onApply(FoodFilter(
                sort: _sort,
                vegOnly: _vegOnly,
                maxCalories: _maxCalories)),
            child: const Text('Apply Filters',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  static const _blue = Color(0xFF0077B6);
  const _SortChip(
      {required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
            color: selected ? _blue : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? _blue : const Color(0xFFE5E5EA),
                width: 1.5)),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : const Color(0xFF1C1C1E))),
      ),
    );
  }
}
// ─────────────────────────────────────────────
// Food search delegate
// ─────────────────────────────────────────────
class _RestaurantMatch {
  final String id, name, cuisine, deliveryTime, imageUrl;
  final double rating;
  final bool isActive;
  final double? distanceKm;
  final String shortAddress;
  const _RestaurantMatch({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.deliveryTime,
    required this.imageUrl,
    required this.rating,
    required this.isActive,
    this.distanceKm,
    this.shortAddress = '',
  });
}

class _SearchData {
  final List<_RestaurantMatch> restaurants;
  final List<FoodSearchResult> items;
  const _SearchData(this.restaurants, this.items);
}

class _FoodItemSearchDelegate extends SearchDelegate<String> {
  static const _blue = Color(0xFF0077B6);
  FoodFilter _filter;
  _FoodItemSearchDelegate(
      {FoodFilter initialFilter = const FoodFilter()})
      : _filter = initialFilter;

  @override
  String get searchFieldLabel => 'Search dishes, food items...';

  @override
  ThemeData appBarTheme(BuildContext context) =>
      Theme.of(context).copyWith(
        appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white, elevation: 0),
        inputDecorationTheme:
            const InputDecorationTheme(border: InputBorder.none),
      );

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.clear_rounded,
                  color: Color(0xFF6E6E73)),
              onPressed: () => query = ''),
        StatefulBuilder(
          builder: (ctx, setS) =>
              Stack(alignment: Alignment.topRight, children: [
            IconButton(
              icon: const Icon(Icons.tune_rounded,
                  color: Color(0xFF1C1C1E)),
              onPressed: () async {
                await showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _FilterSheet(
                    current: _filter,
                    onApply: (f) {
                      _filter = f;
                      Navigator.pop(ctx);
                      final current = query;
                      query = '';
                      query = current.isEmpty ? ' ' : current;
                      if (current.isEmpty) {
                        Future.microtask(() => query = '');
                      }
                      setS(() {});
                    },
                  ),
                );
              },
            ),
            if (_filter.isActive)
              Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: _blue,
                          shape: BoxShape.circle))),
          ]),
        ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
      icon: const Icon(Icons.arrow_back_rounded,
          color: Color(0xFF1C1C1E)),
      onPressed: () => close(context, ''));

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) =>
      _buildBody(context);

  Widget _buildBody(BuildContext context) {
    // When query is empty and no filter, run the search with empty string
    // so ALL food items are shown (q.isEmpty path in _searchFoodItems already
    // matches every item via `matchesQuery = q.isEmpty || ...`).
    // We only show the placeholder if the data is still loading.

    return AnimatedBuilder(
      animation: LocationService.instance,
      builder: (_, __) => FutureBuilder<_SearchData>(
      future: _searchFoodItems(query.trim().toLowerCase()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _blue));
        }

        final data = snapshot.data ?? const _SearchData([], []);
        final restaurants = data.restaurants;
        final results = data.items;

        if (restaurants.isEmpty && results.isEmpty) {
          // For empty query this shouldn't happen unless there's truly no data
          if (query.trim().isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🍔', style: TextStyle(fontSize: 52)),
                  SizedBox(height: 12),
                  Text('No food items found',
                      style: TextStyle(
                          fontSize: 15, color: Color(0xFF6E6E73))),
                ],
              ),
            );
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('😕',
                    style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('No results for "$query"',
                    style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF6E6E73))),
                const SizedBox(height: 6),
                const Text('Try different keywords',
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFAEAEB2))),
              ],
            ),
          );
        }

        return Column(
          children: [
            if (_filter.isActive) _buildActiveFilterBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (restaurants.isNotEmpty) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Row(children: [
                        const Text('🏪 Restaurants',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _blue.withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: Text('${restaurants.length}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _blue)),
                        ),
                      ]),
                    ),
                    ...restaurants.map((r) =>
                        _RestaurantSearchCard(
                          result: r,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  RestaurantDetailScreen(
                                restaurantId: r.id,
                                restaurantName: r.name,
                                restaurantImageUrl: r.imageUrl,
                              ),
                            ),
                          ),
                        )),
                    const SizedBox(height: 8),
                  ],
                  if (results.isNotEmpty) ...[
                    if (restaurants.isNotEmpty || query.trim().isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Row(children: [
                          const Text('🍽️ Dishes',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _blue.withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Text('${results.length}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _blue)),
                          ),
                        ]),
                      ),
                    ...results
                        .map((r) => _FoodResultTile(result: r)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      ),
    );
  }

  Widget _buildActiveFilterBar() {
    final chips = <String>[];
    if (_filter.vegOnly) chips.add('🌿 Veg only');
    if (_filter.sort == SortOption.priceLow)
      chips.add('💰 Price: Low→High');
    if (_filter.sort == SortOption.priceHigh)
      chips.add('💎 Price: High→Low');
    if (_filter.sort == SortOption.caloriesLow)
      chips.add('🥗 Cal: Lowest first');
    if (_filter.sort == SortOption.caloriesHigh)
      chips.add('🔥 Cal: Highest first');
    if (_filter.maxCalories != null)
      chips.add('≤ ${_filter.maxCalories} kcal');
    return Container(
      height: 40,
      color: const Color(0xFFF7F7F7),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: chips
            .map((c) => Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                      color: _blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _blue.withOpacity(0.3))),
                  child: Text(c,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _blue,
                          fontWeight: FontWeight.w600)),
                ))
            .toList(),
      ),
    );
  }

  Future<_SearchData> _searchFoodItems(String q) async {
    final restaurantsSnap = await FirebaseFirestore.instance
        .collection('restaurants')
        .get();
    final List<_RestaurantMatch> matchedRestaurants = [];
    final List<FoodSearchResult> results = [];

    for (final restDoc in restaurantsSnap.docs) {
      final restData     = restDoc.data();

      if (!isRestaurantNearby(restData)) continue;

      final restName     = (restData['name'] ?? '').toString();
      final isRestActive = restData['isActive'] ?? true;

      if (q.isNotEmpty &&
          restName.toLowerCase().contains(q)) {
        matchedRestaurants.add(_RestaurantMatch(
          id:           restDoc.id,
          name:         restName,
          cuisine:      restData['cuisine'] ?? '',
          deliveryTime: restData['deliveryTime'] ?? '30–40 min',
          imageUrl:     restData['imageUrl'] ?? '',
          rating:       (restData['rating'] ?? 0.0).toDouble(),
          isActive:     isRestActive,
          distanceKm:   distanceToRestaurant(restData),
          shortAddress: (restData['location'] as Map<String, dynamic>?)?['shortName'] as String? ?? '',
        ));
      }

      final menuSnap = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restDoc.id)
          .collection('menuItems')
          .get();
      for (final itemDoc in menuSnap.docs) {
        final item        = itemDoc.data();
        final itemName    = (item['name'] ?? '').toString().toLowerCase();
        final description = (item['description'] ?? '').toString().toLowerCase();
        final category    = (item['category'] ?? '').toString().toLowerCase();
        final matchesQuery = q.isEmpty ||
            itemName.contains(q) ||
            description.contains(q) ||
            category.contains(q);
        if (!matchesQuery) continue;
        final isVeg       = item['isVeg'] ?? false;
        final isItemAvail = item['isAvailable'] ?? true;
        final calories    = (item['calories'] ?? 0) as int;
        final price       = (item['price'] ?? 0).toDouble();
        final protein     = (item['protein'] ?? 0).toDouble();
        final carbs       = (item['carbs'] ?? 0).toDouble();
        final fat         = (item['fat'] ?? 0).toDouble();
        if (_filter.vegOnly && !isVeg) continue;
        if (_filter.maxCalories != null &&
            calories > _filter.maxCalories! &&
            isItemAvail &&
            isRestActive) continue;
        final Map<String, double> portionPrices = {};
        final qp = item['quarterPrice'];
        final hp = item['halfPrice'];
        final fp = item['fullPrice'];
        if (qp != null && (qp as num) > 0)
          portionPrices['quarter'] = (qp as num).toDouble();
        if (hp != null && (hp as num) > 0)
          portionPrices['half'] = (hp as num).toDouble();
        if (fp != null && (fp as num) > 0)
          portionPrices['full'] = (fp as num).toDouble();
        final Map<String, PortionNutrition> portionNutrition = {};
        if (portionPrices.isNotEmpty) {
          portionNutrition['quarter'] = PortionNutrition(
              calories: (item['quarterCalories'] ?? 0) as int,
              protein: (item['quarterProtein'] ?? 0).toDouble(),
              carbs: (item['quarterCarbs'] ?? 0).toDouble(),
              fat: (item['quarterFat'] ?? 0).toDouble());
          portionNutrition['half'] = PortionNutrition(
              calories: (item['halfCalories'] ?? 0) as int,
              protein: (item['halfProtein'] ?? 0).toDouble(),
              carbs: (item['halfCarbs'] ?? 0).toDouble(),
              fat: (item['halfFat'] ?? 0).toDouble());
          portionNutrition['full'] = PortionNutrition(
              calories: (item['fullCalories'] ?? 0) as int,
              protein: (item['fullProtein'] ?? 0).toDouble(),
              carbs: (item['fullCarbs'] ?? 0).toDouble(),
              fat: (item['fullFat'] ?? 0).toDouble());
        }
        results.add(FoodSearchResult(
          itemName:          item['name'] ?? '',
          restaurantId:      restDoc.id,
          restaurantName:    restName,
          price:             price,
          isVeg:             isVeg,
          calories:          calories,
          protein:           protein,
          carbs:             carbs,
          fat:               fat,
          imageUrl:          item['imageUrl'] ?? '',
          description:       item['description'] ?? '',
          portionPrices:     portionPrices,
          portionNutrition:  portionNutrition,
          isItemAvailable:   isItemAvail,
          isRestaurantActive: isRestActive,
          distanceKm:        distanceToRestaurant(restData),
          restaurantAddress: (restData['location'] as Map<String, dynamic>?)?['shortName'] as String? ?? '',
        ));
      }
    }
    switch (_filter.sort) {
      case SortOption.priceLow:
        results.sort((a, b) => a.price.compareTo(b.price));
        break;
      case SortOption.priceHigh:
        results.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortOption.caloriesLow:
        results.sort((a, b) => a.calories.compareTo(b.calories));
        break;
      case SortOption.caloriesHigh:
        results.sort((a, b) => b.calories.compareTo(a.calories));
        break;
      case SortOption.none:
        break;
    }
    return _SearchData(matchedRestaurants, results);
  }
}

// ─────────────────────────────────────────────
// Food result tile
// ─────────────────────────────────────────────
class _FoodResultTile extends StatelessWidget {
  final FoodSearchResult result;
  static const _blue = Color(0xFF0077B6);
  const _FoodResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CartProvider.instance,
      builder: (_, __) {
        final cart       = CartProvider.instance;
        final qty        = cart.getQuantity(
            result.itemName, result.restaurantId);
        final hasPortions = result.portionPrices.isNotEmpty;
        final canOrder   = result.isRestaurantActive &&
            result.isItemAvailable;

        return Opacity(
          opacity: canOrder ? 1.0 : 0.75,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ]),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColorFiltered(
                    colorFilter: canOrder
                        ? const ColorFilter.mode(
                            Colors.transparent,
                            BlendMode.saturation)
                        : const ColorFilter.matrix(<double>[
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0, 0, 0, 1, 0,
                          ]),
                    child: result.imageUrl.isNotEmpty
                        ? Image.network(result.imageUrl,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _placeholder())
                        : _placeholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                  Row(children: [
                    Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: result.isVeg
                                    ? const Color(0xFF34C759)
                                    : _blue,
                                width: 1.5),
                            borderRadius:
                                BorderRadius.circular(2)),
                        child: Center(
                            child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: result.isVeg
                                        ? const Color(
                                            0xFF34C759)
                                        : _blue,
                                    shape:
                                        BoxShape.circle)))),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(result.itemName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: canOrder
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFF9E9E9E)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    StreamBuilder<double>(
                      stream: FavoritesRatingsService.instance
                          .itemAverageRatingStream(
                              result.restaurantId,
                              result.itemName),
                      builder: (_, snap) {
                        final avg = snap.data ?? 0.0;
                        if (avg <= 0)
                          return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759),
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Text(avg.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w700)),
                            const Icon(Icons.star_rounded,
                                color: Colors.white,
                                size: 10),
                          ]),
                        );
                      },
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.store_rounded,
                        size: 12, color: Color(0xFF6E6E73)),
                    const SizedBox(width: 3),
                    Flexible(
                        child: Text(result.restaurantName,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6E6E73)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    if (result.restaurantAddress.isNotEmpty || result.distanceKm != null) ...[
                      const SizedBox(width: 6),
                      const Text('•', style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2))),
                      const SizedBox(width: 4),
                      const Icon(Icons.location_on_rounded, size: 11, color: Color(0xFF0077B6)),
                      const SizedBox(width: 1),
                      if (result.restaurantAddress.isNotEmpty)
                        Flexible(child: Text(
                          result.restaurantAddress,
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF0077B6),
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )),
                      if (result.distanceKm != null) ...[
                        if (result.restaurantAddress.isNotEmpty)
                          const Text(' • ', style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2))),
                        Text(_fmtDistance(result.distanceKm!),
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF0077B6),
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ]),
                  const SizedBox(height: 4),
                  if (!result.isRestaurantActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFF9E9E9E)
                              .withOpacity(0.12),
                          borderRadius:
                              BorderRadius.circular(6)),
                      child: const Text(
                          'Restaurant Unavailable',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9E9E9E))),
                    )
                  else if (!result.isItemAvailable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: _blue.withOpacity(0.08),
                          borderRadius:
                              BorderRadius.circular(6),
                          border: Border.all(
                              color: _blue.withOpacity(0.25))),
                      child: const Text('Item Unavailable',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _blue)),
                    ),
                  const SizedBox(height: 3),
                  hasPortions
                      ? Text(
                          '₹${_minP(result.portionPrices).toStringAsFixed(0)} – ₹${_maxP(result.portionPrices).toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: canOrder
                                  ? _blue
                                  : const Color(0xFF9E9E9E)))
                      : Text(
                          '₹${result.price.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: canOrder
                                  ? _blue
                                  : const Color(0xFF9E9E9E))),
                ])),
                const SizedBox(width: 8),
                FavoriteHeartButton(
                  restaurantId:   result.restaurantId,
                  restaurantName: result.restaurantName,
                  itemName:       result.itemName,
                  imageUrl:       result.imageUrl,
                  isVeg:          result.isVeg,
                  price:          result.price,
                  size: 22,
                ),
                const SizedBox(width: 6),
                if (!canOrder)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text('N/A',
                        style: TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  )
                else if (qty == 0)
                  GestureDetector(
                    onTap: () => _addToCart(cart, context),
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: _blue,
                            borderRadius:
                                BorderRadius.circular(10)),
                        child: const Text('ADD',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight:
                                    FontWeight.w800))))
                else
                  Container(
                    decoration: BoxDecoration(
                        border:
                            Border.all(color: _blue, width: 1.5),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      InkWell(
                          onTap: () => cart.removeItem(
                              result.itemName,
                              result.restaurantId),
                          child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              child: Icon(
                                  Icons.remove_rounded,
                                  size: 16,
                                  color: _blue))),
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6),
                          child: Text('$qty',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1C1C1E)))),
                      InkWell(
                          onTap: () =>
                              _addToCart(cart, context),
                          child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              child: Icon(Icons.add_rounded,
                                  size: 16, color: _blue))),
                    ])),
              ]),
              if (!hasPortions &&
                  (result.calories > 0 || result.protein > 0)) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (result.calories > 0)
                    _chip('🔥', '${result.calories}kcal',
                        const Color(0xFFFF9500)),
                  if (result.protein > 0)
                    _chip(
                        '💪',
                        '${result.protein.toStringAsFixed(0)}g P',
                        const Color(0xFF007AFF)),
                  if (result.carbs > 0)
                    _chip(
                        '🌾',
                        '${result.carbs.toStringAsFixed(0)}g C',
                        const Color(0xFF34C759)),
                  if (result.fat > 0)
                    _chip(
                        '🥑',
                        '${result.fat.toStringAsFixed(0)}g F',
                        const Color(0xFFFF9500)),
                ]),
              ],
              if (hasPortions) ...[
                const SizedBox(height: 8),
                _portionNutrRow(result.portionNutrition),
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _portionNutrRow(Map<String, PortionNutrition> nutr) {
    const keys   = ['quarter', 'half', 'full'];
    const labels = ['¼', '½', 'Full'];
    final valid  = <int>[];
    for (int i = 0; i < keys.length; i++) {
      final n = nutr[keys[i]];
      if (n != null &&
          (result.portionPrices[keys[i]] ?? 0) > 0) valid.add(i);
    }
    if (valid.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF9F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE0B2))),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: valid.map((i) {
            final n = nutr[keys[i]]!;
            return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(labels[i],
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6E6E73))),
              if (n.calories > 0)
                Text('🔥${n.calories}',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFFF9500),
                        fontWeight: FontWeight.w700)),
              if (n.protein > 0)
                Text('P:${n.protein.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF007AFF))),
              if (n.carbs > 0)
                Text('C:${n.carbs.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF34C759))),
              if (n.fat > 0)
                Text('F:${n.fat.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF0077B6))),
            ]);
          }).toList()),
    );
  }

  Widget _chip(String e, String label, Color color) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Text('$e $label',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  double _minP(Map<String, double> p) {
    final v = p.values.where((x) => x > 0);
    return v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b);
  }

  double _maxP(Map<String, double> p) {
    final v = p.values.where((x) => x > 0);
    return v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
  }

  void _addToCart(CartProvider cart, BuildContext context) {
    if (result.portionPrices.isNotEmpty) {
      PortionSheet.show(
          context:        context,
          name:           result.itemName,
          restaurantId:   result.restaurantId,
          restaurantName: result.restaurantName,
          imageUrl:       result.imageUrl,
          isVeg:          result.isVeg,
          portionPrices:  result.portionPrices,
          portionNutrition: result.portionNutrition,
          cart:           cart);
      return;
    }
    cart.addItem(CartItem(
        name:           result.itemName,
        restaurantId:   result.restaurantId,
        restaurantName: result.restaurantName,
        price:          result.price,
        imageUrl:       result.imageUrl,
        isVeg:          result.isVeg,
        calories:       result.calories,
        protein:        result.protein,
        carbs:          result.carbs,
        fat:            result.fat));
  }

  Widget _placeholder() => Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
          color: _blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.fastfood_rounded,
          color: _blue, size: 30));
}

// ─────────────────────────────────────────────
// Favorite heart button
// ─────────────────────────────────────────────
class FavoriteHeartButton extends StatelessWidget {
  final String restaurantId, restaurantName, itemName, imageUrl;
  final bool isVeg;
  final double price, size;

  const FavoriteHeartButton({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.itemName,
    required this.imageUrl,
    required this.isVeg,
    required this.price,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final svc = FavoritesRatingsService.instance;
    return StreamBuilder<bool>(
      stream: svc.isFavoriteStream(restaurantId, itemName),
      builder: (context, snap) {
        final isFav = snap.data ?? false;
        return GestureDetector(
          onTap: () => svc.toggleFavorite(FavoriteItem(
            itemName:       itemName,
            restaurantId:   restaurantId,
            restaurantName: restaurantName,
            imageUrl:       imageUrl,
            isVeg:          isVeg,
            price:          price,
          )),
          child: Icon(
            isFav
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: isFav ? Colors.red : const Color(0xFFAEAEB2),
            size: size,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Restaurant search card
// ─────────────────────────────────────────────
class _RestaurantSearchCard extends StatelessWidget {
  final _RestaurantMatch result;
  final VoidCallback onTap;
  static const _blue = Color(0xFF0077B6);
  const _RestaurantSearchCard(
      {required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: result.isActive ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ]),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16)),
            child: ColorFiltered(
              colorFilter: result.isActive
                  ? const ColorFilter.mode(
                      Colors.transparent, BlendMode.saturation)
                  : const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0, 0, 0, 1, 0,
                    ]),
              child: SizedBox(
                width: 88,
                height: 80,
                child: result.imageUrl.isNotEmpty
                    ? Image.network(result.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            color: _blue.withOpacity(0.08),
                            child: const Center(
                                child: Icon(
                                    Icons.restaurant_rounded,
                                    size: 32,
                                    color: _blue))))
                    : Container(
                        color: _blue.withOpacity(0.08),
                        child: const Center(
                            child: Icon(Icons.restaurant_rounded,
                                size: 32, color: _blue))),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                    child: Text(result.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: result.isActive
                                ? const Color(0xFF1C1C1E)
                                : const Color(0xFF9E9E9E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (result.isActive && result.rating > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFF34C759),
                          borderRadius:
                              BorderRadius.circular(6)),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(result.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const Icon(Icons.star_rounded,
                            color: Colors.white, size: 10),
                      ]),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(result.cuisine,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6E6E73)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                if (!result.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: _blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text(
                        'Currently Unavailable',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _blue)),
                  )
                else
                  Row(children: [
                    const Icon(Icons.access_time_rounded,
                        size: 12, color: Color(0xFF6E6E73)),
                    const SizedBox(width: 3),
                    Text(_calcDeliveryTime(
                            deliveryTimeStr: result.deliveryTime,
                            distanceKm: result.distanceKm),
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF6E6E73))),
                    if (result.shortAddress.isNotEmpty || result.distanceKm != null) ...[
                      const SizedBox(width: 8),
                      const Text('•', style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2))),
                      const SizedBox(width: 6),
                      const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF0077B6)),
                      const SizedBox(width: 2),
                      if (result.shortAddress.isNotEmpty)
                        Flexible(child: Text(
                          result.shortAddress,
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF0077B6),
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )),
                      if (result.distanceKm != null) ...[
                        if (result.shortAddress.isNotEmpty)
                          const Text(' • ', style: TextStyle(fontSize: 10, color: Color(0xFFAEAEB2))),
                        Text(_fmtDistance(result.distanceKm!),
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF0077B6),
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 11, color: Color(0xFFAEAEB2)),
                    const SizedBox(width: 2),
                    const Text('View menu',
                        style: TextStyle(
                            fontSize: 11,
                            color: _blue,
                            fontWeight: FontWeight.w600)),
                  ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Mini ring painter
// ─────────────────────────────────────────────
class _MiniRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _MiniRingPainter(
      {required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        math.min(size.width, size.height) / 2 - 5;
    const strokeWidth = 7.0;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFFF0F0F0)
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    if (progress > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2,
          2 * math.pi * progress.clamp(0.0, 1.0),
          false,
          Paint()
            ..color = color
            ..strokeWidth = strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_MiniRingPainter old) =>
      old.progress != progress;
}

// ─────────────────────────────────────────────
// FoodItemsGridLoader — 2 random items per restaurant
//
// KEY FIX: The widget now accepts an explicit Key from the parent.
// The parent passes ValueKey('${category}_$refreshCounter').
// - Tab switches do NOT change this key → widget is reused → no re-fetch.
// - Category change OR Refresh tap changes the key → Flutter disposes
//   the old widget and creates a new one → initState runs → fresh fetch.
//
// The internal _lastFetchKey guard is kept as a secondary safety net
// for edge cases (e.g. hot-reload), but the key mechanism above is
// the primary fix.
// ─────────────────────────────────────────────
class _FoodItemsGridLoader extends StatefulWidget {
  final List<QueryDocumentSnapshot> restaurantDocs;
  final String selectedCategory;

  const _FoodItemsGridLoader({
    super.key, // ← accepts the ValueKey from parent
    required this.restaurantDocs,
    required this.selectedCategory,
  });

  @override
  State<_FoodItemsGridLoader> createState() => _FoodItemsGridLoaderState();
}

class _FoodItemsGridLoaderState extends State<_FoodItemsGridLoader> {
  // ── Static cache: survives tab switches and widget rebuilds ──────────
  // Key = '${category}|${restaurantIds}', Value = fetched items list.
  static final Map<String, List<_FoodGridItem>> _cache = {};

  List<_FoodGridItem> _items = [];
  bool _loading = true;

  // Secondary guard — only matters if key doesn't change but props do.
  String? _lastFetchKey;

  String _buildFetchKey() {
    final ids = widget.restaurantDocs.map((d) => d.id).join(',');
    return '${widget.selectedCategory}|$ids';
  }

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  @override
  void didUpdateWidget(_FoodItemsGridLoader old) {
    super.didUpdateWidget(old);
    // With the ValueKey approach the parent uses, this branch is only
    // reached when the widget is reused with genuinely changed props.
    final newKey = _buildFetchKey();
    if (_lastFetchKey != newKey) {
      _fetchItems();
    }
  }

  Future<void> _fetchItems() async {
    if (!mounted) return;

    final key = _buildFetchKey();

    // ── Serve from cache immediately (no flicker, no re-fetch) ──────────
    if (_cache.containsKey(key)) {
      if (mounted) {
        setState(() {
          _items = _cache[key]!;
          _loading = false;
          _lastFetchKey = key;
        });
      }
      return;
    }

    if (_lastFetchKey == key && _items.isNotEmpty) return;
    _lastFetchKey = key;

    setState(() => _loading = true);

    // Use a date-based seed so the same items are shown all day.
    // The seed only changes when the user taps Refresh (which clears
    // the cache and appends the refreshKey to the ValueKey, causing
    // a new widget with a fresh _sessionSeed to be created).
    final now = DateTime.now();
    final dateSeed = now.year * 10000 + now.month * 100 + now.day;
    final rng = math.Random(dateSeed + key.hashCode);
    final allItems = <_FoodGridItem>[];

    final futures = widget.restaurantDocs.take(8).map((rDoc) async {
      try {
        final data      = rDoc.data() as Map<String, dynamic>;
        final restName  = (data['name'] ?? 'Restaurant') as String;
        final restImg   = (data['imageUrl'] ?? '') as String;
        final restRating = (data['rating'] ?? 4.0).toDouble();
        final isActive  = data['isActive'] ?? true;

        QuerySnapshot menuSnap;
        if (widget.selectedCategory == 'All') {
          menuSnap = await FirebaseFirestore.instance
              .collection('restaurants')
              .doc(rDoc.id)
              .collection('menuItems')
              .limit(30)
              .get();
        } else {
          menuSnap = await FirebaseFirestore.instance
              .collection('restaurants')
              .doc(rDoc.id)
              .collection('menuItems')
              .where('category', isEqualTo: widget.selectedCategory)
              .limit(30)
              .get();
        }

        if (menuSnap.docs.isEmpty) return <_FoodGridItem>[];

        final shuffled = List.of(menuSnap.docs)..shuffle(rng);
        return shuffled.take(2).map((doc) {
          final m = doc.data() as Map<String, dynamic>;
          final portionsEnabled = m['portionsEnabled'] ?? false;
          final Map<String, double> portionPrices = portionsEnabled
              ? {
                  'quarter': (m['quarterPrice'] ?? 0).toDouble(),
                  'half':    (m['halfPrice']    ?? 0).toDouble(),
                  'full':    (m['fullPrice']     ?? 0).toDouble(),
                }
              : {};
          final Map<String, PortionNutrition> portionNutrition = portionsEnabled
              ? {
                  'quarter': PortionNutrition(
                    calories: (m['quarterCalories'] ?? 0) as int,
                    protein:  (m['quarterProtein'] ?? 0).toDouble(),
                    carbs:    (m['quarterCarbs']   ?? 0).toDouble(),
                    fat:      (m['quarterFat']     ?? 0).toDouble(),
                  ),
                  'half': PortionNutrition(
                    calories: (m['halfCalories'] ?? 0) as int,
                    protein:  (m['halfProtein']  ?? 0).toDouble(),
                    carbs:    (m['halfCarbs']    ?? 0).toDouble(),
                    fat:      (m['halfFat']      ?? 0).toDouble(),
                  ),
                  'full': PortionNutrition(
                    calories: (m['fullCalories'] ?? 0) as int,
                    protein:  (m['fullProtein']  ?? 0).toDouble(),
                    carbs:    (m['fullCarbs']    ?? 0).toDouble(),
                    fat:      (m['fullFat']      ?? 0).toDouble(),
                  ),
                }
              : {};
          return _FoodGridItem(
            restaurantId:      rDoc.id,
            restaurantName:    restName,
            restaurantImg:     restImg,
            itemName:          (m['name'] ?? m['itemName'] ?? 'Item') as String,
            imageUrl:          (m['imageUrl'] ?? '') as String,
            description:       (m['description'] ?? '') as String,
            price:             (m['price'] ?? 0).toDouble(),
            originalPrice:     (m['originalPrice'] ?? 0).toDouble(),
            rating:            restRating,
            isVeg:             m['isVeg'] ?? false,
            calories:          (m['calories'] ?? 0) as int,
            protein:           (m['protein'] ?? 0).toDouble(),
            carbs:             (m['carbs']   ?? 0).toDouble(),
            fat:               (m['fat']     ?? 0).toDouble(),
            portionsEnabled:   portionsEnabled as bool,
            portionPrices:     portionPrices,
            portionNutrition:  portionNutrition,
            isItemAvailable:   m['isAvailable'] ?? true,
            isRestaurantActive: isActive as bool,
          );
        }).toList();
      } catch (_) {
        return <_FoodGridItem>[];
      }
    }).toList();

    final results = await Future.wait(futures);
    final valid = results.expand((list) => list).toList()..shuffle(rng);

    if (mounted) {
      _cache[key] = valid; // ← persist so tab switches / rebuilds reuse data
      setState(() { _items = valid; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator(color: Color(0xFF0077B6))),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();

    const double cardHeight = 260;
    const double hPad = 16, hGap = 12;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: hPad),
      child: Wrap(
        spacing: hGap,
        runSpacing: hGap,
        children: _items.map((item) {
          final cardWidth =
              (MediaQuery.of(context).size.width - hPad * 2 - hGap) / 2;
          return SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: _FoodItemCard(item: item),
          );
        }).toList(),
      ),
    );
  }
}

class _FoodGridItem {
  final String restaurantId, restaurantName, restaurantImg;
  final String itemName, imageUrl, description;
  final double price, originalPrice, rating;
  final bool isVeg;
  final int calories;
  final double protein, carbs, fat;
  final bool portionsEnabled;
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;
  final bool isItemAvailable, isRestaurantActive;

  const _FoodGridItem({
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantImg,
    required this.itemName,
    required this.imageUrl,
    required this.description,
    required this.price,
    required this.originalPrice,
    required this.rating,
    required this.isVeg,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.portionsEnabled,
    required this.portionPrices,
    required this.portionNutrition,
    required this.isItemAvailable,
    required this.isRestaurantActive,
  });
}

// ─────────────────────────────────────────────
// Food item grid card
// ─────────────────────────────────────────────
class _FoodItemCard extends StatelessWidget {
  final _FoodGridItem item;
  const _FoodItemCard({required this.item});

  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);
  static const _vegGreen = Color(0xFF34C759);
  static const _nonVegRed = Color(0xFFE63946);

  bool get _canOrder => item.isItemAvailable && item.isRestaurantActive;

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemDetailSheet(
        name:               item.itemName,
        price:              item.price,
        originalPrice:      item.originalPrice,
        calories:           item.calories,
        protein:            item.protein,
        carbs:              item.carbs,
        fat:                item.fat,
        imageUrl:           item.imageUrl,
        description:        item.description,
        isVeg:              item.isVeg,
        portionsEnabled:    item.portionsEnabled,
        portionPrices:      item.portionPrices,
        portionNutrition:   item.portionNutrition,
        rating:             item.rating,
        canOrder:           _canOrder,
        isItemAvailable:    item.isItemAvailable,
        isRestaurantActive: item.isRestaurantActive,
        restaurantId:       item.restaurantId,
        restaurantName:     item.restaurantName,
        cart:               CartProvider.instance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 130,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                    child: item.imageUrl.isNotEmpty
                        ? Image.network(item.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imgPlaceholder())
                        : _imgPlaceholder(),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: item.isVeg ? _vegGreen : _nonVegRed,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: item.isVeg ? _vegGreen : _nonVegRed,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: FavoriteHeartButton(
                      restaurantId:   item.restaurantId,
                      restaurantName: item.restaurantName,
                      itemName:       item.itemName,
                      imageUrl:       item.imageUrl,
                      isVeg:          item.isVeg,
                      price:          item.price,
                      size:           20,
                    ),
                  ),
                  if (item.calories > 0)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.local_fire_department_rounded,
                              color: _orng, size: 10),
                          const SizedBox(width: 2),
                          Text('${item.calories} kcal',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              )),
                        ]),
                      ),
                    ),
                  if (!_canOrder)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                      child: Container(
                        color: Colors.black.withOpacity(0.45),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Unavailable',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.restaurantName,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF6E6E73)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (item.protein > 0 || item.carbs > 0 || item.fat > 0)
                      Row(children: [
                        if (item.protein > 0)
                          _nutrChip('P:${item.protein.toStringAsFixed(0)}g',
                              const Color(0xFF007AFF)),
                        if (item.carbs > 0) ...[
                          const SizedBox(width: 4),
                          _nutrChip('C:${item.carbs.toStringAsFixed(0)}g',
                              _green),
                        ],
                        if (item.fat > 0) ...[
                          const SizedBox(width: 4),
                          _nutrChip('F:${item.fat.toStringAsFixed(0)}g',
                              _orng),
                        ],
                      ]),
                    const Spacer(),
                    Row(
                      children: [
                        if (item.price > 0)
                          Text(
                            '₹${item.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _blue,
                            ),
                          ),
                        const Spacer(),
                        AnimatedBuilder(
                          animation: CartProvider.instance,
                          builder: (context, _) {
                            final cart = CartProvider.instance;
                            final qty = cart.getQuantity(
                                item.itemName, item.restaurantId);
                            if (!_canOrder) {
                              return const SizedBox.shrink();
                            }
                            if (qty == 0) {
                              return GestureDetector(
                                onTap: () {
                                  if (item.portionsEnabled) {
                                    _openDetail(context);
                                  } else {
                                    cart.addItem(CartItem(
                                      name:           item.itemName,
                                      restaurantId:   item.restaurantId,
                                      restaurantName: item.restaurantName,
                                      price:          item.price,
                                      imageUrl:       item.imageUrl,
                                      isVeg:          item.isVeg,
                                      calories:       item.calories,
                                      protein:        item.protein,
                                      carbs:          item.carbs,
                                      fat:            item.fat,
                                    ));
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: _blue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item.portionsEnabled ? 'SELECT' : 'ADD',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: _blue, width: 1.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                GestureDetector(
                                  onTap: () => cart.removeItem(
                                      item.itemName, item.restaurantId),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 4),
                                    child: Icon(Icons.remove_rounded,
                                        size: 14, color: _blue),
                                  ),
                                ),
                                Text('$qty',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1C1C1E))),
                                GestureDetector(
                                  onTap: () => cart.addItem(CartItem(
                                    name:           item.itemName,
                                    restaurantId:   item.restaurantId,
                                    restaurantName: item.restaurantName,
                                    price:          item.price,
                                    imageUrl:       item.imageUrl,
                                    isVeg:          item.isVeg,
                                    calories:       item.calories,
                                    protein:        item.protein,
                                    carbs:          item.carbs,
                                    fat:            item.fat,
                                  )),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 4),
                                    child: Icon(Icons.add_rounded,
                                        size: 14, color: _blue),
                                  ),
                                ),
                              ]),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFFFA500), size: 12),
                      const SizedBox(width: 2),
                      Text(item.rating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E))),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nutrChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _imgPlaceholder() => Container(
        color: _blue.withOpacity(0.08),
        child: const Center(
            child: Icon(Icons.fastfood_rounded, size: 40, color: _blue)),
      );
}

// ─────────────────────────────────────────────
// Item detail bottom sheet
// ─────────────────────────────────────────────
class _ItemDetailSheet extends StatelessWidget {
  final String name;
  final double price, originalPrice;
  final int calories;
  final double protein, carbs, fat;
  final String imageUrl, description;
  final bool isVeg, portionsEnabled;
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;
  final double rating;
  final bool canOrder, isItemAvailable, isRestaurantActive;
  final String restaurantId, restaurantName;
  final CartProvider cart;

  const _ItemDetailSheet({
    required this.name,
    required this.price,
    required this.originalPrice,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.imageUrl,
    required this.description,
    required this.isVeg,
    required this.portionsEnabled,
    required this.portionPrices,
    required this.portionNutrition,
    required this.rating,
    required this.canOrder,
    required this.isItemAvailable,
    required this.isRestaurantActive,
    required this.restaurantId,
    required this.restaurantName,
    required this.cart,
  });

  static const _red   = Color(0xFF0077B6);
  static const _blue  = Color(0xFF007AFF);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    final hasDiscount = originalPrice > 0 && originalPrice > price;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: ctrl,
          padding: EdgeInsets.zero,
          children: [
            Stack(children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: SizedBox(
                  height: 240,
                  width: double.infinity,
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imgPlaceholder())
                      : _imgPlaceholder(),
                ),
              ),
              const Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 40,
                    height: 4,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Colors.white54,
                            borderRadius:
                                BorderRadius.all(Radius.circular(2)))),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: isVeg ? _green : _red, width: 1.5),
                          borderRadius: BorderRadius.circular(2)),
                      child: Center(
                          child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                  color: isVeg ? _green : _red,
                                  shape: BoxShape.circle))),
                    ),
                    const SizedBox(width: 4),
                    Text(isVeg ? 'Veg' : 'Non-Veg',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isVeg ? _green : _red)),
                  ]),
                ),
              ),
              if (!canOrder)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24))),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3))),
                        child: Text(
                            !isRestaurantActive
                                ? 'Restaurant Unavailable'
                                : 'Item Unavailable',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
            ]),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1C1E))),
                  ),
                  const SizedBox(width: 12),
                  StreamBuilder<double>(
                    stream: FavoritesRatingsService.instance
                        .itemAverageRatingStream(restaurantId, name),
                    builder: (ctx, snap) {
                      final sv  = snap.data;
                      final avg = (sv != null && sv > 0) ? sv : rating;
                      return GestureDetector(
                        onTap: () async {
                          final hasOrdered = await FavoritesRatingsService
                              .instance
                              .hasOrderedFromRestaurant(restaurantId);
                          if (!ctx.mounted) return;
                          ReviewsSheet.showItem(
                            ctx,
                            restaurantId:   restaurantId,
                            itemName:       name,
                            restaurantName: restaurantName,
                            hasOrdered:     hasOrdered,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: _green,
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(avg.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(width: 3),
                            const Icon(Icons.star_rounded,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 3),
                            const Icon(Icons.chevron_right_rounded,
                                color: Colors.white70, size: 14),
                          ]),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 6),

                if (!portionsEnabled) ...[
                  Row(children: [
                    Text('₹${price.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _red)),
                    if (hasDiscount) ...[
                      const SizedBox(width: 8),
                      Text('₹${originalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFFAEAEB2),
                              decoration: TextDecoration.lineThrough)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE8F8EF),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(
                            '${(((originalPrice - price) / originalPrice) * 100).toStringAsFixed(0)}% OFF',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _green)),
                      ),
                    ],
                  ]),
                ],
                const SizedBox(height: 14),

                if (description.isNotEmpty) ...[
                  const Text('Description',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 6),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF6E6E73),
                          height: 1.5)),
                  const SizedBox(height: 16),
                ],

                if (calories > 0 || protein > 0 || carbs > 0 || fat > 0) ...[
                  const Text('Nutrition Info',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF9F0),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFFFE0B2))),
                    child: Column(children: [
                      if (calories > 0) ...[
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          const Icon(
                              Icons.local_fire_department_rounded,
                              color: _orng,
                              size: 16),
                          const SizedBox(width: 6),
                          Text('$calories kcal',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: _orng)),
                          const SizedBox(width: 5),
                          const Text('per serving',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6E6E73))),
                        ]),
                        const SizedBox(height: 12),
                      ],
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                        if (protein > 0)
                          _nutrPill('💪', 'Protein',
                              '${protein.toStringAsFixed(1)}g', _blue),
                        if (carbs > 0)
                          _nutrPill('🌾', 'Carbs',
                              '${carbs.toStringAsFixed(1)}g', _green),
                        if (fat > 0)
                          _nutrPill('🥑', 'Fat',
                              '${fat.toStringAsFixed(1)}g', _orng),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                if (portionsEnabled && portionPrices.isNotEmpty) ...[
                  const Text('Portion Sizes & Prices',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 10),
                  _PortionDetailTable(
                      portionPrices:    portionPrices,
                      portionNutrition: portionNutrition),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            canOrder ? _red : const Color(0xFFE5E5EA),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0),
                    onPressed: canOrder
                        ? () {
                            Navigator.pop(context);
                            if (portionsEnabled) {
                              PortionSheet.show(
                                context:          context,
                                name:             name,
                                restaurantId:     restaurantId,
                                restaurantName:   restaurantName,
                                imageUrl:         imageUrl,
                                isVeg:            isVeg,
                                portionPrices:    portionPrices,
                                portionNutrition: portionNutrition,
                                cart:             cart,
                              );
                            } else {
                              cart.addItem(CartItem(
                                name:           name,
                                restaurantId:   restaurantId,
                                restaurantName: restaurantName,
                                price:          price,
                                imageUrl:       imageUrl,
                                isVeg:          isVeg,
                                calories:       calories,
                                protein:        protein,
                                carbs:          carbs,
                                fat:            fat,
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                content: Text('$name added to cart 🛒'),
                                backgroundColor: _green,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ));
                            }
                          }
                        : null,
                    child: Text(
                        !canOrder
                            ? (!isRestaurantActive
                                ? 'Restaurant Unavailable'
                                : 'Item Unavailable')
                            : (portionsEnabled
                                ? 'Choose Portion & Add'
                                : 'Add to Cart — ₹${price.toStringAsFixed(0)}'),
                        style: TextStyle(
                            color: canOrder
                                ? Colors.white
                                : const Color(0xFF9E9E9E),
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nutrPill(String emoji, String label, String value, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color)),
      Text(label,
          style: const TextStyle(
              fontSize: 10.5, color: Color(0xFF6E6E73))),
    ]);
  }

  Widget _imgPlaceholder() => Container(
        color: _red.withOpacity(0.08),
        child: const Center(
            child: Icon(Icons.fastfood_rounded, color: _red, size: 60)),
      );
}

// ─────────────────────────────────────────────
// Portion detail table
// ─────────────────────────────────────────────
class _PortionDetailTable extends StatelessWidget {
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;

  static const _keys   = ['quarter', 'half', 'full'];
  static const _labels = ['🍗 Quarter', '🍖 Half', '🫕 Full'];
  static const _blue   = Color(0xFF007AFF);
  static const _green  = Color(0xFF34C759);
  static const _orng   = Color(0xFFFF9500);
  static const _red    = Color(0xFF0077B6);

  const _PortionDetailTable(
      {required this.portionPrices, required this.portionNutrition});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E5EA)),
          borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
              color: Color(0xFFF7F7F7),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(13))),
          child: const Row(children: [
            Expanded(
                flex: 2,
                child: Text('Portion',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
            Expanded(
                child: Text('Price',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
            Expanded(
                child: Text('Cal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
            Expanded(
                child: Text('P/C/F',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6E6E73)))),
          ]),
        ),
        ...List.generate(_keys.length, (i) {
          final key  = _keys[i];
          final p    = portionPrices[key] ?? 0;
          if (p <= 0) return const SizedBox.shrink();
          final nutr   = portionNutrition[key];
          final isLast = i == _keys.length - 1 ||
              (_keys.sublist(i + 1).every(
                  (k) => (portionPrices[k] ?? 0) <= 0));

          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFE5E5EA)))),
            child: Row(children: [
              Expanded(
                  flex: 2,
                  child: Text(_labels[i],
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C1E)))),
              Expanded(
                  child: Text('₹${p.toStringAsFixed(0)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _red))),
              Expanded(
                  child: Text(
                      nutr != null && nutr.calories > 0
                          ? '${nutr.calories}'
                          : '—',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _orng))),
              Expanded(
                  child: nutr != null &&
                          (nutr.protein > 0 ||
                              nutr.carbs > 0 ||
                              nutr.fat > 0)
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                              if (nutr.protein > 0)
                                _macroMini(
                                    'P:${nutr.protein.toStringAsFixed(0)}g',
                                    _blue),
                              if (nutr.carbs > 0)
                                _macroMini(
                                    'C:${nutr.carbs.toStringAsFixed(0)}g',
                                    _green),
                              if (nutr.fat > 0)
                                _macroMini(
                                    'F:${nutr.fat.toStringAsFixed(0)}g',
                                    _orng),
                            ])
                      : const Text('—',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9E9E9E)))),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _macroMini(String label, Color color) => Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color),
      );
}

// ─────────────────────────────────────────────
// Restaurant card
// ─────────────────────────────────────────────
class _RestaurantCard extends StatelessWidget {
  final String id, name, cuisine, deliveryTime, imageUrl;
  final double rating;
  final bool isPromoted, isActive;
  final VoidCallback onTap;
  final double? distanceKm;
  final String shortAddress;
  static const _blue = Color(0xFF0077B6);

  const _RestaurantCard({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.rating,
    required this.deliveryTime,
    required this.imageUrl,
    required this.isPromoted,
    required this.onTap,
    this.isActive = true,
    this.distanceKm,
    this.shortAddress = '',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isActive ? 1.0 : 0.72,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 20,
                    offset: const Offset(0, 4))
              ]),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
                child: ColorFiltered(
                  colorFilter: isActive
                      ? const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.saturation)
                      : const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: imageUrl.isNotEmpty
                          ? Image.network(imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _placeholder())
                          : _placeholder()),
                ),
              ),
              if (!isActive)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18)),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.72),
                          borderRadius:
                              BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  Colors.white.withOpacity(0.3)),
                        ),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.store_outlined,
                              color: Colors.white70, size: 15),
                          SizedBox(width: 6),
                          Text('Currently Unavailable',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight:
                                      FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ),
                ),
              if (isPromoted)
                Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(6)),
                        child: const Text('Promoted',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    Color(0xFF6E6E73))))),
              Positioned(
                bottom: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () async {
                    final hasOrdered =
                        await FavoritesRatingsService.instance
                            .hasOrderedFromRestaurant(id);
                    if (!context.mounted) return;
                    ReviewsSheet.showRestaurant(
                      context,
                      restaurantId:   id,
                      restaurantName: name,
                      hasOrdered:     hasOrdered,
                    );
                  },
                  child: StreamBuilder<double>(
                    stream: FavoritesRatingsService.instance
                        .restaurantAverageRatingStream(id),
                    builder: (_, snap) {
                      final snapVal = snap.data;
                      final avg = (snapVal != null &&
                              snapVal > 0)
                          ? snapVal
                          : rating;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: const Color(0xFF34C759),
                            borderRadius:
                                BorderRadius.circular(8)),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(avg.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight:
                                      FontWeight.w700)),
                          const Icon(Icons.star_rounded,
                              color: Colors.white,
                              size: 12),
                        ]),
                      );
                    },
                  ),
                ),
              ),
            ]),
            Padding(
                padding:
                    const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Text(name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? const Color(0xFF1C1C1E)
                            : const Color(0xFF9E9E9E)))),
            Padding(
                padding:
                    const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Text(cuisine,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6E6E73)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            Padding(
                padding:
                    const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Row(children: [
                  const Icon(Icons.access_time_rounded,
                      size: 14, color: Color(0xFF6E6E73)),
                  const SizedBox(width: 4),
                  Text(_calcDeliveryTime(
                          deliveryTimeStr: deliveryTime,
                          distanceKm: distanceKm),
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF6E6E73))),
                  if (shortAddress.isNotEmpty || distanceKm != null) ...[
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(fontSize: 12, color: Color(0xFFAEAEB2))),
                    const SizedBox(width: 6),
                    const Icon(Icons.location_on_rounded,
                        size: 13, color: Color(0xFF0077B6)),
                    const SizedBox(width: 2),
                    if (shortAddress.isNotEmpty)
                      Flexible(child: Text(
                        shortAddress,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF0077B6),
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                    if (distanceKm != null) ...[
                      if (shortAddress.isNotEmpty)
                        const Text(' • ', style: TextStyle(fontSize: 12, color: Color(0xFFAEAEB2))),
                      Text(_fmtDistance(distanceKm!),
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF0077B6),
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                  const Spacer(),
                  if (isActive) ...[
                    const Icon(Icons.delivery_dining_rounded,
                        size: 14, color: Color(0xFF34C759)),
                    const SizedBox(width: 4),
                    const Text('Free delivery',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF34C759))),
                  ] else
                    const Text('Unavailable',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF9E9E9E))),
                ])),
          ]),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
      color: _blue.withOpacity(0.08),
      child: const Center(
          child: Icon(Icons.restaurant_rounded,
              size: 60, color: _blue)));
}