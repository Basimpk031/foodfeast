// ─────────────────────────────────────────────
// admin_screen.dart — FoodFeast Admin Panel
// Updated: protein, carbs, fat fields on menu items
//          per-portion protein/carbs/fat (quarter / half / full)
//          order details show item-level nutrition
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'main.dart' show AuthGate;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'fcm_service.dart'; // ← notify users on admin reply
import 'local_notification_service.dart'; // ← popup on new support items
import 'location_service.dart';
import 'finance_dashboard_screen.dart';

class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF0077B6))));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
            builder: (context, userSnap) {
              if (userSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF0077B6))));
              }
              final data = userSnap.data?.data() as Map<String, dynamic>?;
              if (data?['role'] == 'admin') return const AdminDashboard();
              return const AdminLoginScreen();
            },
          );
        }
        return const AdminLoginScreen();
      },
    );
  }
}

// ─── ADMIN LOGIN ──────────────────────────────
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> with SingleTickerProviderStateMixin {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure    = true;
  bool _isLoading  = false;
  late AnimationController _btnCtrl;

  static const _dark   = Color(0xFF1A1A2E);
  static const _accent = Color(0xFF0077B6);
  static const _gold   = Color(0xFFFFB800);

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); _btnCtrl.dispose(); super.dispose(); }

  Future<void> _adminLogin() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter email and password'), backgroundColor: _accent));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _passwordCtrl.text.trim());
      final doc  = await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data?['role'] != 'admin') {
        await FirebaseAuth.instance.signOut();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access denied. Not an admin account.'), backgroundColor: _accent));
        return;
      }
      // Save this device's FCM token so users' support submissions can reach it
      FcmService.saveAdminToken();
      // Navigate to AuthGate — it will detect the signed-in admin
      // and route to AdminDashboard correctly.
      // Root AuthGate detects the new sign-in and routes automatically.
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Login failed'), backgroundColor: _accent));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dark,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Positioned(top: -80, right: -80, child: Container(width: 280, height: 280, decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.08)))),
        Positioned(bottom: -60, left: -60, child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, color: _gold.withOpacity(0.06)))),
        SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const SizedBox(height: 60),
            Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: _gold.withOpacity(0.15), border: Border.all(color: _gold.withOpacity(0.4), width: 2)),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFFFB800), size: 40)),
            const SizedBox(height: 20),
            const Text('Admin Portal', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text('FoodFeast Management Console', style: TextStyle(fontSize: 13.5, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.1), width: 1)),
              child: Column(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: _accent.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: _accent.withOpacity(0.3), width: 1)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.security_rounded, color: _accent, size: 16),
                      const SizedBox(width: 8),
                      Text('Restricted Access — Admin Only', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ])),
                const SizedBox(height: 22),
                _darkField(_emailCtrl, 'Admin Email', Icons.alternate_email_rounded, type: TextInputType.emailAddress),
                const SizedBox(height: 14),
                _darkField(_passwordCtrl, 'Admin Password', Icons.lock_outline_rounded, obscure: _obscure,
                    suffix: IconButton(icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.white.withOpacity(0.4)), onPressed: () => setState(() => _obscure = !_obscure))),
                const SizedBox(height: 24),
                _buildAdminLoginBtn(),
              ]),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false),
              child: Text('← Back to User Login', style: TextStyle(fontSize: 13.5, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 40),
          ]),
        )),
      ]),
    );
  }

  Widget _darkField(TextEditingController ctrl, String label, IconData icon, {TextInputType? type, bool obscure = false, Widget? suffix}) {
    return TextField(
      controller: ctrl, keyboardType: type, obscureText: obscure,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
      decoration: InputDecoration(
          labelText: label, labelStyle: TextStyle(fontSize: 13.5, color: Colors.white.withOpacity(0.5)),
          prefixIcon: Icon(icon, size: 20, color: _gold), suffixIcon: suffix,
          filled: true, fillColor: Colors.white.withOpacity(0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _gold, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14)),
    );
  }

  Widget _buildAdminLoginBtn() {
    return GestureDetector(
      onTapDown: (_) => _btnCtrl.forward(),
      onTapUp: (_) { _btnCtrl.reverse(); _adminLogin(); },
      onTapCancel: () => _btnCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _btnCtrl,
        builder: (_, __) => Transform.scale(
          scale: 1 - _btnCtrl.value * 0.03,
          child: Container(
            width: double.infinity, height: 52,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFB800), Color(0xFFFFA000)]), borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: _gold.withOpacity(0.4 + _btnCtrl.value * 0.3), blurRadius: 18 + _btnCtrl.value * 14, offset: const Offset(0, 6))]),
            child: Center(child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Login as Admin', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                  ])),
          ),
        ),
      ),
    );
  }
}

// ─── ADMIN DASHBOARD ─────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _tab = 0;
  static const _red  = Color(0xFF0077B6);
  static const _dark = Color(0xFF1A1A2E);
  static const _gold = Color(0xFFFFB800);

  // ── Support-inbox live listeners ─────────────────────────────────
  static const _supportCollections = [
    {'col': 'support_tickets',  'emoji': '🎫', 'label': 'Support Ticket'},
    {'col': 'problem_reports',  'emoji': '🚨', 'label': 'Problem Report'},
    {'col': 'support_messages', 'emoji': '✉️',  'label': 'Contact Message'},
    {'col': 'app_feedback',     'emoji': '⭐', 'label': 'App Feedback'},
  ];

  final List<StreamSubscription<QuerySnapshot>> _supportSubs = [];
  StreamSubscription<RemoteMessage>? _fcmFgSub;

  // Seed known IDs on first snapshot so we don't fire on initial load.
  final Map<String, Set<String>> _knownIds = {};

  @override
  void initState() {
    super.initState();
    _startSupportListeners();
    _startFcmForegroundListener();
  }

  void _startSupportListeners() {
    final db = FirebaseFirestore.instance;
    for (final entry in _supportCollections) {
      final col   = entry['col']!;
      final emoji = entry['emoji']!;
      final label = entry['label']!;
      _knownIds[col] = {};

      final sub = db
          .collection(col)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snap) {
        final known = _knownIds[col]!;

        if (known.isEmpty) {
          // First snapshot — seed known IDs, no popup.
          known.addAll(snap.docs.map((d) => d.id));
          return;
        }

        final newDocs = snap.docs.where((d) => !known.contains(d.id)).toList();
        for (final doc in newDocs) {
          known.add(doc.id);
          final data     = doc.data() as Map<String, dynamic>;
          final userName = (data['userName'] as String?)?.isNotEmpty == true
              ? data['userName'] as String
              : 'A user';

          final String body;
          if (col == 'support_tickets') {
            final type   = (data['type'] as String? ?? 'ticket').replaceAll('_', ' ');
            final reason = (data['refundReason'] ?? data['issueType'] ?? '') as String;
            body = '$userName · $type${reason.isNotEmpty ? ' — $reason' : ''}';
          } else if (col == 'problem_reports') {
            final category = data['category'] as String? ?? '';
            body = '$userName${category.isNotEmpty ? ' · $category' : ''}';
          } else if (col == 'support_messages') {
            final subject = data['subject'] as String? ?? '';
            body = '$userName${subject.isNotEmpty ? ' · $subject' : ''}';
          } else {
            // app_feedback
            final stars = data['rating']?.toString() ?? '';
            body = '$userName${stars.isNotEmpty ? ' · $stars ⭐' : ''}';
          }

          LocalNotificationService.showNotification(
            id:    doc.id.hashCode,
            title: '$emoji New $label',
            body:  body,
          );
        }
      });

      _supportSubs.add(sub);
    }
  }

  void _startFcmForegroundListener() {
    _fcmFgSub = FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      LocalNotificationService.showNotification(
        id:    message.hashCode,
        title: n.title ?? 'FoodFeast Admin',
        body:  n.body  ?? '',
      );
    });
  }

  @override
  void dispose() {
    for (final s in _supportSubs) s.cancel();
    _fcmFgSub?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signOut();
    // Root AuthGate reacts to signOut automatically — no navigation needed.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: _dark, elevation: 0, automaticallyImplyLeading: false,
        title: Row(children: [
          const Icon(Icons.admin_panel_settings_rounded, color: _gold, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: const TextSpan(children: [
                TextSpan(text: 'Food', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                TextSpan(text: 'Feast', style: TextStyle(color: _red, fontWeight: FontWeight.w800, fontSize: 15)),
                TextSpan(text: ' Admin', style: TextStyle(color: _gold, fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
            ),
          ),
        ]),
        actions: [IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.white70), tooltip: 'Logout', onPressed: _logout)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: _dark,
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _tabBtn('Restaurants', 0, Icons.store_rounded),
                  _tabBtn('Menu Items', 1, Icons.restaurant_menu_rounded),
                  _tabBtn('Orders', 2, Icons.receipt_long_rounded),
                  _tabBtn('Accounts', 3, Icons.manage_accounts_rounded),
                  _tabBtn('Users', 4, Icons.people_rounded),
                  _tabBtn('Agents', 5, Icons.delivery_dining_rounded),
                  _tabBtn('Coupons', 6, Icons.local_offer_rounded),
                  _tabBtn('Notify', 7, Icons.campaign_rounded),
                  _tabBtn('Support', 8, Icons.support_agent_rounded),
                  _tabBtn('Finance', 9, Icons.account_balance_wallet_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _tab, children: const [_RestaurantManager(), _MenuItemManager(), _OrdersView(), _RestaurantAccountsManager(), _UsersManager(), _AgentApplicationsManager(), _CouponManager(), _NotificationManager(), _SupportInbox(), _AdminFinanceTab()]),
    );
  }

  Widget _tabBtn(String label, int index, IconData icon) {
    final isActive = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? _gold : Colors.transparent, width: 3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: isActive ? _gold : Colors.white.withOpacity(0.5)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? _gold : Colors.white.withOpacity(0.5))),
        ]),
      ),
    );
  }
}

// ─── RESTAURANT MANAGER ───────────────────────
class _RestaurantManager extends StatelessWidget {
  const _RestaurantManager();
  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _red,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Restaurant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showRestaurantDialog(context, null, null),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: _red));
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('🏪', style: TextStyle(fontSize: 56)), SizedBox(height: 12), Text('No restaurants yet', style: TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600))]));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc      = docs[i];
              final data     = doc.data() as Map<String, dynamic>;
              final imageUrl = data['imageUrl'] ?? '';
              final locMap   = data['location'] as Map<String, dynamic>?;
              final locShort = (locMap?['shortName'] as String?) ?? '';
              final hasLoc   = locMap != null && locMap['lat'] != null;
              return Container(
                margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))]),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: imageUrl.isNotEmpty ? Image.network(imageUrl, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _restPlaceholder()) : _restPlaceholder()),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(data['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                    Text((data['categories'] as List?)?.join(', ') ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                    const SizedBox(height: 3),
                    // ── Live location badge ────────────────────────
                    Row(children: [
                      Icon(
                        hasLoc ? Icons.location_on_rounded : Icons.location_off_rounded,
                        size: 12,
                        color: hasLoc ? _red : const Color(0xFFAEAEB2),
                      ),
                      const SizedBox(width: 3),
                      Flexible(child: Text(
                        hasLoc
                            ? (locShort.isNotEmpty ? locShort : 'Location set')
                            : 'No location set',
                        style: TextStyle(
                          fontSize: 11,
                          color: hasLoc ? _red : const Color(0xFFAEAEB2),
                          fontWeight: hasLoc ? FontWeight.w600 : FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )),
                    ]),
                  ])),
                  Switch(value: data['isActive'] ?? true, activeColor: _red, onChanged: (v) => FirebaseFirestore.instance.collection('restaurants').doc(doc.id).update({'isActive': v})),
                  IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6E6E73)), onPressed: () => _showRestaurantDialog(context, doc.id, data)),
                  IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _red), onPressed: () => FirebaseFirestore.instance.collection('restaurants').doc(doc.id).delete()),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _restPlaceholder() => Container(width: 52, height: 52, decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.store_rounded, color: _red, size: 24));

  void _showRestaurantDialog(BuildContext context, String? id, Map<String, dynamic>? data) {
    final nameCtrl       = TextEditingController(text: data?['name'] ?? '');
    final imageUrlCtrl   = TextEditingController(text: data?['imageUrl'] ?? '');
    final deliveryCtrl   = TextEditingController(text: data?['deliveryTime'] ?? '');
    // Selected restaurant categories (multi-select)
    List<String> selectedRestCats = List<String>.from(
        (data?['categories'] as List?)?.cast<String>() ?? []);
    bool isActive    = data?['isActive'] ?? true;
    bool isPromoted  = data?['isPromoted'] ?? false;

    // ── Restore previously saved location ──────────────────────
    final locMap = data?['location'] as Map<String, dynamic>?;
    AppLocation? pickedLocation = locMap != null ? AppLocation.fromMap(locMap) : null;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(builder: (ctx, setModalState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(id == null ? 'Add Restaurant' : 'Edit Restaurant', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 18),
              _field(nameCtrl, 'Restaurant Name', Icons.store_rounded),
              const SizedBox(height: 12),
              _field(imageUrlCtrl, 'Image URL', Icons.image_outlined),
              const SizedBox(height: 12),
              _field(deliveryCtrl, 'Preparation Time (e.g. 10 min)', Icons.access_time_rounded),
              const SizedBox(height: 12),
              // ── Restaurant Category Picker ──────────────
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

              // ── Restaurant Location ──────────────────────────────
              const Text('Restaurant Location',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 8),

              // Show current picked location
              if (pickedLocation != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _red.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded, color: _red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(pickedLocation!.shortName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                      if (pickedLocation!.address.isNotEmpty)
                        Text(pickedLocation!.address,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    ])),
                    GestureDetector(
                      onTap: () => setModalState(() => pickedLocation = null),
                      child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF9E9E9E)),
                    ),
                  ]),
                ),

              // Pick / change on map button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _red.withOpacity(0.5), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final loc = await Navigator.push<AppLocation?>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => MapPickerScreen(
                          initialLocation: pickedLocation,
                          title: 'Set Restaurant Location',
                        ),
                      ),
                    );
                    if (loc != null) setModalState(() => pickedLocation = loc);
                  },
                  icon: Icon(Icons.map_rounded, color: _red, size: 18),
                  label: Text(
                    pickedLocation == null ? 'Set Location on Map' : 'Change Location',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _red),
                  ),
                ),
              ),

              const SizedBox(height: 14),
              Row(children: [
                Switch(value: isActive, activeColor: _red, onChanged: (v) => setModalState(() => isActive = v)),
                const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(width: 20),
                Switch(value: isPromoted, activeColor: _red, onChanged: (v) => setModalState(() => isPromoted = v)),
                const Text('Promoted', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final docData = {
                    'name': nameCtrl.text.trim(),
                    'imageUrl': imageUrlCtrl.text.trim(),
                    'deliveryTime': deliveryCtrl.text.trim(),
                    'categories': selectedRestCats,
                    'isActive': isActive,
                    'isPromoted': isPromoted,
                    'rating': data?['rating'] ?? 4.0,
                    'updatedAt': FieldValue.serverTimestamp(),
                    if (pickedLocation != null) 'location': pickedLocation!.toMap(),
                  };
                  if (id == null) { docData['createdAt'] = FieldValue.serverTimestamp(); await FirebaseFirestore.instance.collection('restaurants').add(docData); }
                  else { await FirebaseFirestore.instance.collection('restaurants').doc(id).update(docData); }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(id == null ? 'Add Restaurant' : 'Save Changes', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ),
      )),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(controller: ctrl, style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)), decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)), prefixIcon: Icon(icon, size: 18, color: _red), filled: true, fillColor: const Color(0xFFF7F7F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _red, width: 1.5)), contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)));
  }
}

