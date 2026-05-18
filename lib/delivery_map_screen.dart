// ─────────────────────────────────────────────────────────────────────────────
// delivery_map_screen.dart — FoodFeast
//
// Multi-restaurant support:
//   ✅ Shows all restaurant pins + customer pin on map
//   ✅ TSP nearest-neighbour route: agent → best restaurant order → customer
//   ✅ Per-restaurant "Order Picked from [Name]" buttons
//   ✅ Skips already-picked restaurants (pickedRestaurantIds Firestore field)
//   ✅ After all restaurants picked → "Delivering to [Customer]" phase
//   ✅ Route redraws after each pickup
//   ✅ Backwards-compatible: single restaurantLat/Lng still works
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'local_notification_service.dart';

const _kOsrmBase        = 'https://router.project-osrm.org/route/v1/driving';
const _kArrivalRadius   = 80.0;
const _kRerouteInterval = 30;
const _kRerouteThreshold = 120;   // FIX: was 60s — too sensitive, caused constant reroutes
const _kNoRerouteRadius  = 300.0; // FIX: skip reroute when within 300 m of destination

// ── Restaurant stop model ────────────────────────────────────────────────────
class RestaurantStop {
  final String id;         // unique key (index-based if not provided)
  final String name;
  final LatLng location;
  bool picked;

