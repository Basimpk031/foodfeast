// ─────────────────────────────────────────────
// profile_screen.dart — FoodFeast
// Updated:
//   • BMI-based calorie suggestion card below Body Metrics
//   • Edit button on calorie ring card → edit today's nutrition totals
//   • Real order count + order history sheet
//   • FIX: Edit Today's Nutrition sheet dismisses instantly (no Firestore await)
//          Snackbar shows immediately after dismiss
// ─────────────────────────────────────────────
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'calorie_tracker.dart';
import 'ai_recommendation_engine.dart'; // ✅ AI Recommendation Engine
import 'login_screen.dart';
import 'favorites_ratings_service.dart';
import 'reviews_sheet.dart';
import 'favorites_screen.dart';
import 'notification_screen.dart';
import 'help_support_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ScaffoldMessengerState? scaffoldMessenger; // ADD THIS
  const ProfileScreen({super.key, this.scaffoldMessenger}); // ADD THIS
  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  static const _red   = Color(0xFF0077B6);
  static const _blue  = Color(0xFF007AFF);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);

  Map<String, dynamic> _userData = {};
  bool _isLoading  = true;
  late final Stream<int> _orderCountStream;

  // ── Count-up animation ───────────────────────
  late AnimationController _countUpCtrl;
  late Animation<double> _countUpAnim;

  // Called by HomeScreen when this tab is selected
  void replayAnimation() {
    if (mounted) _countUpCtrl.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _countUpCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _countUpAnim =
        CurvedAnimation(parent: _countUpCtrl, curve: Curves.easeOutCubic);
    _countUpCtrl.forward();
    _loadUser();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _orderCountStream = FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .snapshots()
          .map((snap) => snap.docs.length)
          .distinct();
    } else {
      _orderCountStream = Stream.value(0);
    }
  }

  @override
  void dispose() {
    _countUpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() {
          _userData  = doc.data() ?? {};
          // Fallback: use FirebaseAuth display name/email if Firestore doc is empty
          if (_userData['name'] == null && user.displayName != null) {
            _userData['name'] = user.displayName;
          }
          if (_userData['email'] == null && user.email != null) {
            _userData['email'] = user.email;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ProfileScreen _loadUser error: $e');
      if (mounted) {
        setState(() {
          // Populate from FirebaseAuth so screen is never blank
          _userData = {
            'name': user.displayName ?? 'Foodie',
            'email': user.email ?? '',
          };
          _isLoading = false;
        });
      }
    }
  }

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    final parts = trimmed.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  double? _calcBMI() {
    final h = (_userData['height'] as num?)?.toDouble();
    final w = (_userData['weight'] as num?)?.toDouble();
    if (h == null || w == null || h <= 0) return null;
    final hM = h / 100;
    return w / (hM * hM);
  }

  CalorieSuggestion? _calcSuggestion() {
    final h   = (_userData['height'] as num?)?.toDouble();
    final w   = (_userData['weight'] as num?)?.toDouble();
    final age = (_userData['age']    as num?)?.toInt();
    if (h == null || w == null || age == null) return null;
    return CalorieSuggestion.calculate(
      weightKg:      w,
      heightCm:      h,
      age:           age,
      gender:        _userData['gender'] ?? 'Male',
      activityLevel: _userData['activityLevel'] ?? 'Moderate',
    );
  }

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25.0) return 'Normal';
    if (bmi < 30.0) return 'Overweight';
    return 'Obese';
  }

  Color _bmiColor(double bmi) {
    if (bmi < 18.5) return _blue;
    if (bmi < 25.0) return _green;
    if (bmi < 30.0) return _orng;
    return _red;
  }

  Future<void> _signOut() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Sign Out?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF6E6E73)))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              CalorieTracker.instance.reset();
              await FirebaseAuth.instance.signOut();
              // Root AuthGate reacts to signOut automatically — no navigation needed.
            },
            child: const Text('Sign Out',
                style: TextStyle(
                    color: _red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _openOrderHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderHistorySheet(uid: user.uid),
    );
  }

  // ── Edit today's nutrition totals ────────────
  void _showEditTodayNutrition() {
    final tracker = CalorieTracker.instance;
    final calCtrl  = TextEditingController(
        text: tracker.consumedCalories > 0
            ? tracker.consumedCalories.toString()
            : '');
    final proCtrl  = TextEditingController(
        text: tracker.consumedProtein > 0
            ? tracker.consumedProtein.toStringAsFixed(1)
            : '');
    final carbCtrl = TextEditingController(
        text: tracker.consumedCarbs > 0
            ? tracker.consumedCarbs.toStringAsFixed(1)
            : '');
    final fatCtrl  = TextEditingController(
        text: tracker.consumedFat > 0
            ? tracker.consumedFat.toStringAsFixed(1)
            : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
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
            Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: _red.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded,
                      color: _red, size: 18)),
              const SizedBox(width: 12),
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Edit Today\'s Nutrition',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E))),
                Text('Correct or update today\'s totals',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6E6E73))),
              ]),
            ]),
            const SizedBox(height: 20),
            _editField(calCtrl, 'Total Calories (kcal)',
                Icons.local_fire_department_rounded, _red),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _editField(proCtrl, 'Protein (g)',
                      Icons.fitness_center_rounded, _blue)),
              const SizedBox(width: 8),
              Expanded(
                  child: _editField(carbCtrl, 'Carbs (g)',
                      Icons.grain_rounded, _green)),
              const SizedBox(width: 8),
              Expanded(
                  child: _editField(fatCtrl, 'Fat (g)',
                      Icons.water_drop_rounded, _orng)),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6E6E73),
                      side: const BorderSide(
                          color: Color(0xFFE5E5EA)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14)),
                  // ── FIX: instant dismiss + instant snackbar ──────────
                  // No await before Navigator.pop — sheet closes
                  // immediately just like the Health Goals sheet does.
                  // Firestore sync runs in the background.
                  onPressed: () {
                    final cal  = int.tryParse(calCtrl.text.trim()) ?? 0;
                    final pro  = double.tryParse(proCtrl.text.trim()) ?? 0;
                    final carb = double.tryParse(carbCtrl.text.trim()) ?? 0;
                    final fat  = double.tryParse(fatCtrl.text.trim()) ?? 0;

                    // 1. Update in-memory instantly → ring & macros
                    //    refresh immediately via notifyListeners()
                    CalorieTracker.instance.editTodayNutritionLocally(
                        calories: cal, protein: pro, carbs: carb, fat: fat);

                    // 2. Dismiss the sheet right away
                    if (ctx.mounted) Navigator.pop(ctx);

                    // 3. Show snackbar immediately (no waiting)
                    widget.scaffoldMessenger?.showSnackBar(
                      SnackBar(
                        content: Text(
                          "Today's nutrition updated ✅  "
                          "$cal kcal  •  P:${pro.toStringAsFixed(1)}g  "
                          "•  C:${carb.toStringAsFixed(1)}g  •  F:${fat.toStringAsFixed(1)}g",
                        ),
                        backgroundColor: const Color(0xFF34C759),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        duration: const Duration(seconds: 3),
                      ),
                    );

                    // 4. Persist to Firestore in background (fire-and-forget)
                    CalorieTracker.instance.editTodayNutrition(
                        calories: cal, protein: pro, carbs: carb, fat: fat);
                  },
                  child: const Text('Save Changes',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _editField(TextEditingController ctrl, String label,
      IconData icon, Color color) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12, color: color),
          prefixIcon: Icon(icon, size: 18, color: color),
          filled: true,
          fillColor: color.withOpacity(0.05),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide:
                  BorderSide(color: color.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide:
                  BorderSide(color: color.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: color, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _red));
    }
    final name   = _userData['name'] ?? 'Foodie';
    final email  = _userData['email'] ?? '';
    final bmi    = _calcBMI();
    final height = _userData['height'];
    final weight = _userData['weight'];
    final suggestion = _calcSuggestion();

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 0,
      ),
      child: Column(children: [
        _buildHeader(name, email),
        const SizedBox(height: 20),
        _buildStatsRow(),
        const SizedBox(height: 16),
        _buildCalorieRingCard(),
        const SizedBox(height: 16),
        _buildHealthGoalsCard(),
        const SizedBox(height: 16),
        if (bmi != null || height != null || weight != null)
          _buildBodyMetricsCard(bmi, height, weight),
        // ✅ Calorie suggestion card — shows after Body Metrics
        if (suggestion != null) ...[
          const SizedBox(height: 16),
          _buildCalorieSuggestionCard(suggestion),
        ],
        const SizedBox(height: 16),
        _buildActionsCard(name, email),
        const SizedBox(height: 24),
        Text('FoodFeast v1.1.0',
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── Header ──────────────────────────────────
  Widget _buildHeader(String name, String email) {
    final photoUrl = (_userData['photoUrl'] as String?)?.trim() ?? '';
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF023E8A), Color(0xFF0077B6), Color(0xFF00B4D8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 28),
      child: Column(children: [
        Stack(alignment: Alignment.bottomRight, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 20)
                ]),
            child: ClipOval(
              child: photoUrl.isNotEmpty
                  ? Image.network(photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _initialsWidget(name))
                  : _initialsWidget(name),
            ),
          ),
          GestureDetector(
            onTap: _showEditProfile,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 6)
                  ]),
              child: const Icon(Icons.camera_alt_rounded,
                  size: 14, color: _red),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(name,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.3)),
        const SizedBox(height: 3),
        if (email.isNotEmpty)
          Text(email,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.8))),
      ]),
    );
  }

  Widget _initialsWidget(String name) => Center(
      child: Text(_getInitials(name),
          style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: _red)));

  // ── Stats row ────────────────────────────────
  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ]),
        child: IntrinsicHeight(
          child: Row(children: [
            // ── Orders ──────────────────────────────
            StreamBuilder<int>(
              stream: _orderCountStream,
              builder: (context, snap) {
                final orderCount = snap.data ?? 0;
                return Expanded(
              child: GestureDetector(
                onTap: _openOrderHistory,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 20, color: _red),
                    const SizedBox(height: 4),
                    Text('$orderCount',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1C1E))),
                    const Text('Orders',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF6E6E73))),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: _red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('View all',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _red)),
                    ),
                  ]),
                ),
              ),
            );
              },
            ),

            _vDivider(),

            // ── Favorites (live count from Firestore) ─
            StreamBuilder<List<FavoriteItem>>(
              stream: FavoritesRatingsService.instance.favoritesStream(),
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FavoritesScreen()),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: _statItem('$count', 'Favorites',
                        Icons.favorite_outline_rounded),
                  ),
                );
              },
            ),

            _vDivider(),

            // ── Reviews tap button ───
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RateReviewScreen()),
                ),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(children: [
                    const SizedBox(height: 6),
                    const Icon(Icons.star_rounded, size: 26, color: _red),
                    const SizedBox(height: 6),
                    const Text('Reviews',
                        style: TextStyle(
                            fontSize: 11.5, color: Color(0xFF6E6E73))),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _statItem(String value, String label, IconData icon) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Icon(icon, size: 20, color: _red),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5, color: Color(0xFF6E6E73))),
        ]),
      );

  Widget _vDivider() => Container(
      width: 1, color: const Color(0xFFE5E5EA));

  // ── Calorie ring card (with edit button) ─────
  Widget _buildCalorieRingCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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

          final double rawRatio    = tracker.goalCalories > 0
              ? tracker.consumedCalories / tracker.goalCalories
              : 0.0;
          final bool isNearLimit   = rawRatio >= 0.9 && rawRatio < 1.0;
          final bool isGoalReached = rawRatio == 1.0;
          final bool isExceeded    = rawRatio > 1.0;
          final Color ringColor    = isExceeded
              ? Colors.red
              : isGoalReached
                  ? const Color(0xFF34C759)
                  : isNearLimit
                      ? const Color(0xFFF59E0B)
                      : _red;

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4))
                ]),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: _red.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: const Icon(
                        Icons.local_fire_department_rounded,
                        color: _red,
                        size: 18)),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text("Today's Calories",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E)))),
                // ✅ Edit button
                GestureDetector(
                  onTap: _showEditTodayNutrition,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: _blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                      Icon(Icons.edit_rounded,
                          size: 13, color: _blue),
                      SizedBox(width: 4),
                      Text('Edit',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _blue)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CustomPaint(
                    painter: _RingPainter(
                        progress: progress, color: ringColor),
                    child: Center(
                        child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                          Text('$consumed',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1C1C1E))),
                          Text('of $goal',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6E6E73))),
                        ])),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                  _calorieStatRow('Consumed', consumed, ringColor),
                  const SizedBox(height: 10),
                  _calorieStatRow('Remaining', remaining, _green),
                  const SizedBox(height: 10),
                  _calorieStatRow('Goal', goal, const Color(0xFF6E6E73)),
                  if (isExceeded) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.warning_rounded,
                          size: 13, color: Colors.red),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text(
                          'You have exceeded your calorie limit!',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.red),
                        ),
                      ),
                    ]),
                  ] else if (isGoalReached) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 13, color: Color(0xFF34C759)),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text(
                          'You\'ve reached your calorie goal!',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF34C759)),
                        ),
                      ),
                    ]),
                  ] else if (isNearLimit) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 13, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text(
                          'Approaching your daily calorie limit!',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF59E0B)),
                        ),
                      ),
                    ]),
                  ],
                  if (tracker.consumedProtein > 0 ||
                      tracker.consumedCarbs > 0 ||
                      tracker.consumedFat > 0) ...[
                    const SizedBox(height: 12),
                    const Divider(
                        height: 1, color: Color(0xFFF0F0F0)),
                    const SizedBox(height: 8),
                    _macroSmallRow(
                        'P', tracker.consumedProtein * t, _blue),
                    const SizedBox(height: 3),
                    _macroSmallRow(
                        'C', tracker.consumedCarbs * t, _green),
                    const SizedBox(height: 3),
                    _macroSmallRow(
                        'F', tracker.consumedFat * t, _orng),
                  ],
                ])),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _macroSmallRow(String label, double value, Color color) =>
      Row(children: [
        Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label: ',
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
        Text('${value.toStringAsFixed(1)}g',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      ]);

  Widget _calorieStatRow(String label, int value, Color color) =>
      Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5, color: Color(0xFF6E6E73))),
          Text('$value kcal',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ]),
      ]);

  // ── Health goals card ────────────────────────
  Widget _buildHealthGoalsCard() {
    final tracker       = CalorieTracker.instance;
    final goal          = (_userData['goalCalories'] as num?)?.toInt() ?? tracker.goalCalories;
    final activityLevel = _userData['activityLevel'] ?? 'Moderate';
    final List<String> dietPrefs = List<String>.from(_userData['dietPreferences'] ?? ['Balanced']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: _red.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.track_changes_rounded,
                    color: _red, size: 18)),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Health Goals',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E)))),
            GestureDetector(
              onTap: () =>
                  _showEditHealthGoals(goal, activityLevel, dietPrefs),
              child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: _red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('Edit',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _red))),
            ),
          ]),
          const SizedBox(height: 18),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            const Text('Daily Calorie Goal',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFF6E6E73))),
            Text('$goal cal',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _red)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ((goal - 1200) / (4000 - 1200)).clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFF0F0F0),
              valueColor: const AlwaysStoppedAnimation<Color>(_red),
              minHeight: 8,
            ),
          ),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                const Text('1200',
                    style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFAEAEB2))),
                const Text('4000',
                    style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFAEAEB2))),
              ])),
          const SizedBox(height: 16),
          const Text('Activity Level',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF6E6E73))),
          const SizedBox(height: 8),
          Row(
              children:
                  ['Light', 'Moderate', 'Active'].map((a) {
            final isSel = activityLevel == a;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                    color: isSel ? _red : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isSel
                            ? _red
                            : const Color(0xFFE5E5EA),
                        width: 1.5)),
                child: Text(a,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isSel
                            ? Colors.white
                            : const Color(0xFF6E6E73))),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),
          const Text('Diet Preferences',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF6E6E73))),
          const SizedBox(height: 8),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Balanced',
                'Low Carb',
                'High Protein',
                'Vegan',
                'Keto'
              ].map((d) {
            final isSel = dietPrefs.contains(d);
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                  color: isSel ? _red : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSel ? _red : const Color(0xFFE5E5EA),
                      width: 1.5)),
              child: Text(d,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isSel
                          ? Colors.white
                          : const Color(0xFF6E6E73))),
            );
          }).toList()),
        ]),
      ),
    );
  }

  // ── Body metrics card ────────────────────────
  Widget _buildBodyMetricsCard(double? bmi, dynamic height, dynamic weight) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: _red.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.monitor_heart_outlined,
                    color: _red, size: 18)),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Body Metrics',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E)))),
            // Edit body metrics button
            GestureDetector(
              onTap: _showEditProfile,
              child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: _green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                    Icon(Icons.edit_rounded,
                        size: 13, color: _green),
                    SizedBox(width: 4),
                    Text('Update',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _green)),
                  ])),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            if (weight != null)
              Expanded(
                  child: _metricTile(
                      Icons.monitor_weight_outlined,
                      'Weight',
                      '${weight.toStringAsFixed(1)} kg',
                      _blue)),
            if (weight != null && height != null)
              const SizedBox(width: 12),
            if (height != null)
              Expanded(
                  child: _metricTile(Icons.height_rounded, 'Height',
                      '${height.toStringAsFixed(0)} cm', _green)),
          ]),
          if (bmi != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _bmiColor(bmi).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _bmiColor(bmi).withOpacity(0.3),
                      width: 1.5)),
              child: Row(children: [
                Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: _bmiColor(bmi).withOpacity(0.15),
                        shape: BoxShape.circle),
                    child: const Text('🍏',
                        style: TextStyle(fontSize: 20),
                        textAlign: TextAlign.center)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                  Text(
                      'BMI: ${bmi.toStringAsFixed(1)} (${_bmiCategory(bmi)})',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _bmiColor(bmi))),
                  Text(
                      bmi < 18.5
                          ? 'Target: gain weight'
                          : bmi < 25
                              ? 'You\'re at a healthy weight!'
                              : 'Target: lose weight',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6E6E73))),
                ])),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _metricTile(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: color.withOpacity(0.2), width: 1.5)),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF6E6E73))),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
        ]),
      ]),
    );
  }

  // ✅ BMI-based calorie suggestion card
  Widget _buildCalorieSuggestionCard(CalorieSuggestion s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: _orng.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.tips_and_updates_rounded,
                    color: _orng, size: 18)),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Calorie Targets',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E)))),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _bmiColor(s.bmi).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('BMI ${s.bmi.toStringAsFixed(1)}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _bmiColor(s.bmi))),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              'Based on your height, weight, age & activity level',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 18),

          // Three goal tiles
          Row(children: [
            Expanded(
                child: _goalTile(
              emoji: '📉',
              label: 'Lose Weight',
              kcal: s.loseWeight,
              subtitle: '~500 kcal deficit',
              color: _red,
              isRecommended: s.bmi >= 25,
            )),
            const SizedBox(width: 10),
            Expanded(
                child: _goalTile(
              emoji: '⚖️',
              label: 'Maintain',
              kcal: s.maintain,
              subtitle: 'Your TDEE',
              color: _blue,
              isRecommended:
                  s.bmi >= 18.5 && s.bmi < 25,
            )),
            const SizedBox(width: 10),
            Expanded(
                child: _goalTile(
              emoji: '📈',
              label: 'Gain Weight',
              kcal: s.gainWeight,
              subtitle: '~500 kcal surplus',
              color: _green,
              isRecommended: s.bmi < 18.5,
            )),
          ]),

          const SizedBox(height: 14),
          // Apply recommendation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: Color(0xFF6E6E73)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      s.bmi < 18.5
                          ? 'You\'re underweight. A surplus diet + strength training is recommended.'
                          : s.bmi < 25
                              ? 'Your BMI is healthy! Maintain your current calorie intake.'
                              : 'A moderate calorie deficit with regular exercise is recommended.',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6E6E73)))),
            ]),
          ),
          const SizedBox(height: 14),

          // One-tap apply button
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _bmiColor(s.bmi),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0),
              onPressed: () async {
                final recommended = s.bmi < 18.5
                    ? s.gainWeight
                    : s.bmi < 25
                        ? s.maintain
                        : s.loseWeight;
                await CalorieTracker.instance
                    .updateGoal(recommended);
                // ✅ AI: refresh recommendations after goal change
                FoodRecommendationEngine.instance.invalidateCache();
                FoodRecommendationEngine.instance.getRecommendations();
                // Also save to Firestore
                final user =
                    FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .update({'goalCalories': recommended});
                }
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(
                    content: Text(
                        'Goal updated to $recommended kcal ✅'),
                    backgroundColor: _green,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
              child: Text(
                  'Apply Recommended: ${s.bmi < 18.5 ? s.gainWeight : s.bmi < 25 ? s.maintain : s.loseWeight} kcal',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _goalTile({
    required String emoji,
    required String label,
    required int kcal,
    required String subtitle,
    required Color color,
    required bool isRecommended,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
          color: isRecommended
              ? color.withOpacity(0.1)
              : const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isRecommended
                  ? color.withOpacity(0.4)
                  : const Color(0xFFE5E5EA),
              width: isRecommended ? 2 : 1)),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('$kcal',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isRecommended
                    ? color
                    : const Color(0xFF1C1C1E))),
        Text('kcal/day',
            style: const TextStyle(
                fontSize: 9, color: Color(0xFF6E6E73))),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                fontSize: 9,
                color: color.withOpacity(0.7)),
            textAlign: TextAlign.center),
        if (isRecommended) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6)),
            child: const Text('✓ For you',
                style: TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
    );
  }

  // ── Actions card ─────────────────────────────
  Widget _buildActionsCard(String name, String email) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 4))
            ]),
        child: Column(children: [
          _actionTile(Icons.manage_accounts_rounded,
              'Account Settings', _blue, _showEditProfile),
          _divider(),
          _actionTile(Icons.receipt_long_rounded,
              'Order History', _orng, _openOrderHistory),
          _divider(),
          _actionTile(
            Icons.rate_review_outlined,
            'Rate & Review',
            const Color(0xFFFF9500),
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RateReviewScreen()),
            ),
          ),
          _divider(),
          _actionTile(Icons.favorite_outline_rounded,
              'Favorites', const Color(0xFFFF2D55),
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FavoritesScreen()),
              )),
          _divider(),
          _actionTile(Icons.notifications_outlined,
            'Notifications', _orng, () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            )),
          _divider(),
          _actionTile(Icons.help_outline_rounded, 'Help & Support',
              const Color(0xFF6E6E73),
              () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const HelpSupportScreen()))),
          _divider(),
          _actionTile(
              Icons.logout_rounded, 'Logout', _red, _signOut),
        ]),
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, Color color,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 14),
          Text(label,
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E))),
          const Spacer(),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: Colors.grey[400]),
        ]),
      ),
    );
  }

  Widget _divider() => const Divider(
      height: 1,
      indent: 68,
      endIndent: 18,
      color: Color(0xFFE5E5EA));

  // ── Edit Health Goals ─────────────────────────
  void _showEditHealthGoals(int currentGoal, String currentActivity,
      List<String> currentDiet) {
    // Clamp to slider range so values above 4000 don't crash the Slider assertion
    int tempGoal        = currentGoal.clamp(1200, 4000);
    String tempActivity = currentActivity;
    List<String> tempDiet = List.from(currentDiet);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
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
              const Text('Edit Health Goals',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 20),
              Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                const Text('Daily Calorie Goal',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text('$tempGoal kcal',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _red)),
              ]),
              const SizedBox(height: 8),
              Slider(
                  value: tempGoal.toDouble(),
                  min: 1200,
                  max: 4000,
                  divisions: 56,
                  activeColor: _red,
                  inactiveColor: _red.withOpacity(0.2),
                  onChanged: (v) =>
                      setModal(() => tempGoal = v.round())),
              const SizedBox(height: 16),
              const Text('Activity Level',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                  children: ['Light', 'Moderate', 'Active']
                      .map((a) {
                final isSelected = tempActivity == a;
                return Expanded(
                    child: GestureDetector(
                  onTap: () =>
                      setModal(() => tempActivity = a),
                  child: AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10),
                    decoration: BoxDecoration(
                        color: isSelected
                            ? _red
                            : const Color(0xFFF7F7F7),
                        borderRadius:
                            BorderRadius.circular(12),
                        border: Border.all(
                            color: isSelected
                                ? _red
                                : const Color(0xFFE5E5EA))),
                    child: Center(
                        child: Text(a,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(
                                        0xFF6E6E73)))),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 16),
              const Text('Diet Preferences',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'Balanced',
                    'Low Carb',
                    'High Protein',
                    'Vegan',
                    'Keto'
                  ].map((d) {
                final isSelected = tempDiet.contains(d);
                return GestureDetector(
                  onTap: () => setModal(() {
                    if (isSelected) {
                      tempDiet.remove(d);
                    } else {
                      tempDiet.add(d);
                    }
                  }),
                  child: AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: isSelected
                            ? _red
                            : const Color(0xFFF7F7F7),
                        borderRadius:
                            BorderRadius.circular(20),
                        border: Border.all(
                            color: isSelected
                                ? _red
                                : const Color(
                                    0xFFE5E5EA))),
                    child: Text(d,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : const Color(
                                    0xFF6E6E73))),
                  ),
                );
              }).toList()),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14))),
                  onPressed: () async {
                    final user =
                        FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      // ✅ AI: refresh recommendations after profile update
                        FoodRecommendationEngine.instance.invalidateCache();
                        FoodRecommendationEngine.instance.getRecommendations();
                        await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .update({
                        'goalCalories': tempGoal,
                        'activityLevel': tempActivity,
                        'dietPreferences': tempDiet,
                      });
                      await CalorieTracker.instance
                          .updateGoal(tempGoal);
                      setState(() {
                        _userData['goalCalories'] =
                            tempGoal;
                        _userData['activityLevel'] =
                            tempActivity;
                        _userData['dietPreferences'] =
                            tempDiet;
                      });
                    }
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
      )),
    );
  }

  // ── Edit Profile ─────────────────────────────
  void _showEditProfile() {
    final nameCtrl     = TextEditingController(text: _userData['name'] ?? '');
    final phoneCtrl    = TextEditingController(text: (_userData['phone'] ?? '').toString().replaceFirst('+91', ''));
    final ageCtrl      = TextEditingController(text: _userData['age']?.toString() ?? '');
    final heightCtrl   = TextEditingController(text: _userData['height']?.toString() ?? '');
    final weightCtrl   = TextEditingController(text: _userData['weight']?.toString() ?? '');
    final photoUrlCtrl = TextEditingController(text: _userData['photoUrl'] ?? '');
    String tempGender  = _userData['gender'] ?? 'Male';
    String previewUrl  = _userData['photoUrl'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: const Color(0xFFE5E5EA),
                          borderRadius:
                              BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Account Settings',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 20),
              const Text('Profile Photo',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF0F0F0),
                      border: Border.all(
                          color: _red.withOpacity(0.3),
                          width: 2)),
                  child: ClipOval(
                      child: previewUrl.isNotEmpty
                          ? Image.network(previewUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _initialsWidget(_userData[
                                          'name'] ??
                                      'U'))
                          : _initialsWidget(
                              _userData['name'] ?? 'U')),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: TextField(
                  controller: photoUrlCtrl,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1C1C1E)),
                  decoration: InputDecoration(
                      labelText: 'Paste photo URL',
                      labelStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6E6E73)),
                      hintText: 'https://...',
                      prefixIcon: const Icon(
                          Icons.link_rounded,
                          size: 20,
                          color: _red),
                      filled: true,
                      fillColor: const Color(0xFFF7F7F7),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(13),
                          borderSide: const BorderSide(
                              color: Color(0xFFE5E5EA))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(13),
                          borderSide: const BorderSide(
                              color: Color(0xFFE5E5EA))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(13),
                          borderSide: const BorderSide(
                              color: _red, width: 1.8)),
                      contentPadding:
                          const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 12)),
                  onChanged: (v) =>
                      setModal(() => previewUrl = v.trim()),
                )),
              ]),
              const SizedBox(height: 18),
              const Divider(color: Color(0xFFF0F0F0)),
              const SizedBox(height: 14),
              _sheetField(nameCtrl, 'Full Name',
                  Icons.person_outline_rounded),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF1C1C1E)),
                decoration: InputDecoration(
                    labelText: 'Phone Number',
                    counterText: '',
                    prefixIcon: const Icon(
                        Icons.phone_outlined,
                        size: 20,
                        color: _red),
                    prefix: const Text('+91 ',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    filled: true,
                    fillColor: const Color(0xFFF7F7F7),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(13),
                        borderSide: const BorderSide(
                            color: Color(0xFFE5E5EA))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(13),
                        borderSide: const BorderSide(
                            color: Color(0xFFE5E5EA))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(13),
                        borderSide: const BorderSide(
                            color: _red, width: 1.8)),
                    contentPadding:
                        const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 14)),
              ),
              const SizedBox(height: 16),
              const Text('Gender',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                  children: ['Male', 'Female', 'Other']
                      .map((g) {
                final isSel = tempGender == g;
                return Expanded(
                    child: GestureDetector(
                  onTap: () =>
                      setModal(() => tempGender = g),
                  child: AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10),
                    decoration: BoxDecoration(
                        color: isSel
                            ? _red
                            : const Color(0xFFF7F7F7),
                        borderRadius:
                            BorderRadius.circular(12),
                        border: Border.all(
                            color: isSel
                                ? _red
                                : const Color(
                                    0xFFE5E5EA))),
                    child: Center(
                        child: Text(g,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSel
                                    ? Colors.white
                                    : const Color(
                                        0xFF6E6E73)))),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _sheetField(ageCtrl, 'Age',
                        Icons.cake_outlined,
                        type: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(
                    child: _sheetField(heightCtrl,
                        'Height (cm)', Icons.height_rounded,
                        type: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(
                    child: _sheetField(weightCtrl,
                        'Weight (kg)',
                        Icons.monitor_weight_outlined,
                        type: TextInputType.number)),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14))),
                  onPressed: () async {
                    final user =
                        FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      final newName =
                          nameCtrl.text.trim();
                      final phone =
                          phoneCtrl.text.trim();
                      final h = double.tryParse(
                          heightCtrl.text);
                      final w = double.tryParse(
                          weightCtrl.text);
                      double? bmi;
                      if (h != null &&
                          w != null &&
                          h > 0) {
                        final hM = h / 100;
                        bmi = w / (hM * hM);
                      }
                      final newPhotoUrl =
                          photoUrlCtrl.text.trim();
                      final updates = {
                        'name': newName,
                        'phone': phone.isEmpty
                            ? ''
                            : '+91$phone',
                        'gender': tempGender,
                        'age': int.tryParse(
                                ageCtrl.text) ??
                            _userData['age'],
                        'height':
                            h ?? _userData['height'],
                        'weight':
                            w ?? _userData['weight'],
                        'photoUrl': newPhotoUrl,
                        if (bmi != null) 'bmi': bmi,
                      };
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .update(updates);
                      await user
                          .updateDisplayName(newName);
                      setState(() =>
                          _userData.addAll(updates));
                    }
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
      )),
    );
  }

  Widget _sheetField(TextEditingController ctrl,
      String label, IconData icon,
      {TextInputType? type}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(
          fontSize: 14, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              fontSize: 13.5, color: Color(0xFF6E6E73)),
          prefixIcon: Icon(icon, size: 20, color: _red),
          filled: true,
          fillColor: const Color(0xFFF7F7F7),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E5EA))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E5EA))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
                  const BorderSide(color: _red, width: 1.8)),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 14, horizontal: 14)),
    );
  }
}