// ─── MENU ITEM MANAGER ────────────────────────
class _MenuItemManager extends StatelessWidget {
  const _MenuItemManager();
  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _red,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showItemDialog(context, null, null, null),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
        builder: (context, restSnap) {
          if (restSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: _red));
          final restaurants = restSnap.data?.docs ?? [];
          if (restaurants.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('🍽️', style: TextStyle(fontSize: 56)), SizedBox(height: 12), Text('Add restaurants first', style: TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600))]));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: restaurants.length,
            itemBuilder: (_, ri) {
              final restDoc  = restaurants[ri];
              final restData = restDoc.data() as Map<String, dynamic>;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(bottom: 8, top: 4), child: Row(children: [const Icon(Icons.store_rounded, size: 18, color: Color(0xFF1C1C1E)), const SizedBox(width: 8), Text(restData['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E)))])),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('restaurants').doc(restDoc.id).collection('menuItems').snapshots(),
                  builder: (context, itemSnap) {
                    if (!itemSnap.hasData) return const SizedBox();
                    final items = itemSnap.data!.docs;
                    return Column(children: [
                      ...items.map((itemDoc) {
                        final item = itemDoc.data() as Map<String, dynamic>;
                        return _menuItemTile(context, restDoc.id, itemDoc.id, item);
                      }),
                      GestureDetector(
                        onTap: () => _showItemDialog(context, restDoc.id, null, null),
                        child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(border: Border.all(color: _red.withOpacity(0.3), width: 1.5), borderRadius: BorderRadius.circular(12)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_circle_outline_rounded, color: _red, size: 18), SizedBox(width: 6), Text('Add menu item', style: TextStyle(color: _red, fontSize: 13.5, fontWeight: FontWeight.w600))])),
                      ),
                    ]);
                  },
                ),
                const Divider(height: 20),
              ]);
            },
          );
        },
      ),
    );
  }

  Widget _menuItemTile(BuildContext context, String restId, String itemId, Map<String, dynamic> item) {
    final imageUrl    = item['imageUrl'] ?? '';
    final hasPortions = item['portionsEnabled'] == true;
    final calories    = item['calories'] ?? 0;
    final protein     = (item['protein'] ?? 0).toDouble();
    final carbs       = (item['carbs'] ?? 0).toDouble();
    final fat         = (item['fat'] ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))]),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: imageUrl.isNotEmpty ? Image.network(imageUrl, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _itemPlaceholder()) : _itemPlaceholder()),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
          const SizedBox(height: 3),
          Row(children: [
            Text('₹${item['price'] ?? ''}', style: const TextStyle(fontSize: 13, color: _red, fontWeight: FontWeight.w700)),
            if (calories > 0) ...[
              const SizedBox(width: 6),
              const Icon(Icons.local_fire_department_rounded, size: 12, color: Color(0xFFFF9500)),
              Text(' $calories kcal', style: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73))),
            ],
            if (hasPortions) ...[
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: const Color(0xFF007AFF).withOpacity(0.12), borderRadius: BorderRadius.circular(5)), child: const Text('Portions', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF007AFF)))),
            ],
          ]),
          if (protein > 0 || carbs > 0 || fat > 0)
            Wrap(spacing: 4, children: [
              if (protein > 0) _macroTag('P:${protein.toStringAsFixed(0)}g', const Color(0xFF007AFF)),
              if (carbs > 0)   _macroTag('C:${carbs.toStringAsFixed(0)}g', const Color(0xFF34C759)),
              if (fat > 0)     _macroTag('F:${fat.toStringAsFixed(0)}g', const Color(0xFFFF9500)),
            ]),
        ])),
        Switch(value: item['isAvailable'] ?? true, activeColor: _red, onChanged: (v) => FirebaseFirestore.instance.collection('restaurants').doc(restId).collection('menuItems').doc(itemId).update({'isAvailable': v})),
        IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF6E6E73)), onPressed: () => _showItemDialog(context, restId, itemId, item)),
        IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _red), onPressed: () => FirebaseFirestore.instance.collection('restaurants').doc(restId).collection('menuItems').doc(itemId).delete()),
      ]),
    );
  }

  Widget _macroTag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
    child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _itemPlaceholder() => Container(width: 52, height: 52, decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.fastfood_rounded, color: _red, size: 24));

  // ─── helper: safe parse double ──────────────
  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  int    _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _showItemDialog(BuildContext context, String? restId, String? itemId, Map<String, dynamic>? data) {
    // ── Base fields ──────────────────────────────
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
    String? selectedRestId  = restId;
    // Food category for filtering in Popular Items
    String selectedFoodCategory = (data?['category'] as String?) ?? '';

    // ── Portion toggles ──────────────────────────
    bool portionsEnabled = data?['portionsEnabled'] ?? false;

    // ── Portion prices ───────────────────────────
    final quarterPriceCtrl = TextEditingController(text: data?['quarterPrice']?.toString() ?? '');
    final halfPriceCtrl    = TextEditingController(text: data?['halfPrice']?.toString() ?? '');
    final fullPriceCtrl    = TextEditingController(text: data?['fullPrice']?.toString() ?? '');

    // ── Portion calories ─────────────────────────
    final quarterCaloriesCtrl = TextEditingController(text: data?['quarterCalories']?.toString() ?? '');
    final halfCaloriesCtrl    = TextEditingController(text: data?['halfCalories']?.toString() ?? '');
    final fullCaloriesCtrl    = TextEditingController(text: data?['fullCalories']?.toString() ?? '');

    // ── Portion macros — Quarter ──────────────────
    final quarterProteinCtrl = TextEditingController(text: data?['quarterProtein']?.toString() ?? '');
    final quarterCarbsCtrl   = TextEditingController(text: data?['quarterCarbs']?.toString() ?? '');
    final quarterFatCtrl     = TextEditingController(text: data?['quarterFat']?.toString() ?? '');

    // ── Portion macros — Half ─────────────────────
    final halfProteinCtrl = TextEditingController(text: data?['halfProtein']?.toString() ?? '');
    final halfCarbsCtrl   = TextEditingController(text: data?['halfCarbs']?.toString() ?? '');
    final halfFatCtrl     = TextEditingController(text: data?['halfFat']?.toString() ?? '');

    // ── Portion macros — Full ─────────────────────
    final fullProteinCtrl = TextEditingController(text: data?['fullProtein']?.toString() ?? '');
    final fullCarbsCtrl   = TextEditingController(text: data?['fullCarbs']?.toString() ?? '');
    final fullFatCtrl     = TextEditingController(text: data?['fullFat']?.toString() ?? '');

    // ── Save handler ─────────────────────────────
    Future<void> saveItem(BuildContext ctx) async {
      if (nameCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Item name is required'), backgroundColor: _red));
        return;
      }
      final targetRestId = selectedRestId;
      if (targetRestId == null) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please select a restaurant'), backgroundColor: _red));
        return;
      }

      final docData = <String, dynamic>{
        // ── Base info ────────────────────────────
        'name':          nameCtrl.text.trim(),
        'description':   descCtrl.text.trim(),
        'imageUrl':      imageUrlCtrl.text.trim(),
        'price':         _d(priceCtrl),
        'originalPrice': _d(originalPriceCtrl),
        'isVeg':         isVeg,
        'category':      selectedFoodCategory,
        'isAvailable':   data?['isAvailable'] ?? true,

        // ── Base nutrition ───────────────────────
        'calories': _i(caloriesCtrl),
        'protein':  _d(proteinCtrl),
        'carbs':    _d(carbsCtrl),
        'fat':      _d(fatCtrl),

        // ── Portions toggle ──────────────────────
        'portionsEnabled': portionsEnabled,

        // ── Portion prices ───────────────────────
        'quarterPrice': _d(quarterPriceCtrl),
        'halfPrice':    _d(halfPriceCtrl),
        'fullPrice':    _d(fullPriceCtrl),

        // ── Portion calories ─────────────────────
        'quarterCalories': _i(quarterCaloriesCtrl),
        'halfCalories':    _i(halfCaloriesCtrl),
        'fullCalories':    _i(fullCaloriesCtrl),

        // ── Quarter macros ───────────────────────
        'quarterProtein': _d(quarterProteinCtrl),
        'quarterCarbs':   _d(quarterCarbsCtrl),
        'quarterFat':     _d(quarterFatCtrl),

        // ── Half macros ──────────────────────────
        'halfProtein': _d(halfProteinCtrl),
        'halfCarbs':   _d(halfCarbsCtrl),
        'halfFat':     _d(halfFatCtrl),

        // ── Full macros ──────────────────────────
        'fullProtein': _d(fullProteinCtrl),
        'fullCarbs':   _d(fullCarbsCtrl),
        'fullFat':     _d(fullFatCtrl),

        'updatedAt': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(targetRestId)
          .collection('menuItems');

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
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Sheet handle ─────────────────────────
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(itemId == null ? 'Add Menu Item' : 'Edit Menu Item',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 18),

                  // ── Restaurant selector (when opened from FAB) ─
                  if (restId == null) ...[
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
                      builder: (_, snap) {
                        if (!snap.hasData) return const SizedBox();
                        return DropdownButtonFormField<String>(
                          value: selectedRestId,
                          hint: const Text('Select Restaurant'),
                          decoration: InputDecoration(
                              filled: true, fillColor: const Color(0xFFF7F7F7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _red, width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                          items: snap.data!.docs.map((doc) {
                            final d = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem<String>(value: doc.id, child: Text(d['name'] ?? ''));
                          }).toList(),
                          onChanged: (v) => setModalState(() => selectedRestId = v),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Basic info ────────────────────────────
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
                  const SizedBox(height: 12),

                  // ── Food Category ──────────────────────────
                  const Text('Food Category',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: ['Pizza','Burger','Indian','Chinese','Desserts','Biryani','Chicken','Seafood','Sandwich','Salad','Drinks']
                        .map((cat) {
                      final sel = selectedFoodCategory == cat;
                      return GestureDetector(
                        onTap: () => setModalState(() =>
                            selectedFoodCategory = sel ? '' : cat),
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
                  const SizedBox(height: 14),

                  // ── Base nutrition ─────────────────────────
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

                  // ── Veg / Non-Veg toggle ───────────────────
                  Row(children: [
                    Switch(value: isVeg, activeColor: const Color(0xFF34C759), onChanged: (v) => setModalState(() => isVeg = v)),
                    const SizedBox(width: 4),
                    Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(border: Border.all(color: isVeg ? const Color(0xFF34C759) : _red, width: 1.5), borderRadius: BorderRadius.circular(3)),
                        child: Center(child: Container(width: 6, height: 6, decoration: BoxDecoration(color: isVeg ? const Color(0xFF34C759) : _red, shape: BoxShape.circle)))),
                    const SizedBox(width: 6),
                    Text(isVeg ? 'Veg' : 'Non-Veg', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isVeg ? const Color(0xFF34C759) : _red)),
                  ]),
                  const SizedBox(height: 16),

                  // ── Portion section ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: portionsEnabled ? const Color(0xFF007AFF).withOpacity(0.05) : const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: portionsEnabled ? const Color(0xFF007AFF).withOpacity(0.3) : const Color(0xFFE5E5EA), width: 1.5)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Toggle row
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

                        // ── Prices ────────────────────────────
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

                        // ── Calories ──────────────────────────
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

                        // ── Quarter macros ────────────────────
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

                        // ── Half macros ───────────────────────
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

                        // ── Full macros ───────────────────────
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

                  // ── Save button ───────────────────────────
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: () => saveItem(ctx),
                      child: Text(itemId == null ? 'Add Item' : 'Save Changes',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Field helpers ─────────────────────────────
  Widget _itemField(TextEditingController ctrl, String label, IconData icon, {TextInputType? type}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
        prefixIcon: Icon(icon, size: 18, color: _red),
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _red, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  /// Coloured macro field with emoji prefix (base nutrition row)
  Widget _macroField(TextEditingController ctrl, String label, String emoji, Color accentColor) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 13, color: accentColor, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11.5, color: accentColor.withOpacity(0.7)),
        prefixText: '$emoji ',
        filled: true,
        fillColor: accentColor.withOpacity(0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentColor.withOpacity(0.25), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentColor.withOpacity(0.25), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentColor, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      ),
    );
  }

  /// Compact calorie field used inside portions
  Widget _portionCalField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 12, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)),
        filled: true, fillColor: const Color(0xFFFFF3E0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFFFCC80), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFFFCC80), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFFF9500), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
      ),
    );
  }

  /// Compact price field used inside portions
  Widget _portionField(TextEditingController ctrl, String label, String prefix) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)),
        prefixText: '$prefix ',
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
      ),
    );
  }

  /// Compact macro field used inside portions (Protein / Carbs / Fat per portion)
  Widget _macroPortionField(TextEditingController ctrl, String label, Color color) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 10.5, color: color.withOpacity(0.75)),
        filled: true,
        fillColor: color.withOpacity(0.07),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: color.withOpacity(0.25), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: color.withOpacity(0.25), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: color, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
        suffixText: 'g',
        suffixStyle: TextStyle(fontSize: 11, color: color.withOpacity(0.6)),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
  );

  Widget _portionSectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A3A3C)),
  );
}

