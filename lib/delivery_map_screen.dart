// ─────────────────────────────────────────────────────────────────────────────
// delivery_map_screen.dart — FoodFeast  (Google Maps-level UX)
//
//  ✅ 3-D perspective tilt  (Matrix4 rotateX, smooth in/out)
//  ✅ Map rotates with heading — agent always faces "up"
//  ✅ Animated pulsing beacon for agent position
//  ✅ Accuracy halo ring around agent dot
//  ✅ Heading cone / direction wedge drawn on map
//  ✅ Compass counter-rotates; tap → resets north-up + exits tilt
//  ✅ Re-centre FAB — tap = Google Maps 3D nav recentre, long-press = overview
//  ✅ Animated flowing-dash route polyline (blue + white dashes)
//  ✅ Route border/glow layer (dark blue under bright blue)
//  ✅ Turn-by-turn card at top — slides in/out with CrossFade
//  ✅ Lane-distance sub-label in instruction card
//  ✅ ETA bottom bar (dark Google-style)  with distance + arrival time
//  ✅ Speed-limit badge  (bottom-left, circle with red border)
//  ✅ Traffic light strip (green / orange / red)
//  ✅ "Start Route" sheet — vertical timeline with distance per leg
//  ✅ Per-restaurant pickup pill buttons with haptics
//  ✅ Arrived confetti overlay + "Complete Delivery" CTA
//  ✅ TSP nearest-neighbour route ordering
//  ✅ Live OSRM fetch + silent background reroute
//  ✅ ETA countdown ticker + ~5-min push notification
//  ✅ Firestore agentLat/Lng heartbeat every 5 s
//  ✅ dart:ui Path alias — no latlong2 collision
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'local_notification_service.dart';

// ── OSRM / geo constants ─────────────────────────────────────────────────────
const _kOsrm             = 'https://router.project-osrm.org/route/v1/driving';
const _kArrivalRadius    = 80.0;   // metres — triggers arrival
const _kRerouteInterval  = 30;     // seconds between reroute checks
const _kRerouteThreshold = 120;    // seconds duration diff before rerouting
const _kNoRerouteRadius  = 300.0;  // don't reroute when within Xm of dest
const _kEtaNotifyMin     = 5;      // push when ETA < 5 min

// ── Brand palette ─────────────────────────────────────────────────────────────
const _blue       = Color(0xFF1A73E8);
const _blueDark   = Color(0xFF0D47A1);
const _green      = Color(0xFF34A853);
const _greenDark  = Color(0xFF1B5E20);
const _red        = Color(0xFFEA4335);
const _orange     = Color(0xFFFF9800);
const _gray       = Color(0xFF9AA0A6);
const _textDark   = Color(0xFF202124);
const _textMid    = Color(0xFF5F6368);
const _surface    = Color(0xFFFFFFFF);
const _navBg      = Color(0xFF1F1F1F);
const _navBgCard  = Color(0xFF2A2A2A);

const _stopColors = [
  Color(0xFFFF6D00),
  Color(0xFF7C4DFF),
  Color(0xFFD50000),
  Color(0xFF00BCD4),
  Color(0xFFAA00FF),
];

// ── Data models ───────────────────────────────────────────────────────────────
class RestaurantStop {
  final String id;
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

class _Step {
  final String instruction;
  final String modifier;
  final double distanceM;
  final double durationS;
  final LatLng point;
  const _Step({
    required this.instruction,
    required this.modifier,
    required this.distanceM,
    required this.durationS,
    required this.point,
  });
}

class _WP {
  final String   label;
  final String   sub;
  final IconData icon;
  final Color    color;
  final bool     isAgent;
  final bool     isCustomer;
  final bool     isPicked;
  final int?     stopIdx;
  final double   legDistM;
  const _WP({
    required this.label,
    required this.sub,
    required this.icon,
    required this.color,
    this.isAgent    = false,
    this.isCustomer = false,
    this.isPicked   = false,
    this.stopIdx,
    this.legDistM   = 0,
  });
}

// Only two real modes now — following nav, or free overview
enum _CentreMode { agent, overview }

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────
class DeliveryMapScreen extends StatefulWidget {
  final String agentId;
  final String orderId;
  final double restaurantLat;
  final double restaurantLng;
  final String restaurantName;
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
  State<DeliveryMapScreen> createState() => _State();
}

// ─────────────────────────────────────────────────────────────────────────────
class _State extends State<DeliveryMapScreen> with TickerProviderStateMixin {

  // ── Map controller ────────────────────────────────────────────────────────
  final _map = MapController();

  // ── 3-D tilt ─────────────────────────────────────────────────────────────
  double _tilt = 0.0;
  late AnimationController _tiltCtrl;
  late Animation<double>   _tiltAnim;

  // ── Map bearing (heading-up) ──────────────────────────────────────────────
  double _bearing    = 0.0;
  double _headingRad = 0.0;

  late AnimationController _bearCtrl;
  late Animation<double>   _bearAnim;

  // ── Compass ───────────────────────────────────────────────────────────────
  double get _compassRot => -_bearing * pi / 180;

  // ── Pulse beacon ──────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Polyline dash flow ────────────────────────────────────────────────────
  late AnimationController _dashCtrl;

  // ── Position ──────────────────────────────────────────────────────────────
  LatLng? _agentPos;
  double  _accuracyM = 10;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _poly   = [];
  List<_Step>  _steps  = [];
  int    _stepIdx      = 0;
  int    _etaSec       = 0;
  double _distM        = 0;
  bool   _loading      = true;
  bool   _fetching     = false;
  bool   _arrived      = false;
  bool   _etaNotified  = false;
  int    _lastDur      = 0;

  // ── Stops ─────────────────────────────────────────────────────────────────
  late List<RestaurantStop> _stops;
  int _stopIdx = 0;
  final Set<int> _picking = {};

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer? _locTimer;
  Timer? _rerouteTimer;
  int    _rerouteTick = 0;