  RestaurantStop({
    required this.id,
    required this.name,
    required this.location,
    this.picked = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
class DeliveryMapScreen extends StatefulWidget {
  final String agentId;
  final String orderId;

  // Legacy single-restaurant params (kept for backwards compat)
  final double restaurantLat;
  final double restaurantLng;
  final String restaurantName;

  // Multi-restaurant list (preferred). Each map must have:
  //   { 'name': String, 'lat': double, 'lng': double, 'id': String? }
  final List<Map<String, dynamic>> restaurants;

  final double customerLat;
  final double customerLng;
  final String customerName;

  const DeliveryMapScreen({
    super.key,
    required this.agentId,
    required this.orderId,
    required this.restaurantLat,
    required this.restaurantLng,
    required this.restaurantName,
    required this.customerLat,
    required this.customerLng,
    required this.customerName,
    this.restaurants = const [],
  });

  @override
  State<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends State<DeliveryMapScreen> {
  static const _primary = Color(0xFF0077B6);
  static const _green   = Color(0xFF34C759);
  static const _orange  = Color(0xFFFF9500);
  static const _red     = Color(0xFFFF3B30);

  // Restaurant pin colours — cycle through these for multiple restaurants
  static const _pinColors = [
    Color(0xFFFF9500), // orange
    Color(0xFFAF52DE), // purple
    Color(0xFFFF2D55), // red-pink
    Color(0xFF5856D6), // indigo
    Color(0xFFFF6B35), // deep orange
  ];

  final _mapCtrl = MapController();

  // Resolved list of stops (built in initState from widget params)
  late List<RestaurantStop> _stops;

  // Index into _stops of the restaurant we're currently heading to.
  // -1 means all picked, heading to customer.
  int _currentStopIndex = 0;

  LatLng? _agentPos;

  List<LatLng> _polyline    = [];
  List<_Step>  _steps       = [];
  int          _currentStep = 0;
  int          _etaSeconds  = 0;
  double       _distanceM   = 0;
  bool         _loadingRoute = true;
  bool         _arrived      = false;
  bool         _etaNotified  = false;

  // Per-restaurant picking in-progress guard (index → bool)
  final Set<int> _pickingIndices = {};

  Timer? _locationTimer;
  Timer? _rerouteTimer;
  int    _secondsSinceReroute = 0;
  int    _lastRouteDuration   = 0;

  static const _kEtaNotifyMinutes = 5;

  bool get _allPicked =>
      _stops.every((s) => s.picked) || _currentStopIndex < 0;

  bool get _hasCustomerCoords =>
      widget.customerLat != 0.0 || widget.customerLng != 0.0;

  LatLng get _customerPos =>
      LatLng(widget.customerLat, widget.customerLng);

  // ── Destination for current leg ──────────────────────────────────────────
  LatLng? get _currentDest {
    if (_allPicked) return _hasCustomerCoords ? _customerPos : null;
    if (_currentStopIndex >= _stops.length) return null;
    return _stops[_currentStopIndex].location;
  }

  String get _currentDestLabel {
    if (_allPicked) return widget.customerName;
    if (_currentStopIndex >= _stops.length) return '';
    return _stops[_currentStopIndex].name;
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _buildStops();
    _bootstrap();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _rerouteTimer?.cancel();
    super.dispose();
  }

  // ── Build restaurant stops list ───────────────────────────────────────────
  void _buildStops() {
    if (widget.restaurants.isNotEmpty) {
      _stops = widget.restaurants.asMap().entries.map((e) {
        final i = e.key;
        final r = e.value;
        return RestaurantStop(
          id:       r['id'] as String? ?? 'rest_$i',
          name:     r['name'] as String? ?? 'Restaurant ${i + 1}',
          location: LatLng(
            (r['lat'] as num).toDouble(),
            (r['lng'] as num).toDouble(),
          ),
        );
      }).toList();
    } else {
      // Legacy single restaurant
      _stops = [
        RestaurantStop(
          id:       'rest_0',
          name:     widget.restaurantName,
          location: LatLng(widget.restaurantLat, widget.restaurantLng),
        ),
      ];
    }
  }

  // ── Bootstrap ─────────────────────────────────────────────────────────────
  Future<void> _bootstrap() async {
    try {
      await _requestPermission();
      await _restoreOrderPhase();
      await _updatePosition();
      if (_agentPos != null) _optimiseRouteOrder();
      await _fetchRoute();
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
    } finally {
      // Always start timers so location keeps updating even if route failed
      if (mounted) _startTimers();
    }
  }

  // ── TSP nearest-neighbour: sort unpicked stops by distance from agent ─────
  void _optimiseRouteOrder() {
    // If all stops are already picked (restored from Firestore), don't reorder
    if (_currentStopIndex < 0) return;
    if (_agentPos == null) return;
    final unpicked = _stops.where((s) => !s.picked).toList();
    if (unpicked.length <= 1) return;

    final sorted = <RestaurantStop>[];
    var current = _agentPos!;

    final remaining = List<RestaurantStop>.from(unpicked);
    while (remaining.isNotEmpty) {
      remaining.sort((a, b) =>
          _haversine(current, a.location)
              .compareTo(_haversine(current, b.location)));
      sorted.add(remaining.removeAt(0));
      current = sorted.last.location;
    }

    // Re-order _stops: picked first (preserve order), then sorted unpicked
    final picked   = _stops.where((s) => s.picked).toList();
    _stops         = [...picked, ...sorted];
    _currentStopIndex = picked.length;
  }

  // ── Restore pickup state from Firestore ──────────────────────────────────
  Future<void> _restoreOrderPhase() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .get();
      final data   = doc.data();
      if (data == null) return;

      final status = data['status'] as String? ?? '';
      final pickedIds = (data['pickedRestaurantIds'] as List?)
          ?.map((e) => e.toString())
          .toSet() ?? {};

      if (!mounted) return;
      setState(() {
        for (final s in _stops) {
          if (pickedIds.contains(s.id)) s.picked = true;
        }
        // Find first unpicked
        _currentStopIndex = _stops.indexWhere((s) => !s.picked);
        if (_currentStopIndex == -1 ||
            status == 'out_for_delivery' ||
            status == 'delivered') {
          // All picked or already out for delivery
          _currentStopIndex = -1;
          for (final s in _stops) s.picked = true;
        }
      });
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _requestPermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) return;
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
  }

  Future<void> _updatePosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() => _agentPos = LatLng(pos.latitude, pos.longitude));
      try {
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .set(
          {
            'agentLat':      pos.latitude,
            'agentLng':      pos.longitude,
            'agentLastSeen': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() =>
              _agentPos = LatLng(last.latitude, last.longitude));
        }
      } catch (_) {}
    }
  }

  // ── Fetch OSRM route for remaining legs ──────────────────────────────────
  // Builds: agent → stop[i] → stop[i+1] → … → customer (all in one call)
  Future<void> _fetchRoute() async {
    if (_fetchingRoute) return;
    _fetchingRoute = true;
    final start = _agentPos;
    if (start == null) {
      if (mounted) setState(() => _loadingRoute = false);
      return;
    }

    // Build waypoints: agent + unpicked stops + customer
    final waypoints = <LatLng>[start];
    for (final s in _stops) {
      if (!s.picked) waypoints.add(s.location);
    }
    if (_hasCustomerCoords) waypoints.add(_customerPos);

    if (waypoints.length < 2) {
      if (mounted) setState(() => _loadingRoute = false);
      return;
    }

    final coords = waypoints
        .map((w) => '${w.longitude},${w.latitude}')
        .join(';');

    final url = Uri.parse(
      '$_kOsrmBase/$coords'
      '?overview=full&geometries=geojson&steps=true',
    );

    try {
      final resp =
          await http.get(url).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        if (mounted) setState(() => _loadingRoute = false);
        return;
      }
      final json   = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        if (mounted) setState(() => _loadingRoute = false);
        return;
      }

      final route = routes.first as Map<String, dynamic>;

      final polyCoords = (route['geometry']['coordinates'] as List)
          .map((c) =>
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final legs = route['legs'] as List;
      final steps = <_Step>[];
      for (final leg in legs) {
        for (final s in (leg['steps'] as List)) {
          final man   = s['maneuver'] as Map<String, dynamic>;
          final instr = _buildInstruction(man, s['name'] as String? ?? '');
          final dist  = (s['distance'] as num).toDouble();
          final dur   = (s['duration'] as num).toDouble();
          final loc   = man['location'] as List;
          steps.add(_Step(
            instruction: instr,
            distanceM:   dist,
            durationS:   dur,
            point: LatLng(
              (loc[1] as num).toDouble(),
              (loc[0] as num).toDouble(),
            ),
          ));
        }
      }

      // Total duration from all legs
      final totalDur = legs.fold<int>(
          0, (sum, leg) => sum + (leg['duration'] as num).toInt());
      final totalDist = (route['distance'] as num).toDouble();

      if (!mounted) return;
      setState(() {
        _polyline          = polyCoords;
        _steps             = steps;
        _currentStep       = 0;
        _etaSeconds        = totalDur;
        _distanceM         = totalDist;
        _lastRouteDuration = totalDur;
        _loadingRoute      = false;
      });

      if (_agentPos != null) _mapCtrl.move(_agentPos!, 14);
      _checkEtaNotification();
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
    } finally {
      _fetchingRoute = false;
    }
  }

  // ── Agent tapped "Order Picked from [Restaurant]" ────────────────────────
  Future<void> _onPickedFromRestaurant(int stopIndex) async {
    if (_pickingIndices.contains(stopIndex)) return;
    if (stopIndex >= _stops.length) return;
    final stop = _stops[stopIndex];

    setState(() => _pickingIndices.add(stopIndex));

    // Mark stop picked
    final pickedIds = _stops
        .where((s) => s.picked || s.id == stop.id)
        .map((s) => s.id)
        .toList();

    // Determine next Firestore status
    final nextUnpickedCount =
        _stops.where((s) => !s.picked && s.id != stop.id).length;
    final isLastPickup = nextUnpickedCount == 0;
    final nextStatus   = isLastPickup ? 'out_for_delivery' : 'picked_up';

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'pickedRestaurantIds': pickedIds,
        'status':              nextStatus,
      });
    } catch (_) {
      // Non-fatal — continue locally
    }

    if (!mounted) return;
    setState(() {
      stop.picked = true;
      _pickingIndices.remove(stopIndex);

      // Advance to next unpicked stop
      _currentStopIndex = _stops.indexWhere((s) => !s.picked);
      if (_currentStopIndex == -1) {
        // All picked!
      }
      _etaNotified  = false;
      _loadingRoute = true;
    });

    await _fetchRoute();
  }

  // ─────────────────────────────────────────────────────────────────────────
  void _startTimers() {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _updatePosition();
      _advanceStep();
      _checkArrival();
      _tickEta();
    });

    _rerouteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _secondsSinceReroute++;
      if (_secondsSinceReroute >= _kRerouteInterval) {
        _secondsSinceReroute = 0;
        _trafficReroute();
      }
    });
  }

  void _tickEta() {
    if (!mounted) return;
    // Decay ETA by the timer interval (5s). Also approximate distance decay:
    // use speed = distance/time to estimate how many metres were covered.
    final prevEta = _etaSeconds;
    setState(() {
      _etaSeconds = max(0, _etaSeconds - 5);
      if (prevEta > 0 && _distanceM > 0) {
        final fraction = 5.0 / prevEta;
        _distanceM = max(0, _distanceM - _distanceM * fraction);
      }
    });
    _checkEtaNotification();
  }

  // Track whether a route fetch is in progress (prevents reroute race)
  bool _fetchingRoute = false;

  Future<void> _trafficReroute() async {
    if (_agentPos == null || _arrived || _fetchingRoute) return;
    if (_currentDest == null) return;

    // FIX: Don't reroute when agent is already close to the current destination.
    // This prevents the "long diagonal line" redraw that appears when GPS jitter
    // causes OSRM to draw a new route from the agent's position back to a pin
    // that is only a few metres away.
    if (_haversine(_agentPos!, _currentDest!) <= _kNoRerouteRadius) return;

    try {
      _fetchingRoute = true;
      // Re-fetch full remaining route
      final waypoints = <LatLng>[_agentPos!];
      for (final s in _stops) {
        if (!s.picked) waypoints.add(s.location);
      }
      if (_hasCustomerCoords) waypoints.add(_customerPos);

      if (waypoints.length < 2) return;

      final coords = waypoints
          .map((w) => '${w.longitude},${w.latitude}')
          .join(';');

      final url = Uri.parse(
        '$_kOsrmBase/$coords'
        '?overview=full&geometries=geojson&steps=true',
      );

      final resp =
          await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;

      final json   = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route      = routes.first as Map<String, dynamic>;
      final legs       = route['legs'] as List;
      final newDur     = legs.fold<int>(
          0, (sum, leg) => sum + (leg['duration'] as num).toInt());

      if ((newDur - _lastRouteDuration).abs() < _kRerouteThreshold) return;

      final newCoords = (route['geometry']['coordinates'] as List)
          .map((c) =>
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final newSteps = <_Step>[];
      for (final leg in legs) {
        for (final s in (leg['steps'] as List)) {
          final man   = s['maneuver'] as Map<String, dynamic>;
          final instr = _buildInstruction(man, s['name'] as String? ?? '');
          final dist  = (s['distance'] as num).toDouble();
          final dur   = (s['duration'] as num).toDouble();
          final loc   = man['location'] as List;
          newSteps.add(_Step(
            instruction: instr,
            distanceM:   dist,
            durationS:   dur,
            point: LatLng(
              (loc[1] as num).toDouble(),
              (loc[0] as num).toDouble(),
            ),
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _polyline          = newCoords;
        _steps             = newSteps;
        _currentStep       = 0;
        _etaSeconds        = newDur;
        _distanceM         = (route['distance'] as num).toDouble();
        _lastRouteDuration = newDur;
      });

      await LocalNotificationService.showNotification(
        id:    2001,
        title: '🔄 Route Updated',
        body:  'Traffic detected — route updated. New ETA: '
               '${_formatDuration(newDur)}',
      );
    } catch (_) {} finally {
      _fetchingRoute = false;
    }
  }

  void _advanceStep() {
    if (_agentPos == null || _steps.isEmpty) return;
    if (_currentStep >= _steps.length - 1) return;
    if (_haversine(_agentPos!, _steps[_currentStep].point) < 30) {
      if (!mounted) return;
      setState(() => _currentStep++);
    }
  }

  void _checkArrival() {
    if (_agentPos == null || _arrived) return;
    // Auto-arrival only at customer (final stop)
    if (_allPicked && _hasCustomerCoords) {
      if (_haversine(_agentPos!, _customerPos) <= _kArrivalRadius) {
        if (!mounted) return;
        // FIX: cancel reroute timer immediately so no further reroute fires
        // between now and the next location-timer tick.
        _rerouteTimer?.cancel();
        _rerouteTimer = null;
        setState(() => _arrived = true);
        _fireArrivalNotification();
      }
    }
  }

  void _checkEtaNotification() {
    if (_etaNotified || _arrived) return;
    if (_etaSeconds <= _kEtaNotifyMinutes * 60) {
      _etaNotified = true;
      LocalNotificationService.showNotification(
        id:    2000,
        title: '📍 Almost there!',
        body:
            'You\'ll reach $_currentDestLabel in ~${_formatDuration(_etaSeconds)}.',
      );
    }
  }

  Future<void> _fireArrivalNotification() async {
    await LocalNotificationService.showNotification(
      id:    2002,
      title: '✅ Arrived at Destination',
      body:
          'You have reached ${widget.customerName}\'s location. Complete the delivery!',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  double _haversine(LatLng a, LatLng b) {
    const r    = 6371000.0;
    final dLat = _rad(b.latitude  - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h    = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) * cos(_rad(b.latitude)) *
            sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(sqrt(h));
  }

  double _rad(double deg) => deg * pi / 180;

  String _buildInstruction(
      Map<String, dynamic> maneuver, String roadName) {
    final type     = maneuver['type']     as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';
    final road     = roadName.isNotEmpty ? ' onto $roadName' : '';

    switch (type) {
      case 'depart':   return 'Head ${modifier.isNotEmpty ? modifier : 'forward'}$road';
      case 'arrive':   return 'You have arrived';
      case 'turn':
        switch (modifier) {
          case 'left':         return 'Turn left$road';
          case 'right':        return 'Turn right$road';
          case 'slight left':  return 'Keep slight left$road';
          case 'slight right': return 'Keep slight right$road';
          case 'sharp left':   return 'Turn sharp left$road';
          case 'sharp right':  return 'Turn sharp right$road';
          case 'uturn':        return 'Make a U-turn';
          default:             return 'Continue$road';
        }
      case 'new name':  return 'Continue$road';
      case 'continue':  return 'Continue$road';
      case 'merge':     return 'Merge${modifier.isNotEmpty ? ' $modifier' : ''}$road';
      case 'ramp':      return 'Take the ramp$road';
      case 'fork':
        return modifier.contains('left')
            ? 'Keep left at the fork$road'
            : 'Keep right at the fork$road';
      case 'end of road':
        return modifier.contains('left')
            ? 'Turn left at the end of the road$road'
            : 'Turn right at the end of the road$road';
      case 'roundabout':
      case 'rotary':
        final exit = maneuver['exit'] as int?;
        return exit != null
            ? 'At the roundabout, take exit $exit$road'
            : 'Enter the roundabout$road';
      default:
        return 'Continue$road';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds sec';
    final m = seconds ~/ 60;
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    return '${h}h ${m % 60}min';
  }

  String _formatDistance(double metres) {
    if (metres < 1000) return '${metres.toStringAsFixed(0)} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  IconData _turnIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left'))       return Icons.turn_left_rounded;
    if (lower.contains('right'))      return Icons.turn_right_rounded;
    if (lower.contains('u-turn'))     return Icons.u_turn_left_rounded;
    if (lower.contains('roundabout')) return Icons.rotate_right_rounded;
    if (lower.contains('arrived'))    return Icons.location_on_rounded;
    return Icons.straight_rounded;
  }

  // ── Nav panel ────────────────────────────────────────────────────────────
  Widget? _buildNavPanel() {
    if (_loadingRoute || _steps.isEmpty || _arrived) return null;
    if (_currentStep >= _steps.length) return null;
    final step = _steps[_currentStep];
    if (step.instruction.toLowerCase().contains('have arrived')) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_turnIcon(step.instruction),
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step.instruction,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDistance(step.distanceM),
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E6E73),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom action buttons (one per unpicked restaurant or delivery banner)
  Widget _buildBottomPanel() {
    // Always return a Positioned so Stack children are consistent
    if (_loadingRoute || _arrived) {
      return const Positioned(bottom: 0, left: 0, right: 0, child: SizedBox.shrink());
    }

    if (_allPicked) {
      // Delivering-to banner
      return Positioned(
        bottom: 40,
        left: 20,
        right: 20,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _green,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.delivery_dining_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Delivering to ${widget.customerName}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show pickup buttons for all unpicked restaurants (scrollable row)
    final unpickedStops = _stops
        .asMap()
        .entries
        .where((e) => !e.value.picked)
        .toList();

    return Positioned(
      bottom: 30,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: unpickedStops.map((e) {
          final idx  = e.key;
          final stop = e.value;
          final isNext = idx == _currentStopIndex;
          final picking = _pickingIndices.contains(idx);
          final color = _pinColors[idx % _pinColors.length];

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: isNext && !picking
                  ? () => _onPickedFromRestaurant(idx)
                  : null,
              child: AnimatedOpacity(
                opacity: isNext ? 1.0 : 0.55,
                duration: const Duration(milliseconds: 200),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: picking ? Colors.grey.shade500 : color,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (picking)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      else
                        const Icon(Icons.storefront_rounded,
                            color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          picking
                              ? 'Updating route…'
                              : isNext
                                  ? 'Order Picked from ${stop.name} ✅'
                                  : '⏳ Next: ${stop.name}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Build map markers ─────────────────────────────────────────────────────
  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Agent
    if (_agentPos != null) {
      markers.add(Marker(
        point:  _agentPos!,
        width:  44,
        height: 44,
        child:  _AgentMarker(),
      ));
    }

    // Restaurant stops
    for (int i = 0; i < _stops.length; i++) {
      final stop  = _stops[i];
      final color = _pinColors[i % _pinColors.length];
      markers.add(Marker(
        point:  stop.location,
        width:  40,
        height: 50,
        child:  _RestaurantMarker(
          name:    stop.name,
          color:   color,
          picked:  stop.picked,
          number:  i + 1,
        ),
      ));
    }

    // Customer
    if (_hasCustomerCoords) {
      markers.add(Marker(
        point:  _customerPos,
        width:  36,
        height: 36,
        child:  _PinMarker(icon: Icons.person_rounded, color: _green),
      ));
    }

    return markers;
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final destLabel = _currentDestLabel;
    final destPos   = _currentDest;
    final mapCenter = _agentPos ?? destPos ?? _customerPos;

    final toRestaurant = !_allPicked;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────────
          SizedBox.expand(
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: mapCenter,
                initialZoom:   14,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.foodfeast.app',
                ),
                if (_polyline.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(
                      points:      _polyline,
                      color:       _primary,
                      strokeWidth: 5,
                    ),
                  ]),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),
          ),

          // ── Header ──────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(children: [
                    _CircleBtn(
                      icon:  Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    if (!_loadingRoute && !_arrived)
                      _EtaChip(
                        eta:          _formatDuration(_etaSeconds),
                        dist:         _formatDistance(_distanceM),
                        label:        destLabel,
                        toRestaurant: toRestaurant,
                        stopCount:    _stops.where((s) => !s.picked).length,
                      ),
                    const SizedBox(width: 8),
                    _CircleBtn(
                      icon:  Icons.my_location_rounded,
                      onTap: () {
                        if (_agentPos != null)
                          _mapCtrl.move(_agentPos!, 15);
                      },
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _buildNavPanel() ?? const SizedBox.shrink(),
                ],
              ),
            ),
          ),

          // ── Bottom action area ───────────────────────────────────────────
          _buildBottomPanel(),

          // ── Loading overlay ──────────────────────────────────────────────
          if (_loadingRoute)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal data model
// ─────────────────────────────────────────────────────────────────────────────
class _Step {
  final String instruction;
  final double distanceM;
  final double durationS;
  final LatLng point;
  const _Step({
    required this.instruction,
    required this.distanceM,
    required this.durationS,
    required this.point,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// UI Components
// ─────────────────────────────────────────────────────────────────────────────

class _AgentMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      const Color(0xFF0077B6).withOpacity(0.2))),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0077B6),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6)
              ],
            ),
            child: const Icon(Icons.navigation_rounded,
                color: Colors.white, size: 14),
          ),
        ],
      );
}

