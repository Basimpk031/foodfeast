// ─────────────────────────────────────────────
// restaurant_screen.dart — FoodFeast
// Restaurant Owner Portal
//  • Login gate: only users with role == 'restaurant' can enter
//  • Scoped to their own restaurantId (set by admin in Firestore)
//  • Tabs: My Restaurant | Menu Items | Orders
//  • Cannot add new restaurants (admin-only)
// ─────────────────────────────────────────────
//
// FIRESTORE SETUP (admin must do this once per restaurant owner):
//   users/{uid}  →  { role: 'restaurant', restaurantId: '<restaurantDocId>', name: '...', email: '...' }
//
// HOW TO WIRE INTO main.dart — add to AuthGate role check:
//   if (role == 'restaurant') return const RestaurantDashboard();
//
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'login_screen.dart';
import 'fcm_service.dart';
import 'local_notification_service.dart';
import 'main.dart' show AuthGate;
import 'location_service.dart';
import 'finance_dashboard_screen.dart';

// ══════════════════════════════════════════════
//  AUTH GATE
// ══════════════════════════════════════════════
class RestaurantAuthGate extends StatelessWidget {
  const RestaurantAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0077B6))));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(snapshot.data!.uid)
                .get(),
            builder: (context, userSnap) {
              if (userSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                    body: Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF0077B6))));
              }
              final data =
                  userSnap.data?.data() as Map<String, dynamic>?;
              if (data?['role'] == 'restaurant' || data?['role'] == 'restaurant_owner') {
                return RestaurantDashboard(
                    restaurantId: data!['restaurantId'] as String);
              }
              return const _RestaurantLoginScreen();
            },
          );
        }
        return const _RestaurantLoginScreen();
      },
    );
  }
}

// ══════════════════════════════════════════════
//  LOGIN SCREEN
// ══════════════════════════════════════════════
class _RestaurantLoginScreen extends StatefulWidget {
  const _RestaurantLoginScreen();

  @override
  State<_RestaurantLoginScreen> createState() =>
      _RestaurantLoginScreenState();
}

class _RestaurantLoginScreenState extends State<_RestaurantLoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure   = true;
  bool _isLoading = false;
  late AnimationController _btnCtrl;

  static const _dark   = Color(0xFF0D1B2A);
  static const _accent = Color(0xFF0077B6);
  static const _teal   = Color(0xFF00C9A7);

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.trim().isEmpty) {
      _snack('Please enter email and password');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim());
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data?['role'] != 'restaurant_owner' && data?['role'] != 'restaurant') {
        await FirebaseAuth.instance.signOut();
        if (mounted) _snack('Access denied. Not a restaurant account.');
        return;
      }
      final restaurantId = data?['restaurantId'] as String?;
      if (restaurantId == null || restaurantId.isEmpty) {
        await FirebaseAuth.instance.signOut();
        if (mounted) _snack('No restaurant linked. Contact admin.');
        return;
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _snack(e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _accent));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Positioned(
            top: -90,
            right: -90,
            child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _teal.withOpacity(0.08)))),
        Positioned(
            bottom: -70,
            left: -70,
            child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent.withOpacity(0.07)))),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const SizedBox(height: 60),
              Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _teal.withOpacity(0.14),
                      border: Border.all(
                          color: _teal.withOpacity(0.45), width: 2)),
                  child: const Icon(Icons.storefront_rounded,
                      color: Color(0xFF00C9A7), size: 42)),
              const SizedBox(height: 20),
              const Text('Restaurant Portal',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Manage your restaurant on FoodFeast',
                  style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.white.withOpacity(0.5))),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.1), width: 1)),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                        color: _teal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _teal.withOpacity(0.3), width: 1)),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_rounded,
                              color: Color(0xFF00C9A7), size: 16),
                          const SizedBox(width: 8),
                          Text('Restaurant Owner Access',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                  const SizedBox(height: 22),
                  _darkField(_emailCtrl, 'Email', Icons.alternate_email_rounded,
                      type: TextInputType.emailAddress),
                  const SizedBox(height: 14),
                  _darkField(
                      _passwordCtrl, 'Password', Icons.lock_outline_rounded,
                      obscure: _obscure,
                      suffix: IconButton(
                          icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: Colors.white.withOpacity(0.4)),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure))),
                  const SizedBox(height: 24),
                  _buildLoginBtn(),
                ]),
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false),
                child: Text('← Back to User Login',
                    style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _darkField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? type, bool obscure = false, Widget? suffix}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
      decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(fontSize: 13.5, color: Colors.white.withOpacity(0.5)),
          prefixIcon: Icon(icon, size: 20, color: _teal),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: _teal, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 14)),
    );
  }

  Widget _buildLoginBtn() {
    return GestureDetector(
      onTapDown: (_) => _btnCtrl.forward(),
      onTapUp: (_) {
        _btnCtrl.reverse();
        _login();
      },
      onTapCancel: () => _btnCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _btnCtrl,
        builder: (_, __) => Transform.scale(
          scale: 1 - _btnCtrl.value * 0.03,
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF00C9A7), Color(0xFF009688)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _teal
                          .withOpacity(0.4 + _btnCtrl.value * 0.3),
                      blurRadius: 18 + _btnCtrl.value * 14,
                      offset: const Offset(0, 6))
                ]),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront_rounded,
                            color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Login as Restaurant Owner',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2)),
                      ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  MAIN DASHBOARD
// ══════════════════════════════════════════════
class RestaurantDashboard extends StatefulWidget {
  final String restaurantId;
  const RestaurantDashboard({super.key, required this.restaurantId});

  @override
  State<RestaurantDashboard> createState() => _RestaurantDashboardState();
}

class _RestaurantDashboardState extends State<RestaurantDashboard> {
  int _tab = 0;
  final _ordersFilter = ValueNotifier<String>('all');
  static const _accent = Color(0xFF0077B6);
  static const _dark   = Color(0xFF0D1B2A);
  static const _teal   = Color(0xFF00C9A7);

  late final List<Widget> _tabChildren;

  @override
  void initState() {
    super.initState();
    _tabChildren = [
      _RestaurantInfoTab(
        restaurantId: widget.restaurantId,
        onNavigateToOrders: (filter) {
          _ordersFilter.value = filter;
          setState(() => _tab = 2);
        },
      ),
      _MenuItemTab(restaurantId: widget.restaurantId),
      _RestaurantOrdersTab(
        restaurantId: widget.restaurantId,
        filterNotifier: _ordersFilter,
      ),
    ];
    FcmService.saveToken();
    FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'] as String? ?? '';
      if (type != 'new_order') {
        LocalNotificationService.showFromRemoteMessage(message);
      }
    });
  }

  @override
  void dispose() {
    _ordersFilter.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: _dark,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(children: [
          const Icon(Icons.storefront_rounded, color: _teal, size: 22),
          const SizedBox(width: 8),
          RichText(
              text: const TextSpan(children: [
            TextSpan(
                text: 'Food',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            TextSpan(
                text: 'Feast',
                style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            TextSpan(
                text: ' Restaurant',
                style: TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ])),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white70),
              tooltip: 'Logout',
              onPressed: _logout)
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: _dark,
            child: Row(children: [
              _tabBtn('My Restaurant', 0, Icons.store_rounded),
              _tabBtn('Menu Items', 1, Icons.restaurant_menu_rounded),
              _tabBtn('Orders', 2, Icons.receipt_long_rounded),
            ]),
          ),
        ),
      ),
      body: IndexedStack(index: _tab, children: _tabChildren),
    );
  }

  Widget _tabBtn(String label, int index, IconData icon) {
    final isActive = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: isActive ? _teal : Colors.transparent,
                      width: 3))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 16,
                color: isActive ? _teal : Colors.white.withOpacity(0.5)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? _teal
                        : Colors.white.withOpacity(0.5))),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  TAB 1 — MY RESTAURANT INFO
