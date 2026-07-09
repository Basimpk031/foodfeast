// ─────────────────────────────────────────────
// calorie_tracker.dart — FoodFeast
// Fixed: loadTodayData now accepts optional uid so it can be called
//        from main() before runApp(), guaranteeing Firestore data is
//        loaded even when FirebaseAuth.currentUser is not yet restored.
//        Added _isLoading guard to prevent concurrent loads.
//        Added editTodayNutritionLocally() for instant UI update
//        without waiting for Firestore (fire-and-forget pattern).
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
// NOTE: ai_recommendation_engine import is intentionally omitted here
// to avoid circular dependencies. Cache invalidation is handled in
// cart_screen.dart and profile_screen.dart after each user action.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DayNutrition {
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final String dateKey;

  const DayNutrition({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.dateKey = '',
  });

  Map<String, dynamic> toMap() => {
    'consumed': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'date': dateKey,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory DayNutrition.fromMap(Map<String, dynamic> data, String dateKey) {
    return DayNutrition(
      calories: (data['consumed'] ?? 0).toInt(),
      protein: (data['protein'] ?? 0).toDouble(),
      carbs: (data['carbs'] ?? 0).toDouble(),
      fat: (data['fat'] ?? 0).toDouble(),
      dateKey: dateKey,
    );
  }
}

// ─────────────────────────────────────────────
// BMR / TDEE calorie suggestion
// ─────────────────────────────────────────────
class CalorieSuggestion {
  final int loseWeight;
  final int maintain;
  final int gainWeight;
  final double bmi;
  final String bmiCategory;

  const CalorieSuggestion({
    required this.loseWeight,
    required this.maintain,
    required this.gainWeight,
    required this.bmi,
    required this.bmiCategory,
  });

  /// Mifflin-St Jeor BMR -> multiply by activity factor -> TDEE
  static CalorieSuggestion? calculate({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
    required String activityLevel,
  }) {
    if (weightKg <= 0 || heightCm <= 0 || age <= 0) return null;

    double bmr;
    if (gender == 'Female') {
      bmr = 10 * weightKg + 6.25 * heightCm - 5 * age - 161;
    } else {
      bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + 5;
    }

    final factor = activityLevel == 'Light'
        ? 1.375
        : activityLevel == 'Active'
            ? 1.725
            : 1.55;

    final tdee = (bmr * factor).round();
    final hM = heightCm / 100;
    final bmi = weightKg / (hM * hM);

    String bmiCat;
    if (bmi < 18.5) {
      bmiCat = 'Underweight';
    } else if (bmi < 25.0) {
      bmiCat = 'Normal';
    } else if (bmi < 30.0) {
      bmiCat = 'Overweight';
    } else {
      bmiCat = 'Obese';
    }

    return CalorieSuggestion(
      loseWeight: (tdee - 500).clamp(1200, 99999),
      maintain: tdee,
      gainWeight: tdee + 500,
      bmi: bmi,
      bmiCategory: bmiCat,
    );
  }
}

// ─────────────────────────────────────────────
// CalorieTracker singleton
// ─────────────────────────────────────────────
class CalorieTracker extends ChangeNotifier {
  static final CalorieTracker instance = CalorieTracker._internal();
  CalorieTracker._internal();

  int _consumedCalories = 0;
  double _consumedProtein = 0;
  double _consumedCarbs = 0;
  double _consumedFat = 0;
  int _goalCalories = 2000;
  String _todayKey = '';

  // Guard: prevents concurrent loads from racing against each other
  bool _isLoading = false;

  List<DayNutrition> _weeklyData  = _buildEmptyWeek();
  List<DayNutrition> _monthlyData = _buildEmptyMonth();

  static List<DayNutrition> _buildEmptyWeek() {
    return lastNDays(7).map((d) => DayNutrition(dateKey: dateKey(d))).toList();
  }

  static List<DayNutrition> _buildEmptyMonth() {
    return currentMonthDays().map((d) => DayNutrition(dateKey: dateKey(d))).toList();
  }

  int    get consumedCalories  => _consumedCalories;
  double get consumedProtein   => _consumedProtein;
  double get consumedCarbs     => _consumedCarbs;
  double get consumedFat       => _consumedFat;
  int    get goalCalories      => _goalCalories;
  int    get remainingCalories => (_goalCalories - _consumedCalories).clamp(0, _goalCalories);
  double get progress => _goalCalories > 0
      ? (_consumedCalories / _goalCalories).clamp(0.0, 1.0)
      : 0.0;

  // Legacy
  List<int>          get weeklyCalories => _weeklyData.map((d) => d.calories).toList();
  List<DayNutrition> get weeklyData     => _weeklyData;
  List<DayNutrition> get monthlyData    => _monthlyData;