// ─────────────────────────────────────────────
// Order History Sheet
// ─────────────────────────────────────────────
class _OrderHistorySheet extends StatelessWidget {
  final String uid;
  static const _red = Color(0xFF0077B6);
  const _OrderHistorySheet({required this.uid});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SizedBox(height: 12),
          Center(
              child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Icon(Icons.receipt_long_rounded, color: _red, size: 22),
              SizedBox(width: 10),
              Text('Order History',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C1E))),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('userId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: _red));
                }
                // Sort client-side by createdAt descending
                final docs = List<QueryDocumentSnapshot>.from(
                    snapshot.data?.docs ?? []);
                docs.sort((a, b) {
                  final aTs = (a.data() as Map<String, dynamic>)['createdAt'];
                  final bTs = (b.data() as Map<String, dynamic>)['createdAt'];
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  try {
                    return (bTs as dynamic).toDate().compareTo((aTs as dynamic).toDate());
                  } catch (_) { return 0; }
                });
                if (docs.isEmpty) {
                  return const Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Text('📦', style: TextStyle(fontSize: 56)),
                        SizedBox(height: 12),
                        Text('No orders yet',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E))),
                      ]));
                }
                return ListView.builder(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc  = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return _HistoryOrderCard(orderId: doc.id, data: data);
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// History Order Card — expandable + cancel button
// ─────────────────────────────────────────────
class _HistoryOrderCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  const _HistoryOrderCard({required this.orderId, required this.data});

  @override
  State<_HistoryOrderCard> createState() => _HistoryOrderCardState();
}