// ══════════════════════════════════════════════
class _RestaurantInfoTab extends StatefulWidget {
  final String restaurantId;
  final void Function(String filter) onNavigateToOrders;
  const _RestaurantInfoTab({required this.restaurantId, required this.onNavigateToOrders});

  @override
  State<_RestaurantInfoTab> createState() => _RestaurantInfoTabState();
}

class _RestaurantInfoTabState extends State<_RestaurantInfoTab> {
  static const _red = Color(0xFF0077B6);
  late final Stream<DocumentSnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          return _RestaurantInfoBody(
              restaurantId: widget.restaurantId,
              data: data,
              onNavigateToOrders: widget.onNavigateToOrders);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _red));
        }
        return const Center(
            child: Text('Restaurant not found.',
                style: TextStyle(color: Color(0xFF6E6E73))));
      },
    );
  }
}

class _RestaurantInfoBody extends StatelessWidget {
  final String restaurantId;
  final Map<String, dynamic> data;
  final void Function(String filter) onNavigateToOrders;
  const _RestaurantInfoBody(
      {required this.restaurantId, required this.data, required this.onNavigateToOrders});

  static const _red  = Color(0xFF0077B6);
  static const _teal = Color(0xFF00C9A7);

  @override
  Widget build(BuildContext context) {
    final imageUrl  = data['imageUrl'] ?? '';
    final isActive  = data['isActive'] ?? true;
    final name      = data['name'] ?? '';
    final delivery  = data['deliveryTime'] ?? '';
    final rating    = (data['rating'] ?? 4.0).toDouble();
    final categories =
        (data['categories'] as List?)?.cast<String>().join(', ') ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Hero card ──────────────────────────────────────
        Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 6))
              ]),
          child: Column(children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _coverPlaceholder())
                  : _coverPlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1C1C1E)))),
                          _statusChip(
                              isActive ? 'Active' : 'Inactive',
                              isActive
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFF6E6E73)),
                        ]),
                    const SizedBox(height: 8),
                    if (categories.isNotEmpty)
                      Row(children: [
                        const Icon(Icons.category_outlined,
                            size: 13, color: Color(0xFF6E6E73)),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(categories,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF6E6E73)))),
                      ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.access_time_rounded,
                          size: 13, color: Color(0xFF6E6E73)),
                      const SizedBox(width: 4),
                      Text(delivery.isNotEmpty ? delivery : '—',
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF6E6E73))),
                      const SizedBox(width: 16),
                      const Icon(Icons.star_rounded,
                          size: 13, color: Color(0xFFFF9500)),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF6E6E73),
                              fontWeight: FontWeight.w600)),
                    ]),
                  ]),
            ),
          ]),
        ),

        const SizedBox(height: 20),

        // ── Quick controls ─────────────────────────────────
        _sectionHeader('Quick Controls'),
        const SizedBox(height: 12),
        Row(children: [
          _quickToggle(
            context,
            icon: isActive
                ? Icons.toggle_on_rounded
                : Icons.toggle_off_rounded,
            label: isActive ? 'Restaurant is Open' : 'Restaurant is Closed',
            sublabel: 'Tap to ${isActive ? 'close' : 'open'}',
            color: isActive ? const Color(0xFF34C759) : const Color(0xFF6E6E73),
            onTap: () => FirebaseFirestore.instance
                .collection('restaurants')
                .doc(restaurantId)
                .update({'isActive': !isActive}),
          ),
          const SizedBox(width: 12),
          _quickToggle(
            context,
            icon: Icons.edit_rounded,
            label: 'Edit Details',
            sublabel: 'Name, image, hours',
            color: _red,
            onTap: () => _showEditDialog(context),
          ),
        ]),

        const SizedBox(height: 24),

        // ── Stats row ──────────────────────────────────────
        _sectionHeader('Today at a Glance'),
        const SizedBox(height: 12),
        _TodayStatsRow(
          restaurantId: restaurantId,
          onNavigateToOrders: onNavigateToOrders,
        ),
      ]),
    );
  }

  Widget _coverPlaceholder() => Container(
      height: 180,
      width: double.infinity,
      color: _red.withOpacity(0.08),
      child: const Icon(Icons.store_rounded, color: _red, size: 56));

  Widget _statusChip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color)));

  Widget _sectionHeader(String text) => Text(text,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1C1C1E)));

  Widget _quickToggle(BuildContext context,
      {required IconData icon,
      required String label,
      required String sublabel,
      required Color color,
      required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3))
              ]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color)),
            const SizedBox(height: 2),
            Text(sublabel,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6E6E73))),
          ]),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final nameCtrl       = TextEditingController(text: data['name'] ?? '');
    final imageUrlCtrl   = TextEditingController(text: data['imageUrl'] ?? '');
    final deliveryCtrl   = TextEditingController(text: data['deliveryTime'] ?? '');
    List<String> selectedRestCats = List<String>.from(
        (data['categories'] as List?)?.cast<String>() ?? []);
    bool isActive   = data['isActive'] ?? true;

    final locMap = data['location'] as Map<String, dynamic>?;
    AppLocation? pickedLocation = locMap != null
        ? AppLocation.fromMap(locMap)
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                    const Text('Edit Restaurant Details',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1C1E))),
                    const SizedBox(height: 18),
                    _field(nameCtrl, 'Restaurant Name', Icons.store_rounded),
                    const SizedBox(height: 12),
                    _field(imageUrlCtrl, 'Cover Image URL',
                        Icons.image_outlined),
                    const SizedBox(height: 12),
                    _field(deliveryCtrl, 'Delivery Time (e.g. 30 min)',
                        Icons.access_time_rounded),
                    const SizedBox(height: 12),
                  const Text('Restaurant Categories',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: ['Pizza','Burger','Indian','Chinese','Desserts','Biryani','Chicken','Seafood','Sandwich','Salad','Drinks']
                        .map((cat) {
                      final sel = selectedRestCats.contains(cat);
                      return GestureDetector(
                        onTap: () => setModalState(() {
                          if (sel) selectedRestCats.remove(cat);
                          else selectedRestCats.add(cat);
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: sel ? _red : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? _red : const Color(0xFFE5E5EA), width: 1.5),
                          ),
                          child: Text(cat, style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : const Color(0xFF6E6E73))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                    const Text('Restaurant Location',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E))),
                    const SizedBox(height: 6),

                    if (pickedLocation != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF0077B6).withOpacity(0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF0077B6), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              Text(pickedLocation!.shortName,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1C1C1E))),
                              const SizedBox(height: 2),
                              Text(pickedLocation!.address,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF6E6E73)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                        ]),
                      ),

                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final loc = await LocationService.instance
                                .fetchCurrentLocation();
                            if (loc != null) {
                              setModalState(() => pickedLocation = loc);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0077B6).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                  color: const Color(0xFF0077B6)
                                      .withOpacity(0.25)),
                            ),
                            child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                              Icon(Icons.my_location_rounded,
                                  color: Color(0xFF0077B6), size: 16),
                              SizedBox(width: 6),
                              Text('Auto-detect',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0077B6))),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            Navigator.pop(ctx);
                            final loc =
                                await Navigator.push<AppLocation?>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MapPickerScreen(
                                  initialLocation: pickedLocation,
                                  title: 'Pin Restaurant Location',
                                ),
                              ),
                            );
                            if (loc != null && context.mounted) {
                              // ignore: use_build_context_synchronously
                              _showEditDialogWith(
                                context,
                                nameCtrl: nameCtrl,
                                imageUrlCtrl: imageUrlCtrl,
                                deliveryCtrl: deliveryCtrl,
                                selectedRestCats: selectedRestCats,
                                isActive: isActive,
                                pickedLocation: loc,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7F7),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                  color: const Color(0xFFE5E5EA)),
                            ),
                            child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                              Icon(Icons.map_rounded,
                                  color: Color(0xFF1C1C1E), size: 16),
                              SizedBox(width: 6),
                              Text('Pick on Map',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1C1C1E))),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    Row(children: [
                      Switch(
                          value: isActive,
                          activeColor: _red,
                          onChanged: (v) =>
                              setModalState(() => isActive = v)),
                      const Text('Active',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                    ]),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          await FirebaseFirestore.instance
                              .collection('restaurants')
                              .doc(restaurantId)
                              .update({
                            'name': nameCtrl.text.trim(),
                            'imageUrl': imageUrlCtrl.text.trim(),
                            'deliveryTime': deliveryCtrl.text.trim(),
                            'categories': selectedRestCats,
                            'isActive': isActive,
                            if (pickedLocation != null)
                              'location': pickedLocation!.toMap(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('Save Changes',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDialogWith(
    BuildContext context, {
    required TextEditingController nameCtrl,
    required TextEditingController imageUrlCtrl,
    required TextEditingController deliveryCtrl,
    required List<String> selectedRestCats,
    required bool isActive,
    required AppLocation pickedLocation,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          AppLocation? loc = pickedLocation;
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24))),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                      const Text('Edit Restaurant Details',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1C1E))),
                      const SizedBox(height: 18),
                      _field(nameCtrl, 'Restaurant Name', Icons.store_rounded),
                      const SizedBox(height: 12),
                      _field(imageUrlCtrl, 'Cover Image URL', Icons.image_outlined),
                      const SizedBox(height: 12),
                      _field(deliveryCtrl, 'Delivery Time (e.g. 30 min)', Icons.access_time_rounded),
                      const SizedBox(height: 12),
                      const Text('Restaurant Categories',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: ['Pizza','Burger','Indian','Chinese','Desserts','Biryani','Chicken','Seafood','Sandwich','Salad','Drinks']
                            .map((cat) {
                          final sel = selectedRestCats.contains(cat);
                          return GestureDetector(
                            onTap: () => setModalState(() {
                              if (sel) selectedRestCats.remove(cat);
                              else selectedRestCats.add(cat);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: sel ? _red : const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? _red : const Color(0xFFE5E5EA), width: 1.5),
                              ),
                              child: Text(cat, style: TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : const Color(0xFF6E6E73))),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Restaurant Location',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF0077B6).withOpacity(0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF0077B6), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(loc!.shortName,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                              Text(loc.address,
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73)),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Switch(
                            value: isActive,
                            activeColor: _red,
                            onChanged: (v) => setModalState(() => isActive = v)),
                        const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      ]),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty) return;
                            await FirebaseFirestore.instance
                                .collection('restaurants')
                                .doc(restaurantId)
                                .update({
                              'name': nameCtrl.text.trim(),
                              'imageUrl': imageUrlCtrl.text.trim(),
                              'deliveryTime': deliveryCtrl.text.trim(),
                              'categories': selectedRestCats,
                              'isActive': isActive,
                              'location': loc!.toMap(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('Save Changes',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
          prefixIcon: Icon(icon, size: 18, color: _red),
          filled: true,
          fillColor: const Color(0xFFF7F7F7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _red, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
    );
  }
}

// ── Today stats widget ─────────────────────────
class _TodayStatsRow extends StatefulWidget {
  final String restaurantId;
  final void Function(String filter) onNavigateToOrders;
  const _TodayStatsRow({required this.restaurantId, required this.onNavigateToOrders});

  @override
  State<_TodayStatsRow> createState() => _TodayStatsRowState();
}

class _TodayStatsRowState extends State<_TodayStatsRow> {
  static const _red = Color(0xFF0077B6);
  late final Stream<QuerySnapshot> _stream;

  String get _todayStr {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('orders')
        .where('restaurantIds', arrayContains: widget.restaurantId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final today = _todayStr;
        final todayDocs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final ts = data['createdAt'] as Timestamp?;
          if (ts == null) return false;
          final dt = ts.toDate();
          final key =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          return key == today;
        }).toList();

        final totalRevenue = todayDocs.fold<double>(0, (sum, d) {
          final data = d.data() as Map<String, dynamic>;
          final perList = data['perRestaurant'] as List?;
          final perEntry = perList
              ?.cast<Map<String, dynamic>>()
              .where((e) => e['restaurantId'] == widget.restaurantId)
              .firstOrNull;
          if (perEntry != null) {
            return sum + (perEntry['subtotal'] as num? ?? 0).toDouble();
          }
          final items = (data['items'] as List? ?? []);
          final myItems = items.where((i) =>
              (i as Map<String, dynamic>)['restaurantId'] == widget.restaurantId);
          return sum + myItems.fold<double>(0.0, (s, i) {
            final m = i as Map<String, dynamic>;
            return s + (m['price'] as num? ?? 0).toDouble()
                     * (m['quantity'] as num? ?? 1).toInt();
          });
        });
        final pending = todayDocs
            .where((d) =>
                (d.data() as Map<String, dynamic>)['status'] == 'pending')
            .length;
        final delivered = todayDocs
            .where((d) =>
                (d.data() as Map<String, dynamic>)['status'] == 'delivered')
            .length;

        return Row(children: [
          _statCard('Today\'s Orders', '${todayDocs.length}',
              Icons.receipt_rounded, const Color(0xFF007AFF),
              onTap: () => widget.onNavigateToOrders('all')),
          const SizedBox(width: 10),
          _statCard('Revenue', '₹${totalRevenue.toStringAsFixed(0)}',
              Icons.currency_rupee_rounded, const Color(0xFF34C759),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FinanceDashboardScreen(
                    role:         FinanceRole.restaurant,
                    restaurantId: widget.restaurantId,
                  ),
                ),
              )),
          const SizedBox(width: 10),
          _statCard('Pending', '$pending',
              Icons.hourglass_top_rounded, const Color(0xFFFF9500),
              onTap: () => widget.onNavigateToOrders('pending')),
          const SizedBox(width: 10),
          _statCard('Delivered', '$delivered',
              Icons.check_circle_rounded, _red,
              onTap: () => widget.onNavigateToOrders('delivered')),
        ]);
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ]),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 9.5, color: Color(0xFF6E6E73))),
          if (onTap != null) ...[
            const SizedBox(height: 3),
            Icon(Icons.arrow_forward_ios_rounded, size: 8, color: color.withOpacity(0.5)),
          ],
        ]),
      ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  TAB 2 — MENU ITEMS