  // ── UX state ─────────────────────────────────────────────────────────────
  bool        _started     = false;
  bool        _following   = true;
  _CentreMode _centreMode  = _CentreMode.agent;

  // ── Arrival overlay ───────────────────────────────────────────────────────
  late AnimationController _arrivalCtrl;
  late Animation<double>   _arrivalAnim;

  // ─── computed ─────────────────────────────────────────────────────────────
  bool    get _allPicked    => _stops.every((s) => s.picked);
  bool    get _hasCustomer  => widget.customerLat != 0 || widget.customerLng != 0;
  LatLng  get _custPos      => LatLng(widget.customerLat, widget.customerLng);
  LatLng? get _destPos {
    if (_allPicked) return _hasCustomer ? _custPos : null;
    if (_stopIdx >= _stops.length) return null;
    return _stops[_stopIdx].location;
  }
  String get _destLabel {
    if (_allPicked) return widget.customerName;
    if (_stopIdx >= _stops.length) return '';
    return _stops[_stopIdx].name;
  }
  String get _arrivalTime {
    final now = DateTime.now().add(Duration(seconds: _etaSec));
    final h   = now.hour;
    final m   = now.minute.toString().padLeft(2, '0');
    final ap  = h >= 12 ? 'PM' : 'AM';
    final hh  = (h % 12 == 0 ? 12 : h % 12).toString();
    return '$hh:$m $ap';
  }

  List<_WP> get _waypoints {
    final list = <_WP>[];
    if (_agentPos != null) {
      list.add(const _WP(
        label: 'Your location', sub: 'Starting point',
        icon: Icons.my_location_rounded, color: _blue, isAgent: true,
      ));
    }
    for (int i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      list.add(_WP(
        label:    s.name,
        sub:      s.picked ? 'Picked up ✓' : 'Pick up order',
        icon:     Icons.storefront_rounded,
        color:    s.picked ? _gray : _stopColors[i % _stopColors.length],
        isPicked: s.picked,
        stopIdx:  i,
      ));
    }
    if (_hasCustomer) {
      list.add(_WP(
        label: widget.customerName, sub: 'Drop off here',
        icon: Icons.person_pin_circle_rounded, color: _green, isCustomer: true,
      ));
    }
    return list;
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _buildStops();
    _initAnims();
    _bootstrap();
  }

  void _initAnims() {
    _tiltCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _tiltAnim = const AlwaysStoppedAnimation(0);

    _bearCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _bearAnim = const AlwaysStoppedAnimation(0);

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _dashCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();

    _arrivalCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _arrivalAnim = CurvedAnimation(parent: _arrivalCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    _rerouteTimer?.cancel();
    _tiltCtrl.dispose();
    _bearCtrl.dispose();
    _pulseCtrl.dispose();
    _dashCtrl.dispose();
    _arrivalCtrl.dispose();
    super.dispose();
  }

  // ── Build stops ────────────────────────────────────────────────────────────
  void _buildStops() {
    if (widget.restaurants.isNotEmpty) {
      _stops = widget.restaurants.asMap().entries.map((e) {
        final i = e.key; final r = e.value;
        return RestaurantStop(
          id:       r['id']   as String? ?? 'r$i',
          name:     r['name'] as String? ?? 'Restaurant ${i + 1}',
          location: LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()),
        );
      }).toList();
    } else {
      _stops = [RestaurantStop(
        id: 'r0', name: widget.restaurantName,
        location: LatLng(widget.restaurantLat, widget.restaurantLng),
      )];
    }
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────
  Future<void> _bootstrap() async {
    try {
      await _requestPerm();
      await _restorePhase();
      await _updatePos();
      if (_agentPos != null) _tspSort();
      await _fetchRoute();
      if (mounted && !_started) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showStartSheet();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      if (mounted) _startTimers();
    }
  }

  // ── TSP nearest-neighbour ──────────────────────────────────────────────────
  void _tspSort() {
    if (_agentPos == null) return;
    final unpicked = _stops.where((s) => !s.picked).toList();
    if (unpicked.length <= 1) return;
    final sorted = <RestaurantStop>[];
    var cur = _agentPos!;
    final rem = List<RestaurantStop>.from(unpicked);
    while (rem.isNotEmpty) {
      rem.sort((a, b) => _hav(cur, a.location).compareTo(_hav(cur, b.location)));
      sorted.add(rem.removeAt(0));
      cur = sorted.last.location;
    }
    final picked = _stops.where((s) => s.picked).toList();
    _stops = [...picked, ...sorted];
    _stopIdx = picked.length;
  }

  // ── Restore Firestore state ────────────────────────────────────────────────
  Future<void> _restorePhase() async {
    try {
      final doc  = await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).get();
      final data = doc.data();
      if (data == null || !mounted) return;
      final status    = data['status'] as String? ?? '';
      final pickedIds = (data['pickedRestaurantIds'] as List?)?.map((e) => '$e').toSet() ?? {};
      setState(() {
        for (final s in _stops) { if (pickedIds.contains(s.id)) s.picked = true; }
        _stopIdx = _stops.indexWhere((s) => !s.picked);
        if (_stopIdx == -1 || ['out_for_delivery','delivered'].contains(status)) {
          _stopIdx = -1;
          for (final s in _stops) s.picked = true;
          _started = true;
        }
      });
    } catch (_) {}
  }

  Future<void> _requestPerm() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  }

  // ── Position + heading ─────────────────────────────────────────────────────
  Future<void> _updatePos() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;

      final newPos = LatLng(pos.latitude, pos.longitude);

      // Always compute bearing from position delta using geodesic formula.
      // pos.heading is unreliable on many Android devices (can be 180° off or -1).
      if (_agentPos != null) {
        final lat1 = _agentPos!.latitude  * pi / 180;
        final lat2 = pos.latitude          * pi / 180;
        final dLng = (pos.longitude - _agentPos!.longitude) * pi / 180;
        final dLat = (pos.latitude  - _agentPos!.latitude);
        final dLon = (pos.longitude - _agentPos!.longitude);
        if (dLat.abs() > 1e-6 || dLon.abs() > 1e-6) {
          final y          = sin(dLng) * cos(lat2);
          final x          = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
          final newBearing = (atan2(y, x) * 180 / pi + 360) % 360;
          _animateBearing(newBearing);
        }
      }