  static String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _getTodayKey() => dateKey(DateTime.now());

  static List<DateTime> lastNDays(int n) {
    final now = DateTime.now();
    return List.generate(n, (i) => now.subtract(Duration(days: n - 1 - i)));
  }

  static List<DateTime> currentMonthDays() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return List.generate(daysInMonth, (i) => DateTime(now.year, now.month, i + 1));
  }

  // ── Load today ──────────────────────────────────────────────────────────
  // KEY FIX: [uid] can be passed directly from main() before runApp() so we
  // never rely on FirebaseAuth.currentUser being restored yet on cold start.
  // HomeScreen.initState() still calls loadTodayData() with no argument as
  // a safety net — the _isLoading guard prevents a double-fetch.
  Future<void> loadTodayData({String? uid}) async {
    // Resolve uid: prefer explicit arg, fall back to currentUser
    final resolvedUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (resolvedUid == null) {
      debugPrint('CalorieTracker.loadTodayData: no uid available, skipping');
      return;
    }

    // Prevent concurrent loads (main() + HomeScreen.initState() race)
    if (_isLoading) return;
    _isLoading = true;

    final today = _getTodayKey();
    _todayKey = today;

    try {
      // 1. Calorie goal from user doc
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(resolvedUid).get();
      final data = userDoc.data();
      if (data != null) {
        _goalCalories = (data['goalCalories'] ?? 2000).toInt();
      }

      // 2. Today's nutrition log
      final logDoc = await FirebaseFirestore.instance
          .collection('users').doc(resolvedUid)
          .collection('calorieLogs').doc(today).get();

      if (logDoc.exists) {
        final ld = logDoc.data()!;
        _consumedCalories = (ld['consumed'] ?? 0).toInt();
        _consumedProtein  = (ld['protein']  ?? 0).toDouble();
        _consumedCarbs    = (ld['carbs']    ?? 0).toDouble();
        _consumedFat      = (ld['fat']      ?? 0).toDouble();
      } else {
        // No log yet today — correct to start at zero
        _consumedCalories = 0;
        _consumedProtein  = 0;
        _consumedCarbs    = 0;
        _consumedFat      = 0;
      }

      // Update today slot immediately so UI renders before history loads
      _syncTodayIntoLists();
      notifyListeners();

      // 3. Weekly + monthly history for stats charts
      await _loadWeeklyData(resolvedUid);
      await _loadMonthlyData(resolvedUid);
      notifyListeners();
    } catch (e) {
      debugPrint('CalorieTracker.loadTodayData error: $e');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _loadWeeklyData(String uid) async {
    final days = lastNDays(7);
    final List<DayNutrition> weekly = [];
    for (final day in days) {
      final key = dateKey(day);
      if (key == _todayKey) { weekly.add(_todayEntry()); continue; }
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('calorieLogs').doc(key).get();
        weekly.add(doc.exists
            ? DayNutrition.fromMap(doc.data()!, key)
            : DayNutrition(dateKey: key));
      } catch (_) {
        weekly.add(DayNutrition(dateKey: key));
      }
    }
    _weeklyData = weekly;
  }

  Future<void> _loadMonthlyData(String uid) async {
    final days = currentMonthDays();
    final List<DayNutrition> monthly = [];
    for (final day in days) {
      final key = dateKey(day);
      if (key == _todayKey) { monthly.add(_todayEntry()); continue; }
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('calorieLogs').doc(key).get();
        monthly.add(doc.exists
            ? DayNutrition.fromMap(doc.data()!, key)
            : DayNutrition(dateKey: key));
      } catch (_) {
        monthly.add(DayNutrition(dateKey: key));
      }
    }
    _monthlyData = monthly;
  }

  DayNutrition _todayEntry() => DayNutrition(
    calories: _consumedCalories,
    protein:  _consumedProtein,
    carbs:    _consumedCarbs,
    fat:      _consumedFat,
    dateKey:  _todayKey,
  );

  void _syncTodayIntoLists() {
    if (_todayKey.isEmpty) return;
    final entry = _todayEntry();
    _weeklyData  = _weeklyData.map((d) => d.dateKey == _todayKey ? entry : d).toList();
    _monthlyData = _monthlyData.map((d) => d.dateKey == _todayKey ? entry : d).toList();
  }

  // ── Add from order ──────────────────────────
  // ✅ AI Integration note: FoodRecommendationEngine.instance.invalidateCache()
  // is called from cart_screen.dart after this completes, so collaborative
  // filtering picks up the new order on the next recommendation fetch.
  Future<void> addOrderNutrition({
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    await _addNutrition(
        calories: calories, protein: protein, carbs: carbs, fat: fat);
  }

  // ── Persist-only manual log (no in-memory change) ──────────────
  // Use this when the UI has already called editTodayNutritionLocally()
  // for instant feedback. This method only writes the current totals to
  // Firestore and appends a manualLogs entry — it does NOT add to the
  // in-memory counters again, preventing the 2x double-count bug.
  Future<void> persistManualLogOnly({
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
    String label = 'Home food',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = _getTodayKey();

    try {
      // Write the already-updated totals (set by editTodayNutritionLocally)
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('calorieLogs').doc(today)
          .set(DayNutrition(
            calories: _consumedCalories,
            protein:  _consumedProtein,
            carbs:    _consumedCarbs,
            fat:      _consumedFat,
            dateKey:  today,
          ).toMap(), SetOptions(merge: true));

      // Append to manualLogs sub-collection for history
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('manualLogs').add({
        'label':    label,
        'calories': calories,
        'protein':  protein,
        'carbs':    carbs,
        'fat':      fat,
        'date':     today,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Refresh weekly/monthly history in background
      await _loadWeeklyData(user.uid);
      await _loadMonthlyData(user.uid);
      notifyListeners();
    } catch (e) {
      debugPrint('CalorieTracker.persistManualLogOnly error: $e');
    }
  }

  // ── Manual log (home food) ──────────────────
  Future<void> addManualLog({
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
    String label = 'Home food',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _addNutrition(
        calories: calories, protein: protein, carbs: carbs, fat: fat);

    try {
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('manualLogs').add({
        'label':    label,
        'calories': calories,
        'protein':  protein,
        'carbs':    carbs,
        'fat':      fat,
        'date':     _getTodayKey(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('CalorieTracker.addManualLog sub-collection error: $e');
    }
  }

  /// Internal helper: add to in-memory totals + persist to Firestore
  Future<void> _addNutrition({
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = _getTodayKey();
    if (_todayKey.isNotEmpty && _todayKey != today) {
      _consumedCalories = 0;
      _consumedProtein  = 0;
      _consumedCarbs    = 0;
      _consumedFat      = 0;
    }
    _todayKey = today;

    _consumedCalories += calories;
    _consumedProtein  += protein;
    _consumedCarbs    += carbs;
    _consumedFat      += fat;
    _syncTodayIntoLists();
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('calorieLogs').doc(today)
          .set(DayNutrition(
            calories: _consumedCalories,
            protein:  _consumedProtein,
            carbs:    _consumedCarbs,
            fat:      _consumedFat,
            dateKey:  today,
          ).toMap(), SetOptions(merge: true));

      await _loadWeeklyData(user.uid);
      await _loadMonthlyData(user.uid);
      notifyListeners();
    } catch (e) {
      debugPrint('CalorieTracker._addNutrition error: $e');
    }
  }

  // ── Instant local update (no Firestore await) ─────────────────────────
  // Call this first for immediate UI feedback, then call editTodayNutrition()
  // fire-and-forget for background Firestore persistence.
  void editTodayNutritionLocally({
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
  }) {
    _todayKey         = _getTodayKey();
    _consumedCalories = calories;
    _consumedProtein  = protein;
    _consumedCarbs    = carbs;
    _consumedFat      = fat;
    _syncTodayIntoLists();
    notifyListeners();
  }

  // ── Edit today's totals (manual correction) ─
  Future<void> editTodayNutrition({
    required int calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = _getTodayKey();
    _todayKey         = today;
    _consumedCalories = calories;
    _consumedProtein  = protein;
    _consumedCarbs    = carbs;
    _consumedFat      = fat;
    _syncTodayIntoLists();
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('calorieLogs').doc(today)
          .set(DayNutrition(
            calories: calories,
            protein:  protein,
            carbs:    carbs,
            fat:      fat,
            dateKey:  today,
          ).toMap(), SetOptions(merge: true));

      await _loadWeeklyData(user.uid);
      await _loadMonthlyData(user.uid);
      notifyListeners();
    } catch (e) {
      debugPrint('CalorieTracker.editTodayNutrition error: $e');
    }
  }

  // Legacy compat
  Future<void> addOrderCalories(int calories) async =>
      addOrderNutrition(calories: calories, protein: 0, carbs: 0, fat: 0);

  Future<void> updateGoal(int newGoal) async {
    _goalCalories = newGoal;
    notifyListeners();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .update({'goalCalories': newGoal});
    } catch (e) {
      debugPrint('CalorieTracker.updateGoal error: $e');
    }
  }

  Future<void> refreshData() async => loadTodayData();

  void reset() {
    _consumedCalories = 0;
    _consumedProtein  = 0;
    _consumedCarbs    = 0;
    _consumedFat      = 0;
    _goalCalories     = 2000;
    _todayKey         = '';
    _isLoading        = false;
    _weeklyData       = _buildEmptyWeek();
    _monthlyData      = _buildEmptyMonth();
    notifyListeners();
  }
}