// ─── ORDERS VIEW ──────────────────────────────
class _OrdersView extends StatefulWidget {
  const _OrdersView();
  @override
  State<_OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<_OrdersView> {
  static const _blue = Color(0xFF0077B6);
  String _filter = 'all';
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _filters = [
    ('all',               'All'),
    ('pending',           'Pending'),
    ('confirmed',         'Confirmed'),
    ('preparing',         'Preparing'),
    ('ready_for_pickup',  'Ready 🛵'),
    ('picked_up',         'Picked Up'),
    ('out_for_delivery',  'On the Way'),
    ('delivered',         'Delivered'),
    ('cancelled',         'Cancelled'),
  ];

  Color _chipColor(String key) {
    switch (key) {
      case 'pending':           return const Color(0xFFFF9500);
      case 'confirmed':         return const Color(0xFF007AFF);
      case 'preparing':         return const Color(0xFF5856D6);
      case 'ready_for_pickup':  return const Color(0xFFFF6B00);
      case 'picked_up':         return const Color(0xFF0077B6);
      case 'out_for_delivery':  return const Color(0xFF0077B6);
      case 'delivered':         return const Color(0xFF34C759);
      case 'cancelled':         return const Color(0xFFFF3B30);
      default:                  return _blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Order ID / keyword search bar ───────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
          style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
          decoration: InputDecoration(
            hintText: 'Search by order ID, customer name…',
            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFFAEAEB2)),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _blue),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: Color(0xFF6E6E73)),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    })
                : IconButton(
                    icon: const Icon(Icons.content_paste_rounded,
                        size: 16, color: _blue),
                    tooltip: 'Paste order ID',
                    onPressed: () async {
                      final clip =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      final text = clip?.text?.trim() ?? '';
                      if (text.isNotEmpty) {
                        _searchCtrl.text = text;
                        setState(() => _searchQuery = text.toLowerCase());
                      }
                    }),
            filled: true,
            fillColor: const Color(0xFFF7F7F7),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _blue, width: 1.5)),
          ),
        ),
      ),

      // ── Filter chips ────────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _filters.map((f) {
              final (key, label) = f;
              final isSelected = _filter == key;
              final color = _chipColor(key);
              return GestureDetector(
                onTap: () => setState(() => _filter = key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                      color: isSelected ? color : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFF6E6E73))),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const Divider(height: 1),

      // ── Orders stream ────────────────────────────────────────────
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: _blue));
            }
            final allDocs = snapshot.data?.docs ?? [];
            var docs = _filter == 'all'
                ? allDocs
                : allDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    return (data['status'] ?? '') == _filter;
                  }).toList();

            // Apply order ID / name search filter
            if (_searchQuery.isNotEmpty) {
              docs = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final id       = d.id.toLowerCase();
                final orderId  = (data['orderId']  as String? ?? '').toLowerCase();
                final userName = (data['userName'] as String? ?? '').toLowerCase();
                final restName = (data['restaurantName'] as String? ?? '').toLowerCase();
                return id.contains(_searchQuery)       ||
                       orderId.contains(_searchQuery)  ||
                       userName.contains(_searchQuery) ||
                       restName.contains(_searchQuery);
              }).toList();
            }

            if (docs.isEmpty) {
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('📋', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No orders match "$_searchQuery"'
                      : _filter == 'all' ? 'No orders yet' : 'No $_filter orders',
                  style: const TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
              ]));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final doc  = docs[i];
                final data = doc.data() as Map<String, dynamic>;
                return _OrderCard(orderId: doc.id, data: data);
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _OrderCard extends StatefulWidget {
  const _OrderCard({
    super.key,
    required this.orderId,
    required this.data,
    // When set (owner portal), only show this restaurant's items & their subtotal
    this.ownerRestaurantId,
  });
  final String orderId;
  final Map<String, dynamic> data;
  final String? ownerRestaurantId;
  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  static const _red = Color(0xFF0077B6);
  static const _validStatuses = ['pending', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled'];
  late String _localStatus;

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    final raw = (widget.data['status'] ?? 'pending') as String;
    _localStatus = _validStatuses.contains(raw) ? raw : 'cancelled';
  }

  @override
  void didUpdateWidget(_OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final raw = (widget.data['status'] ?? 'pending') as String;
    final incoming = _validStatuses.contains(raw) ? raw : 'cancelled';
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

  @override
  Widget build(BuildContext context) {
    final status = _localStatus;
    final data   = widget.data;
    final allItems = (data['items'] as List?) ?? [];

    // ── Owner view: filter to their items + their subtotal ──────────
    final ownerRid = widget.ownerRestaurantId;
    final items = ownerRid != null
        ? allItems.where((i) =>
            (i as Map<String, dynamic>)['restaurantId'] == ownerRid).toList()
        : allItems;

    final num total;
    if (ownerRid != null) {
      final perList  = data['perRestaurant'] as List?;
      final perEntry = perList?.cast<Map<String, dynamic>>()
          .where((e) => e['restaurantId'] == ownerRid)
          .firstOrNull;
      total = perEntry != null
          ? (perEntry['subtotal'] as num? ?? 0)
          : items.fold<double>(0.0, (s, i) {
              final m = i as Map<String, dynamic>;
              return s + (m['price'] as num? ?? 0).toDouble()
                       * (m['quantity'] as num? ?? 1).toInt();
            });
    } else {
      total = data['grandTotal'] ?? data['total'] ?? 0;
    }

    final userName        = data['userName'] ?? 'Customer';
    final isBundle        = data['isBundle'] == true;
    final bundleName      = data['bundleName'] as String? ?? '';
    final paymentMethod   = data['paymentMethod'] as String? ?? '';
    final deliveryAddress = data['deliveryAddress'] as String? ?? '';
    final ts              = data['createdAt'] as Timestamp?;
    final timeStr         = ts != null ? _fmtTime(ts.toDate()) : '';

    // ── Restaurant label: all names for admin, own name for owner ───
    String restaurantLabel;
    if (ownerRid != null) {
      final perList  = data['perRestaurant'] as List?;
      final perEntry = perList?.cast<Map<String, dynamic>>()
          .where((e) => e['restaurantId'] == ownerRid)
          .firstOrNull;
      restaurantLabel = perEntry?['restaurantName'] as String? ??
          (items.isNotEmpty
              ? (items.first as Map<String, dynamic>)['restaurantName'] as String? ?? ''
              : '');
    } else {
      final raw = data['restaurantName'] as String? ?? '';
      if (raw.isNotEmpty) {
        restaurantLabel = raw;
      } else {
        final names = allItems
            .map((i) => (i as Map<String, dynamic>)['restaurantName'] as String? ?? '')
            .where((n) => n.isNotEmpty).toSet().toList();
        restaurantLabel = names.isEmpty ? 'Unknown Restaurant' : names.join(', ');
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
          border: Border.all(color: const Color(0xFFF0F0F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header (always visible) ──────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              Text(
                status == 'pending'           ? '🕐' :
                status == 'confirmed'         ? '✅' :
                status == 'preparing'         ? '👨‍🍳' :
                status == 'ready_for_pickup'  ? '🛵' :
                status == 'picked_up'         ? '📦' :
                status == 'out_for_delivery'  ? '🚀' :
                status == 'delivered'         ? '🎉' : '❌',
                style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Order ID + bundle badge
                Row(children: [
                  Text('Order #${widget.orderId.substring(0, 6).toUpperCase()}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                  if (isBundle) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('📦', style: TextStyle(fontSize: 9)),
                        const SizedBox(width: 3),
                        Text(bundleName.isNotEmpty ? bundleName : 'Bundle',
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF8B5CF6))),
                      ]),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                // Customer
                Row(children: [
                  const Icon(Icons.person_outline_rounded, size: 12, color: Color(0xFF6E6E73)),
                  const SizedBox(width: 3),
                  Text(userName, style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                ]),
                const SizedBox(height: 2),
                // Restaurant name(s)
                if (restaurantLabel.isNotEmpty)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.storefront_rounded, size: 12, color: _red),
                    const SizedBox(width: 3),
                    Expanded(child: Text(restaurantLabel,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _red))),
                  ]),
                if (timeStr.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(timeStr, style: const TextStyle(fontSize: 10.5, color: Color(0xFFAEAEB2))),
                  ),
              ])),
              // Status badge + total on right
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status))),
                ),
                const SizedBox(height: 4),
                Text(
                  ownerRid != null
                      ? '₹${total.toStringAsFixed(0)}'
                      : '₹${total.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _red)),
              ]),
            ]),
          ),
        ),

        // ── Expand / collapse toggle ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              Icon(
                  _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18, color: const Color(0xFF6E6E73)),
              const SizedBox(width: 4),
              Text(_expanded ? 'Hide details' : 'View details',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73), fontWeight: FontWeight.w500)),
            ]),
          ),
        ),

        // ── Expanded details ─────────────────────────────────────────
        if (_expanded) ...[
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),

          // Items list
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              children: items.map<Widget>((item) {
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
                // For multi-restaurant admin view, show which restaurant each item is from
                final itemRest  = ownerRid == null
                    ? (itemMap['restaurantName'] as String? ?? '')
                    : '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.circle, size: 6, color: Color(0xFFE5E5EA)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(
                            '$name${portion.isNotEmpty ? ' ($portion)' : ''}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E)))),
                        Text('×$qty  ₹${itemPrice.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 12.5, color: _red, fontWeight: FontWeight.w700)),
                      ]),
                      if (itemRest.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(itemRest,
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFF6E6E73))),
                        ),
                      const SizedBox(height: 3),
                      Wrap(spacing: 4, runSpacing: 2, children: [
                        if (calories > 0) _nutritionBadge('🔥 $calories kcal', const Color(0xFFFF9500)),
                        if (protein > 0)  _nutritionBadge('💪 ${protein.toStringAsFixed(0)}g P', const Color(0xFF007AFF)),
                        if (carbs > 0)    _nutritionBadge('🌾 ${carbs.toStringAsFixed(0)}g C', const Color(0xFF34C759)),
                        if (fat > 0)      _nutritionBadge('🥑 ${fat.toStringAsFixed(0)}g F', const Color(0xFFFF9500)),
                      ]),
                    ])),
                  ]),
                );
              }).toList(),
            ),
          ),

          // Address & Payment
          if (deliveryAddress.isNotEmpty || paymentMethod.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Divider(height: 14, color: Color(0xFFF0F0F5)),
                if (deliveryAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.location_on_rounded, size: 13, color: _red),
                      const SizedBox(width: 5),
                      Expanded(child: Text(deliveryAddress,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73)))),
                    ]),
                  ),
                if (paymentMethod.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.payment_rounded, size: 13, color: _red),
                    const SizedBox(width: 5),
                    Text(paymentMethod,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
                  ]),
              ]),
            ),

          // Status changer + total footer
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _statusColor(status).withOpacity(0.3))),
                child: DropdownButton<String>(
                  value: status,
                  isDense: true,
                  underline: const SizedBox(),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _statusColor(status)),
                  style: TextStyle(fontSize: 12.5, color: _statusColor(status), fontWeight: FontWeight.w700),
                  items: [
                    'pending', 'confirmed', 'preparing',
                    'ready_for_pickup', 'picked_up',
                    'out_for_delivery', 'delivered', 'cancelled',
                  ]
                      .map((s) => DropdownMenuItem(
                          value: s, child: Text(_statusLabel(s))))
                      .toList(),
                  onChanged: (v) async {
                    if (v != null) {
                      setState(() => _localStatus = v);
                      final Map<String, dynamic> updateData = {'status': v};
                      // When marking ready_for_pickup, stamp restaurant coords so
                      // delivery agents can compute distance for radius filtering.
                      if (v == 'ready_for_pickup') {
                        final restId = widget.data['restaurantId'] as String? ?? '';
                        if (restId.isNotEmpty) {
                          try {
                            final restDoc = await FirebaseFirestore.instance
                                .collection('restaurants')
                                .doc(restId)
                                .get();
                            final rd = restDoc.data();
                            if (rd != null) {
                              final locMap = rd['location'] as Map<String, dynamic>?;
                              final lat = locMap?['lat'] ?? rd['lat'] ?? rd['latitude'];
                              final lng = locMap?['lng'] ?? rd['lng'] ?? rd['longitude'];
                              if (lat != null && lng != null) {
                                updateData['restaurantLat'] = (lat as num).toDouble();
                                updateData['restaurantLng'] = (lng as num).toDouble();
                              }
                            }
                          } catch (_) {}
                        }
                      }
                      FirebaseFirestore.instance.collection('orders').doc(widget.orderId).update(updateData);
                    }
                  },
                ),
              ),
              Text(
                ownerRid != null
                    ? 'My Items: ₹${total.toStringAsFixed(0)}'
                    : 'Total: ₹${total.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
            ]),
          ),
        ],
      ]),
    );
  }

  String _fmtTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }

  Widget _nutritionBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
  );
}