class _HistoryOrderCardState extends State<_HistoryOrderCard> {
  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  bool _expanded   = false;
  bool _cancelling = false;

  Color _statusColor(String s) {
    switch (s) {
      case 'confirmed': return const Color(0xFF007AFF);
      case 'preparing': return const Color(0xFFFF9500);
      case 'delivered': return const Color(0xFF34C759);
      case 'cancelled': return _red;
      default:          return const Color(0xFF6E6E73);
    }
  }

  String _statusEmoji(String s) {
    switch (s) {
      case 'confirmed': return '✅';
      case 'preparing': return '👨‍🍳';
      case 'delivered': return '🎉';
      case 'cancelled': return '❌';
      default:          return '🕐';
    }
  }

  String _fmt(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  bool get _canCancel {
    final status = widget.data['status'] ?? 'pending';
    return status == 'pending' || status == 'confirmed';
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel Order?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        content: const Text(
            'Are you sure you want to cancel this order? '
            'The calories will be removed from your tracker.',
            style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Order',
                  style: TextStyle(color: Color(0xFF6E6E73)))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Cancel',
                  style: TextStyle(color: _red, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      // 1. Update order status in Firestore
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({'status': 'cancelled'});

      // 2. Reduce calories/macros from tracker
      final calories = (widget.data['totalCalories'] ?? 0) as int;
      final protein  = (widget.data['totalProtein']  ?? 0).toDouble();
      final carbs    = (widget.data['totalCarbs']    ?? 0).toDouble();
      final fat      = (widget.data['totalFat']      ?? 0).toDouble();

      if (calories > 0 || protein > 0 || carbs > 0 || fat > 0) {
        final tracker = CalorieTracker.instance;
        final newCal  = (tracker.consumedCalories - calories).clamp(0, 99999);
        final newPro  = (tracker.consumedProtein  - protein).clamp(0.0, 99999.0);
        final newCarb = (tracker.consumedCarbs    - carbs).clamp(0.0, 99999.0);
        final newFat  = (tracker.consumedFat      - fat).clamp(0.0, 99999.0);
        await tracker.editTodayNutrition(
          calories: newCal, protein: newPro, carbs: newCarb, fat: newFat,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order cancelled & calories removed ✅'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to cancel: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status      = widget.data['status'] ?? 'pending';
    final items       = (widget.data['items'] as List?) ?? [];
    final total       = widget.data['grandTotal'] ?? widget.data['total'] ?? 0;
    final paymentMethod   = widget.data['paymentMethod'] as String? ?? '';
    final deliveryAddress = widget.data['deliveryAddress'] as String? ?? '';
    final calories    = widget.data['totalCalories'] ?? 0;
    final protein     = (widget.data['totalProtein'] ?? 0).toDouble();
    final carbs       = (widget.data['totalCarbs']   ?? 0).toDouble();
    final fat         = (widget.data['totalFat']     ?? 0).toDouble();
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4))],
          border: Border.all(color: const Color(0xFFF0F0F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header row ───────────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(children: [
              Text(_statusEmoji(status), style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Order #${widget.orderId.substring(0, 6).toUpperCase()}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E))),
                Text(widget.data['restaurantName'] ?? '',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                if (_fmt(widget.data['createdAt']).isNotEmpty)
                  Text(_fmt(widget.data['createdAt']),
                      style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2))),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                ),
                const SizedBox(height: 4),
                Text('₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _red)),
              ]),
            ]),
          ),
        ),