// ══════════════════════════════════════════════
class _MenuItemTab extends StatefulWidget {
  final String restaurantId;
  const _MenuItemTab({required this.restaurantId});

  @override
  State<_MenuItemTab> createState() => _MenuItemTabState();
}

class _MenuItemTabState extends State<_MenuItemTab> {
  static const _red = Color(0xFF0077B6);
  late final Stream<QuerySnapshot> _stream;

  double _d(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;
  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('restaurants')
        .doc(widget.restaurantId)
        .collection('menuItems')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _red,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Item',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showItemDialog(context, null, null),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _red));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text('🍽️', style: TextStyle(fontSize: 56)),
                  SizedBox(height: 12),
                  Text('No menu items yet',
                      style: TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
                  SizedBox(height: 6),
                  Text('Tap + to add your first item',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
                ]));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc  = docs[i];
              final item = doc.data() as Map<String, dynamic>;
              return _menuItemTile(context, doc.id, item);
            },
          );
        },
      ),
    );
  }

  Widget _menuItemTile(BuildContext context, String itemId, Map<String, dynamic> item) {
    final imageUrl    = item['imageUrl'] ?? '';
    final hasPortions = item['portionsEnabled'] == true;
    final calories    = item['calories'] ?? 0;
    final protein     = (item['protein'] ?? 0).toDouble();
    final carbs       = (item['carbs'] ?? 0).toDouble();
    final fat         = (item['fat'] ?? 0).toDouble();
    final isAvailable = item['isAvailable'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))
          ]),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: imageUrl.isNotEmpty
              ? Image.network(imageUrl, width: 60, height: 60, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _itemPlaceholder())
              : _itemPlaceholder(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(item['name'] ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E)))),
              Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                      border: Border.all(color: (item['isVeg'] ?? false) ? const Color(0xFF34C759) : _red, width: 1.5),
                      borderRadius: BorderRadius.circular(3)),
                  child: Center(child: Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                          color: (item['isVeg'] ?? false) ? const Color(0xFF34C759) : _red,
                          shape: BoxShape.circle)))),
            ]),
            const SizedBox(height: 3),
            Wrap(
              spacing: 6, runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('₹${item['price'] ?? ''}',
                    style: const TextStyle(fontSize: 13, color: _red, fontWeight: FontWeight.w700)),
                if (calories > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.local_fire_department_rounded, size: 12, color: Color(0xFFFF9500)),
                    Text(' $calories kcal', style: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73))),
                  ]),
                if (hasPortions)
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFF007AFF).withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                      child: const Text('Portions', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF007AFF)))),
              ],
            ),
            if (protein > 0 || carbs > 0 || fat > 0)
              Wrap(spacing: 4, children: [
                if (protein > 0) _macroTag('P:${protein.toStringAsFixed(0)}g', const Color(0xFF007AFF)),
                if (carbs > 0)   _macroTag('C:${carbs.toStringAsFixed(0)}g',  const Color(0xFF34C759)),
                if (fat > 0)     _macroTag('F:${fat.toStringAsFixed(0)}g',    const Color(0xFFFF9500)),
              ]),
          ]),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Switch(
              value: isAvailable,
              activeColor: _red,
              onChanged: (v) => FirebaseFirestore.instance
                  .collection('restaurants').doc(widget.restaurantId)
                  .collection('menuItems').doc(itemId)
                  .update({'isAvailable': v})),
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6E6E73)),
                onPressed: () => _showItemDialog(context, itemId, item)),
            IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _red),
                onPressed: () => _confirmDelete(context, itemId)),
          ]),
        ]),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx, String itemId) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item?'),
        content: const Text('This item will be permanently removed from your menu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: _red))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('restaurants').doc(widget.restaurantId)
          .collection('menuItems').doc(itemId).delete();
    }
  }

  Widget _macroTag(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)));

  Widget _itemPlaceholder() => Container(
      width: 60, height: 60,
      decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.fastfood_rounded, color: _red, size: 26));

  void _showItemDialog(BuildContext context, String? itemId, Map<String, dynamic>? data) {
    final nameCtrl          = TextEditingController(text: data?['name'] ?? '');
    final priceCtrl         = TextEditingController(text: data?['price']?.toString() ?? '');
    final originalPriceCtrl = TextEditingController(text: data?['originalPrice']?.toString() ?? '');
    final caloriesCtrl      = TextEditingController(text: data?['calories']?.toString() ?? '');
    final proteinCtrl       = TextEditingController(text: data?['protein']?.toString() ?? '');
    final carbsCtrl         = TextEditingController(text: data?['carbs']?.toString() ?? '');
    final fatCtrl           = TextEditingController(text: data?['fat']?.toString() ?? '');
    final descCtrl          = TextEditingController(text: data?['description'] ?? '');
    final imageUrlCtrl      = TextEditingController(text: data?['imageUrl'] ?? '');
    bool isVeg              = data?['isVeg'] ?? false;
    bool portionsEnabled    = data?['portionsEnabled'] ?? false;
    String selectedFoodCategory = data?['category'] ?? '';

    final quarterPriceCtrl    = TextEditingController(text: data?['quarterPrice']?.toString() ?? '');
    final halfPriceCtrl       = TextEditingController(text: data?['halfPrice']?.toString() ?? '');
    final fullPriceCtrl       = TextEditingController(text: data?['fullPrice']?.toString() ?? '');
    final quarterCaloriesCtrl = TextEditingController(text: data?['quarterCalories']?.toString() ?? '');
    final halfCaloriesCtrl    = TextEditingController(text: data?['halfCalories']?.toString() ?? '');
    final fullCaloriesCtrl    = TextEditingController(text: data?['fullCalories']?.toString() ?? '');
    final quarterProteinCtrl  = TextEditingController(text: data?['quarterProtein']?.toString() ?? '');
    final quarterCarbsCtrl    = TextEditingController(text: data?['quarterCarbs']?.toString() ?? '');
    final quarterFatCtrl      = TextEditingController(text: data?['quarterFat']?.toString() ?? '');
    final halfProteinCtrl     = TextEditingController(text: data?['halfProtein']?.toString() ?? '');
    final halfCarbsCtrl       = TextEditingController(text: data?['halfCarbs']?.toString() ?? '');
    final halfFatCtrl         = TextEditingController(text: data?['halfFat']?.toString() ?? '');
    final fullProteinCtrl     = TextEditingController(text: data?['fullProtein']?.toString() ?? '');
    final fullCarbsCtrl       = TextEditingController(text: data?['fullCarbs']?.toString() ?? '');
    final fullFatCtrl         = TextEditingController(text: data?['fullFat']?.toString() ?? '');

    Future<void> saveItem(BuildContext ctx) async {
      if (nameCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Item name is required'), backgroundColor: _red));
        return;
      }
      final docData = <String, dynamic>{
        'name': nameCtrl.text.trim(), 'description': descCtrl.text.trim(),
        'imageUrl': imageUrlCtrl.text.trim(), 'price': _d(priceCtrl),
        'originalPrice': _d(originalPriceCtrl), 'isVeg': isVeg,
        'category': selectedFoodCategory, 'isAvailable': data?['isAvailable'] ?? true,
        'calories': _i(caloriesCtrl), 'protein': _d(proteinCtrl),
        'carbs': _d(carbsCtrl), 'fat': _d(fatCtrl),
        'portionsEnabled': portionsEnabled,
        'quarterPrice': _d(quarterPriceCtrl), 'halfPrice': _d(halfPriceCtrl), 'fullPrice': _d(fullPriceCtrl),
        'quarterCalories': _i(quarterCaloriesCtrl), 'halfCalories': _i(halfCaloriesCtrl), 'fullCalories': _i(fullCaloriesCtrl),
        'quarterProtein': _d(quarterProteinCtrl), 'quarterCarbs': _d(quarterCarbsCtrl), 'quarterFat': _d(quarterFatCtrl),
        'halfProtein': _d(halfProteinCtrl), 'halfCarbs': _d(halfCarbsCtrl), 'halfFat': _d(halfFatCtrl),
        'fullProtein': _d(fullProteinCtrl), 'fullCarbs': _d(fullCarbsCtrl), 'fullFat': _d(fullFatCtrl),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final col = FirebaseFirestore.instance
          .collection('restaurants').doc(widget.restaurantId).collection('menuItems');
      if (itemId == null) {
        docData['createdAt'] = FieldValue.serverTimestamp();
        await col.add(docData);
      } else {
        await col.doc(itemId).update(docData);
      }
      if (ctx.mounted) Navigator.pop(ctx);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text(itemId == null ? 'Add Menu Item' : 'Edit Menu Item',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                const SizedBox(height: 18),
                _itemField(nameCtrl, 'Item Name', Icons.fastfood_rounded),
                const SizedBox(height: 12),
                _itemField(imageUrlCtrl, 'Food Image URL', Icons.image_outlined),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _itemField(priceCtrl, 'Price (₹)', Icons.currency_rupee_rounded, type: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: _itemField(originalPriceCtrl, 'Original (₹)', Icons.sell_outlined, type: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                _itemField(descCtrl, 'Description', Icons.description_outlined),
                const SizedBox(height: 14),
                const Text('Food Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: ['Pizza','Burger','Indian','Chinese','Desserts','Biryani','Chicken','Seafood','Sandwich','Salad','Drinks']
                      .map((cat) {
                    final sel = selectedFoodCategory == cat;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedFoodCategory = sel ? '' : cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? _red : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? _red : const Color(0xFFE5E5EA), width: 1.5),
                        ),
                        child: Text(cat, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : const Color(0xFF6E6E73))),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                _sectionLabel('📊 Nutrition per serving'),
                const SizedBox(height: 10),
                _itemField(caloriesCtrl, 'Calories (kcal)', Icons.local_fire_department_rounded, type: TextInputType.number),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _macroField(proteinCtrl, 'Protein (g)', '💪', const Color(0xFF007AFF))),
                  const SizedBox(width: 8),
                  Expanded(child: _macroField(carbsCtrl, 'Carbs (g)', '🌾', const Color(0xFF34C759))),
                  const SizedBox(width: 8),
                  Expanded(child: _macroField(fatCtrl, 'Fat (g)', '🥑', const Color(0xFFFF9500))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Switch(value: isVeg, activeColor: const Color(0xFF34C759), onChanged: (v) => setModalState(() => isVeg = v)),
                  const SizedBox(width: 4),
                  Container(width: 14, height: 14,
                      decoration: BoxDecoration(border: Border.all(color: isVeg ? const Color(0xFF34C759) : _red, width: 1.5), borderRadius: BorderRadius.circular(3)),
                      child: Center(child: Container(width: 6, height: 6,
                          decoration: BoxDecoration(color: isVeg ? const Color(0xFF34C759) : _red, shape: BoxShape.circle)))),
                  const SizedBox(width: 6),
                  Text(isVeg ? 'Veg' : 'Non-Veg', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: isVeg ? const Color(0xFF34C759) : _red)),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: portionsEnabled ? const Color(0xFF007AFF).withOpacity(0.05) : const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: portionsEnabled ? const Color(0xFF007AFF).withOpacity(0.3) : const Color(0xFFE5E5EA), width: 1.5)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.restaurant_menu_rounded, size: 18, color: Color(0xFF007AFF)),
                      const SizedBox(width: 8),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Portion Sizes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                        Text('Allow Quarter / Half / Full ordering', style: TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73))),
                      ])),
                      Switch(value: portionsEnabled, activeColor: const Color(0xFF007AFF), onChanged: (v) => setModalState(() => portionsEnabled = v)),
                    ]),
                    if (portionsEnabled) ...[
                      const SizedBox(height: 14),
                      _portionSectionLabel('Prices (₹)'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _portionField(quarterPriceCtrl, '🍗 Quarter', '₹')),
                        const SizedBox(width: 8),
                        Expanded(child: _portionField(halfPriceCtrl, '🍖 Half', '₹')),
                        const SizedBox(width: 8),
                        Expanded(child: _portionField(fullPriceCtrl, '🫕 Full', '₹')),
                      ]),
                      const SizedBox(height: 14),
                      _portionSectionLabel('🔥 Calories (kcal)'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _portionCalField(quarterCaloriesCtrl, '¼ kcal')),
                        const SizedBox(width: 8),
                        Expanded(child: _portionCalField(halfCaloriesCtrl, '½ kcal')),
                        const SizedBox(width: 8),
                        Expanded(child: _portionCalField(fullCaloriesCtrl, 'Full kcal')),
                      ]),
                      const SizedBox(height: 14),
                      _portionSectionLabel('🍗 Quarter — Macros (g)'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _macroPortionField(quarterProteinCtrl, 'Protein', const Color(0xFF007AFF))),
                        const SizedBox(width: 8),
                        Expanded(child: _macroPortionField(quarterCarbsCtrl, 'Carbs', const Color(0xFF34C759))),
                        const SizedBox(width: 8),
                        Expanded(child: _macroPortionField(quarterFatCtrl, 'Fat', const Color(0xFFFF9500))),
                      ]),
                      const SizedBox(height: 14),
                      _portionSectionLabel('🍖 Half — Macros (g)'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _macroPortionField(halfProteinCtrl, 'Protein', const Color(0xFF007AFF))),
                        const SizedBox(width: 8),
                        Expanded(child: _macroPortionField(halfCarbsCtrl, 'Carbs', const Color(0xFF34C759))),
                        const SizedBox(width: 8),
                        Expanded(child: _macroPortionField(halfFatCtrl, 'Fat', const Color(0xFFFF9500))),
                      ]),
                      const SizedBox(height: 14),
                      _portionSectionLabel('🫕 Full — Macros (g)'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _macroPortionField(fullProteinCtrl, 'Protein', const Color(0xFF007AFF))),
                        const SizedBox(width: 8),
                        Expanded(child: _macroPortionField(fullCarbsCtrl, 'Carbs', const Color(0xFF34C759))),
                        const SizedBox(width: 8),
                        Expanded(child: _macroPortionField(fullFatCtrl, 'Fat', const Color(0xFFFF9500))),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: () => saveItem(ctx),
                    child: Text(itemId == null ? 'Add Item' : 'Save Changes',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemField(TextEditingController ctrl, String label, IconData icon, {TextInputType? type}) {
    return TextField(
      controller: ctrl, keyboardType: type,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
        prefixIcon: Icon(icon, size: 18, color: _red), filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _red, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  Widget _macroField(TextEditingController ctrl, String label, String emoji, Color accentColor) {
    return TextField(
      controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 13, color: accentColor, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(fontSize: 11.5, color: accentColor.withOpacity(0.7)),
        prefixText: '$emoji ', filled: true, fillColor: accentColor.withOpacity(0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentColor.withOpacity(0.25), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentColor.withOpacity(0.25), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentColor, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      ),
    );
  }

  Widget _portionCalField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl, keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 12, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)),
        filled: true, fillColor: const Color(0xFFFFF3E0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFFFCC80), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFFFCC80), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFFF9500), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
      ),
    );
  }

  Widget _portionField(TextEditingController ctrl, String label, String prefix) {
    return TextField(
      controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)),
        prefixText: '$prefix ', filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
      ),
    );
  }

  Widget _macroPortionField(TextEditingController ctrl, String label, Color color) {
    return TextField(
      controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label, labelStyle: TextStyle(fontSize: 10.5, color: color.withOpacity(0.75)),
        filled: true, fillColor: color.withOpacity(0.07),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: color.withOpacity(0.25), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: color.withOpacity(0.25), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: color, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
        suffixText: 'g', suffixStyle: TextStyle(fontSize: 11, color: color.withOpacity(0.6)),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))));

  Widget _portionSectionLabel(String text) =>
      Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A3A3C)));
}