// ══════════════════════════════════════════════
// RESTAURANT ACCOUNTS MANAGER (Admin Tab)
// Admin creates email+password accounts for
// restaurant owners and links them to a restaurant
// ══════════════════════════════════════════════
class _RestaurantAccountsManager extends StatelessWidget {
  const _RestaurantAccountsManager();
  static const _red  = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFB800);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _red,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('Create Owner Account',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showCreateAccountDialog(context),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'restaurant_owner')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _red));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('👨‍🍳', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                const Text('No restaurant owner accounts yet',
                    style: TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Tap "+ Create Owner Account" to get started',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc  = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              return _OwnerAccountTile(uid: doc.id, data: data);
            },
          );
        },
      ),
    );
  }

  void _showCreateAccountDialog(BuildContext context) {
    final emailCtrl    = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nameCtrl     = TextEditingController();
    String? selectedRestId;
    String? selectedRestName;
    bool obscure   = true;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Handle
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),

                // Title
                Row(children: [
                  Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.person_add_rounded, color: _red, size: 20)),
                  const SizedBox(width: 10),
                  const Text('Create Owner Account',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                ]),
                const SizedBox(height: 6),
                Text('Owner will log in with these credentials and can manage their restaurant.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
                const SizedBox(height: 20),

                // Owner display name
                _acctField(nameCtrl, 'Owner Name', Icons.badge_rounded),
                const SizedBox(height: 12),

                // Restaurant selector
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
                  builder: (_, snap) {
                    if (!snap.hasData) return const SizedBox();
                    final restDocs = snap.data!.docs;
                    return DropdownButtonFormField<String>(
                      value: selectedRestId,
                      hint: const Text('Assign to Restaurant'),
                      decoration: _dropDecoration(),
                      items: restDocs.map((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(d['name'] ?? '', style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (v) {
                        final match = snap.data!.docs.firstWhere((d) => d.id == v);
                        final rName = (match.data() as Map<String, dynamic>)['name'] ?? '';
                        setModal(() {
                          selectedRestId   = v;
                          selectedRestName = rName;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Email
                _acctField(emailCtrl, 'Login Email', Icons.alternate_email_rounded,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 12),

                // Password
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscure,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
                  decoration: InputDecoration(
                    labelText: 'Password (min 6 chars)',
                    labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: _red),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20, color: Colors.grey),
                      onPressed: () => setModal(() => obscure = !obscure),
                    ),
                    filled: true, fillColor: const Color(0xFFF7F7F7),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(color: _red, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
                const SizedBox(height: 6),

                // Password hint
                Row(children: [
                  const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF6E6E73)),
                  const SizedBox(width: 4),
                  Text('Share these credentials with the restaurant owner.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                ]),
                const SizedBox(height: 22),

                // Submit button
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: isLoading ? null : () async {
                      final email    = emailCtrl.text.trim();
                      final password = passwordCtrl.text.trim();
                      final name     = nameCtrl.text.trim();

                      if (name.isEmpty || email.isEmpty || password.isEmpty || selectedRestId == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Fill all fields and select a restaurant'),
                            backgroundColor: _red));
                        return;
                      }
                      if (password.length < 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Password must be at least 6 characters'),
                            backgroundColor: _red));
                        return;
                      }

                      setModal(() => isLoading = true);
                      FirebaseApp? secondaryApp;
                      try {
                        // ── Create owner using a secondary Firebase app ──
                        // This avoids signing out the current admin session.
                        const secondaryAppName = 'ownerCreation';
                        try {
                          secondaryApp = Firebase.app(secondaryAppName);
                        } catch (_) {
                          secondaryApp = await Firebase.initializeApp(
                            name: secondaryAppName,
                            options: DefaultFirebaseOptions.currentPlatform,
                          );
                        }

                        final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
                        final cred = await secondaryAuth
                            .createUserWithEmailAndPassword(email: email, password: password);

                        // Write Firestore user doc (uses default app — admin is still signed in)
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(cred.user!.uid)
                            .set({
                          'uid':            cred.user!.uid,
                          'name':           name,
                          'email':          email,
                          'role':           'restaurant_owner',
                          'restaurantId':   selectedRestId,
                          'restaurantName': selectedRestName ?? '',
                          'createdAt':      FieldValue.serverTimestamp(),
                        });

                        // Tag restaurant with ownerUid
                        await FirebaseFirestore.instance
                            .collection('restaurants')
                            .doc(selectedRestId)
                            .update({'ownerUid': cred.user!.uid, 'ownerEmail': email});

                        // Sign out secondary app user (does NOT affect admin session)
                        await secondaryAuth.signOut();

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('✅ Account created for $name'),
                            backgroundColor: const Color(0xFF34C759),
                            duration: const Duration(seconds: 3),
                          ));
                        }
                      } on FirebaseAuthException catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(e.message ?? 'Error creating account'),
                              backgroundColor: _red));
                        }
                      } finally {
                        // Clean up secondary app
                        try { await secondaryApp?.delete(); } catch (_) {}
                        if (ctx.mounted) setModal(() => isLoading = false);
                      }
                    },
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _acctField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? type}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
        prefixIcon: Icon(icon, size: 18, color: _red),
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _red, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  InputDecoration _dropDecoration() => InputDecoration(
    filled: true, fillColor: const Color(0xFFF7F7F7),
    prefixIcon: const Icon(Icons.store_rounded, size: 18, color: _red),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _red, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
  );
}

// ── Owner account list tile ───────────────────
class _OwnerAccountTile extends StatelessWidget {
  const _OwnerAccountTile({required this.uid, required this.data});
  final String uid;
  final Map<String, dynamic> data;

  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final name     = data['name'] ?? 'Owner';
    final email    = data['email'] ?? '';
    final restName = data['restaurantName'] ?? '';
    final restId   = data['restaurantId'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
              color: _red.withOpacity(0.1), shape: BoxShape.circle),
          child: Center(
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _red)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
          const SizedBox(height: 2),
          Text(email, style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.store_rounded, size: 13, color: _red),
            const SizedBox(width: 4),
            Text(restName.isNotEmpty ? restName : 'No restaurant assigned',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: restName.isNotEmpty ? _red : Colors.grey)),
          ]),
        ])),
        // Delete account button
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: _red, size: 20),
          tooltip: 'Remove owner account',
          onPressed: () => _confirmDelete(context, uid, restId),
        ),
      ]),
    );
  }

  void _confirmDelete(BuildContext context, String uid, String restId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Owner Account?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
            'This permanently deletes the owner\'s login (Firebase Auth) and all their data. '
            'The restaurant will remain but become unowned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // 1. Call Cloud Function to delete from Firebase Auth
                await _deleteUserFromAuth(uid);
                // 2. Remove ownerUid fields from restaurant doc
                if (restId.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('restaurants').doc(restId)
                      .update({'ownerUid': FieldValue.delete(), 'ownerEmail': FieldValue.delete()});
                }
                // 3. Delete Firestore user doc
                await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('✅ Owner account fully deleted'),
                      backgroundColor: Color(0xFF34C759)));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error deleting account: $e'),
                      backgroundColor: _red));
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}


// ─── Shared helper: delete a user from Firebase Auth via REST API ─────────────
// Uses the same service_account.json already bundled for FCM notifications.
// No Cloud Function deployment needed.
const _fbProjectId = 'flutter-app-2026-acb44';

Future<void> _deleteUserFromAuth(String uid) async {
  // 1. Load service account and get OAuth2 token (Identity Toolkit scope)
  final jsonStr = await rootBundle.loadString('assets/service_account.json');
  final credentials = ServiceAccountCredentials.fromJson(jsonStr);
  final client = await clientViaServiceAccount(
    credentials,
    ['https://www.googleapis.com/auth/identitytoolkit'],
  );

  try {
    // 2. Call Firebase Auth REST API to delete the user
    final response = await client.post(
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/projects/$_fbProjectId/accounts:delete'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'localId': uid}),
    );
    if (response.statusCode != 200) {
      // If Auth account is already gone, that's fine — just clean up Firestore
      final bodyJson = jsonDecode(response.body) as Map<String, dynamic>;
      final errMsg = (bodyJson['error'] as Map?)?['message'] as String? ?? '';
      if (errMsg != 'USER_NOT_FOUND') {
        throw Exception('Auth delete failed: ${response.body}');
      }
      // USER_NOT_FOUND: Auth already deleted, proceed to clean Firestore only
    }
  } finally {
    client.close();
  }
}

// ─── AGENT APPLICATIONS MANAGER ───────────────
// Shows pending delivery agent applications.
// Admin can approve or reject with one tap.
class _AgentApplicationsManager extends StatelessWidget {
  const _AgentApplicationsManager();
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _red   = Color(0xFFFF3B30);
  static const _orng  = Color(0xFFFF9500);

  // ── Approve agent ─────────────────────────────
  Future<void> _approve(BuildContext context, String uid, Map<String, dynamic> data) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        'role':       'delivery_agent',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // Notify via FCM if token available
      final token = data['fcmToken'] as String?;
      if (token != null && token.isNotEmpty) {
        await FcmService.sendPushToToken(
          fcmToken: token,
          title:    '🎉 Application Approved!',
          body:     'Welcome to FoodFeast! You can now log in as a delivery partner.',
          data:     {'type': 'agent_approved'},
        );
      }

      // Write in-app notification
      await FcmService.writeNotificationForUser(
        userId: uid,
        title:  '🎉 Application Approved!',
        body:   'Welcome to FoodFeast! Log in to start delivering.',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Agent approved successfully'),
          backgroundColor: _green,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _red,
        ));
      }
    }
  }

  // ── Reject agent ──────────────────────────────
  Future<void> _reject(BuildContext context, String uid, Map<String, dynamic> data) async {
    // Confirm before rejecting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject Application?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            'Are you sure you want to reject ${data['name'] ?? 'this applicant'}\'s application?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reject',
                  style: TextStyle(color: _red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        'role':       'delivery_agent_rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      final token = data['fcmToken'] as String?;
      if (token != null && token.isNotEmpty) {
        await FcmService.sendPushToToken(
          fcmToken: token,
          title:    'Application Update',
          body:     'Unfortunately your delivery partner application was not approved at this time.',
          data:     {'type': 'agent_rejected'},
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Application rejected'),
          backgroundColor: _red,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Delivery Agents',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          bottom: const TabBar(
            labelColor: _blue,
            unselectedLabelColor: Color(0xFF6E6E73),
            indicatorColor: _blue,
            tabs: [
              Tab(text: '⏳ Pending'),
              Tab(text: '✅ Approved'),
              Tab(text: '🚫 Revoked'),
            ],
          ),
        ),
        body: TabBarView(children: [
          // ── Pending applications ───────────────────────────
          _AgentList(
            roleFilter: 'delivery_agent_pending',
            emptyMessage: 'No pending applications',
            emptyEmoji: '🛵',
            buildActions: (context, uid, data) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Approve
                GestureDetector(
                  onTap: () => _approve(context, uid, data),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _green.withOpacity(0.4), width: 1),
                    ),
                    child: const Row(children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: _green),
                      SizedBox(width: 4),
                      Text('Approve',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _green)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                // Reject
                GestureDetector(
                  onTap: () => _reject(context, uid, data),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _red.withOpacity(0.3), width: 1),
                    ),
                    child: const Row(children: [
                      Icon(Icons.cancel_outlined, size: 14, color: _red),
                      SizedBox(width: 4),
                      Text('Reject',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _red)),
                    ]),
                  ),
                ),
              ],
            ),
          ),

          // ── Approved agents ────────────────────────────────
          _AgentList(
            roleFilter: 'delivery_agent',
            emptyMessage: 'No approved agents yet',
            emptyEmoji: '🛵',
            buildActions: (context, uid, data) {
              final isOnline = data['isOnline'] == true;
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? _green.withOpacity(0.12)
                        : _orng.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isOnline ? '🟢 Online' : '⭕ Offline',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isOnline ? _green : _orng),
                  ),
                ),
                const SizedBox(width: 8),
                // Revoke
                GestureDetector(
                  onTap: () async {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .update({'role': 'delivery_agent_rejected'});
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Agent access revoked')));
                    }
                  },
                  child: const Icon(Icons.block_rounded,
                      size: 18, color: _red),
                ),
              ]);
            },
          ),

          // ── Revoked agents ─────────────────────────────────
          _AgentList(
            roleFilter: 'delivery_agent_rejected',
            emptyMessage: 'No revoked agents',
            emptyEmoji: '✅',
            buildActions: (context, uid, data) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Re-approve button
                GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        title: const Text('Re-approve Agent?',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        content: Text(
                            'Restore delivery access for ${data['name'] ?? 'this agent'}?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Re-approve',
                                  style: TextStyle(
                                      color: _green,
                                      fontWeight: FontWeight.w700))),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .update({
                      'role': 'delivery_agent',
                      'approvedAt': FieldValue.serverTimestamp(),
                    });
                    // Send FCM notification if token available
                    final token = data['fcmToken'] as String?;
                    if (token != null && token.isNotEmpty) {
                      await FcmService.sendPushToToken(
                        fcmToken: token,
                        title: '🎉 Access Restored!',
                        body:
                            'Your FoodFeast delivery partner access has been restored.',
                        data: {'type': 'agent_approved'},
                      );
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Agent re-approved successfully'),
                          backgroundColor: _green,
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _green.withOpacity(0.4), width: 1),
                    ),
                    child: const Row(children: [
                      Icon(Icons.restore_rounded, size: 14, color: _green),
                      SizedBox(width: 4),
                      Text('Re-approve',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _green)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                // Delete permanently
                GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        title: const Text('Delete Agent?',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        content: Text(
                            'Permanently remove ${data['name'] ?? 'this agent'} from the system?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete',
                                  style: TextStyle(
                                      color: _red,
                                      fontWeight: FontWeight.w700))),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .delete();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Agent deleted'),
                          backgroundColor: _red,
                        ),
                      );
                    }
                  },
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: _red),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Reusable agent list ────────────────────────
class _AgentList extends StatelessWidget {
  final String roleFilter;
  final String emptyMessage;
  final String emptyEmoji;
  final Widget Function(BuildContext, String, Map<String, dynamic>) buildActions;

  const _AgentList({
    required this.roleFilter,
    required this.emptyMessage,
    required this.emptyEmoji,
    required this.buildActions,
  });

  static const _blue = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: roleFilter)
          .orderBy('appliedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        // ── Surface Firestore errors (e.g. missing composite index) ──
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: Color(0xFFFF3B30)),
                  const SizedBox(height: 12),
                  const Text('Failed to load agents',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 8),
                  SelectableText(
                    snap.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6E6E73)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tip: Open the link above in your browser to\ncreate the missing Firestore index.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0077B6),
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _blue));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(emptyEmoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(emptyMessage,
                  style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF6E6E73),
                      fontWeight: FontWeight.w600)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc  = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final name    = data['name']  ?? 'Unknown';
            final phone   = data['phone'] ?? '';
            final vehicle = data['vehicleType'] ?? '';
            final email   = data['email'] ?? '';

            // Applied-on date
            String appliedStr = '';
            try {
              final ts = data['appliedAt'];
              if (ts != null) {
                final dt = (ts as dynamic).toDate() as DateTime;
                appliedStr = '${dt.day}/${dt.month}/${dt.year}';
              }
            } catch (_) {}

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 3))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  // Avatar
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                        color: _blue.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _blue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E))),
                      const SizedBox(height: 2),
                      Text(email,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6E6E73))),
                      if (phone.isNotEmpty)
                        Text(phone,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6E6E73))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                // Details row
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (vehicle.isNotEmpty)
                    _badge(
                        icon: Icons.two_wheeler_rounded,
                        label: vehicle,
                        color: _blue),
                  if (appliedStr.isNotEmpty)
                    _badge(
                        icon: Icons.calendar_today_rounded,
                        label: 'Applied $appliedStr',
                        color: const Color(0xFF6E6E73)),
                ]),
                const SizedBox(height: 12),
                // Actions
                buildActions(context, doc.id, data),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _badge(
      {required IconData icon,
      required String label,
      required Color color}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color)),
      ]),
    );
  }
}

// ─── USERS MANAGER ────────────────────────────
// Shows ALL users with role != 'admin' and != 'restaurant_owner'
// Admin can search by name/email and delete any user.
class _UsersManager extends StatefulWidget {
  const _UsersManager();
  @override
  State<_UsersManager> createState() => _UsersManagerState();
}