        // ── View details / Hide details toggle ───────────────────────────
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
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6E6E73), fontWeight: FontWeight.w500)),
            ]),
          ),
        ),

        // ── Expanded details ─────────────────────────────────────────────
        if (_expanded) ...[
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),

          // Items list
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(children: items.map<Widget>((item) {
                final iMap     = item as Map<String, dynamic>;
                final iName    = iMap['name'] ?? '';
                final iQty     = iMap['quantity'] ?? 1;
                final _pp = iMap['portionPrice'];
                final iPrice = (_pp != null && (_pp as num) > 0)
                    ? (_pp as num).toDouble()
                    : (iMap['price'] ?? 0).toDouble();
                final iPortion = iMap['portion'];
                final iCal     = iMap['calories'] ?? 0;
                final iProtein = (iMap['protein'] ?? 0).toDouble();
                final iCarbs   = (iMap['carbs'] ?? 0).toDouble();
                final iFat     = (iMap['fat'] ?? 0).toDouble();
                final isVeg    = iMap['isVeg'] ?? true;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                        width: 14, height: 14,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                            border: Border.all(color: isVeg ? const Color(0xFF34C759) : _red, width: 1.5),
                            borderRadius: BorderRadius.circular(2)),
                        child: Center(child: Container(width: 5, height: 5,
                            decoration: BoxDecoration(color: isVeg ? const Color(0xFF34C759) : _red, shape: BoxShape.circle)))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                          iQty > 1
                              ? '$iQty× $iName${iPortion != null && iPortion.isNotEmpty ? ' ($iPortion)' : ''}'
                              : '$iName${iPortion != null && iPortion.isNotEmpty ? ' ($iPortion)' : ''}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
                      if (iCal > 0 || iProtein > 0)
                        Wrap(spacing: 5, children: [
                          if (iCal > 0)     _miniChip('🔥 ${iCal}kcal',                    const Color(0xFFFF9500)),
                          if (iProtein > 0) _miniChip('P:${iProtein.toStringAsFixed(0)}g', const Color(0xFF007AFF)),
                          if (iCarbs > 0)   _miniChip('C:${iCarbs.toStringAsFixed(0)}g',   const Color(0xFF34C759)),
                          if (iFat > 0)     _miniChip('F:${iFat.toStringAsFixed(0)}g',     _red),
                        ]),
                    ])),
                    Text('₹${(iPrice * iQty).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
                  ]),
                );
              }).toList()),
            ),

          // ── Address & Payment info ────────────────────────────────────
          if (deliveryAddress.isNotEmpty || paymentMethod.isNotEmpty) ...[
            const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (deliveryAddress.isNotEmpty) ...[
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF0077B6)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(deliveryAddress,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73)))),
                    ]),
                    const SizedBox(height: 6),
                  ],
                  if (paymentMethod.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.payment_rounded, size: 14, color: Color(0xFF0077B6)),
                      const SizedBox(width: 6),
                      Text(paymentMethod,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73),
                              fontWeight: FontWeight.w600)),
                    ]),
                ],
              ),
            ),
          ],

          // Nutrition summary
          if (calories > 0 || protein > 0) ...[
            const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFF9F0), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  if (calories > 0) _nutrCell('🔥', '${calories}kcal', 'Calories', const Color(0xFFFF9500)),
                  if (protein > 0)  _nutrCell('💪', '${protein.toStringAsFixed(0)}g', 'Protein', const Color(0xFF007AFF)),
                  if (carbs > 0)    _nutrCell('🌾', '${carbs.toStringAsFixed(0)}g', 'Carbs', const Color(0xFF34C759)),
                  if (fat > 0)      _nutrCell('🥑', '${fat.toStringAsFixed(0)}g', 'Fat', _red),
                ]),
              ),
            ),
          ],

          // Cancellation policy note (pending/confirmed only)
          if (status != 'delivered' && status != 'cancelled') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.6), width: 1.2)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('📋', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cancellation Policy: Orders can be cancelled free of charge '
                      'only while status is Pending or Confirmed. '
                      'Cancellations after the order moves to Preparing or later are not allowed.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF7A5800), height: 1.5),
                    ),
                  ),
                ]),
              ),
            ),
          ],

          // ── Active cancel button (pending / confirmed) ───────────────
          if (_canCancel)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: SizedBox(
                width: double.infinity, height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _cancelling ? null : _cancelOrder,
                  icon: _cancelling
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: _red, strokeWidth: 2))
                      : const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(_cancelling ? 'Cancelling...' : 'Cancel Order',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),

          // ── Disabled cancel button (preparing+) ──────────────────────
          if (!_canCancel && status != 'cancelled' && status != 'delivered')
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: SizedBox(
                width: double.infinity, height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFBDBDBD),
                      side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                      backgroundColor: const Color(0xFFF5F5F5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: null,
                  icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFBDBDBD)),
                  label: const Text('Cancel Order',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFBDBDBD))),
                ),
              ),
            ),

          const SizedBox(height: 14),
        ],
      ]),
    );
  }

  Widget _miniChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color)),
  );

  Widget _nutrCell(String emoji, String value, String label, Color color) => Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 14)),
    Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
    Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6E6E73))),
  ]);
}