// ══════════════════════════════════════════════
//  TAB 3 — ORDERS
// ══════════════════════════════════════════════
class _RestaurantOrdersTab extends StatefulWidget {
  final String restaurantId;
  final ValueNotifier<String> filterNotifier;
  const _RestaurantOrdersTab({required this.restaurantId, required this.filterNotifier});

  @override
  State<_RestaurantOrdersTab> createState() => _RestaurantOrdersTabState();
}

class _RestaurantOrdersTabState extends State<_RestaurantOrdersTab> {
  String _filter = 'all';
  String? _selectedSlot;
  static const _red = Color(0xFF0077B6);

  Set<String> _knownOrderIds = {};
  bool _firstSnapshot = true;
  final List<Map<String, String>> _newOrderBanners = [];
  List<String>? _lastDocIds;

  void _dismissBanner(String orderId) {
    setState(() => _newOrderBanners.removeWhere((b) => b['id'] == orderId));
  }

  void _processSnapshot(List<QueryDocumentSnapshot> docs) {
    final currentIds = docs.map((d) => d.id).toList();
    if (_lastDocIds != null && _listEquals(_lastDocIds!, currentIds)) return;
    _lastDocIds = currentIds;

    if (_firstSnapshot) {
      _knownOrderIds = currentIds.toSet();
      _firstSnapshot = false;
      return;
    }

    final incoming = docs.where((d) {
      final data   = d.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '') as String;
      return !_knownOrderIds.contains(d.id) && status == 'pending';
    }).toList();