class _UsersManagerState extends State<_UsersManager> {
  static const _blue = Color(0xFF0077B6);
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration: InputDecoration(
              hintText: 'Search by name or email…',
              hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF6E6E73)),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: _blue),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF6E6E73)),
                      onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                  : null,
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                  borderSide: const BorderSide(color: _blue, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            ),
          ),
        ),

        // User list
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isNotEqualTo: 'admin')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _blue));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)));
              }
              var docs = snapshot.data?.docs ?? [];

              // Client-side search filter
              if (_searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final name  = (d['name']  ?? '').toString().toLowerCase();
                  final email = (d['email'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery) || email.contains(_searchQuery);
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('👥', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 12),
                    Text(_searchQuery.isNotEmpty ? 'No users match "$_searchQuery"' : 'No users found',
                        style: const TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
                  ]),
                );
              }

              // Count badge
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text('${docs.length} user${docs.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _blue)),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final doc  = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      return _UserTile(uid: doc.id, data: data);
                    },
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ── Individual user tile ──────────────────────
class _UserTile extends StatelessWidget {
  const _UserTile({required this.uid, required this.data});
  final String uid;
  final Map<String, dynamic> data;

  static const _blue = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final name      = data['name']  ?? 'Unknown';
    final email     = data['email'] ?? '';
    final role      = data['role']  ?? 'user';
    final photoUrl  = data['photoUrl'] ?? '';
    final phone     = data['phone'] ?? '';
    final isOwner   = role == 'restaurant_owner';
    final roleColor = isOwner ? const Color(0xFFFF9500) : _blue;
    final roleLabel = isOwner ? 'Restaurant Owner' : 'User';
    final roleIcon  = isOwner ? Icons.store_rounded : Icons.person_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(shape: BoxShape.circle, color: roleColor.withOpacity(0.1)),
          child: photoUrl.isNotEmpty
              ? ClipOval(child: Image.network(photoUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _avatarFallback(name, roleColor)))
              : _avatarFallback(name, roleColor),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
          const SizedBox(height: 2),
          Text(email, style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(phone, style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
          ],
          const SizedBox(height: 5),
          Row(children: [
            Icon(roleIcon, size: 12, color: roleColor),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Text(roleLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: roleColor)),
            ),
            if (isOwner && (data['restaurantName'] ?? '').isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(child: Text('· ${data['restaurantName']}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)))),
            ],
          ]),
        ])),
        // Delete button
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF3B30), size: 20),
          tooltip: 'Delete user',
          onPressed: () => _confirmDelete(context),
        ),
      ]),
    );
  }

  Widget _avatarFallback(String name, Color color) => Center(
    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
  );

  void _confirmDelete(BuildContext context) {
    final name  = data['name']  ?? 'this user';
    final role  = data['role']  ?? 'user';
    final restId = data['restaurantId'] ?? '';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Account?',
            style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Color(0xFF6E6E73), height: 1.5),
            children: [
              const TextSpan(text: 'This will permanently delete '),
              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
              const TextSpan(text: '\'s account from both Firebase Auth and Firestore. This cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const TextStyle(color: Color(0xFF6E6E73)).toString() == '' ? const Text('Cancel') : const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              Navigator.pop(context);
              try {
                // 1. Delete from Firebase Auth via Cloud Function
                await _deleteUserFromAuth(uid);
                // 2. If restaurant owner, unlink from restaurant
                if (role == 'restaurant_owner' && restId.isNotEmpty) {
                  await FirebaseFirestore.instance
                      .collection('restaurants').doc(restId)
                      .update({'ownerUid': FieldValue.delete(), 'ownerEmail': FieldValue.delete()});
                }
                // 3. Delete Firestore user doc
                await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('✅ $name\'s account deleted'),
                      backgroundColor: const Color(0xFF34C759)));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: const Color(0xFFFF3B30)));
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}


// ══════════════════════════════════════════════
// RESTAURANT OWNER PORTAL
// Shown when role == 'restaurant_owner'
// Can manage their own restaurant's menu + see orders
// ══════════════════════════════════════════════
class RestaurantOwnerPortal extends StatefulWidget {
  const RestaurantOwnerPortal({super.key});

  @override
  State<RestaurantOwnerPortal> createState() => _RestaurantOwnerPortalState();
}

class _RestaurantOwnerPortalState extends State<RestaurantOwnerPortal> {
  int _tab = 0;
  String? _restaurantId;
  String? _restaurantName;
  bool _loading = true;

  static const _red  = Color(0xFF0077B6);
  static const _dark = Color(0xFF1A1A2E);
  static const _gold = Color(0xFFFFB800);

  @override
  void initState() {
    super.initState();
    _loadOwnerData();
  }

  Future<void> _loadOwnerData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    setState(() {
      _restaurantId   = data?['restaurantId'] as String?;
      _restaurantName = data?['restaurantName'] as String?;
      _loading        = false;
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signOut();
    // Root AuthGate reacts to signOut automatically — no navigation needed.
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF0077B6))));
    }
    if (_restaurantId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🏪', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text('No Restaurant Assigned', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Ask your admin to assign a restaurant to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73))),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            label: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: _dark, elevation: 0, automaticallyImplyLeading: false,
        title: Row(children: [
          const Icon(Icons.storefront_rounded, color: _gold, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(text: const TextSpan(children: [
              TextSpan(text: 'Owner', style: TextStyle(color: _gold, fontWeight: FontWeight.w800, fontSize: 16)),
              TextSpan(text: ' Portal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 14)),
            ])),
            if (_restaurantName != null)
              Text(_restaurantName!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
        ]),
        actions: [IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.white70), onPressed: _logout)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(color: _dark, child: Row(children: [
            _tabBtn('Menu', 0, Icons.restaurant_menu_rounded),
            _tabBtn('Orders', 1, Icons.receipt_long_rounded),
            _tabBtn('Restaurant', 2, Icons.store_rounded),
          ])),
        ),
      ),
      body: IndexedStack(index: _tab, children: [
        _OwnerMenuManager(restaurantId: _restaurantId!),
        _OwnerOrdersView(restaurantId: _restaurantId!),
        _OwnerRestaurantEditor(restaurantId: _restaurantId!),
      ]),
    );
  }

Widget _tabBtn(String label, int index, IconData icon) {
  final isActive = _tab == index;
  return Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? _gold : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14,
                color: isActive ? _gold : Colors.white.withOpacity(0.5)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? _gold : Colors.white.withOpacity(0.5),
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

// ── Owner: Edit their restaurant profile ───────
class _OwnerRestaurantEditor extends StatefulWidget {
  const _OwnerRestaurantEditor({required this.restaurantId});
  final String restaurantId;

  @override
  State<_OwnerRestaurantEditor> createState() => _OwnerRestaurantEditorState();
}

class _OwnerRestaurantEditorState extends State<_OwnerRestaurantEditor> {
  static const _red = Color(0xFF0077B6);
  bool _saving = false;

  final _nameCtrl       = TextEditingController();
  final _imageCtrl      = TextEditingController();
  final _deliveryCtrl   = TextEditingController();
  final _categoriesCtrl = TextEditingController();
  bool _isActive   = true;
  bool _isPromoted = false;
  bool _loaded     = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final doc = await FirebaseFirestore.instance
        .collection('restaurants').doc(widget.restaurantId).get();
    final d = doc.data();
    if (d != null && mounted) {
      setState(() {
        _nameCtrl.text       = d['name'] ?? '';
        _imageCtrl.text      = d['imageUrl'] ?? '';
        _deliveryCtrl.text   = d['deliveryTime'] ?? '';
        _categoriesCtrl.text = (d['categories'] as List?)?.join(', ') ?? '';
        _isActive            = d['isActive'] ?? true;
        _isPromoted          = d['isPromoted'] ?? false;
        _loaded              = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final categories = _categoriesCtrl.text
          .split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      await FirebaseFirestore.instance
          .collection('restaurants').doc(widget.restaurantId)
          .update({
        'name':         _nameCtrl.text.trim(),
        'imageUrl':     _imageCtrl.text.trim(),
        'deliveryTime': _deliveryCtrl.text.trim(),
        'categories':   categories,
        'isActive':     _isActive,
        'isPromoted':   _isPromoted,
        'updatedAt':    FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Restaurant updated!'), backgroundColor: Color(0xFF34C759)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: _red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator(color: _red));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Restaurant Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
        const SizedBox(height: 4),
        const Text('Update your restaurant details visible to customers.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
        const SizedBox(height: 20),
        _field(_nameCtrl, 'Restaurant Name', Icons.store_rounded),
        const SizedBox(height: 12),
        _field(_imageCtrl, 'Image URL', Icons.image_outlined),
        const SizedBox(height: 12),
        _field(_deliveryCtrl, 'Preparation Time (e.g. 10 min)', Icons.access_time_rounded),
        const SizedBox(height: 12),
        _field(_categoriesCtrl, 'Categories (comma separated)', Icons.category_outlined),
        const SizedBox(height: 16),
        Row(children: [
          Switch(value: _isActive, activeColor: _red, onChanged: (v) => setState(() => _isActive = v)),
          const Text('Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 20),
          Switch(value: _isPromoted, activeColor: _red, onChanged: (v) => setState(() => _isPromoted = v)),
          const Text('Promoted', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.save_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ]),
          ),
        ),
      ]),
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
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _red, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }
}

// ── Owner: Menu manager (their restaurant only) ─
class _OwnerMenuManager extends StatelessWidget {
  const _OwnerMenuManager({required this.restaurantId});
  final String restaurantId;
  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _red,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showItemDialog(context, restaurantId, null, null),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants').doc(restaurantId)
            .collection('menuItems').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _red));
          }
          final items = snap.data?.docs ?? [];
          if (items.isEmpty) {
            return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('🍽️', style: TextStyle(fontSize: 56)),
              SizedBox(height: 12),
              Text('No menu items yet', style: TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
            ]));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final doc  = items[i];
              final item = doc.data() as Map<String, dynamic>;
              return _ownerMenuTile(context, restaurantId, doc.id, item);
            },
          );
        },
      ),
    );
  }

  Widget _ownerMenuTile(BuildContext context, String restId, String itemId, Map<String, dynamic> item) {
    final imageUrl = item['imageUrl'] ?? '';
    final calories = item['calories'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))]),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10),
          child: imageUrl.isNotEmpty
              ? Image.network(imageUrl, width: 52, height: 52, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder())
              : _placeholder()),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['name'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
          const SizedBox(height: 3),
          Row(children: [
            Text('₹${item['price'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: _red, fontWeight: FontWeight.w700)),
            if (calories > 0) ...[ const SizedBox(width: 4),
              const Icon(Icons.local_fire_department_rounded, size: 11, color: Color(0xFFFF9500)),
              Text(' $calories kcal',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6E6E73))),
            ],
          ]),
        ])),
        const SizedBox(width: 4),
        // Toggle availability
        Transform.scale(
          scale: 0.8,
          child: Switch(
            value: item['isAvailable'] ?? true,
            activeColor: _red,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => FirebaseFirestore.instance
                .collection('restaurants').doc(restId)
                .collection('menuItems').doc(itemId)
                .update({'isAvailable': v}),
          ),
        ),
        // Edit & Delete as small icon buttons
        SizedBox(
          width: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF6E6E73)),
            onPressed: () => _showItemDialog(context, restId, itemId, item),
          ),
        ),
        SizedBox(
          width: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: _red),
            onPressed: () => FirebaseFirestore.instance
                .collection('restaurants').doc(restId)
                .collection('menuItems').doc(itemId).delete(),
          ),
        ),
      ]),
    );
  }

  Widget _placeholder() => Container(width: 52, height: 52,
      decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.fastfood_rounded, color: _red, size: 24));

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  int    _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  void _showItemDialog(BuildContext context, String restId, String? itemId, Map<String, dynamic>? data) {
    // ── Base fields ──────────────────────────────
    final nameCtrl          = TextEditingController(text: data?['name'] ?? '');
    final priceCtrl         = TextEditingController(text: data?['price']?.toString() ?? '');
    final originalPriceCtrl = TextEditingController(text: data?['originalPrice']?.toString() ?? '');
    final caloriesCtrl      = TextEditingController(text: data?['calories']?.toString() ?? '');
    final proteinCtrl       = TextEditingController(text: data?['protein']?.toString() ?? '');
    final carbsCtrl         = TextEditingController(text: data?['carbs']?.toString() ?? '');
    final fatCtrl           = TextEditingController(text: data?['fat']?.toString() ?? '');
    final descCtrl          = TextEditingController(text: data?['description'] ?? '');
    final imageCtrl         = TextEditingController(text: data?['imageUrl'] ?? '');
    bool isVeg              = data?['isVeg'] ?? false;
    bool portionsEnabled    = data?['portionsEnabled'] ?? false;

    // ── Portion prices ───────────────────────────
    final quarterPriceCtrl = TextEditingController(text: data?['quarterPrice']?.toString() ?? '');
    final halfPriceCtrl    = TextEditingController(text: data?['halfPrice']?.toString() ?? '');
    final fullPriceCtrl    = TextEditingController(text: data?['fullPrice']?.toString() ?? '');

    // ── Portion calories ─────────────────────────
    final quarterCaloriesCtrl = TextEditingController(text: data?['quarterCalories']?.toString() ?? '');
    final halfCaloriesCtrl    = TextEditingController(text: data?['halfCalories']?.toString() ?? '');
    final fullCaloriesCtrl    = TextEditingController(text: data?['fullCalories']?.toString() ?? '');

    // ── Portion macros — Quarter ──────────────────
    final quarterProteinCtrl = TextEditingController(text: data?['quarterProtein']?.toString() ?? '');
    final quarterCarbsCtrl   = TextEditingController(text: data?['quarterCarbs']?.toString() ?? '');
    final quarterFatCtrl     = TextEditingController(text: data?['quarterFat']?.toString() ?? '');

    // ── Portion macros — Half ─────────────────────
    final halfProteinCtrl = TextEditingController(text: data?['halfProtein']?.toString() ?? '');
    final halfCarbsCtrl   = TextEditingController(text: data?['halfCarbs']?.toString() ?? '');
    final halfFatCtrl     = TextEditingController(text: data?['halfFat']?.toString() ?? '');

    // ── Portion macros — Full ─────────────────────
    final fullProteinCtrl = TextEditingController(text: data?['fullProtein']?.toString() ?? '');
    final fullCarbsCtrl   = TextEditingController(text: data?['fullCarbs']?.toString() ?? '');
    final fullFatCtrl     = TextEditingController(text: data?['fullFat']?.toString() ?? '');

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Handle
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(itemId == null ? 'Add Menu Item' : 'Edit Menu Item',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 18),

              // ── Basic info ─────────────────────────────
              _ownerField(nameCtrl, 'Item Name', Icons.fastfood_rounded),
              const SizedBox(height: 12),
              _ownerField(imageCtrl, 'Food Image URL', Icons.image_outlined),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _ownerField(priceCtrl, 'Price (₹)', Icons.currency_rupee_rounded, type: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _ownerField(originalPriceCtrl, 'Original (₹)', Icons.sell_outlined, type: TextInputType.number)),
              ]),
              const SizedBox(height: 12),
              _ownerField(descCtrl, 'Description', Icons.description_outlined),
              const SizedBox(height: 14),

              // ── Base nutrition ──────────────────────────
              _sectionLabel('📊 Nutrition per serving'),
              const SizedBox(height: 10),
              _ownerField(caloriesCtrl, 'Calories (kcal)', Icons.local_fire_department_rounded, type: TextInputType.number),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _macroField(proteinCtrl, 'Protein (g)', '💪', const Color(0xFF007AFF))),
                const SizedBox(width: 8),
                Expanded(child: _macroField(carbsCtrl, 'Carbs (g)', '🌾', const Color(0xFF34C759))),
                const SizedBox(width: 8),
                Expanded(child: _macroField(fatCtrl, 'Fat (g)', '🥑', const Color(0xFFFF9500))),
              ]),
              const SizedBox(height: 12),

              // ── Veg toggle ──────────────────────────────
              Row(children: [
                Switch(value: isVeg, activeColor: const Color(0xFF34C759),
                    onChanged: (v) => setModal(() => isVeg = v)),
                const SizedBox(width: 4),
                Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    border: Border.all(color: isVeg ? const Color(0xFF34C759) : _red, width: 1.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Center(child: Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: isVeg ? const Color(0xFF34C759) : _red, shape: BoxShape.circle))),
                ),
                const SizedBox(width: 6),
                Text(isVeg ? 'Veg' : 'Non-Veg',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: isVeg ? const Color(0xFF34C759) : _red)),
              ]),
              const SizedBox(height: 16),

              // ── Portions section ────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: portionsEnabled ? const Color(0xFF007AFF).withOpacity(0.05) : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: portionsEnabled ? const Color(0xFF007AFF).withOpacity(0.3) : const Color(0xFFE5E5EA),
                    width: 1.5,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Toggle row
                  Row(children: [
                    const Icon(Icons.restaurant_menu_rounded, size: 18, color: Color(0xFF007AFF)),
                    const SizedBox(width: 8),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Portion Sizes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                      Text('Allow Quarter / Half / Full ordering', style: TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73))),
                    ])),
                    Switch(value: portionsEnabled, activeColor: const Color(0xFF007AFF),
                        onChanged: (v) => setModal(() => portionsEnabled = v)),
                  ]),

                  if (portionsEnabled) ...[
                    const SizedBox(height: 14),

                    // Prices
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

                    // Calories per portion
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

                    // Quarter macros
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

                    // Half macros
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

                    // Full macros
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

              // ── Save button ─────────────────────────────
              SizedBox(width: double.infinity, height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _red,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final col = FirebaseFirestore.instance
                        .collection('restaurants').doc(restId).collection('menuItems');
                    final docData = <String, dynamic>{
                      'name':          nameCtrl.text.trim(),
                      'imageUrl':      imageCtrl.text.trim(),
                      'description':   descCtrl.text.trim(),
                      'price':         _d(priceCtrl),
                      'originalPrice': _d(originalPriceCtrl),
                      'isVeg':         isVeg,
                      'isAvailable':   data?['isAvailable'] ?? true,
                      // Base nutrition
                      'calories': _i(caloriesCtrl),
                      'protein':  _d(proteinCtrl),
                      'carbs':    _d(carbsCtrl),
                      'fat':      _d(fatCtrl),
                      // Portions
                      'portionsEnabled': portionsEnabled,
                      'quarterPrice': _d(quarterPriceCtrl),
                      'halfPrice':    _d(halfPriceCtrl),
                      'fullPrice':    _d(fullPriceCtrl),
                      'quarterCalories': _i(quarterCaloriesCtrl),
                      'halfCalories':    _i(halfCaloriesCtrl),
                      'fullCalories':    _i(fullCaloriesCtrl),
                      'quarterProtein': _d(quarterProteinCtrl),
                      'quarterCarbs':   _d(quarterCarbsCtrl),
                      'quarterFat':     _d(quarterFatCtrl),
                      'halfProtein': _d(halfProteinCtrl),
                      'halfCarbs':   _d(halfCarbsCtrl),
                      'halfFat':     _d(halfFatCtrl),
                      'fullProtein': _d(fullProteinCtrl),
                      'fullCarbs':   _d(fullCarbsCtrl),
                      'fullFat':     _d(fullFatCtrl),
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    if (itemId == null) {
                      docData['createdAt'] = FieldValue.serverTimestamp();
                      await col.add(docData);
                    } else {
                      await col.doc(itemId).update(docData);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(itemId == null ? 'Add Item' : 'Save Changes',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      )),
    );
  }

  Widget _ownerField(TextEditingController ctrl, String label, IconData icon, {TextInputType? type}) {
    return TextField(
      controller: ctrl, keyboardType: type,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
        prefixIcon: Icon(icon, size: 18, color: _red),
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: _red, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }

  Widget _macroField(TextEditingController ctrl, String label, String emoji, Color accentColor) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 13, color: accentColor, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11.5, color: accentColor.withOpacity(0.7)),
        prefixText: '$emoji ',
        filled: true, fillColor: accentColor.withOpacity(0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accentColor.withOpacity(0.25), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accentColor.withOpacity(0.25), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: accentColor, width: 1.5)),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFFFCC80), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFFFCC80), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFFF9500), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
      ),
    );
  }

  Widget _portionField(TextEditingController ctrl, String label, String prefix) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF6E6E73)),
        prefixText: '$prefix ',
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
      ),
    );
  }

  Widget _macroPortionField(TextEditingController ctrl, String label, Color color) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 10.5, color: color.withOpacity(0.75)),
        filled: true, fillColor: color.withOpacity(0.07),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: color.withOpacity(0.25), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: color.withOpacity(0.25), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: color, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 9),
        suffixText: 'g',
        suffixStyle: TextStyle(fontSize: 11, color: color.withOpacity(0.6)),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
  );

  Widget _portionSectionLabel(String text) => Text(
    text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A3A3C)),
  );
}

