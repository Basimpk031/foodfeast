// ─────────────────────────────────────────────
// stats_screen.dart — FoodFeast
// Fixed:
//   • Period summary cards change with Week/Month toggle
//     (avg kcal/day, total kcal, best day)
//   • Nutrition breakdown switches between Today / Period avg
//   • Macro trend bars always visible (monthly included)
//   • loadTodayData() called with uid to fix cold-start zeroes
//   • Added period average row above charts
// ─────────────────────────────────────────────
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'calorie_tracker.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => StatsScreenState();
}

class StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  static const _blue   = Color(0xFF0077B6);
  static const _sky    = Color(0xFF007AFF);
  static const _green  = Color(0xFF34C759);
  static const _orange = Color(0xFFFF9500);

  bool _showWeekly   = true;
  bool _isRefreshing = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  // Separate count-up animation for numbers & bars
  late Animation<double> _countUpAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _countUpAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();

    // Always reload with uid so cold-start direct-to-Stats works correctly
    final uid = FirebaseAuth.instance.currentUser?.uid;
    CalorieTracker.instance.loadTodayData(uid: uid);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // Called by HomeScreen when this tab is selected
  void replayAnimation() {
    if (mounted) _animCtrl.forward(from: 0);
  }

  void _toggleView(bool weekly) {
    if (_showWeekly == weekly) return;
    _animCtrl.reverse().then((_) {
      setState(() => _showWeekly = weekly);
      _animCtrl.forward(from: 0);
    });
  }

  // ── Period helpers ───────────────────────────
  List<DayNutrition> _activeDays(CalorieTracker t) =>
      (_showWeekly ? t.weeklyData : t.monthlyData)
          .where((d) => d.calories > 0)
          .toList();

  int _periodTotalCal(CalorieTracker t) =>
      _activeDays(t).fold(0, (s, d) => s + d.calories);

  int _periodAvgCal(CalorieTracker t) {
    final active = _activeDays(t);
    if (active.isEmpty) return 0;
    return (_periodTotalCal(t) / active.length).round();
  }

  int _periodBestCal(CalorieTracker t) {
    final active = _activeDays(t);
    if (active.isEmpty) return 0;
    return active.map((d) => d.calories).reduce(math.max);
  }

  double _periodAvgProtein(CalorieTracker t) {
    final a = _activeDays(t);
    if (a.isEmpty) return 0;
    return a.fold(0.0, (s, d) => s + d.protein) / a.length;
  }

  double _periodAvgCarbs(CalorieTracker t) {
    final a = _activeDays(t);
    if (a.isEmpty) return 0;
    return a.fold(0.0, (s, d) => s + d.carbs) / a.length;
  }

  double _periodAvgFat(CalorieTracker t) {
    final a = _activeDays(t);
    if (a.isEmpty) return 0;
    return a.fold(0.0, (s, d) => s + d.fat) / a.length;
  }

  // ── Build ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge(
              [CalorieTracker.instance, _countUpAnim]),
          builder: (_, __) {
            final tracker = CalorieTracker.instance;
            final data =
                _showWeekly ? tracker.weeklyData : tracker.monthlyData;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(child: _buildToggle()),
                SliverToBoxAdapter(child: _buildPeriodSummaryCards(tracker)),
                SliverToBoxAdapter(child: _buildPeriodAverageRow(tracker)),
                SliverToBoxAdapter(child: _buildCalorieChart(data)),
                SliverToBoxAdapter(child: _buildNutritionBreakdown(tracker)),
                SliverToBoxAdapter(child: _buildMacroHistory(data)),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        const Text('Nutrition Stats',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
        GestureDetector(
          onTap: () async {
            if (_isRefreshing) return;
            setState(() => _isRefreshing = true);
            final uid = FirebaseAuth.instance.currentUser?.uid;
            await CalorieTracker.instance.loadTodayData(uid: uid);
            if (mounted) {
              setState(() => _isRefreshing = false);
              replayAnimation();
            }
          },
          child: AnimatedRotation(
            turns: _isRefreshing ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 600),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: _blue.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.refresh_rounded,
                  color: _isRefreshing
                      ? _blue.withOpacity(0.5)
                      : _blue,
                  size: 20),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Week / Month toggle ──────────────────────
  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          _toggleBtn('This Week', _showWeekly),
          _toggleBtn('This Month', !_showWeekly),
        ]),
      ),
    );
  }

  Widget _toggleBtn(String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _toggleView(label == 'This Week'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8)
                    ]
                  : []),
          child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: active ? _blue : const Color(0xFF6E6E73)))),
        ),
      ),
    );
  }

  // ── Period summary cards — CHANGE with toggle ─
  Widget _buildPeriodSummaryCards(CalorieTracker tracker) {
    final isWeekly = _showWeekly;
    final t        = _countUpAnim.value; // 0.0 → 1.0

    final avgCal  = (_periodAvgCal(tracker)  * t).round();
    final total   = (_periodTotalCal(tracker) * t).round();
    final best    = (_periodBestCal(tracker)  * t).round();
    final active  = _activeDays(tracker).length;
    final period  = isWeekly ? '7-day' : 'Month';

    // Non-animated (always static) values animated through t
    final todayCal     = (tracker.consumedCalories * t).round();
    final goalCal      = tracker.goalCalories;
    final remainingCal = (tracker.remainingCalories * t).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          // Top row: today / goal / left (always relevant)
          Row(children: [
            Expanded(
                child: _summaryCard('🔥', 'Today',
                    '$todayCal', 'kcal', _blue)),
            const SizedBox(width: 10),
            Expanded(
                child: _summaryCard(
                    '🎯', 'Goal', '$goalCal', 'kcal', _sky)),
            const SizedBox(width: 10),
            Expanded(
                child: _summaryCard('✅', 'Left',
                    '$remainingCal', 'kcal', _green)),
          ]),
          const SizedBox(height: 10),
          // Bottom row: period-specific stats
          Row(children: [
            Expanded(
                child: _summaryCard(
                    '📅',
                    '$period Avg',
                    avgCal > 0 ? '$avgCal' : '—',
                    'kcal/day',
                    _blue)),
            const SizedBox(width: 10),
            Expanded(
                child: _summaryCard(
                    '⚡',
                    '$period Total',
                    total > 0 ? '$total' : '—',
                    'kcal',
                    _orange)),
            const SizedBox(width: 10),
            Expanded(
                child: _summaryCard(
                    '🏆',
                    'Best Day',
                    best > 0 ? '$best' : '—',
                    'kcal  ($active days)',
                    _green)),
          ]),
        ]),
      ),
    );
  }

  Widget _summaryCard(
      String emoji, String label, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        Text(unit,
            style: const TextStyle(fontSize: 9, color: Color(0xFF6E6E73))),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6E6E73))),
      ]),
    );
  }

  // ── Period average macro strip ────────────────
  Widget _buildPeriodAverageRow(CalorieTracker tracker) {
    final active = _activeDays(tracker);
    if (active.isEmpty) return const SizedBox();

    final avgP = _periodAvgProtein(tracker);
    final avgC = _periodAvgCarbs(tracker);
    final avgF = _periodAvgFat(tracker);
    final hasMacros = avgP > 0 || avgC > 0 || avgF > 0;
    if (!hasMacros) return const SizedBox();

    final label = _showWeekly ? 'Weekly' : 'Monthly';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: _blue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _blue.withOpacity(0.15))),
          child: Row(children: [
            Text('$label avg macros',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _blue.withOpacity(0.8))),
            const Spacer(),
            _avgMacroChip('💪', '${avgP.toStringAsFixed(0)}g', _sky),
            const SizedBox(width: 8),
            _avgMacroChip('🌾', '${avgC.toStringAsFixed(0)}g', _green),
            const SizedBox(width: 8),
            _avgMacroChip('🥑', '${avgF.toStringAsFixed(0)}g', _orange),
          ]),
        ),
      ),
    );
  }

  Widget _avgMacroChip(String emoji, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 3),
      Text(value,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: color)),
    ]);
  }

  // ── Calorie bar chart ─────────────────────────
  Widget _buildCalorieChart(List<DayNutrition> data) {
    if (data.isEmpty) return const SizedBox();
    final maxCal =
        data.map((d) => d.calories).reduce(math.max).toDouble();
    final effectiveMax = math.max(maxCal, 500.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Calorie History',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  _showWeekly ? '7 days' : '${data.length} days',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _blue)),
            ),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: _showWeekly
                ? _weeklyBarChart(data, effectiveMax)
                : _monthlyBarChart(data, effectiveMax),
          ),
        ]),
      ),
    );
  }

  Widget _weeklyBarChart(List<DayNutrition> data, double maxVal) {
    final dayLabels = _getDayLabels(data);
    final t = _countUpAnim.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(data.length, (i) {
        final d = data[i];
        final ratio =
            maxVal > 0 ? (d.calories / maxVal).clamp(0.0, 1.0) : 0.0;
        final animatedRatio = ratio * t;
        final isToday = _isToday(d.dateKey);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
              if (d.calories > 0)
                Text('${(d.calories * t).round()}',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? _blue
                            : const Color(0xFF6E6E73))),
              const SizedBox(height: 3),
              Container(
                height: math.max(animatedRatio * 110, d.calories > 0 && t > 0 ? 2 : 0),
                decoration: BoxDecoration(
                    color: isToday ? _blue : _blue.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(6)),
              ),
              const SizedBox(height: 6),
              Text(dayLabels[i],
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: isToday
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: isToday
                          ? _blue
                          : const Color(0xFF6E6E73))),
            ]),
          ),
        );
      }),
    );
  }

  Widget _monthlyBarChart(List<DayNutrition> data, double maxVal) {
    final t = _countUpAnim.value;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(data.length, (i) {
          final d = data[i];
          final ratio =
              maxVal > 0 ? (d.calories / maxVal).clamp(0.0, 1.0) : 0.0;
          final animatedRatio = ratio * t;
          final dayNum = i + 1;
          final isToday = _isToday(d.dateKey);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(
              width: 22,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                Container(
                  height: math.max(animatedRatio * 110, d.calories > 0 && t > 0 ? 2 : 0),
                  decoration: BoxDecoration(
                      color: isToday
                          ? _blue
                          : _blue.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 4),
                Text('$dayNum',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: isToday
                            ? FontWeight.w800
                            : FontWeight.w400,
                        color: isToday
                            ? _blue
                            : const Color(0xFF6E6E73))),
              ]),
            ),
          );
        }),
      ),
    );
  }

  List<String> _getDayLabels(List<DayNutrition> data) {
    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return data.map((d) {
      try {
        final parts = d.dateKey.split('-');
        final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]),
            int.parse(parts[2]));
        return dayNames[dt.weekday - 1];
      } catch (_) {
        return '-';
      }
    }).toList();
  }

  bool _isToday(String dk) =>
      dk == CalorieTracker.dateKey(DateTime.now());

  // ── Nutrition breakdown — context-aware ───────
  // Shows TODAY values when on This Week view,
  // shows PERIOD AVERAGES when on This Month view.
  Widget _buildNutritionBreakdown(CalorieTracker tracker) {
    final isWeekly = _showWeekly;
    final double protein;
    final double carbs;
    final double fat;
    final int calories;
    final String sectionTitle;
    final String calLabel;

    if (isWeekly) {
      // Show today's actual intake
      protein      = tracker.consumedProtein;
      carbs        = tracker.consumedCarbs;
      fat          = tracker.consumedFat;
      calories     = tracker.consumedCalories;
      sectionTitle = "Today's Nutrition";
      calLabel     = '$calories kcal today';
    } else {
      // Show this-month daily averages
      protein      = _periodAvgProtein(tracker);
      carbs        = _periodAvgCarbs(tracker);
      fat          = _periodAvgFat(tracker);
      calories     = _periodAvgCal(tracker);
      sectionTitle = 'Monthly Avg Nutrition';
      calLabel     = '~$calories kcal/day avg';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4))
              ]),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(sectionTitle,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E))),
              const Spacer(),
              Text(calLabel,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6E6E73))),
            ]),
            const SizedBox(height: 20),

            _macroBar('💪 Protein', protein, 50.0, _sky, 'g'),
            const SizedBox(height: 14),
            _macroBar('🌾 Carbohydrates', carbs, 250.0, _green, 'g'),
            const SizedBox(height: 14),
            _macroBar('🥑 Fat', fat, 65.0, _orange, 'g'),

            const SizedBox(height: 20),

            Row(children: [
              Expanded(
                  child: _macroSummaryTile('Protein', protein, 'g', _sky)),
              Expanded(
                  child: _macroSummaryTile('Carbs', carbs, 'g', _green)),
              Expanded(
                  child: _macroSummaryTile('Fat', fat, 'g', _orange)),
            ]),

            if (calories == 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [
                  Text('🍽️', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'Order food to see your nutrition breakdown here',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6E6E73)))),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _macroBar(
      String label, double value, double goal, Color color, String unit) {
    final t = _countUpAnim.value;
    final animatedValue = value * t;
    final ratio = goal > 0 ? (animatedValue / goal).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E))),
        Row(children: [
          Text('${animatedValue.toStringAsFixed(1)}$unit',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(' / ${goal.toStringAsFixed(0)}$unit',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
        ]),
      ]),
      const SizedBox(height: 7),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 10,
          backgroundColor: const Color(0xFFF0F0F0),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    ]);
  }

  Widget _macroSummaryTile(
      String label, double value, String unit, Color color) {
    final animatedValue = value * _countUpAnim.value;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text('${animatedValue.toStringAsFixed(1)}$unit',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6E6E73),
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Macro history bars (week/month) ──────────
  Widget _buildMacroHistory(List<DayNutrition> data) {
    if (data.isEmpty) return const SizedBox();

    // Show section even if only some days have macro data
    final hasAnyMacro =
        data.any((d) => d.protein > 0 || d.carbs > 0 || d.fat > 0);
    if (!hasAnyMacro) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ]),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Macro Trends',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_showWeekly ? '7 days' : 'This month',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _blue)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Protein · Carbs · Fat in grams',
              style:
                  TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
          const SizedBox(height: 16),
          _buildMacroTrendBar(
              '💪 Protein', data.map((d) => d.protein).toList(), _sky),
          const SizedBox(height: 12),
          _buildMacroTrendBar(
              '🌾 Carbs', data.map((d) => d.carbs).toList(), _green),
          const SizedBox(height: 12),
          _buildMacroTrendBar(
              '🥑 Fat', data.map((d) => d.fat).toList(), _orange),
        ]),
      ),
    );
  }

  Widget _buildMacroTrendBar(
      String label, List<double> values, Color color) {
    final maxVal =
        values.isEmpty ? 1.0 : values.reduce(math.max);
    final effectiveMax = math.max(maxVal, 10.0);
    final totalGrams = values.fold(0.0, (s, v) => s + v);
    final activeDays =
        values.where((v) => v > 0).length;
    final avgGrams = activeDays > 0 ? totalGrams / activeDays : 0.0;
    final t = _countUpAnim.value;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const Spacer(),
        Text(
            '${(totalGrams * t).toStringAsFixed(0)}g total  ·  '
            '${(avgGrams * t).toStringAsFixed(0)}g avg/day',
            style:
                const TextStyle(fontSize: 11, color: Color(0xFF6E6E73))),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 28,
        child: _showWeekly
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(values.length, (i) {
                  final ratio =
                      (values[i] / effectiveMax).clamp(0.0, 1.0) * t;
                  final isToday = i == values.length - 1;
                  return Expanded(
                      child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: math.max(
                          ratio * 24, values[i] > 0 && t > 0 ? 2 : 0),
                      decoration: BoxDecoration(
                          color: isToday
                              ? color
                              : color.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ));
                }),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(values.length, (i) {
                    final ratio =
                        (values[i] / effectiveMax).clamp(0.0, 1.0) * t;
                    final isToday =
                        _isToday((_showWeekly
                                ? CalorieTracker.instance.weeklyData
                                : CalorieTracker
                                    .instance.monthlyData)[i]
                            .dateKey);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 1.5),
                      child: Container(
                        width: 8,
                        height: math.max(
                            ratio * 24, values[i] > 0 && t > 0 ? 2 : 0),
                        decoration: BoxDecoration(
                            color: isToday
                                ? color
                                : color.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(3)),
                      ),
                    );
                  }),
                ),
              ),
      ),
    ]);
  }
}