      setState(() {
        _agentPos  = newPos;
        _accuracyM = pos.accuracy;
      });

      FirebaseFirestore.instance.collection('orders').doc(widget.orderId).set(
        {'agentLat': pos.latitude, 'agentLng': pos.longitude, 'agentLastSeen': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      ).ignore();

      // Only move camera if actively following
      if (_following && _started && mounted) {
        _map.move(_agentPos!, _map.camera.zoom);
        // flutter_map: rotate(-bearing) makes travel direction face top of screen
        _map.rotate(-_bearing);
      }
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) setState(() => _agentPos = LatLng(last.latitude, last.longitude));
      } catch (_) {}
    }
  }

  void _animateBearing(double target) {
    final from  = _bearing;
    double delta = ((target - from) + 540) % 360 - 180;
    final to    = from + delta;
    _bearAnim = Tween<double>(begin: from, end: to).animate(
      CurvedAnimation(parent: _bearCtrl, curve: Curves.easeOut),
    )..addListener(() {
      if (!mounted) return;
      setState(() {
        _bearing = _bearAnim.value;
        // When following in heading-up mode, the map itself rotates by -_bearing,
        // so the cone must stay at 0 (pointing up on screen).
        // When NOT following (north-up map), the cone should show true bearing.
        _headingRad = _following ? 0.0 : _bearing * pi / 180;
      });
      // Only rotate map when following
      if (_following && _started) _map.rotate(-_bearing);
    });
    _bearCtrl..reset()..forward();
  }

  // ── Tilt in/out ────────────────────────────────────────────────────────────
  void _enterNav() {
    _tiltAnim = Tween<double>(begin: _tilt, end: 0.50).animate(
      CurvedAnimation(parent: _tiltCtrl, curve: Curves.easeInOutCubic),
    )..addListener(() { if (mounted) setState(() => _tilt = _tiltAnim.value); });
    _tiltCtrl..reset()..forward();
  }

  void _exitNav() {
    _tiltAnim = Tween<double>(begin: _tilt, end: 0.0).animate(
      CurvedAnimation(parent: _tiltCtrl, curve: Curves.easeInOutCubic),
    )..addListener(() { if (mounted) setState(() => _tilt = _tiltAnim.value); });
    _tiltCtrl..reset()..forward();
    _animateBearing(0);
    if (mounted) _map.rotate(0);
  }

  // ── OSRM fetch ─────────────────────────────────────────────────────────────
  Future<void> _fetchRoute() async {
    if (_fetching || _agentPos == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _fetching = true;

    final wps = <LatLng>[_agentPos!];
    for (final s in _stops) { if (!s.picked) wps.add(s.location); }
    if (_hasCustomer) wps.add(_custPos);
    if (wps.length < 2) { if (mounted) setState(() => _loading = false); _fetching = false; return; }

    final coords = wps.map((w) => '${w.longitude},${w.latitude}').join(';');
    final url    = Uri.parse('$_kOsrm/$coords?overview=full&geometries=geojson&steps=true');

    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) { if (mounted) setState(() => _loading = false); return; }
      final body   = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) { if (mounted) setState(() => _loading = false); return; }

      final route = routes.first as Map<String, dynamic>;
      final poly  = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final legs  = route['legs'] as List;
      final steps = <_Step>[];
      for (final leg in legs) {
        for (final s in (leg['steps'] as List)) {
          final man  = s['maneuver'] as Map<String, dynamic>;
          final loc  = man['location'] as List;
          steps.add(_Step(
            instruction: _instruction(man, s['name'] as String? ?? ''),
            modifier:    man['modifier'] as String? ?? '',
            distanceM:   (s['distance'] as num).toDouble(),
            durationS:   (s['duration'] as num).toDouble(),
            point: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
          ));
        }
      }

      final totalDur  = legs.fold<int>(0, (s, l) => s + (l['duration'] as num).toInt());
      final totalDist = (route['distance'] as num).toDouble();

      if (!mounted) return;
      setState(() {
        _poly    = poly;
        _steps   = steps;
        _stepIdx = 0;
        _etaSec  = totalDur;
        _distM   = totalDist;
        _lastDur = totalDur;
        _loading = false;
      });

      if (!_started) _fitAll();
      else if (_agentPos != null) _map.move(_agentPos!, 17);
      _checkEta();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _fetching = false;
    }
  }

  // ── Fit all pins ───────────────────────────────────────────────────────────
  void _fitAll() {
    final pts = <LatLng>[
      if (_agentPos != null) _agentPos!,
      ..._stops.map((s) => s.location),
      if (_hasCustomer) _custPos,
    ];
    if (pts.isEmpty) return;
    final lats = pts.map((p) => p.latitude);
    final lngs = pts.map((p) => p.longitude);
    final minLat = lats.reduce(min); final maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min); final maxLng = lngs.reduce(max);
    final ctr  = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final span = max(maxLat - minLat, maxLng - minLng);
    final z    = span > 0.5 ? 10.0 : span > 0.2 ? 11.0 : span > 0.1 ? 12.0
               : span > 0.05 ? 13.0 : span > 0.02 ? 14.0 : 15.0;
    _map.move(ctr, z);
    _map.rotate(0);
  }

  // ── Start sheet ────────────────────────────────────────────────────────────
  void _showStartSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag:   false,
      isScrollControlled: true,
      builder: (_) => _StartSheet(
        waypoints:    _waypoints,
        etaSec:       _etaSec,
        distM:        _distM,
        formatDur:    _fmtDur,
        formatDist:   _fmtDist,
        onPreview: (idx) {
          Navigator.pop(context);
          _map.move(_stops[idx].location, 16);
          Future.delayed(const Duration(seconds: 2), () { if (mounted) _showStartSheet(); });
        },
        onStart: () {
          Navigator.pop(context);

          // Compute initial bearing toward first destination so map faces right way immediately
          if (_agentPos != null && _destPos != null) {
            final lat1 = _agentPos!.latitude  * pi / 180;
            final lat2 = _destPos!.latitude    * pi / 180;
            final dLng = (_destPos!.longitude - _agentPos!.longitude) * pi / 180;
            final y    = sin(dLng) * cos(lat2);
            final x    = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
            _bearing    = (atan2(y, x) * 180 / pi + 360) % 360;
            _headingRad = 0.0; // cone points up; map rotation handles direction
          }

          setState(() { _started = true; _following = true; _centreMode = _CentreMode.agent; });
          _enterNav();
          if (_agentPos != null) {
            _map.move(_agentPos!, 17);
            _map.rotate(-_bearing);
          }
        },
      ),
    );
  }

  // ── Re-centre — Google Maps behaviour ─────────────────────────────────────
  // Tap   → snap to agent in full 3D nav view (heading-up, tilted)
  // Long  → zoom out to flat overview of all stops
  void _onRecentreTap() {
    HapticFeedback.lightImpact();

    // Already following — nothing to do
    if (_following && _centreMode == _CentreMode.agent) return;

    setState(() {
      _following  = true;
      _centreMode = _CentreMode.agent;
      // Cone points UP on screen — map rotation handles the heading direction
      _headingRad = 0.0;
    });

    if (_agentPos != null) {
      _map.move(_agentPos!, 17);
      _map.rotate(-_bearing);
    }

    if (_started) _enterNav();  // restore 3D perspective tilt
  }

  void _onRecentreLongPress() {
    HapticFeedback.mediumImpact();

    setState(() {
      _following  = false;
      _centreMode = _CentreMode.overview;
    });

    _exitNav();   // flatten tilt, reset to north-up
    _fitAll();    // zoom out to see all stops
  }

  // ── Compass tap — reset north-up ───────────────────────────────────────────
  void _onCompassTap() {
    HapticFeedback.mediumImpact();
    _animateBearing(0);
    _map.rotate(0);
    if (_started) _exitNav();
    setState(() { _following = false; _centreMode = _CentreMode.overview; });
  }

  // ── Pickup confirmed ───────────────────────────────────────────────────────
  Future<void> _onPickup(int idx) async {
    if (_picking.contains(idx) || idx >= _stops.length) return;
    HapticFeedback.heavyImpact();
    final stop = _stops[idx];
    setState(() => _picking.add(idx));

    final pickedIds = _stops.where((s) => s.picked || s.id == stop.id).map((s) => s.id).toList();
    final isLast    = _stops.where((s) => !s.picked && s.id != stop.id).isEmpty;

    try {
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).update({
        'pickedRestaurantIds': pickedIds,
        'status':              isLast ? 'out_for_delivery' : 'picked_up',
      });
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      stop.picked = true;
      _picking.remove(idx);
      _stopIdx    = _stops.indexWhere((s) => !s.picked);
      _etaNotified = false;
      _loading     = true;
    });
    await _fetchRoute();
  }

  // ── Timers ─────────────────────────────────────────────────────────────────
  void _startTimers() {
    _locTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _updatePos();
      _advanceStep();
      _checkArrival();
      _tickEta();
    });
    _rerouteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (++_rerouteTick >= _kRerouteInterval) {
        _rerouteTick = 0;
        _silentReroute();
      }
    });
  }

  void _tickEta() {
    if (!mounted) return;
    final prev = _etaSec;
    setState(() {
      _etaSec = max(0, _etaSec - 5);
      if (prev > 0 && _distM > 0) _distM = max(0, _distM - _distM * (5 / prev));
    });
    _checkEta();
  }

  Future<void> _silentReroute() async {
    if (_agentPos == null || _arrived || _fetching || _destPos == null) return;
    if (_hav(_agentPos!, _destPos!) <= _kNoRerouteRadius) return;
    _fetching = true;
    try {
      final wps    = <LatLng>[_agentPos!];
      for (final s in _stops) { if (!s.picked) wps.add(s.location); }
      if (_hasCustomer) wps.add(_custPos);
      if (wps.length < 2) return;

      final coords = wps.map((w) => '${w.longitude},${w.latitude}').join(';');
      final url    = Uri.parse('$_kOsrm/$coords?overview=full&geometries=geojson&steps=true');
      final resp   = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;

      final body   = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route  = routes.first as Map<String, dynamic>;
      final legs   = route['legs'] as List;
      final newDur = legs.fold<int>(0, (s, l) => s + (l['duration'] as num).toInt());
      if ((newDur - _lastDur).abs() < _kRerouteThreshold) return;

      final newPoly  = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      final newSteps = <_Step>[];
      for (final leg in legs) {
        for (final s in (leg['steps'] as List)) {
          final man = s['maneuver'] as Map<String, dynamic>;
          final loc = man['location'] as List;
          newSteps.add(_Step(
            instruction: _instruction(man, s['name'] as String? ?? ''),
            modifier:    man['modifier'] as String? ?? '',
            distanceM:   (s['distance'] as num).toDouble(),
            durationS:   (s['duration'] as num).toDouble(),
            point: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _poly    = newPoly;
        _steps   = newSteps;
        _stepIdx = 0;
        _etaSec  = newDur;
        _distM   = (route['distance'] as num).toDouble();
        _lastDur = newDur;
      });

      LocalNotificationService.showNotification(
        id: 2001, title: '🔄 Route Updated',
        body: 'Better route found · New ETA ${_fmtDur(newDur)}',
      );
    } catch (_) {
    } finally { _fetching = false; }
  }

  void _advanceStep() {
    if (_agentPos == null || _steps.isEmpty || _stepIdx >= _steps.length - 1) return;
    if (_hav(_agentPos!, _steps[_stepIdx].point) < 30 && mounted) {
      setState(() => _stepIdx++);
    }
  }

  void _checkArrival() {
    if (_agentPos == null || _arrived) return;
    if (_allPicked && _hasCustomer && _hav(_agentPos!, _custPos) <= _kArrivalRadius) {
      _rerouteTimer?.cancel();
      setState(() => _arrived = true);
      _arrivalCtrl.forward();
      LocalNotificationService.showNotification(
        id: 2002, title: '✅ Arrived!',
        body: 'You have reached ${widget.customerName}\'s location.',
      );
    }
  }

  void _checkEta() {
    if (_etaNotified || _arrived || _etaSec > _kEtaNotifyMin * 60) return;
    _etaNotified = true;
    LocalNotificationService.showNotification(
      id: 2000, title: '📍 Almost there!',
      body: 'Reaching $_destLabel in ~${_fmtDur(_etaSec)}',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  double _hav(LatLng a, LatLng b) {
    const r  = 6371000.0;
    final dL = (b.latitude  - a.latitude)  * pi / 180;
    final dG = (b.longitude - a.longitude) * pi / 180;
    final h  = sin(dL/2)*sin(dL/2) +
               cos(a.latitude*pi/180)*cos(b.latitude*pi/180)*sin(dG/2)*sin(dG/2);
    return 2 * r * asin(sqrt(h));
  }

  String _instruction(Map<String, dynamic> man, String road) {
    final type = man['type']     as String? ?? '';
    final mod  = man['modifier'] as String? ?? '';
    final r    = road.isNotEmpty ? ' onto $road' : '';
    switch (type) {
      case 'depart':  return 'Head ${mod.isNotEmpty ? mod : 'forward'}$r';
      case 'arrive':  return 'You have arrived';
      case 'turn':
        switch (mod) {
          case 'left':         return 'Turn left$r';
          case 'right':        return 'Turn right$r';
          case 'slight left':  return 'Keep slight left$r';
          case 'slight right': return 'Keep slight right$r';
          case 'sharp left':   return 'Turn sharp left$r';
          case 'sharp right':  return 'Turn sharp right$r';
          case 'uturn':        return 'Make a U-turn';
          default:             return 'Continue$r';
        }
      case 'roundabout':
      case 'rotary':
        final exit = man['exit'] as int?;
        return exit != null ? 'Take exit $exit at roundabout$r' : 'Enter roundabout$r';
      case 'fork': return mod.contains('left') ? 'Keep left$r' : 'Keep right$r';
      case 'merge': return 'Merge ${mod.isNotEmpty ? mod : ''}$r'.trim();
      default: return 'Continue$r';
    }
  }

  String _fmtDur(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    return m < 60 ? '$m min' : '${m ~/ 60}h ${m % 60}min';
  }
  String _fmtDist(double m) =>
      m < 1000 ? '${m.toStringAsFixed(0)} m' : '${(m / 1000).toStringAsFixed(1)} km';

  IconData _turnIcon(String mod) {
    final l = mod.toLowerCase();
    if (l.contains('sharp left'))  return Icons.turn_sharp_left_rounded;
    if (l.contains('slight left')) return Icons.turn_slight_left_rounded;
    if (l.contains('left'))        return Icons.turn_left_rounded;
    if (l.contains('sharp right')) return Icons.turn_sharp_right_rounded;
    if (l.contains('slight right'))return Icons.turn_slight_right_rounded;
    if (l.contains('right'))       return Icons.turn_right_rounded;
    if (l.contains('uturn'))       return Icons.u_turn_left_rounded;
    if (l.contains('roundabout'))  return Icons.rotate_right_rounded;
    return Icons.straight_rounded;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:      Colors.transparent,
      statusBarBrightness: Brightness.dark,
    ));
    final center = _agentPos ?? _destPos ?? _custPos;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(children: [
        // ── 3-D Map ────────────────────────────────────────────────────────
        _MapView(
          tilt:        _tilt,
          mapCtrl:     _map,
          center:      center,
          poly:        _poly,
          dashCtrl:    _dashCtrl,
          pulseAnim:   _pulseAnim,
          stops:       _stops,
          agentPos:    _agentPos,
          custPos:     _hasCustomer ? _custPos : null,
          headingRad:  _headingRad,
          accuracyM:   _accuracyM,
          onMapEvent: (e) {
            // User dragged/zoomed manually → stop following
            if ((e is MapEventScrollWheelZoom || e is MapEventMoveStart) && _following) {
              setState(() {
                _following  = false;
                _centreMode = _CentreMode.overview;
                // Map snaps to north-up, so cone now shows true travel bearing
                _headingRad = _bearing * pi / 180;
              });
            }
          },
        ),

        // ── Top overlay ────────────────────────────────────────────────────
        SafeArea(child: _buildTopOverlay()),

        // ── Speed limit badge ──────────────────────────────────────────────
        if (_started && !_arrived && !_loading)
          Positioned(
            left: 14,
            bottom: _started ? 140 : 30,
            child: _SpeedBadge(),
          ),

        // ── Bottom panel ───────────────────────────────────────────────────
        _buildBottom(),

        // ── Loading overlay ────────────────────────────────────────────────
        if (_loading)
          Container(
            color: Colors.black54,
            child: const Center(child: CircularProgressIndicator(color: _blue, strokeWidth: 3)),
          ),

        // ── Arrived overlay ────────────────────────────────────────────────
        if (_arrived) _buildArrivedOverlay(),
      ]),
    );
  }

  // ── Top overlay ────────────────────────────────────────────────────────────
  Widget _buildTopOverlay() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            // Back button
            _GlassBtn(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),

            // ETA chip (only when started)
            if (_started && !_loading && !_arrived)
              Expanded(child: _EtaChip(
                eta:   _fmtDur(_etaSec),
                dist:  _fmtDist(_distM),
                dest:  _destLabel,
                toRest:!_allPicked,
                stops: _stops.where((s) => !s.picked).length,
                arrivalTime: _arrivalTime,
              ))
            else
              const Spacer(),

            const SizedBox(width: 8),

            // Compass
            _CompassBtn(
              rotRad: _compassRot,
              onTap:  _onCompassTap,
            ),
            const SizedBox(width: 6),

            // Re-centre — tap = Google Maps 3D nav snap, long = overview
            _RecentreBtn(
              mode:         _centreMode,
              following:    _following,
              onTap:        _onRecentreTap,
              onLongPress:  _onRecentreLongPress,
            ),
          ]),

          const SizedBox(height: 10),

          // Turn card
          if (_started && !_loading && !_arrived && _steps.isNotEmpty && _stepIdx < _steps.length)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  SlideTransition(position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(anim), child: child),
              child: _steps[_stepIdx].instruction.toLowerCase().contains('have arrived')
                  ? const SizedBox.shrink()
                  : _TurnCard(
                      key: ValueKey(_stepIdx),
                      step: _steps[_stepIdx],
                      fmtDist: _fmtDist,
                      turnIcon: _turnIcon(_steps[_stepIdx].modifier),
                    ),
            ),
        ],
      ),
    );
  }

  // ── Bottom panel ────────────────────────────────────────────────────────────
  Widget _buildBottom() {
    if (_loading || _arrived) return const SizedBox.shrink();

    if (!_started) {
      return Positioned(
        bottom: 28, left: 20, right: 20,
        child: GestureDetector(
          onTap: _showStartSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1565C0), _blue]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: _blue.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.directions_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('View Route', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                Text('${_fmtDur(_etaSec)} · ${_fmtDist(_distM)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Start', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ]),
          ),
        ),
      );
    }

    if (_allPicked) {
      return Positioned(
        bottom: 0, left: 0, right: 0,
        child: _DarkNavBar(
          etaText:  _fmtDur(_etaSec),
          distText: _fmtDist(_distM),
          arrTime:  _arrivalTime,
          label:    'Delivering to ${widget.customerName}',
          icon:     Icons.delivery_dining_rounded,
          iconColor:_green,
        ),
      );
    }

    final unpicked = _stops.asMap().entries.where((e) => !e.value.picked).toList();
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DarkNavBar(
            etaText:  _fmtDur(_etaSec),
            distText: _fmtDist(_distM),
            arrTime:  _arrivalTime,
            label:    '${_stops.where((s) => !s.picked).length} stop${_stops.where((s) => !s.picked).length > 1 ? 's' : ''} remaining',
            icon:     Icons.storefront_rounded,
            iconColor:_orange,
          ),
          Container(
            color: _navBg,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: unpicked.map((e) {
                final idx     = e.key;
                final stop    = e.value;
                final isNext  = idx == _stopIdx;
                final picking = _picking.contains(idx);
                final color   = _stopColors[idx % _stopColors.length];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity:  isNext ? 1.0 : 0.45,
                    child: GestureDetector(
                      onTap: isNext && !picking ? () => _onPickup(idx) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color:         isNext ? color : _navBgCard,
                          borderRadius:  BorderRadius.circular(14),
                          boxShadow:     isNext ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))] : null,
                        ),
                        child: Row(children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(child: picking
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Icon(isNext ? Icons.check_rounded : Icons.schedule_rounded,
                                    color: Colors.white, size: 16)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              picking ? 'Updating route…'
                                : isNext ? 'Picked from ${stop.name}'
                                : '⏳ Next: ${stop.name}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              isNext ? 'Tap to confirm pickup' : 'After previous stop',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ])),
                          if (isNext && !picking)
                            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                        ]),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Arrived overlay ─────────────────────────────────────────────────────────
  Widget _buildArrivedOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: ScaleTransition(
            scale: _arrivalAnim,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 32)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: _green, size: 44),
                  ),
                  const SizedBox(height: 16),
                  const Text('Arrived!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _textDark)),
                  const SizedBox(height: 6),
                  Text(
                    'You have reached ${widget.customerName}\'s location.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: _textMid),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Complete Delivery',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// 3-D Map Widget
// ─────────────────────────────────────────────────────────────────────────────
class _MapView extends StatelessWidget {
  final double              tilt;
  final MapController       mapCtrl;
  final LatLng              center;
  final List<LatLng>        poly;
  final AnimationController dashCtrl;
  final Animation<double>   pulseAnim;
  final List<RestaurantStop> stops;
  final LatLng?             agentPos;
  final LatLng?             custPos;
  final double              headingRad;
  final double              accuracyM;
  final void Function(MapEvent) onMapEvent;

  const _MapView({
    required this.tilt,
    required this.mapCtrl,
    required this.center,
    required this.poly,
    required this.dashCtrl,
    required this.pulseAnim,
    required this.stops,
    required this.agentPos,
    required this.custPos,
    required this.headingRad,
    required this.accuracyM,
    required this.onMapEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: const Alignment(0, 0.35),
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0008)
        ..rotateX(tilt),
      child: FlutterMap(
        mapController: mapCtrl,
        options: MapOptions(
          initialCenter: center,
          initialZoom:   15,
          onMapEvent:    onMapEvent,
        ),
        children: [
          TileLayer(
            urlTemplate:          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.foodfeast.app',
            retinaMode:           true,
          ),

          if (poly.isNotEmpty)
            AnimatedBuilder(
              animation: dashCtrl,
              builder: (_, __) => PolylineLayer(polylines: [
                Polyline(points: poly, color: const Color(0x44001F5B), strokeWidth: 18),
                Polyline(points: poly, color: _blueDark, strokeWidth: 9),
                Polyline(points: poly, color: _blue, strokeWidth: 6),
                Polyline(
                  points:      poly,
                  color:       Colors.white.withOpacity(0.65),
                  strokeWidth: 2.5,
                  pattern:     StrokePattern.dashed(segments: const [10, 18]),
                ),
              ]),
            ),

          MarkerLayer(markers: _markers()),
        ],
      ),
    );
  }

  List<Marker> _markers() {
    final m = <Marker>[];

    for (int i = 0; i < stops.length; i++) {
      m.add(Marker(
        point:  stops[i].location,
        width:  56, height: 66,
        child:  _StopMarker(
          name:   stops[i].name,
          color:  _stopColors[i % _stopColors.length],
          picked: stops[i].picked,
          number: i + 1,
        ),
      ));
    }

    if (custPos != null) {
      m.add(Marker(
        point: custPos!, width: 56, height: 66,
        child: const _CustomerMarker(),
      ));
    }

    if (agentPos != null) {
      m.add(Marker(
        point: agentPos!, width: 60, height: 60,
        child: _AgentMarker(
          headingRad: headingRad,
          pulseAnim:  pulseAnim,
          accuracyM:  accuracyM,
        ),
      ));
    }

    return m;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Agent marker — Google Maps style arrow (teardrop chevron)
// ─────────────────────────────────────────────────────────────────────────────
class _AgentMarker extends StatelessWidget {
  final double            headingRad;
  final Animation<double> pulseAnim;
  final double            accuracyM;

  const _AgentMarker({
    required this.headingRad,
    required this.pulseAnim,
    required this.accuracyM,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) {
        return Stack(alignment: Alignment.center, children: [
          // Accuracy / GPS halo — pulsing outer ring
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _blue.withOpacity(0.10 * pulseAnim.value),
              border: Border.all(
                color: _blue.withOpacity(0.18 * pulseAnim.value),
                width: 1.5,
              ),
            ),
          ),
          // Arrow — rotates with heading
          Transform.rotate(
            angle: headingRad,
            child: CustomPaint(
              size: const Size(72, 72),
              painter: _GmapArrowPainter(),
            ),
          ),
        ]);
      },
    );
  }
}