// ── Owner: Orders for their restaurant only ────
// StatefulWidget so the stream is created once in initState and never
// recreated on rebuild (fixes blinking and the online-only failure caused
// by the composite index requirement for where+orderBy).
class _OwnerOrdersView extends StatefulWidget {
  const _OwnerOrdersView({required this.restaurantId});
  final String restaurantId;
  @override
  State<_OwnerOrdersView> createState() => _OwnerOrdersViewState();
}

class _OwnerOrdersViewState extends State<_OwnerOrdersView> {
  static const _red = Color(0xFF0077B6);
  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    // Only filter by restaurantId — no orderBy avoids the composite index
    // requirement that caused failures when online. Sort client-side instead.
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
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _red));
        }
        if (snapshot.hasError) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Error: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
          ]));
        }
        // Sort client-side by createdAt descending (no composite index needed)
        final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? []);
        docs.sort((a, b) {
          final aTs = (a.data() as Map<String,dynamic>)['createdAt'];
          final bTs = (b.data() as Map<String,dynamic>)['createdAt'];
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          try { return (bTs as dynamic).toDate().compareTo((aTs as dynamic).toDate()); }
          catch (_) { return 0; }
        });
        if (docs.isEmpty) {
          return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('📋', style: TextStyle(fontSize: 56)),
            SizedBox(height: 12),
            Text('No orders yet', style: TextStyle(fontSize: 16, color: Color(0xFF6E6E73), fontWeight: FontWeight.w600)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc  = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _OrderCard(
              key: ValueKey(doc.id),
              orderId: doc.id,
              data: data,
              ownerRestaurantId: widget.restaurantId,
            );
          },
        );
      },
    );
  }
}
// ─── COUPON MANAGER ──────────────────────────
class _CouponManager extends StatefulWidget {
  const _CouponManager();
  @override
  State<_CouponManager> createState() => _CouponManagerState();
}

class _CouponManagerState extends State<_CouponManager> {
  static const _blue = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFB800);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);

  void _showCouponDialog(BuildContext context, String? docId, Map<String, dynamic>? existing) {
    final codeCtrl = TextEditingController(text: existing?['code'] ?? '');
    final valueCtrl = TextEditingController(text: existing?['value']?.toString() ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final minOrderCtrl = TextEditingController(text: existing?['minOrder']?.toString() ?? '');
    final maxDiscountCtrl = TextEditingController(text: existing?['maxDiscount']?.toString() ?? '');
    String discountType = existing?['type'] ?? 'percent'; // 'percent' | 'flat'
    String visualType   = existing?['visualType'] ?? 'percent'; // new
    bool   isActive     = existing?['isActive'] ?? true;

    // Load saved expiry (Timestamp → DateTime) ── new
    DateTime? expiryDate;
    final savedExpiry = existing?['expiryDate'];
    if (savedExpiry != null) {
      expiryDate = (savedExpiry as Timestamp).toDate();
    }

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(docId == null ? '🏷️ Create Coupon' : '✏️ Edit Coupon',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 18),

              // Coupon code
              _couponField(codeCtrl, 'Coupon Code (e.g. FEAST10)', Icons.confirmation_number_outlined,
                  textCapitalization: TextCapitalization.characters),
              const SizedBox(height: 12),

              // Discount type toggle
              const Text('Discount Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setModal(() => discountType = 'percent'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: discountType == 'percent' ? _blue : const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.percent_rounded, size: 16,
                          color: discountType == 'percent' ? Colors.white : const Color(0xFF6E6E73)),
                      const SizedBox(width: 6),
                      Text('Percentage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: discountType == 'percent' ? Colors.white : const Color(0xFF6E6E73))),
                    ]),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => setModal(() => discountType = 'flat'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: discountType == 'flat' ? _blue : const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.currency_rupee_rounded, size: 16,
                          color: discountType == 'flat' ? Colors.white : const Color(0xFF6E6E73)),
                      const SizedBox(width: 6),
                      Text('Flat ₹', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: discountType == 'flat' ? Colors.white : const Color(0xFF6E6E73))),
                    ]),
                  ),
                )),
              ]),
              const SizedBox(height: 12),

              // Value
              _couponField(valueCtrl,
                  discountType == 'percent' ? 'Discount % (e.g. 10 for 10%)' : 'Flat Discount ₹ (e.g. 50)',
                  discountType == 'percent' ? Icons.percent_rounded : Icons.currency_rupee_rounded,
                  type: TextInputType.number),
              const SizedBox(height: 12),

              // Min order
              _couponField(minOrderCtrl, 'Min Order Value ₹ (optional)', Icons.shopping_bag_outlined,
                  type: TextInputType.number),
              const SizedBox(height: 12),

              // Max discount (for percent type)
              if (discountType == 'percent') ...[
                _couponField(maxDiscountCtrl, 'Max Discount ₹ Cap (optional)', Icons.block_outlined,
                    type: TextInputType.number),
                const SizedBox(height: 12),
              ],

              // ── Visual Type picker ─────────────────────────────────────
              const Text('Banner Visual Style',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  _visualChip('welcome', '🎁', 'Welcome',
                      const Color(0xFF7B2FBE), visualType, (v) => setModal(() => visualType = v)),
                  _visualChip('percent', '🔥', 'Hot Deal',
                      const Color(0xFFE8321A), visualType, (v) => setModal(() => visualType = v)),
                  _visualChip('flat',    '💰', 'Flat Off',
                      const Color(0xFF00796B), visualType, (v) => setModal(() => visualType = v)),
                  _visualChip('flash',   '⚡', 'Flash',
                      const Color(0xFF1A237E), visualType, (v) => setModal(() => visualType = v)),
                  _visualChip('free',    '🚚', 'Free Ship',
                      const Color(0xFF2E7D32), visualType, (v) => setModal(() => visualType = v)),
                ],
              ),
              const SizedBox(height: 14),

              // ── Expiry date picker ─────────────────────────────────────
              const Text('Expiry Date (optional)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: expiryDate ?? DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                            primary: Color(0xFF0077B6)),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setModal(() => expiryDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: expiryDate != null
                            ? const Color(0xFF0077B6).withOpacity(0.4)
                            : Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_rounded, size: 18,
                        color: expiryDate != null
                            ? const Color(0xFF0077B6)
                            : Colors.grey),
                    const SizedBox(width: 10),
                    Text(
                      expiryDate != null
                          ? '${expiryDate!.day}/${expiryDate!.month}/${expiryDate!.year}'
                          : 'No expiry (runs indefinitely)',
                      style: TextStyle(
                        fontSize: 14,
                        color: expiryDate != null
                            ? const Color(0xFF1C1C1E)
                            : Colors.grey,
                        fontWeight: expiryDate != null
                            ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                    if (expiryDate != null)
                      GestureDetector(
                        onTap: () => setModal(() => expiryDate = null),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: Colors.grey),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),

              // Description
              _couponField(descCtrl, 'Description shown in notification', Icons.message_outlined),
              const SizedBox(height: 12),

              // Active toggle
              Row(children: [
                Switch(value: isActive, activeColor: _blue, onChanged: (v) => setModal(() => isActive = v)),
                const SizedBox(width: 8),
                Text(isActive ? 'Active' : 'Inactive',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
                        color: isActive ? _blue : const Color(0xFF6E6E73))),
              ]),
              const SizedBox(height: 20),

              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  final code = codeCtrl.text.trim().toUpperCase();
                  if (code.isEmpty) return;
                  final value = double.tryParse(valueCtrl.text.trim()) ?? 0;
                  if (value <= 0) return;
                  // Base fields safe for both add() and update()
                  final baseData = <String, dynamic>{
                    'code':       code,
                    'type':       discountType,
                    'visualType': visualType,
                    'value':      value,
                    'minOrder':   double.tryParse(minOrderCtrl.text.trim()) ?? 0,
                    if (discountType == 'percent')
                      'maxDiscount': double.tryParse(maxDiscountCtrl.text.trim()) ?? 0,
                    'description': descCtrl.text.trim(),
                    'isActive':   isActive,
                    'updatedAt':  FieldValue.serverTimestamp(),
                  };
                  // Only include expiryDate if set (add() rejects FieldValue.delete())
                  if (expiryDate != null) {
                    baseData['expiryDate'] = Timestamp.fromDate(expiryDate!);
                  }
                  if (docId == null) {
                    baseData['createdAt'] = FieldValue.serverTimestamp();
                    baseData['usageCount'] = 0;
                    await FirebaseFirestore.instance.collection('coupons').add(baseData);
                  } else {
                    // On update, explicitly delete the field if expiry was cleared
                    if (expiryDate == null) {
                      baseData['expiryDate'] = FieldValue.delete();
                    }
                    await FirebaseFirestore.instance.collection('coupons').doc(docId).update(baseData);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(docId == null ? 'Create Coupon' : 'Save Changes',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _blue,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Coupon', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        onPressed: () => _showCouponDialog(context, null, null),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('coupons')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _blue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('🏷️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              const Text('No coupons yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF6E6E73))),
              const SizedBox(height: 6),
              Text('Tap + to create your first discount coupon', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
            ]));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final isActive = data['isActive'] == true;
              final type = data['type'] ?? 'percent';
              final value = (data['value'] as num? ?? 0).toDouble();
              final usageCount = data['usageCount'] ?? 0;
              final minOrder = (data['minOrder'] as num? ?? 0).toDouble();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActive ? _blue.withOpacity(0.15) : Colors.grey.shade200,
                    width: 1.5,
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))],
                ),
                child: Column(children: [
                  // Header band
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive ? _blue.withOpacity(0.05) : Colors.grey.shade50,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isActive ? _gold.withOpacity(0.15) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.local_offer_rounded, size: 20,
                            color: isActive ? _gold : Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(data['code'] ?? '', style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800,
                            color: isActive ? const Color(0xFF1C1C1E) : Colors.grey,
                            letterSpacing: 1)),
                        if ((data['description'] as String? ?? '').isNotEmpty)
                          Text(data['description'], style: TextStyle(
                              fontSize: 11.5, color: isActive ? const Color(0xFF6E6E73) : Colors.grey.shade400)),
                      ])),
                      // Discount badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? _green.withOpacity(0.12) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          type == 'percent' ? '${value.toStringAsFixed(0)}% OFF' : '₹${value.toStringAsFixed(0)} OFF',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800,
                              color: isActive ? _green : Colors.grey),
                        ),
                      ),
                    ]),
                  ),

                  // Details row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(children: [
                      _couponDetail(Icons.shopping_bag_outlined,
                          minOrder > 0 ? 'Min ₹${minOrder.toStringAsFixed(0)}' : 'No min order',
                          const Color(0xFF6E6E73)),
                      const SizedBox(width: 16),
                      _couponDetail(Icons.people_outline_rounded,
                          '$usageCount used', _blue),
                      // Expiry chip — show on card if set
                      Builder(builder: (_) {
                        final expiryTs = data['expiryDate'];
                        if (expiryTs == null) return const SizedBox.shrink();
                        final exp = (expiryTs as Timestamp).toDate();
                        final diff = exp.difference(DateTime.now());
                        final expired = diff.isNegative;
                        final label = expired
                            ? 'Expired'
                            : diff.inDays > 0
                                ? 'Exp ${diff.inDays}d'
                                : 'Exp ${diff.inHours}h';
                        return _couponDetail(
                          Icons.schedule_rounded,
                          label,
                          expired ? _red : const Color(0xFFFF9500),
                        );
                      }),
                      const Spacer(),
                      // Toggle active
                      GestureDetector(
                        onTap: () => FirebaseFirestore.instance
                            .collection('coupons').doc(doc.id)
                            .update({'isActive': !isActive}),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isActive ? _green.withOpacity(0.1) : _red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isActive ? 'Active' : 'Inactive',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                  color: isActive ? _green : _red)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Edit
                      GestureDetector(
                        onTap: () => _showCouponDialog(context, doc.id, data),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.edit_rounded, size: 16, color: _blue),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Delete
                      GestureDetector(
                        onTap: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Coupon?'),
                              content: Text('Are you sure you want to delete "${data['code']}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await FirebaseFirestore.instance.collection('coupons').doc(doc.id).delete();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: _red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.delete_outline_rounded, size: 16, color: _red),
                        ),
                      ),
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _visualChip(
    String value,
    String emoji,
    String label,
    Color color,
    String selected,
    void Function(String) onTap,
  ) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : const Color(0xFF6E6E73),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _couponDetail(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _couponField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? type, TextCapitalization textCapitalization = TextCapitalization.none}) {
    return TextField(
      controller: ctrl, keyboardType: type, textCapitalization: textCapitalization,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
        prefixIcon: Icon(icon, size: 18, color: _blue),
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _blue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }
}