    _knownOrderIds = currentIds.toSet();

    if (incoming.isNotEmpty) {
      final newBanners = incoming.map((d) {
        final data    = d.data() as Map<String, dynamic>;
        final uName   = (data['userName'] as String? ?? 'Customer');
        final address = (data['deliveryAddress'] as String? ?? '');
        return {'id': d.id, 'userName': uName, 'address': address};
      }).toList();

      setState(() => _newOrderBanners.addAll(newBanners));

      for (final b in newBanners) {
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted) _dismissBanner(b['id']!);
        });
      }
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const _filters = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('confirmed', 'Confirmed'),
    ('preparing', 'Preparing'),
    ('ready_for_pickup', 'Ready 🛵'),
    ('out_for_delivery', 'On the Way'),
    ('delivered', 'Delivered'),
    ('cancelled', 'Cancelled'),
    ('scheduled', 'Scheduled'),
  ];

  late final Stream<QuerySnapshot> _ordersStream;

  @override
  void initState() {
    super.initState();
    _filter = widget.filterNotifier.value;
    widget.filterNotifier.addListener(_onFilterChanged);
    _ordersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('restaurantIds', arrayContains: widget.restaurantId)
        .snapshots();
  }

  void _onFilterChanged() {
    if (mounted) setState(() => _filter = widget.filterNotifier.value);
  }

  @override
  void dispose() {
    widget.filterNotifier.removeListener(_onFilterChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final (key, label) = f;
                  final isSelected = _filter == key;
                  final isScheduled = key == 'scheduled';
                  return GestureDetector(
                    onTap: () => setState(() {
                      _filter = key;
                      if (key != 'scheduled') _selectedSlot = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                          color: isSelected
                              ? (isScheduled ? const Color(0xFF5856D6) : _red)
                              : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (isScheduled)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.schedule_rounded, size: 12,
                                color: isSelected ? Colors.white : const Color(0xFF5856D6)),
                          ),
                        _ScheduledCountBadge(
                          restaurantId: widget.restaurantId,
                          isScheduled: isScheduled,
                          isSelected: isSelected,
                          label: label,
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _ordersStream,
              builder: (context, snapshotById) {
                if (snapshotById.hasError) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error: ${snapshotById.error}',
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ));
                }
                if (snapshotById.connectionState == ConnectionState.waiting &&
                    !snapshotById.hasData) {
                  return const Center(child: CircularProgressIndicator(color: _red));
                }

                final allDocs = List<QueryDocumentSnapshot>.from(
                    snapshotById.data?.docs ?? []);

                allDocs.sort((a, b) {
                  final aTs = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                  final bTs = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return bTs.compareTo(aTs);
                });

                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _processSnapshot(allDocs));

                // ── SCHEDULED MODE ─────────────────────────────
                if (_filter == 'scheduled') {
                  final today = DateTime.now();
                  final todayStr =
                      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

                  final scheduledDocs = allDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final slot = (data['deliverySlot'] as String? ?? '');
                    if (slot.isEmpty || slot.toUpperCase().contains('ASAP')) return false;
                    final ts = data['createdAt'] as Timestamp?;
                    if (ts == null) return false;
                    final dt = ts.toDate();
                    final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                    return key == todayStr;
                  }).toList();

                  final Map<String, int> slotCounts = {};
                  for (final d in scheduledDocs) {
                    final slot = (d.data() as Map<String, dynamic>)['deliverySlot'] as String? ?? '';
                    slotCounts[slot] = (slotCounts[slot] ?? 0) + 1;
                  }

                  if (_selectedSlot != null) {
                    final slotDocs = scheduledDocs.where((d) {
                      final slot = (d.data() as Map<String, dynamic>)['deliverySlot'] as String? ?? '';
                      return slot == _selectedSlot;
                    }).toList();

                    return Column(children: [
                      GestureDetector(
                        onTap: () => setState(() => _selectedSlot = null),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: const Color(0xFFF5F5F7),
                          child: Row(children: [
                            const Icon(Icons.arrow_back_ios_rounded, size: 14, color: Color(0xFF5856D6)),
                            const SizedBox(width: 6),
                            Expanded(child: Text('🕐 $_selectedSlot',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5856D6)))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFF5856D6), borderRadius: BorderRadius.circular(12)),
                              child: Text('${slotDocs.length} order${slotDocs.length == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ]),
                        ),
                      ),
                      const Divider(height: 1),
                      if (slotDocs.isEmpty)
                        const Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('📋', style: TextStyle(fontSize: 48)),
                          SizedBox(height: 12),
                          Text('No orders for this slot', style: TextStyle(fontSize: 15, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
                        ])))
                      else
                        Expanded(child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: slotDocs.length,
                          itemBuilder: (_, i) {
                            final doc = slotDocs[i];
                            return _RestaurantOrderCard(
                                key: ValueKey(doc.id),
                                orderId: doc.id,
                                data: doc.data() as Map<String, dynamic>,
                                restaurantId: widget.restaurantId);
                          },
                        )),
                    ]);
                  }

                  if (slotCounts.isEmpty) {
                    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('🕐', style: TextStyle(fontSize: 56)),
                      SizedBox(height: 12),
                      Text('No scheduled orders today', style: TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      Text("Today's scheduled orders will appear here", style: TextStyle(fontSize: 13, color: Color(0xFFAEAEB2))),
                    ]));
                  }

                  final sortedSlots = slotCounts.keys.toList()..sort((a, b) => a.compareTo(b));
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: Text('Tap a time slot to view its orders',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF6E6E73), fontWeight: FontWeight.w500)),
                      ),
                      ...sortedSlots.map((slot) {
                        final count = slotCounts[slot]!;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSlot = slot),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF5856D6).withOpacity(0.2), width: 1),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
                            ),
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(color: const Color(0xFF5856D6).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.schedule_rounded, size: 22, color: Color(0xFF5856D6)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(slot, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                                const SizedBox(height: 2),
                                Text('$count order${count == 1 ? '' : 's'} scheduled',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                              ])),
                              Container(
                                width: 34, height: 34,
                                decoration: const BoxDecoration(color: Color(0xFF5856D6), shape: BoxShape.circle),
                                child: Center(child: Text('$count',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF6E6E73)),
                            ]),
                          ),
                        );
                      }),
                    ],
                  );
                }

                // ── NORMAL FILTER MODE ─────────────────────────
                var docs = allDocs;
                if (_filter != 'all') {
                  docs = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return (data['status'] ?? '') == _filter;
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('📋', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 12),
                    Text(_filter == 'all' ? 'No orders yet' : 'No $_filter orders',
                        style: const TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
                  ]));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc  = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return _RestaurantOrderCard(
                        key: ValueKey(doc.id),
                        orderId: doc.id,
                        data: data,
                        restaurantId: widget.restaurantId);
                  },
                );
              },
            ),
          ),
        ]),

        if (_newOrderBanners.isNotEmpty)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Column(
              children: _newOrderBanners.map((banner) => _NewOrderBanner(
                userName:  banner['userName']!,
                address:   banner['address']!,
                onDismiss: () => _dismissBanner(banner['id']!),
              )).toList(),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// New Order Notification Banner widget
// ─────────────────────────────────────────────
class _NewOrderBanner extends StatefulWidget {
  final String userName;
  final String address;
  final VoidCallback onDismiss;
  const _NewOrderBanner({required this.userName, required this.address, required this.onDismiss});

  @override
  State<_NewOrderBanner> createState() => _NewOrderBannerState();
}

class _NewOrderBannerState extends State<_NewOrderBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _animatedDismiss() async {
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0077B6),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: const Color(0xFF0077B6).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
              child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🛎️ New Order!',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              Text('From ${widget.userName}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (widget.address.isNotEmpty)
                Text(widget.address,
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            IconButton(
              onPressed: _animatedDismiss,
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Scheduled count badge
// ─────────────────────────────────────────────
class _ScheduledCountBadge extends StatelessWidget {
  final String restaurantId;
  final bool isScheduled;
  final bool isSelected;
  final String label;
  const _ScheduledCountBadge({
    required this.restaurantId,
    required this.isScheduled,
    required this.isSelected,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (!isScheduled) {
      return Text(label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF6E6E73)));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('restaurantIds', arrayContains: restaurantId)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final today = DateTime.now();
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        final count = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final slot = (data['deliverySlot'] as String? ?? '');
          if (slot.isEmpty || slot.toUpperCase().contains('ASAP')) return false;
          final ts = data['createdAt'] as Timestamp?;
          if (ts == null) return false;
          final dt = ts.toDate();
          final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          return key == todayStr;
        }).length;

        return Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF5856D6))),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.25) : const Color(0xFF5856D6),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$count', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ]);
      },
    );
  }
}