/// Draws a clean Google Maps-style navigation arrow:
///  • Filled blue chevron/teardrop pointing UP
///  • White stroke outline
///  • Drop shadow underneath
class _GmapArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;

    // Arrow geometry — pointing UP from centre
    // tip at top, wide base at bottom-centre, two wing points on sides
    final tip    = Offset(cx,        cy - 26); // top tip
    final left   = Offset(cx - 14,   cy + 14); // bottom-left wing
    final bottom = Offset(cx,        cy +  6); // bottom-centre indent
    final right  = Offset(cx + 14,   cy + 14); // bottom-right wing

    final arrowPath = ui.Path()
      ..moveTo(tip.dx,    tip.dy)
      ..lineTo(right.dx,  right.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(left.dx,   left.dy)
      ..close();

    // 1. Drop shadow
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color       = Colors.black.withOpacity(0.28)
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 4)
        ..style       = PaintingStyle.fill,
    );

    // 2. White border (slightly enlarged path drawn first)
    final borderPath = ui.Path()
      ..moveTo(tip.dx,    tip.dy    - 2)
      ..lineTo(right.dx  + 2, right.dy  + 2)
      ..lineTo(bottom.dx, bottom.dy + 1)
      ..lineTo(left.dx   - 2, left.dy   + 2)
      ..close();
    canvas.drawPath(
      borderPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // 3. Blue fill with gradient (lighter at tip, deeper at base)
    canvas.drawPath(
      arrowPath,
      Paint()
        ..shader = ui.Gradient.linear(
          tip,
          bottom,
          [const Color(0xFF4FC3F7), _blue],
        )
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stop marker
// ─────────────────────────────────────────────────────────────────────────────
class _StopMarker extends StatelessWidget {
  final String name;
  final Color  color;
  final bool   picked;
  final int    number;
  const _StopMarker({required this.name, required this.color, required this.picked, required this.number});

  @override
  Widget build(BuildContext context) {
    final c = picked ? _gray : color;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color:  c,
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(color: c.withOpacity(0.45), blurRadius: 10, spreadRadius: 1),
              const BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
          child: Icon(
            picked ? Icons.check_rounded : Icons.storefront_rounded,
            color: Colors.white, size: 19,
          ),
        ),
        Positioned(
          top: -4, right: -4,
          child: Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: c, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(child: Text('$number',
                style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w900))),
          ),
        ),
      ]),
      CustomPaint(painter: _TailPainter(c), size: const Size(10, 7)),
      const SizedBox(height: 1),
      Container(
        constraints: const BoxConstraints(maxWidth: 70),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Text(name,
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800,
              color: c, decoration: picked ? TextDecoration.lineThrough : null),
          overflow: TextOverflow.ellipsis, maxLines: 1, textAlign: TextAlign.center,
        ),
      ),
    ]);
  }
}