// ─── Ring painter ────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _RingPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const strokeWidth = 10.0;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFF0F0F0)..strokeWidth = strokeWidth..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi * progress, false, Paint()..color = color..strokeWidth = strokeWidth..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
// ─────────────────────────────────────────────
// RateReviewScreen — review delivered orders
// ─────────────────────────────────────────────
// ignore_for_file: use_build_context_synchronously

class RateReviewScreen extends StatefulWidget {
  const RateReviewScreen({super.key});
  @override
  State<RateReviewScreen> createState() => _RateReviewScreenState();
}

class _RateReviewScreenState extends State<RateReviewScreen>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFF0077B6);

  late final TabController _tabCtrl;
  final _svc = FavoritesRatingsService.instance;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _rests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _svc.deliveredItems();
    final rests = await _svc.deliveredRestaurants();
    if (mounted) setState(() {
      _items   = items;
      _rests   = rests;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Rate & Review',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _red,
          unselectedLabelColor: const Color(0xFF6E6E73),
          indicatorColor: _red,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Food Items'), Tab(text: 'Restaurants')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _red))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _items.isEmpty
                    ? _emptyState('No delivered food items yet')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          return _ReviewableFoodCard(
                            item: item,
                            onTap: () => ReviewsSheet.showItem(
                              context,
                              restaurantId: item['restaurantId'],
                              itemName: item['itemName'],
                              restaurantName: item['restaurantName'],
                              hasOrdered: true,
                            ),
                          );
                        },
                      ),
                _rests.isEmpty
                    ? _emptyState('No delivered restaurant orders yet')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rests.length,
                        itemBuilder: (_, i) {
                          final rest = _rests[i];
                          return _ReviewableRestCard(
                            rest: rest,
                            onTap: () => ReviewsSheet.showRestaurant(
                              context,
                              restaurantId: rest['restaurantId'],
                              restaurantName: rest['restaurantName'],
                              hasOrdered: true,
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }

  Widget _emptyState(String msg) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🍽️', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 14),
          Text(msg, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E))),
          const SizedBox(height: 6),
          const Text('Complete an order to review', style: TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
        ]),
      );
}