// ─── NOTIFICATION MANAGER ─────────────────────
class _NotificationManager extends StatefulWidget {
  const _NotificationManager();
  @override
  State<_NotificationManager> createState() => _NotificationManagerState();
}

class _NotificationManagerState extends State<_NotificationManager> {
  static const _blue = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFB800);
  static const _green = Color(0xFF34C759);
  static const _dark = Color(0xFF1A1A2E);

  final _titleCtrl   = TextEditingController();
  final _bodyCtrl    = TextEditingController();
  String _type = 'general'; // 'general' | 'coupon' | 'offer'
  String? _linkedCoupon;
  List<Map<String, dynamic>> _activeCoupons = [];
  bool _sending = false;
  StreamSubscription<QuerySnapshot>? _couponSub;

  @override
  void initState() {
    super.initState();
    _subscribeCoupons();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _couponSub?.cancel();
    super.dispose();
  }

  // ── Real-time coupon list — updates instantly when admin adds a coupon ──
  void _subscribeCoupons() {
    _couponSub = FirebaseFirestore.instance
        .collection('coupons')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _activeCoupons = snap.docs.map((d) {
          return {'id': d.id, ...d.data()};
        }).toList();
      });
    });
  }

  void _linkCoupon(String code) {
    setState(() {
      _linkedCoupon = code;
      final type = _activeCoupons.firstWhere((c) => c['code'] == code, orElse: () => {})['type'] ?? 'percent';
      final value = (_activeCoupons.firstWhere((c) => c['code'] == code, orElse: () => {})['value'] as num? ?? 0).toDouble();
      final discount = type == 'percent' ? '${value.toStringAsFixed(0)}%' : '₹${value.toStringAsFixed(0)}';
      _bodyCtrl.text = 'Use $code for $discount discount on your next order! 🎉';
      _titleCtrl.text = '🏷️ Exclusive Discount Just for You!';
    });
  }

  // ── FCM broadcast via HTTP v1 API ─────────────────────────────────
  //
  // HOW TO SET UP (one-time):
  // 1. Firebase Console → Project Settings → Service Accounts
  //    → "Generate new private key" → save as assets/service_account.json
  // 2. Add to pubspec.yaml:
  //      googleapis_auth: ^1.4.1
  // 3. Add to pubspec.yaml flutter assets section:
  //      assets:
  //        - assets/service_account.json
  // 4. Replace 'YOUR_FIREBASE_PROJECT_ID' below with your actual project id
  //    (found in Firebase Console → Project Settings → General)
  //
  // NOTE: This admin app is not distributed publicly so bundling the
  // service account JSON is acceptable for a final-year project admin panel.
  // ─────────────────────────────────────────────────────────────────
  static const _fcmProjectId = 'flutter-app-2026-acb44'; // ← replace

  Future<void> _sendFcmToAll({
    required String title,
    required String body,
  }) async {
    try {
      // Load service account credentials from bundled asset
      final jsonStr = await DefaultAssetBundle.of(context)
          .loadString('assets/service_account.json');

      // Build OAuth2 client scoped to FCM
      final credentials =
          ServiceAccountCredentials.fromJson(jsonStr);
      final client = await clientViaServiceAccount(
        credentials,
        ['https://www.googleapis.com/auth/firebase.messaging'],
      );

      final response = await client.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$_fcmProjectId/messages:send',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': {
            'topic': 'all_users',
            'notification': {'title': title, 'body': body},
            'data': {'click_action': 'FLUTTER_NOTIFICATION_CLICK'},
          },
        }),
      );
      client.close();
      debugPrint('FCM v1 status: ${response.statusCode}');
    } catch (e) {
      debugPrint('FCM send error: $e');
    }
  }

  Future<void> _sendNotification() async {
    final title = _titleCtrl.text.trim();
    final body  = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title and message'), backgroundColor: _blue));
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': title,
        'body': body,
        'type': _type,
        'linkedCoupon': _linkedCoupon,
        'sentAt': FieldValue.serverTimestamp(),
        'sentBy': FirebaseAuth.instance.currentUser?.uid,
        'read': false,
      });
      // Push live FCM notification to all subscribed devices
      await _sendFcmToAll(title: title, body: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Notification sent to all users!'), backgroundColor: _green));
        _titleCtrl.clear();
        _bodyCtrl.clear();
        setState(() { _type = 'general'; _linkedCoupon = null; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Compose Panel ──────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.campaign_rounded, color: _blue, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Send Notification', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                  Text('Broadcast to all users', style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                ]),
              ]),
              const SizedBox(height: 20),

              // Type chips
              const Text('Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 8),
              Row(children: [
                _typeChip('general',  '📢 General'),
                const SizedBox(width: 8),
                _typeChip('coupon',   '🏷️ Coupon'),
                const SizedBox(width: 8),
                _typeChip('offer',    '🔥 Offer'),
              ]),
              const SizedBox(height: 16),

              // Link coupon (visible when type=coupon)
              if (_type == 'coupon') ...[
                const Text('Link a Coupon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                const SizedBox(height: 8),
                if (_activeCoupons.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(10)),
                    child: const Text('No active coupons found. Create one in the Coupons tab.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                  )
                else
                  Wrap(spacing: 8, runSpacing: 8,
                    children: _activeCoupons.map((c) {
                      final code = c['code'] as String;
                      final isSelected = _linkedCoupon == code;
                      final cType = c['type'] ?? 'percent';
                      final cVal = (c['value'] as num? ?? 0).toDouble();
                      final label = cType == 'percent'
                          ? '$code (${cVal.toStringAsFixed(0)}% OFF)'
                          : '$code (₹${cVal.toStringAsFixed(0)} OFF)';
                      return GestureDetector(
                        onTap: () => _linkCoupon(code),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? _blue : const Color(0xFFF0F6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSelected ? _blue : _blue.withOpacity(0.2)),
                          ),
                          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : _blue)),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),
              ],

              // Title
              _notifField(_titleCtrl, 'Notification Title', Icons.title_rounded),
              const SizedBox(height: 12),

              // Body
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF1C1C1E)),
                decoration: InputDecoration(
                  labelText: 'Message Body',
                  labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
                  prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 56), child: Icon(Icons.message_outlined, size: 18, color: _blue)),
                  filled: true, fillColor: const Color(0xFFF7F7F7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _blue, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
              ),
              const SizedBox(height: 20),

              // Preview box
              if (_titleCtrl.text.isNotEmpty || _bodyCtrl.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [_dark, _dark.withOpacity(0.9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: _gold.withOpacity(0.2)),
                        child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 18)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'Title preview',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(_bodyCtrl.text.isNotEmpty ? _bodyCtrl.text : 'Message preview...',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75)), maxLines: 3, overflow: TextOverflow.ellipsis),
                    ])),
                  ]),
                ),

              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _sending ? null : _sendNotification,
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Send to All Users', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      ]),
              )),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Notification History ───────────────────
          const Text('Sent Notifications', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .orderBy('sentAt', descending: true)
                .limit(30)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: _blue)));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: const Center(child: Text('No notifications sent yet.', style: TextStyle(color: Color(0xFF6E6E73)))),
                );
              }
              return Column(children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
                final linked = data['linkedCoupon'] as String?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.notifications_rounded, size: 18, color: _blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(data['title'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                      const SizedBox(height: 3),
                      Text(data['body'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73)), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (linked != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: _gold.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                            child: Text('🏷️ $linked', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFCC9000))),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (sentAt != null)
                          Text(
                            '${sentAt.day}/${sentAt.month}/${sentAt.year} ${sentAt.hour}:${sentAt.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFAEAEB2)),
                          ),
                      ]),
                    ])),
                    // Delete notification log
                    GestureDetector(
                      onTap: () => FirebaseFirestore.instance.collection('notifications').doc(doc.id).delete(),
                      child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade400),
                    ),
                  ]),
                );
              }).toList());
            },
          ),
        ]),
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    final isSelected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _blue : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF6E6E73))),
      ),
    );
  }

  Widget _notifField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6E6E73)),
        prefixIcon: Icon(icon, size: 18, color: _blue),
        filled: true, fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _blue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }
}

// ─── SUPPORT INBOX ────────────────────────────
// Shows all 4 collections written by HelpSupportScreen:
//   support_tickets  — Order Issues + Refund Requests
//   problem_reports  — Report a Problem
//   support_messages — Contact Us messages
//   app_feedback     — Star ratings & comments
class _SupportInbox extends StatefulWidget {
  const _SupportInbox();
  @override
  State<_SupportInbox> createState() => _SupportInboxState();
}

class _SupportInboxState extends State<_SupportInbox>
    with SingleTickerProviderStateMixin {
  static const _blue  = Color(0xFF0077B6);
  static const _gold  = Color(0xFFFFB800);
  static const _dark  = Color(0xFF1A1A2E);
  static const _green = Color(0xFF34C759);
  static const _red   = Color(0xFFFF3B30);
  static const _orng  = Color(0xFFFF9500);

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: _dark,
        child: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: _gold,
          unselectedLabelColor: Colors.white54,
          indicatorColor: _gold,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          tabs: const [
            Tab(text: '🎫 Tickets'),
            Tab(text: '🚨 Reports'),
            Tab(text: '✉️ Messages'),
            Tab(text: '⭐ Feedback'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _SupportList(
              collection: 'support_tickets',
              titleField: 'issueType',
              subtitleBuilder: (d) =>
                  '${d['type'] == 'refund' ? '💰 Refund' : '📦 Issue'} · ${d['restaurantName'] ?? ''} · ${d['userName'] ?? ''}',
              statusField: 'status',
            ),
            _SupportList(
              collection: 'problem_reports',
              titleField: 'category',
              subtitleBuilder: (d) =>
                  '${d['restaurantName']?.isNotEmpty == true ? d['restaurantName'] + ' · ' : ''}${d['userName'] ?? ''}',
              statusField: 'status',
            ),
            _SupportList(
              collection: 'support_messages',
              titleField: 'subject',
              subtitleBuilder: (d) =>
                  '${d['topic'] ?? ''} · ${d['name'] ?? ''} · ${d['email'] ?? ''}',
              statusField: 'status',
            ),
            _FeedbackList(),
          ],
        ),
      ),
    ]);
  }
}

// ── Generic list for tickets / reports / messages ─
// Full conversation thread, order-ID search, refund account display.
class _SupportList extends StatefulWidget {
  final String collection;
  final String titleField;
  final String Function(Map<String, dynamic>) subtitleBuilder;
  final String statusField;

  const _SupportList({
    required this.collection,
    required this.titleField,
    required this.subtitleBuilder,
    required this.statusField,
  });