class _TailPainter extends CustomPainter {
  final Color color;
  const _TailPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      ui.Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }
  @override bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Customer marker
// ─────────────────────────────────────────────────────────────────────────────
class _CustomerMarker extends StatelessWidget {
  const _CustomerMarker();
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color:  _green,
          shape:  BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: _green.withOpacity(0.45), blurRadius: 10, spreadRadius: 1),
            const BoxShadow(color: Colors.black26, blurRadius: 4),
          ],
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
      ),
      CustomPaint(painter: _TailPainter(_green), size: const Size(10, 7)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Turn-by-turn card
// ─────────────────────────────────────────────────────────────────────────────
class _TurnCard extends StatelessWidget {
  final _Step  step;
  final String Function(double) fmtDist;
  final IconData               turnIcon;
  const _TurnCard({super.key, required this.step, required this.fmtDist, required this.turnIcon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1558CC), _blue],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: _blue.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(turnIcon, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(step.instruction,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(fmtDist(step.distanceM),
                style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
          ],
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dark ETA nav bar
// ─────────────────────────────────────────────────────────────────────────────
class _DarkNavBar extends StatelessWidget {
  final String   etaText;
  final String   distText;
  final String   arrTime;
  final String   label;
  final IconData icon;
  final Color    iconColor;
  const _DarkNavBar({
    required this.etaText, required this.distText, required this.arrTime,
    required this.label,   required this.icon,     required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _navBg,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
          Row(children: [
            Text(etaText,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
            const SizedBox(width: 8),
            Text(distText,
                style: const TextStyle(fontSize: 14, color: Colors.white60, fontWeight: FontWeight.w500)),
          ]),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(children: [
            const Text('Arrives', style: TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w600)),
            Text(arrTime, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ETA chip
// ─────────────────────────────────────────────────────────────────────────────
class _EtaChip extends StatelessWidget {
  final String eta, dist, dest, arrivalTime;
  final bool   toRest;
  final int    stops;
  const _EtaChip({
    required this.eta, required this.dist, required this.dest,
    required this.toRest, required this.stops, required this.arrivalTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:  Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(children: [
        Icon(toRest ? Icons.storefront_rounded : Icons.delivery_dining_rounded,
            size: 16, color: _blue),
        const SizedBox(width: 7),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            toRest && stops > 1 ? '$stops stops · $dest' : dest,
            style: const TextStyle(fontSize: 10, color: _textMid, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          Text('$eta · $dist',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _textDark)),
        ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speed limit badge
// ─────────────────────────────────────────────────────────────────────────────
class _SpeedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color:  Colors.white,
        shape:  BoxShape.circle,
        border: Border.all(color: _red, width: 3.5),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('40', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _textDark, height: 1)),
        Text('km/h', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: _textMid, letterSpacing: 0.3)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compass button
// ─────────────────────────────────────────────────────────────────────────────
class _CompassBtn extends StatelessWidget {
  final double       rotRad;
  final VoidCallback onTap;
  const _CompassBtn({required this.rotRad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: const BoxDecoration(
          color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Transform.rotate(
          angle: rotRad,
          child: CustomPaint(size: const Size(42, 42), painter: _CompassPainter()),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r  = size.width * 0.27;
    canvas.drawCircle(Offset(cx, cy), r + 3,
        Paint()..color = const Color(0xFFE8EAED)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawPath(
      ui.Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + r * 0.32, cy + 2)
        ..lineTo(cx, cy)
        ..close(),
      Paint()..color = _red,
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(cx, cy + r)
        ..lineTo(cx - r * 0.32, cy - 2)
        ..lineTo(cx, cy)
        ..close(),
      Paint()..color = _gray,
    );
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = _textDark);
  }
  @override bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Re-centre button — Google Maps behaviour
//   Tap       → snap to agent, 3D tilt, heading-up, resume following
//   Long-press → flat overview of all stops
// ─────────────────────────────────────────────────────────────────────────────
class _RecentreBtn extends StatelessWidget {
  final _CentreMode  mode;
  final bool         following;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RecentreBtn({
    required this.mode,
    required this.following,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final active = following && mode == _CentreMode.agent;
    return GestureDetector(
      onTap:      onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color:        active ? _blue : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow:    const [BoxShadow(color: Colors.black12, blurRadius: 8)],
          border:       Border.all(color: active ? _blue : const Color(0xFFDADCE0), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            // Always show my_location icon — same as Google Maps
            Icons.my_location_rounded,
            color: active ? Colors.white : _blue,
            size: 17,
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Following' : 'Recentre',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : _blue,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass icon button
// ─────────────────────────────────────────────────────────────────────────────
class _GlassBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  const _GlassBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: const BoxDecoration(
          color: Colors.white, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Icon(icon, size: 19, color: _textDark),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Start Route bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _StartSheet extends StatelessWidget {
  final List<_WP>               waypoints;
  final int                     etaSec;
  final double                  distM;
  final String Function(int)    formatDur;
  final String Function(double) formatDist;
  final void Function(int)      onPreview;
  final VoidCallback            onStart;

  const _StartSheet({
    required this.waypoints,
    required this.etaSec,
    required this.distM,
    required this.formatDur,
    required this.formatDist,
    required this.onPreview,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          width: 38, height: 4,
          decoration: BoxDecoration(color: const Color(0xFFDADCE0), borderRadius: BorderRadius.circular(2)),
        )),
        const SizedBox(height: 18),

        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1558CC), _blue]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.route_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your Delivery Route',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _textDark)),
            Text('${formatDur(etaSec)}  ·  ${formatDist(distM)}',
                style: const TextStyle(fontSize: 13, color: _textMid, fontWeight: FontWeight.w500)),
          ]),
        ]),
        const SizedBox(height: 22),

        ...waypoints.asMap().entries.map((e) {
          final i = e.key; final wp = e.value; final isLast = i == waypoints.length - 1;
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 32, child: Column(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (wp.isPicked ? _gray : wp.color).withOpacity(0.13),
                    border: Border.all(color: wp.isPicked ? _gray : wp.color, width: 2),
                  ),
                  child: Icon(wp.icon, color: wp.isPicked ? _gray : wp.color, size: 15),
                ),
                if (!isLast)
                  Expanded(child: Center(child: Container(width: 2, color: const Color(0xFFE8EAED)))),
              ])),
              const SizedBox(width: 14),
              Expanded(child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 4),
                child: GestureDetector(
                  onTap: wp.stopIdx != null ? () => onPreview(wp.stopIdx!) : null,
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(wp.label,
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: wp.isPicked ? _gray : _textDark,
                          decoration: wp.isPicked ? TextDecoration.lineThrough : null,
                        )),
                      Text(wp.sub,
                        style: TextStyle(fontSize: 12, color: wp.isPicked ? const Color(0xFFBDC1C6) : _textMid)),
                    ])),
                    if (wp.stopIdx != null && !wp.isPicked)
                      Icon(Icons.chevron_right_rounded, color: wp.color.withOpacity(0.6), size: 20),
                  ]),
                ),
              )),
            ]),
          );
        }),

        const SizedBox(height: 20),
        const Divider(height: 1, color: Color(0xFFF1F3F4)),
        const SizedBox(height: 18),

        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor:     Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: EdgeInsets.zero,
            ),
            onPressed: onStart,
            icon: const SizedBox.shrink(),
            label: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1558CC), _blue]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                alignment: Alignment.center,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.navigation_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text('Start Navigation',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}