class _ReviewableFoodCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  const _ReviewableFoodCard({required this.item, required this.onTap});
  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final rid  = item['restaurantId'] as String;
    final name = item['itemName'] as String;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3))]),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: (item['imageUrl'] as String).isNotEmpty
                ? Image.network(item['imageUrl'], width: 64, height: 64, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ph())
                : _ph(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 2),
              Text(item['restaurantName'], style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
              const SizedBox(height: 6),
              StreamBuilder<double>(
                stream: FavoritesRatingsService.instance.itemAverageRatingStream(rid, name),
                builder: (_, snap) {
                  final avg = snap.data ?? 0.0;
                  return avg > 0
                      ? _StarRowSmall(rating: avg)
                      : const Text('Tap to rate', style: TextStyle(fontSize: 11, color: Color(0xFFFF9500), fontWeight: FontWeight.w600));
                },
              ),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFAEAEB2)),
        ]),
      ),
    );
  }

  Widget _ph() => Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: _red.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.fastfood_rounded, color: _red, size: 28),
      );
}

class _ReviewableRestCard extends StatelessWidget {
  final Map<String, dynamic> rest;
  final VoidCallback onTap;
  const _ReviewableRestCard({required this.rest, required this.onTap});
  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final rid  = rest['restaurantId'] as String;
    final name = rest['restaurantName'] as String;
    final mapUrl = (rest['imageUrl'] as String? ?? '').trim();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 3))]),
        child: Row(children: [
          FutureBuilder<String>(
            future: mapUrl.isNotEmpty
                ? Future.value(mapUrl)
                : FirebaseFirestore.instance
                    .collection('restaurants')
                    .doc(rid)
                    .get()
                    .then((d) => (d.data()?['imageUrl'] as String? ?? '').trim()),
            builder: (_, snap) {
              final url = snap.data ?? '';
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: url.isNotEmpty
                    ? Image.network(
                        url,
                        width: 52, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _restPlaceholder(),
                      )
                    : _restPlaceholder(),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E))),
              const SizedBox(height: 6),
              StreamBuilder<double>(
                stream: FavoritesRatingsService.instance.restaurantAverageRatingStream(rid),
                builder: (_, snap) {
                  final avg = snap.data ?? 0.0;
                  return avg > 0
                      ? _StarRowSmall(rating: avg)
                      : const Text('Tap to rate', style: TextStyle(fontSize: 11, color: Color(0xFFFF9500), fontWeight: FontWeight.w600));
                },
              ),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFAEAEB2)),
        ]),
      ),
    );
  }

  Widget _restPlaceholder() => Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
            color: _red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.restaurant_rounded, color: _red, size: 26),
      );
}

class _StarRowSmall extends StatelessWidget {
  final double rating;
  const _StarRowSmall({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) => Icon(
              i < rating.floor()
                  ? Icons.star_rounded
                  : (i < rating ? Icons.star_half_rounded : Icons.star_outline_rounded),
              color: const Color(0xFFFFCC02),
              size: 14,
            )),
        const SizedBox(width: 4),
        Text(rating.toStringAsFixed(1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6E6E73))),
      ],
    );
  }
}