  @override
  State<_SupportList> createState() => _SupportListState();
}

class _SupportListState extends State<_SupportList> {
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);
  static const _red   = Color(0xFFFF3B30);

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // One reply controller + sending flag per visible doc
  final Map<String, TextEditingController> _replyCtrl = {};
  final Map<String, bool> _sending = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _replyCtrl.values) c.dispose();
    super.dispose();
  }

  TextEditingController _ctrlFor(String id) =>
      _replyCtrl.putIfAbsent(id, () => TextEditingController());

  Color _statusColor(String s) {
    switch (s) {
      case 'open':      return _orng;
      case 'unread':    return _red;
      case 'in_review': return _blue;
      case 'resolved':
      case 'read':      return _green;
      default:          return _orng;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':      return 'Open';
      case 'unread':    return 'Unread';
      case 'in_review': return 'In Review';
      case 'resolved':  return 'Resolved';
      case 'read':      return 'Read';
      default:          return s;
    }
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  // ── Send reply: appends to messages sub-collection + pushes user ──
  Future<void> _sendReply(String docId, Map<String, dynamic> data) async {
    final ctrl  = _ctrlFor(docId);
    final reply = ctrl.text.trim();
    if (reply.isEmpty) return;

    setState(() => _sending[docId] = true);
    try {
      final db = FirebaseFirestore.instance;

      // 1. Append message to sub-collection
      await db
          .collection(widget.collection)
          .doc(docId)
          .collection('messages')
          .add({
        'sender':    'admin',
        'text':      reply,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Update ticket: store latest reply snippet + bump status
      await db.collection(widget.collection).doc(docId).update({
        'adminReply':        reply,
        'repliedAt':         FieldValue.serverTimestamp(),
        widget.statusField:  'in_review',
      });

      // 3. Push + write in-app notification for the user
      final userId = data['userId'] as String?;
      if (userId != null && userId.isNotEmpty) {
        final snippet = reply.length > 80 ? '${reply.substring(0, 80)}…' : reply;
        await FcmService.sendPushToUser(
          userId: userId,
          title:  '💬 Support reply from Admin',
          body:   snippet,
          data:   {
            'type':       'admin_reply',
            'collection': widget.collection,
            'docId':      docId,
          },
        );
        await FcmService.writeNotificationForUser(
          userId:     userId,
          title:      '💬 Support reply from Admin',
          body:       snippet,
          ticketId:   docId,
          collection: widget.collection,
        );
      }

      ctrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reply sent & user notified ✅'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send reply: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending[docId] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Order-ID / keyword search bar ─────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
          style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
          decoration: InputDecoration(
            hintText: 'Search by order ID, user, or keyword…',
            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFFAEAEB2)),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _blue),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF6E6E73)),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    })
                : null,
            filled: true,
            fillColor: const Color(0xFFF7F7F7),
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _blue, width: 1.5)),
          ),
        ),
      ),

      // ── Ticket list ───────────────────────────────────────────────
      Expanded(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection(widget.collection)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _blue));
            }
            var docs = snap.data?.docs ?? [];

            // Apply search filter
            if (_searchQuery.isNotEmpty) {
              docs = docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final orderId    = (data['orderId']        as String? ?? '').toLowerCase();
                final userName   = (data['userName']       as String? ?? '').toLowerCase();
                final userEmail  = (data['userEmail']      as String? ?? '').toLowerCase();
                final issueType  = (data['issueType']      as String? ?? '').toLowerCase();
                final category   = (data['category']       as String? ?? '').toLowerCase();
                final desc       = (data['description']    as String? ?? '').toLowerCase();
                final subject    = (data['subject']        as String? ?? '').toLowerCase();
                return orderId.contains(_searchQuery)   ||
                       userName.contains(_searchQuery)  ||
                       userEmail.contains(_searchQuery) ||
                       issueType.contains(_searchQuery) ||
                       category.contains(_searchQuery)  ||
                       desc.contains(_searchQuery)      ||
                       subject.contains(_searchQuery);
              }).toList();
            }

            if (docs.isEmpty) {
              return Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Text('📭', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No results for "$_searchQuery"'
                        : 'No ${widget.collection} yet',
                    style: const TextStyle(color: Color(0xFF6E6E73),
                        fontWeight: FontWeight.w600)),
                ]),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final doc    = docs[i];
                final data   = doc.data() as Map<String, dynamic>;
                final status = data[widget.statusField] as String? ?? 'open';
                final color  = _statusColor(status);
                final isSending = _sending[doc.id] ?? false;
                final isRefund  = data['type'] == 'refund_request';
                final refundAccount = data['refundAccount'] as String?;
                final orderId = data['orderId'] as String?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.12), shape: BoxShape.circle),
                      child: Icon(
                        isRefund
                            ? Icons.currency_rupee_rounded
                            : Icons.support_agent_rounded,
                        color: color, size: 18),
                    ),
                    title: Text(
                      data[widget.titleField] as String? ??
                      data['refundReason']    as String? ??
                      data['category']        as String? ??
                      data['subject']         as String? ?? '—',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E)),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.subtitleBuilder(data),
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF6E6E73))),
                        if (orderId != null && orderId.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: orderId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(children: [
                                    const Icon(Icons.copy_rounded,
                                        size: 15, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Order ID copied — switch to Orders tab and paste to search',
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  ]),
                                  backgroundColor: _blue,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0077B6).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                    color: const Color(0xFF0077B6).withOpacity(0.25)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min,
                                  children: [
                                const Icon(Icons.receipt_long_rounded,
                                    size: 11, color: Color(0xFF0077B6)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Order: $orderId',
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        color: Color(0xFF0077B6),
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Icon(Icons.copy_rounded,
                                    size: 10, color: Color(0xFF0077B6)),
                                const SizedBox(width: 3),
                                const Text('tap to copy & search',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF0077B6),
                                        fontStyle: FontStyle.italic)),
                              ]),
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(_statusLabel(status),
                                style: TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w700,
                                    color: color)),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmtTs(data['createdAt']),
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFFAEAEB2))),
                        ]),
                      ],
                    ),
                    children: [
                      // ── Refund account (only for refund tickets) ──────────
                      if (isRefund && refundAccount != null && refundAccount.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _orng.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _orng.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.account_balance_wallet_rounded,
                                size: 16, color: _orng),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const Text('Refund Account / UPI',
                                    style: TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700,
                                        color: _orng)),
                                const SizedBox(height: 3),
                                Text(refundAccount,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w600,
                                        color: Color(0xFF1C1C1E))),
                              ]),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // ── Order amount (refund) ──────────────────────────────
                      if (isRefund && data['orderAmount'] != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: [
                            const Icon(Icons.currency_rupee_rounded, size: 14, color: Color(0xFF6E6E73)),
                            Text(
                              'Refund amount: ₹${(data['orderAmount'] as num).toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                                  color: Color(0xFF3C3C43)),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // ── Copy Order ID & search in Orders tab ──────────────
                      if (orderId != null && orderId.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: orderId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(children: [
                                  const Icon(Icons.search_rounded,
                                      size: 16, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Order ID copied to clipboard ✓',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white),
                                        ),
                                        Text(
                                          orderId,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white70),
                                        ),
                                        const Text(
                                          'Go to Orders tab → paste in search bar',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]),
                                backgroundColor: const Color(0xFF0077B6),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0077B6).withOpacity(0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF0077B6)
                                      .withOpacity(0.25)),
                            ),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0077B6)
                                      .withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.search_rounded,
                                    size: 14, color: Color(0xFF0077B6)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  const Text('Search this order in Orders tab',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0077B6))),
                                  Text(
                                    orderId,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF3C3C43),
                                        fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ]),
                              ),
                              const Icon(Icons.copy_rounded,
                                  size: 14, color: Color(0xFF0077B6)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // ── Conversation thread (live stream) ─────────────────
                      _ConversationThread(
                        collection: widget.collection,
                        docId:      doc.id,
                        initialDesc: data['description'] as String? ??
                                     data['message']     as String? ?? '',
                        createdAt:  data['createdAt'],
                        userName:   data['userName'] as String? ?? 'User',
                        fmtTs:      _fmtTs,
                      ),
                      const SizedBox(height: 10),

                      // ── Status buttons ────────────────────────────────────
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _statusBtn(doc.id, 'in_review', '🔍 In Review', _blue),
                        _statusBtn(doc.id, 'resolved',  '✅ Resolve',  _green),
                        _deleteBtn(doc.id),
                      ]),
                      const SizedBox(height: 12),

                      // ── Admin reply box ───────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F8FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _blue.withOpacity(0.2)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Reply to User',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: _blue)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _ctrlFor(doc.id),
                            maxLines: 3,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
                            decoration: InputDecoration(
                              hintText: 'Type your reply — user will get a push notification…',
                              hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFFAEAEB2)),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: _blue.withOpacity(0.3))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: _blue.withOpacity(0.3))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _blue, width: 1.5)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _blue,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              onPressed: isSending
                                  ? null
                                  : () => _sendReply(doc.id, data),
                              icon: isSending
                                  ? const SizedBox(
                                      width: 14, height: 14,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.send_rounded,
                                      size: 15, color: Colors.white),
                              label: Text(
                                  isSending ? 'Sending…' : 'Send Reply & Notify User',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _statusBtn(String docId, String newStatus,
      String label, Color color) {
    return GestureDetector(
      onTap: () => FirebaseFirestore.instance
          .collection(widget.collection)
          .doc(docId)
          .update({widget.statusField: newStatus}),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }

  Widget _deleteBtn(String docId) {
    return GestureDetector(
      onTap: () => FirebaseFirestore.instance
          .collection(widget.collection)
          .doc(docId)
          .delete(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _red.withOpacity(0.3)),
        ),
        child: const Text('🗑 Delete',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: _red)),
      ),
    );
  }
}

// ── Conversation thread widget (used by admin & user side) ────────────
// Streams the messages sub-collection and renders a chat-bubble timeline.
class _ConversationThread extends StatelessWidget {
  final String collection;
  final String docId;
  final String initialDesc;
  final dynamic createdAt;
  final String userName;
  final String Function(dynamic) fmtTs;

  const _ConversationThread({
    required this.collection,
    required this.docId,
    required this.initialDesc,
    required this.createdAt,
    required this.userName,
    required this.fmtTs,
  });

  static const _blue = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .collection('messages')
          .orderBy('createdAt')
          .snapshots(),
      builder: (ctx, snap) {
        final msgs = snap.data?.docs ?? [];

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Original user message ──────────────────────────────────
          if (initialDesc.isNotEmpty) ...[
            _bubble(
              sender: userName,
              text:   initialDesc,
              ts:     fmtTs(createdAt),
              isAdmin: false,
            ),
            const SizedBox(height: 6),
          ],

          // ── Thread messages ────────────────────────────────────────
          ...msgs.map((m) {
            final d      = m.data() as Map<String, dynamic>;
            final isAdm  = d['sender'] == 'admin';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _bubble(
                sender:  isAdm ? 'Admin' : userName,
                text:    d['text'] as String? ?? '',
                ts:      fmtTs(d['createdAt']),
                isAdmin: isAdm,
              ),
            );
          }),
        ]);
      },
    );
  }

  Widget _bubble({
    required String sender,
    required String text,
    required String ts,
    required bool isAdmin,
  }) {
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isAdmin
              ? _blue.withOpacity(0.08)
              : const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isAdmin
                ? _blue.withOpacity(0.2)
                : const Color(0xFFE5E5EA),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (isAdmin)
              const Icon(Icons.admin_panel_settings_rounded,
                  size: 12, color: _blue),
            if (isAdmin) const SizedBox(width: 4),
            Text(sender,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isAdmin ? _blue : const Color(0xFF6E6E73))),
            const SizedBox(width: 6),
            Text(ts,
                style: const TextStyle(
                    fontSize: 10, color: Color(0xFFAEAEB2))),
          ]),
          const SizedBox(height: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF3C3C43), height: 1.4)),
        ]),
      ),
    );
  }
}

// ── Star feedback list ────────────────────────────
class _FeedbackList extends StatelessWidget {
  const _FeedbackList();
  static const _blue = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFB800);

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_feedback')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _blue));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text('⭐', style: TextStyle(fontSize: 48)),
              SizedBox(height: 12),
              Text('No feedback yet',
                  style: TextStyle(color: Color(0xFF6E6E73),
                      fontWeight: FontWeight.w600)),
            ]),
          );
        }
        // Average rating header
        final ratings = docs.map((d) =>
            ((d.data() as Map)['rating'] as num?)?.toDouble() ?? 0.0).toList();
        final avg = ratings.isEmpty
            ? 0.0
            : ratings.reduce((a, b) => a + b) / ratings.length;

        return Column(children: [
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF023E8A), Color(0xFF0077B6)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(avg.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: List.generate(5, (i) => Icon(
                    i < avg.round()
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: _gold, size: 20))),
                const SizedBox(height: 4),
                Text('${docs.length} rating${docs.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
              ]),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final stars = (data['rating'] as num?)?.toInt() ?? 0;
                final comment = data['comment'] as String? ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('$stars⭐',
                            style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        ...List.generate(5, (i) => Icon(
                          i < stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: _gold, size: 14)),
                        const SizedBox(width: 8),
                        Text(data['userName'] ?? 'User',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E))),
                      ]),
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(comment,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF3C3C43),
                                height: 1.4)),
                      ],
                      const SizedBox(height: 4),
                      Text(_fmtTs(data['createdAt']),
                          style: const TextStyle(
                              fontSize: 10.5, color: Color(0xFFAEAEB2))),
                    ])),
                    GestureDetector(
                      onTap: () => FirebaseFirestore.instance
                          .collection('app_feedback')
                          .doc(docs[i].id)
                          .delete(),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: Colors.grey.shade400),
                    ),
                  ]),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}
// ══════════════════════════════════════════════
//  FINANCE TAB (Admin) — embedded FinanceDashboardScreen
// ══════════════════════════════════════════════
class _AdminFinanceTab extends StatelessWidget {
  const _AdminFinanceTab();

  @override
  Widget build(BuildContext context) {
    // We embed FinanceDashboardScreen's body directly by removing its Scaffold.
    // Since IndexedStack reuses the widget, we push a full-page route instead
    // so the user gets the standard back-navigation experience.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F1FB),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Color(0xFF0077B6),
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Finance Overview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'View COD collection amounts, restaurant\nrevenue, and agent earnings by period.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Color(0xFF6E6E73), height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0077B6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.open_in_new_rounded,
                    color: Colors.white, size: 18),
                label: const Text(
                  'Open Finance Dashboard',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FinanceDashboardScreen(
                        role: FinanceRole.admin),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}