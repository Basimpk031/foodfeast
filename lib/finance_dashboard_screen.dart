// ─────────────────────────────────────────────────────────────────────────────
// finance_dashboard_screen.dart — FoodFeast
//
// Admin / Finance overview screen with three panels:
//
//   1. COD to Admin  — ADMIN ONLY — sum of all COD orders (grandTotal) that
//                      need to be physically collected and sent to the
//                      FoodFeast admin.
//                      Filtered by Today / This Week / This Month.
//
//   2. Restaurant Revenue — per-restaurant food-subtotal earnings.
//                      Tap a restaurant row to expand period breakdown.
//                      Periods: Today / This Week / This Month / All Time.
//
//   3. Delivery Agent Earnings — per-agent deliveryFee earnings.
//                      Tap an agent row to expand period breakdown.
//                      Periods: Today / This Week / This Month / All Time.
//
// HOW TO NAVIGATE HERE:
//   Admin:
//     Navigator.push(context, MaterialPageRoute(
//       builder: (_) => const FinanceDashboardScreen(role: FinanceRole.admin)));
//
//   Restaurant owner (sees only their restaurant revenue — no COD panel):
//     Navigator.push(context, MaterialPageRoute(
//       builder: (_) => FinanceDashboardScreen(
//         role: FinanceRole.restaurant,
//         restaurantId: myRestaurantId,
//         restaurantName: myRestaurantName)));
//
//   Delivery agent (sees only their own earnings):
//     Navigator.push(context, MaterialPageRoute(
//       builder: (_) => FinanceDashboardScreen(
//         role: FinanceRole.agent,
//         agentId: myAgentId,
//         agentName: myAgentName)));
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Colours (match rest of FoodFeast app) ────────────────────────────────────
const _kPrimary = Color(0xFF0077B6);
const _kDark    = Color(0xFF1A1A2E);
const _kGreen   = Color(0xFF34C759);
const _kOrange  = Color(0xFFFF9500);
const _kRed     = Color(0xFFFF3B30);
const _kGrey    = Color(0xFF6E6E73);
const _kBg      = Color(0xFFF2F2F7);

// ─── Role enum ────────────────────────────────────────────────────────────────
enum FinanceRole { admin, restaurant, agent }

// ─── Period enum ──────────────────────────────────────────────────────────────
enum Period { today, week, month, allTime }

extension PeriodLabel on Period {
  String get label {
    switch (this) {
      case Period.today:   return 'Today';
      case Period.week:    return 'This Week';
      case Period.month:   return 'This Month';
      case Period.allTime: return 'All Time';
    }
  }