/// Restaurant marker with number badge + strikethrough when picked
class _RestaurantMarker extends StatelessWidget {
  final String  name;
  final Color   color;
  final bool    picked;
  final int     number;

  const _RestaurantMarker({
    required this.name,
    required this.color,
    required this.picked,
    required this.number,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: picked ? Colors.grey.shade400 : color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6)
                  ],
                ),
                child: Icon(
                  picked
                      ? Icons.check_rounded
                      : Icons.restaurant_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: picked ? Colors.grey : color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              name,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: picked ? Colors.grey : color,
                decoration:
                    picked ? TextDecoration.lineThrough : null,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      );
}

class _PinMarker extends StatelessWidget {
  final IconData icon;
  final Color    color;
  const _PinMarker({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 6)
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      );
}

class _EtaChip extends StatelessWidget {
  final String eta;
  final String dist;
  final String label;
  final bool   toRestaurant;
  final int    stopCount;

  const _EtaChip({
    required this.eta,
    required this.dist,
    required this.label,
    required this.toRestaurant,
    required this.stopCount,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 8)
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              toRestaurant
                  ? Icons.restaurant_rounded
                  : Icons.delivery_dining_rounded,
              size: 16,
              color: const Color(0xFF0077B6),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  toRestaurant && stopCount > 1
                      ? '$stopCount stops left → $label'
                      : label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6E6E73),
                      fontWeight: FontWeight.w500),
                ),
                Text(
                  '$eta · $dist',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C1E)),
                ),
              ],
            ),
          ],
        ),
      );
}

class _CircleBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
          ),
          child:
              Icon(icon, size: 18, color: const Color(0xFF1C1C1E)),
        ),
      );
}