// ─────────────────────────────────────────────
// Order Card
// ─────────────────────────────────────────────
class _RestaurantOrderCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final String restaurantId;
  const _RestaurantOrderCard(
      {required this.orderId, required this.data, required this.restaurantId, super.key});

  @override
  State<_RestaurantOrderCard> createState() => _RestaurantOrderCardState();
}

class _RestaurantOrderCardState extends State<_RestaurantOrderCard> {
  static const _red = Color(0xFF0077B6);

  late String _localStatus;

  static const _validStatuses = [
    'pending', 'confirmed', 'preparing', 'ready_for_pickup',
    'picked_up', 'out_for_delivery', 'delivered', 'cancelled'
  ];

  @override
  void initState() {
    super.initState();
    final rawStatus = (widget.data['status'] ?? 'pending') as String;
    _localStatus = _validStatuses.contains(rawStatus) ? rawStatus : 'cancelled';
  }

  @override
  void didUpdateWidget(_RestaurantOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rawStatus = (widget.data['status'] ?? 'pending') as String;
    final incoming = _validStatuses.contains(rawStatus) ? rawStatus : 'cancelled';
    if (incoming != _localStatus) setState(() => _localStatus = incoming);
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':           return const Color(0xFFFF9500);
      case 'confirmed':         return const Color(0xFF007AFF);
      case 'preparing':         return const Color(0xFF5856D6);
      case 'ready_for_pickup':  return const Color(0xFFFF6B00);
      case 'picked_up':         return const Color(0xFF0077B6);
      case 'out_for_delivery':  return const Color(0xFF0077B6);
      case 'delivered':         return const Color(0xFF34C759);
      case 'cancelled':         return _red;
      default:                  return const Color(0xFF6E6E73);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status   = _localStatus;
    final data     = widget.data;
    final allItems = (data['items'] as List?) ?? [];

    final rid   = widget.restaurantId;
    final items = allItems.where((i) =>
        (i as Map<String, dynamic>)['restaurantId'] == rid).toList();

    final num total;
    final perList = data['perRestaurant'] as List?;
    final perEntry = perList
        ?.cast<Map<String, dynamic>>()
        .where((e) => e['restaurantId'] == rid)
        .firstOrNull;
    if (perEntry != null) {
      total = perEntry['subtotal'] as num? ?? 0;
    } else {
      total = items.fold<double>(0.0, (s, i) {
        final m = i as Map<String, dynamic>;
        return s + (m['price'] as num? ?? 0).toDouble()
                 * (m['quantity'] as num? ?? 1).toInt();
      });
    }

    final userName        = data['userName'] ?? 'Customer';
    final deliveryAddress = data['deliveryAddress'] as String? ?? '';
    final deliverySlot    = data['deliverySlot'] as String? ?? '';
    final slotDisplay     = deliverySlot.toUpperCase().contains('ASAP') ? 'Now' : deliverySlot;
    final ts              = data['createdAt'] as Timestamp?;
    final timeStr         = ts != null ? _formatTime(ts.toDate()) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Order #${widget.orderId.substring(0, 8).toUpperCase()}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                  if (timeStr.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(timeStr, style: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73))),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.person_outline_rounded, size: 13, color: Color(0xFF6E6E73)),
                  const SizedBox(width: 3),
                  Text(userName, style: const TextStyle(fontSize: 12.5, color: Color(0xFF6E6E73))),
                ]),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(status.toUpperCase(),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _statusColor(status))),
            ),
          ]),
        ),

        const Divider(height: 1),

        // ── Items ──────────────────────────────────────────────────────────
        ...items.map((item) {
          final itemMap   = item as Map<String, dynamic>;
          final name      = itemMap['name'] ?? '';
          final portion   = itemMap['portion'] ?? '';
          final qty       = itemMap['quantity'] ?? 1;
          final pp        = itemMap['portionPrice'];
          final itemPrice = (pp != null && (pp as num) > 0)
              ? (pp as num).toDouble()
              : (itemMap['price'] ?? 0).toDouble();
          final calories  = itemMap['calories'] ?? 0;
          final protein   = (itemMap['protein'] ?? 0).toDouble();
          final carbs     = (itemMap['carbs'] ?? 0).toDouble();
          final fat       = (itemMap['fat'] ?? 0).toDouble();

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.circle, size: 6, color: Color(0xFFE5E5EA)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('$name${portion.isNotEmpty ? ' ($portion)' : ''}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E)))),
                    Text('×$qty  ₹${itemPrice.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12.5, color: _red, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 3),
                  Wrap(spacing: 4, runSpacing: 2, children: [
                    if (calories > 0) _badge('🔥 $calories kcal', const Color(0xFFFF9500)),
                    if (protein > 0)  _badge('💪 ${protein.toStringAsFixed(0)}g P', const Color(0xFF007AFF)),
                    if (carbs > 0)    _badge('🌾 ${carbs.toStringAsFixed(0)}g C', const Color(0xFF34C759)),
                    if (fat > 0)      _badge('🥑 ${fat.toStringAsFixed(0)}g F', const Color(0xFFFF9500)),
                  ]),
                ]),
              ),
            ]),
          );
        }),

        // ── Address & Slot ─────────────────────────────────────────────────
        if (deliveryAddress.isNotEmpty || slotDisplay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(height: 10, color: Color(0xFFF0F0F5)),
              if (deliveryAddress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on_rounded, size: 13, color: _red),
                    const SizedBox(width: 5),
                    Expanded(child: Text(deliveryAddress,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73)))),
                  ]),
                ),
              if (slotDisplay.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, size: 13, color: _red),
                    const SizedBox(width: 5),
                    Text(
                      slotDisplay == 'Now' ? '⚡ Delivery: Now (ASAP)' : '🕐 Scheduled: $slotDisplay',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: slotDisplay == 'Now' ? const Color(0xFF34C759) : const Color(0xFF6E6E73),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
            ]),
          ),

        // ── Footer: payment badge + status dropdown + total ────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Payment method badge ─────────────────────────────────────
              _paymentBadge(data),
              const SizedBox(height: 10),

              // ── Status dropdown + subtotal ───────────────────────────────
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _statusColor(status).withOpacity(0.3), width: 1)),
                  child: DropdownButton<String>(
                    value: _validStatuses.contains(status) ? status : 'pending',
                    isDense: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _statusColor(status)),
                    style: TextStyle(fontSize: 12.5, color: _statusColor(status), fontWeight: FontWeight.w700),
                    items: [
                      DropdownMenuItem(value: 'pending',          child: Text(_statusLabel('pending'))),
                      DropdownMenuItem(value: 'confirmed',        child: Text(_statusLabel('confirmed'))),
                      DropdownMenuItem(value: 'preparing',        child: Text(_statusLabel('preparing'))),
                      DropdownMenuItem(value: 'ready_for_pickup', child: Text(_statusLabel('ready_for_pickup'))),
                      DropdownMenuItem(value: 'cancelled',        child: Text(_statusLabel('cancelled'))),
                      DropdownMenuItem(
                        value: 'picked_up', enabled: false,
                        child: Text(_statusLabel('picked_up'),
                            style: const TextStyle(color: Color(0xFFAEAEB2))),
                      ),
                      DropdownMenuItem(
                        value: 'out_for_delivery', enabled: false,
                        child: Text(_statusLabel('out_for_delivery'),
                            style: const TextStyle(color: Color(0xFFAEAEB2))),
                      ),
                      DropdownMenuItem(
                        value: 'delivered', enabled: false,
                        child: Text(_statusLabel('delivered'),
                            style: const TextStyle(color: Color(0xFFAEAEB2))),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _localStatus = v);
                      final orderRef = FirebaseFirestore.instance
                          .collection('orders').doc(widget.orderId);
                      await orderRef.update({'status': v});
                      if (v == 'ready_for_pickup') {
                        await _assignNearestAgent(orderRef, widget.data);
                      }
                    },
                  ),
                ),
                Text('My Items: ₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Payment method badge ────────────────────────────────────────────────────
  Widget _paymentBadge(Map<String, dynamic> data) {
    final method = (data['paymentMethod'] as String? ?? '').trim();
    final pStatus = (data['paymentStatus'] as String? ?? '').trim();

    if (method.isEmpty && pStatus.isEmpty) return const SizedBox.shrink();

    final isCod = method.toLowerCase().contains('cod') ||
        method.toLowerCase().contains('cash') ||
        pStatus.toLowerCase().contains('cod') ||
        pStatus.toLowerCase().contains('pending_cod') ||
        pStatus.toLowerCase().contains('pending');

    if (isCod) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFE08A), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.money_rounded, size: 14, color: Color(0xFF856404)),
          const SizedBox(width: 5),
          const Text('Cash on Delivery',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF856404))),
        ]),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFD4EDDA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF8FD4A4), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.credit_card_rounded, size: 14, color: Color(0xFF155724)),
          const SizedBox(width: 5),
          Text(method.isNotEmpty ? method : 'Paid Online',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF155724))),
        ]),
      );
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':          return 'Pending';
      case 'confirmed':        return 'Confirmed';
      case 'preparing':        return 'Preparing';
      case 'ready_for_pickup': return 'Ready for Pickup 🛵';
      case 'picked_up':        return 'Picked Up';
      case 'out_for_delivery': return 'Out for Delivery';
      case 'delivered':        return 'Delivered';
      case 'cancelled':        return 'Cancelled';
      default: return s[0].toUpperCase() + s.substring(1);
    }
  }

  Future<void> _assignNearestAgent(
      DocumentReference orderRef, Map<String, dynamic> orderData) async {
    try {
      final restLat = (orderData['restaurantLat'] as num?)?.toDouble();
      final restLng = (orderData['restaurantLng'] as num?)?.toDouble();

      final agentsSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'delivery_agent')
          .where('isOnline', isEqualTo: true)
          .get();

      if (agentsSnap.docs.isEmpty) return;

      final agents = agentsSnap.docs
          .where((d) => d.data()['lastLat'] != null && d.data()['lastLng'] != null)
          .toList();

      if (agents.isEmpty) return;

      DocumentSnapshot? nearest;
      double minDist = double.infinity;

      for (final agent in agents) {
        final data  = agent.data();
        final agLat = (data['lastLat'] as num).toDouble();
        final agLng = (data['lastLng'] as num).toDouble();
        final fromLat = restLat ?? agLat;
        final fromLng = restLng ?? agLng;
        final dist  = _haversine(agLat, agLng, fromLat, fromLng);
        if (dist > 5000) continue;
        if (dist < minDist) {
          minDist = dist;
          nearest = agent;
        }
      }

      if (nearest == null) return;

      final agentData = nearest.data() as Map<String, dynamic>;
      final agentId   = nearest.id;
      final agentName = agentData['name'] as String? ?? 'Agent';

      final existingLat = (orderData['customerLat'] as num?)?.toDouble() ?? 0.0;
      final existingLng = (orderData['customerLng'] as num?)?.toDouble() ?? 0.0;
      final resolvedLat = existingLat != 0.0
          ? existingLat
          : (orderData['deliveryLocation']?['lat'] as num?)?.toDouble() ?? 0.0;
      final resolvedLng = existingLng != 0.0
          ? existingLng
          : (orderData['deliveryLocation']?['lng'] as num?)?.toDouble() ?? 0.0;

      await orderRef.update({
        'assignedAgentId':   agentId,
        'assignedAgentName': agentName,
        'agentAssignedAt':   FieldValue.serverTimestamp(),
        'customerLat':       resolvedLat,
        'customerLng':       resolvedLng,
        'customerAddress':   orderData['deliveryAddress'] ?? orderData['customerAddress'] ?? '',
        'customerName':      orderData['userName'] ?? orderData['customerName'] ?? 'Customer',
        'restaurantLat':     restLat,
        'restaurantLng':     restLng,
      });

      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUid': agentId,
        'orderId':   orderRef.id,
        'title':     '🛵 New Delivery!',
        'body':      'A new order from ${orderData['restaurantName'] ?? 'a restaurant'} is ready for pickup.',
        'type':      'new_delivery',
        'isRead':    false,
        'sentAt':    FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AutoAssign] Error: $e');
    }
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * 3.14159265358979 / 180;
    final dLng = (lng2 - lng1) * 3.14159265358979 / 180;
    final a = (dLat / 2) * (dLat / 2) +
        (lat1 * 3.14159265358979 / 180).abs() *
            (lat2 * 3.14159265358979 / 180).abs() *
            (dLng / 2) * (dLng / 2);
    return 2 * r * (a < 1 ? a : 1);
  }

  Widget _badge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)));

  String _formatTime(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }
}