  /// Returns the start of the period (null = no lower bound = all time).
  DateTime? get startDate {
    final now = DateTime.now();
    switch (this) {
      case Period.today:
        return DateTime(now.year, now.month, now.day);
      case Period.week:
        return now.subtract(Duration(days: now.weekday - 1));
      case Period.month:
        return DateTime(now.year, now.month, 1);
      case Period.allTime:
        return null;
    }
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _CodSummary {
  final double total;
  final int    count;
  _CodSummary({required this.total, required this.count});
}

class _EntitySummary {
  final String id;
  final String name;
  final Map<Period, double> earnings;
  final Map<Period, int>    orderCounts;
  _EntitySummary({
    required this.id,
    required this.name,
    required this.earnings,
    required this.orderCounts,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main screen
// ─────────────────────────────────────────────────────────────────────────────
class FinanceDashboardScreen extends StatefulWidget {
  final FinanceRole role;

  // For restaurant role
  final String? restaurantId;
  final String? restaurantName;

  // For agent role
  final String? agentId;
  final String? agentName;

  const FinanceDashboardScreen({
    super.key,
    required this.role,
    this.restaurantId,
    this.restaurantName,
    this.agentId,
    this.agentName,
  });

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  // ── Selected periods ────────────────────────────────────────────────────────
  Period _codPeriod   = Period.today;
  Period _restPeriod  = Period.today;
  Period _agentPeriod = Period.today;

  // ── Expanded rows ───────────────────────────────────────────────────────────
  String? _expandedRestId;
  String? _expandedAgentId;

  // ── Loading states ──────────────────────────────────────────────────────────
  bool _loadingCod   = true;
  bool _loadingRest  = true;
  bool _loadingAgent = true;

  // ── Data ────────────────────────────────────────────────────────────────────
  _CodSummary?           _codSummary;
  List<_EntitySummary>   _restaurants  = [];
  List<_EntitySummary>   _agents       = [];

  // ── Subscriptions ───────────────────────────────────────────────────────────
  StreamSubscription? _ordersSubscription;
  List<Map<String, dynamic>> _allOrders = [];

  @override
  void initState() {
    super.initState();
    _subscribeOrders();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    super.dispose();
  }

  // ── Stream all orders once and derive everything client-side ─────────────────
  void _subscribeOrders() {
    Query query = FirebaseFirestore.instance.collection('orders');

    // Scope to this restaurant / agent if not admin
    if (widget.role == FinanceRole.restaurant &&
        widget.restaurantId != null) {
      query = query.where('restaurantIds',
          arrayContains: widget.restaurantId);
    } else if (widget.role == FinanceRole.agent && widget.agentId != null) {
      query = query
          .where('assignedAgentId', isEqualTo: widget.agentId)
          .where('status', isEqualTo: 'delivered');
    }

    _ordersSubscription = query.snapshots().listen((snap) {
      _allOrders = snap.docs
          .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
          .toList();
      _recompute();
    });
  }

  void _recompute() {
    _computeCod();
    _computeRestaurants();
    _computeAgents();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  bool _inPeriod(Map<String, dynamic> order, Period period) {
    final start = period.startDate;
    if (start == null) return true;
    final ts = order['createdAt'] as Timestamp?;
    if (ts == null) return false;
    return ts.toDate().isAfter(start);
  }

  // ── COD (admin only) ──────────────────────────────────────────────────────────
  void _computeCod() {
    final filtered = _allOrders.where((o) {
      final method = (o['paymentMethod'] as String? ?? '').toLowerCase();
      final status = (o['paymentStatus'] as String? ?? '').toLowerCase();
      final isCod  = method == 'cod' || status == 'cod' || status == 'pending_cod';
      return isCod && _inPeriod(o, _codPeriod);
    }).toList();

    final total = filtered.fold<double>(
        0, (s, o) => s + (o['grandTotal'] as num? ?? 0).toDouble());

    if (mounted) {
      setState(() {
        _codSummary = _CodSummary(total: total, count: filtered.length);
        _loadingCod = false;
      });
    }
  }

  // ── Restaurants ───────────────────────────────────────────────────────────────
  void _computeRestaurants() {
    final Map<String, Map<String, dynamic>> map = {};

    for (final order in _allOrders) {
      final perList = order['perRestaurant'] as List?;
      if (perList == null) continue;

      for (final entry in perList.cast<Map<String, dynamic>>()) {
        final rId   = entry['restaurantId'] as String? ?? '';
        final rName = entry['restaurantName'] as String? ?? '';
        if (rId.isEmpty) continue;

        map.putIfAbsent(rId, () => {
          'name': rName,
          'earnings': <Period, double>{for (final p in Period.values) p: 0.0},
          'counts':   <Period, int>{for (final p in Period.values) p: 0},
        });

        final sub = (entry['subtotal'] as num? ?? 0).toDouble();
        for (final p in Period.values) {
          if (_inPeriod(order, p)) {
            (map[rId]!['earnings'] as Map<Period, double>)[p] =
                (map[rId]!['earnings'] as Map<Period, double>)[p]! + sub;
            (map[rId]!['counts'] as Map<Period, int>)[p] =
                (map[rId]!['counts'] as Map<Period, int>)[p]! + 1;
          }
        }
      }
    }

    final list = map.entries.map((e) => _EntitySummary(
      id:          e.key,
      name:        e.value['name'] as String,
      earnings:    e.value['earnings'] as Map<Period, double>,
      orderCounts: e.value['counts'] as Map<Period, int>,
    )).toList()
      ..sort((a, b) => (b.earnings[_restPeriod] ?? 0)
          .compareTo(a.earnings[_restPeriod] ?? 0));

    if (mounted) {
      setState(() {
        _restaurants  = list;
        _loadingRest  = false;
      });
    }
  }

  // ── Agents ────────────────────────────────────────────────────────────────────
  void _computeAgents() {
    final Map<String, Map<String, dynamic>> map = {};

    final deliveredOrders = _allOrders.where((o) =>
        (o['status'] as String? ?? '') == 'delivered' &&
        (o['assignedAgentId'] as String? ?? '').isNotEmpty);

    for (final order in deliveredOrders) {
      final agentId   = order['assignedAgentId'] as String;
      final agentName = order['agentName'] as String? ?? 'Agent';
      final fee       = (order['deliveryFee'] as num? ?? 30).toDouble();

      map.putIfAbsent(agentId, () => {
        'name':     agentName,
        'earnings': <Period, double>{for (final p in Period.values) p: 0.0},
        'counts':   <Period, int>{for (final p in Period.values) p: 0},
      });

      for (final p in Period.values) {
        if (_inPeriod(order, p)) {
          (map[agentId]!['earnings'] as Map<Period, double>)[p] =
              (map[agentId]!['earnings'] as Map<Period, double>)[p]! + fee;
          (map[agentId]!['counts'] as Map<Period, int>)[p] =
              (map[agentId]!['counts'] as Map<Period, int>)[p]! + 1;
        }
      }
    }

    final list = map.entries.map((e) => _EntitySummary(
      id:          e.key,
      name:        e.value['name'] as String,
      earnings:    e.value['earnings'] as Map<Period, double>,
      orderCounts: e.value['counts'] as Map<Period, int>,
    )).toList()
      ..sort((a, b) => (b.earnings[_agentPeriod] ?? 0)
          .compareTo(a.earnings[_agentPeriod] ?? 0));

    if (mounted) {
      setState(() {
        _agents       = list;
        _loadingAgent = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: () async => _recompute(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(children: [

            // ── COD panel — ADMIN ONLY ────────────────────────────────────────
            // Restaurants don't collect COD cash — the delivery agent does.
            // Only the admin needs to track and reconcile COD remittances.
            if (widget.role == FinanceRole.admin)
              _CodPanel(
                loading:   _loadingCod,
                summary:   _codSummary,
                period:    _codPeriod,
                onPeriod:  (p) {
                  setState(() => _codPeriod = p);
                  _computeCod();
                },
              ),

            if (widget.role == FinanceRole.admin)
              const SizedBox(height: 20),

            // ── Restaurant revenue panel ──────────────────────────────────────
            if (widget.role == FinanceRole.admin ||
                widget.role == FinanceRole.restaurant)
              _RestaurantPanel(
                loading:      _loadingRest,
                restaurants:  widget.role == FinanceRole.restaurant
                    ? _restaurants
                        .where((r) => r.id == widget.restaurantId)
                        .toList()
                    : _restaurants,
                period:       _restPeriod,
                expandedId:   _expandedRestId,
                onPeriod: (p) {
                  setState(() => _restPeriod = p);
                  _computeRestaurants();
                },
                onExpand: (id) => setState(() =>
                    _expandedRestId = _expandedRestId == id ? null : id),
              ),

            const SizedBox(height: 20),

            // ── Agent earnings panel ──────────────────────────────────────────
            if (widget.role == FinanceRole.admin ||
                widget.role == FinanceRole.agent)
              _AgentPanel(
                loading:    _loadingAgent,
                agents:     widget.role == FinanceRole.agent
                    ? _agents
                        .where((a) => a.id == widget.agentId)
                        .toList()
                    : _agents,
                period:     _agentPeriod,
                expandedId: _expandedAgentId,
                onPeriod: (p) {
                  setState(() => _agentPeriod = p);
                  _computeAgents();
                },
                onExpand: (id) => setState(() =>
                    _expandedAgentId = _expandedAgentId == id ? null : id),
              ),

            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
        backgroundColor: _kDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Finance',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          Text(
            widget.role == FinanceRole.admin
                ? 'Platform overview'
                : widget.role == FinanceRole.restaurant
                    ? widget.restaurantName ?? 'Restaurant'
                    : widget.agentName ?? 'Agent',
            style: const TextStyle(
                color: Colors.white54, fontSize: 11),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  COD PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _CodPanel extends StatelessWidget {
  final bool         loading;
  final _CodSummary? summary;
  final Period       period;
  final void Function(Period) onPeriod;

  const _CodPanel({
    required this.loading,
    required this.summary,
    required this.period,
    required this.onPeriod,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'COD — send to admin',
      icon: Icons.payments_rounded,
      iconColor: _kOrange,
      badge: 'Cash on Delivery',
      badgeColor: const Color(0xFFFFF3CD),
      badgeTextColor: const Color(0xFF856404),
      periods: const [Period.today, Period.week, Period.month],
      selected: period,
      onPeriod: onPeriod,
      child: loading
          ? const _LoadingBox()
          : summary == null || summary!.count == 0
              ? _EmptyBox(
                  message: 'No COD orders ${period.label.toLowerCase()}')
              : _CodBody(summary: summary!, period: period),
    );
  }
}

class _CodBody extends StatelessWidget {
  final _CodSummary summary;
  final Period      period;
  const _CodBody({required this.summary, required this.period});

  @override
  Widget build(BuildContext context) {
    final avg = summary.count > 0 ? summary.total / summary.count : 0.0;
    return Column(children: [
      // Main amount card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE08A)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE08A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.currency_rupee_rounded,
                color: Color(0xFF856404), size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Amount to remit',
                style: TextStyle(
                    fontSize: 12, color: Colors.brown.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                _fmtRupee(summary.total),
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF856404),
                    letterSpacing: -0.5),
              ),
              Text(
                'from ${summary.count} COD order${summary.count == 1 ? '' : 's'} ${period.label.toLowerCase()}',
                style: const TextStyle(
                    fontSize: 11.5, color: Color(0xFFAD8B3A)),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _MiniStat(label: 'Orders', value: '${summary.count}', color: _kOrange),
        const SizedBox(width: 10),
        _MiniStat(
            label: 'Avg order',
            value: _fmtRupee(avg),
            color: _kPrimary),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RESTAURANT PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _RestaurantPanel extends StatelessWidget {
  final bool                  loading;
  final List<_EntitySummary>  restaurants;
  final Period                period;
  final String?               expandedId;
  final void Function(Period) onPeriod;
  final void Function(String) onExpand;

  const _RestaurantPanel({
    required this.loading,
    required this.restaurants,
    required this.period,
    required this.expandedId,
    required this.onPeriod,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final totalEarnings = restaurants.fold<double>(
        0, (s, r) => s + (r.earnings[period] ?? 0));
    final totalOrders = restaurants.fold<int>(
        0, (s, r) => s + (r.orderCounts[period] ?? 0));

    return _SectionCard(
      title: 'Restaurant revenue',
      icon: Icons.storefront_rounded,
      iconColor: _kGreen,
      badge: 'Food sales',
      badgeColor: const Color(0xFFD4EDDA),
      badgeTextColor: const Color(0xFF155724),
      periods: Period.values.toList(),
      selected: period,
      onPeriod: onPeriod,
      child: loading
          ? const _LoadingBox()
          : restaurants.isEmpty
              ? _EmptyBox(
                  message: 'No restaurant data ${period.label.toLowerCase()}')
              : Column(children: [
                  Row(children: [
                    _MiniStat(
                        label: 'Total revenue',
                        value: _fmtRupee(totalEarnings),
                        color: _kGreen),
                    const SizedBox(width: 10),
                    _MiniStat(
                        label: 'Orders',
                        value: '$totalOrders',
                        color: _kPrimary),
                    const SizedBox(width: 10),
                    _MiniStat(
                        label: 'Avg / order',
                        value: _fmtRupee(
                            totalOrders > 0 ? totalEarnings / totalOrders : 0),
                        color: _kOrange),
                  ]),
                  const SizedBox(height: 12),
                  ...restaurants.map((r) => _EntityRow(
                        entity:      r,
                        period:      period,
                        isExpanded:  expandedId == r.id,
                        avatarColor: _kGreen,
                        onTap:       () => onExpand(r.id),
                      )),
                ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AGENT PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _AgentPanel extends StatelessWidget {
  final bool                  loading;
  final List<_EntitySummary>  agents;
  final Period                period;
  final String?               expandedId;
  final void Function(Period) onPeriod;
  final void Function(String) onExpand;

  const _AgentPanel({
    required this.loading,
    required this.agents,
    required this.period,
    required this.expandedId,
    required this.onPeriod,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final totalEarnings = agents.fold<double>(
        0, (s, a) => s + (a.earnings[period] ?? 0));

    return _SectionCard(
      title: 'Delivery agent earnings',
      icon: Icons.directions_bike_rounded,
      iconColor: _kPrimary,
      badge: 'Delivery fees',
      badgeColor: const Color(0xFFCCE5FF),
      badgeTextColor: const Color(0xFF004085),
      periods: Period.values.toList(),
      selected: period,
      onPeriod: onPeriod,
      child: loading
          ? const _LoadingBox()
          : agents.isEmpty
              ? _EmptyBox(
                  message: 'No deliveries ${period.label.toLowerCase()}')
              : Column(children: [
                  Row(children: [
                    _MiniStat(
                        label: 'Total paid out',
                        value: _fmtRupee(totalEarnings),
                        color: _kPrimary),
                    const SizedBox(width: 10),
                    _MiniStat(
                        label: 'Active agents',
                        value: '${agents.length}',
                        color: _kGreen),
                    const SizedBox(width: 10),
                    _MiniStat(
                        label: 'Avg / agent',
                        value: _fmtRupee(
                            agents.isNotEmpty ? totalEarnings / agents.length : 0),
                        color: _kOrange),
                  ]),
                  const SizedBox(height: 12),
                  ...agents.map((a) => _EntityRow(
                        entity:      a,
                        period:      period,
                        isExpanded:  expandedId == a.id,
                        avatarColor: _kPrimary,
                        onTap:       () => onExpand(a.id),
                        showAllPeriods: true,
                      )),
                ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ENTITY ROW (restaurant or agent — expandable)
// ─────────────────────────────────────────────────────────────────────────────
class _EntityRow extends StatelessWidget {
  final _EntitySummary entity;
  final Period         period;
  final bool           isExpanded;
  final Color          avatarColor;
  final VoidCallback   onTap;
  final bool           showAllPeriods;

  const _EntityRow({
    required this.entity,
    required this.period,
    required this.isExpanded,
    required this.avatarColor,
    required this.onTap,
    this.showAllPeriods = false,
  });

  @override
  Widget build(BuildContext context) {
    final initials = entity.name
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    final currentEarnings = entity.earnings[period] ?? 0.0;
    final currentOrders   = entity.orderCounts[period] ?? 0;
    final avg = currentOrders > 0 ? currentEarnings / currentOrders : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: const Color(0x0A000000),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        // ── Header row ────────────────────────────────────────────────────
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: avatarColor.withOpacity(0.15),
                child: Text(
                  initials,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: avatarColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(entity.name,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _kDark)),
                  Text('$currentOrders order${currentOrders == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 11.5, color: _kGrey)),
                ]),
              ),
              Text(
                _fmtRupee(currentEarnings),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _kDark),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: isExpanded ? 0.5 : 0,
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: _kGrey),
              ),
            ]),
          ),
        ),
        // ── Expanded breakdown ─────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: isExpanded
              ? Container(
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(14)),
                  ),
                  child: Column(children: [
                    const Divider(height: 1, color: Color(0xFFE5E5EA)),
                    _BreakdownRow(
                        label: 'Avg order value',
                        value: _fmtRupee(avg)),
                    _BreakdownRow(
                        label: 'Orders (${period.label})',
                        value: '$currentOrders'),
                    const Divider(height: 1, color: Color(0xFFE5E5EA)),
                    ...Period.values.map((p) => _BreakdownRow(
                          label: p.label,
                          value: _fmtRupee(entity.earnings[p] ?? 0),
                          highlight: p == period,
                          highlightColor: avatarColor,
                        )),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION CARD wrapper
// ─────────────────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String              title;
  final IconData            icon;
  final Color               iconColor;
  final String              badge;
  final Color               badgeColor;
  final Color               badgeTextColor;
  final List<Period>        periods;
  final Period              selected;
  final void Function(Period) onPeriod;
  final Widget              child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.badge,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.periods,
    required this.selected,
    required this.onPeriod,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: const Color(0x0D000000),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _kDark)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(badge,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: badgeTextColor)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: periods.map((p) {
                final isActive = p == selected;
                return GestureDetector(
                  onTap: () => onPeriod(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? _kDark : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(p.label,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? Colors.white
                                : _kGrey)),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
              color: _kBg, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 10.5, color: _kGrey)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ]),
        ),
      );
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final bool   highlight;
  final Color  highlightColor;
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.highlight      = false,
    this.highlightColor = _kPrimary,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color: highlight ? highlightColor : _kGrey,
                  fontWeight:
                      highlight ? FontWeight.w700 : FontWeight.w400)),
          Text(value,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: highlight ? highlightColor : _kDark)),
        ]),
      );
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 80,
        child: Center(
            child: CircularProgressIndicator(
                color: _kPrimary, strokeWidth: 2.5)),
      );
}

class _EmptyBox extends StatelessWidget {
  final String message;
  const _EmptyBox({required this.message});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 80,
        child: Center(
          child: Text(message,
              style: const TextStyle(
                  fontSize: 13, color: _kGrey)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────
String _fmtRupee(double v) {
  if (v >= 100000) {
    return '₹${(v / 100000).toStringAsFixed(1)}L';
  } else if (v >= 1000) {
    return '₹${(v / 1000).toStringAsFixed(1)}K';
  }
  return '₹${v.toStringAsFixed(0)}';
}