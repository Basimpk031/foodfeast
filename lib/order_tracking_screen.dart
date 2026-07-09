// order_tracking_screen.dart — FoodFeast
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'local_notification_service.dart';

const _kOsrmBase = 'https://router.project-osrm.org/route/v1/driving';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  static const _primary = Color(0xFF0077B6);
  static const _dark    = Color(0xFF1A1A2E);
  static const _green   = Color(0xFF34C759);
  static const _orange  = Color(0xFFFF9500);
  static const _red     = Color(0xFFFF3B30);
  static const _grey    = Color(0xFF6E6E73);
  static const _bg      = Color(0xFFF2F2F7);

  StreamSubscription<DocumentSnapshot>? _orderSub;
  Map<String, dynamic> _order = {};
  bool _loading = true;

  final _mapCtrl = MapController();
  List<LatLng> _polyline = [];
  int  _etaSeconds = 0;
  bool _fetchingRoute = false;
  bool _routeViaRestaurant = false;

  LatLng? _lastAgentPos;
  String  _prevStatus = '';   // tracks last status for local notification dedup

  @override
  void initState() {
    super.initState();
    _subscribeOrder();
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    super.dispose();
  }

  void _subscribeOrder() {
    _orderSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;

      final oldStatus = _order['status'] as String? ?? '';
      final newStatus = data['status']  as String? ?? '';
      final statusChanged = newStatus != oldStatus && newStatus.isNotEmpty;

      // Show a local heads-up notification whenever status advances
      // (covers foreground state — FCM push handles background).
      if (statusChanged && newStatus != _prevStatus) {
        _prevStatus = newStatus;
        _fireLocalStatusNotification(newStatus);
      }

      setState(() {
        _order   = data;
        _loading = false;
      });

      final agentLat = (data['agentLat'] as num?)?.toDouble();
      final agentLng = (data['agentLng'] as num?)?.toDouble();
      final restLat  = (data['restaurantLat'] as num?)?.toDouble() ?? 0.0;
      final restLng  = (data['restaurantLng'] as num?)?.toDouble() ?? 0.0;

      final hasRealAgent = agentLat != null && agentLng != null &&
          agentLat != 0.0 && agentLng != 0.0;

      if (hasRealAgent) {
        final pos = LatLng(agentLat!, agentLng!);
        final movedEnough = _lastAgentPos == null ||
            _haversine(_lastAgentPos!, pos) > 50; // >50 m
        if ((movedEnough || statusChanged) && !_fetchingRoute) {
          _lastAgentPos = pos;
          _fetchRoute(agentPos: pos);
        }
      } else if (!_fetchingRoute && (statusChanged || _polyline.isEmpty)) {
        // No agent GPS yet — use restaurant pin as route start so customer
        // always sees at least the restaurant→home blue line on screen open.
        final fallback = _lastAgentPos ??
            (restLat != 0.0 || restLng != 0.0
                ? LatLng(restLat, restLng)
                : null);
        if (fallback != null) _fetchRoute(agentPos: fallback);
      }
    });
  }

  // ── Resolve restaurants list (multi or single legacy) ─────────────────────
  List<Map<String, dynamic>> _resolveRestaurants() {
    final raw = _order['restaurants'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    }
    final restLat = (_order['restaurantLat'] as num?)?.toDouble() ?? 0.0;
    final restLng = (_order['restaurantLng'] as num?)?.toDouble() ?? 0.0;
    if (restLat == 0.0 && restLng == 0.0) return [];
    return [
      {
        'id':   'rest_0',
        'name': _order['restaurantName'] ?? 'Restaurant',
        'lat':  restLat,
        'lng':  restLng,
      }
    ];
  }

  Future<void> _fetchRoute({required LatLng agentPos}) async {
    final status  = _order['status'] as String? ?? '';
    final custLat = (_order['customerLat'] as num?)?.toDouble() ?? 0.0;
    final custLng = (_order['customerLng'] as num?)?.toDouble() ?? 0.0;

    if (custLat == 0.0 && custLng == 0.0) return;

    final customerPos = LatLng(custLat, custLng);
    final restaurants = _resolveRestaurants();

    // Determine which restaurants still need pickup
    final pickedIds = (_order['pickedRestaurantIds'] as List?)
        ?.map((e) => e.toString())
        .toSet() ?? {};

    final allPicked = status == 'out_for_delivery' ||
        status == 'delivered' ||
        (restaurants.isNotEmpty &&
            restaurants.every((r) =>
                pickedIds.contains(r['id']?.toString() ?? '')));

    setState(() => _fetchingRoute = true);
    try {
      // Build waypoints: agent + unpicked restaurants + customer
      final waypoints = <LatLng>[agentPos];

      if (!allPicked) {
        for (final r in restaurants) {
          final id  = r['id']?.toString() ?? '';
          if (!pickedIds.contains(id)) {
            final lat = (r['lat'] as num?)?.toDouble() ?? 0.0;
            final lng = (r['lng'] as num?)?.toDouble() ?? 0.0;
            if (lat != 0.0 || lng != 0.0) {
              waypoints.add(LatLng(lat, lng));
            }
          }
        }
      }

      waypoints.add(customerPos);

      if (waypoints.length < 2) return;

      final coordStr = waypoints
          .map((w) => '${w.longitude},${w.latitude}')
          .join(';');

      final url = Uri.parse(
        '$_kOsrmBase/$coordStr?overview=full&geometries=geojson',
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200 || !mounted) return;

      final json   = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route  = routes.first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map((c) =>
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      final legs     = route['legs'] as List;
      final totalSec = legs.fold<int>(
          0, (sum, leg) => sum + (leg['duration'] as num).toInt());

      if (!mounted) return;
      setState(() {
        _polyline           = coords;
        _etaSeconds         = totalSec;
        _routeViaRestaurant = !allPicked && waypoints.length > 2;
      });
    } catch (_) {
      // Non-fatal
    } finally {
      if (mounted) setState(() => _fetchingRoute = false);
    }
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude  - a.latitude)  * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) * cos(b.latitude * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(sqrt(h));
  }

  String _formatEta(int seconds) {
    if (seconds <= 0) return '—';
    if (seconds < 60)  return '$seconds sec';
    final m = seconds ~/ 60;
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    return '${h}h ${m % 60}min';
  }

  int _stepIndex(String status) {
    switch (status) {
      case 'pending':          return 0;
      case 'confirmed':        return 1;
      case 'preparing':        return 1;
      case 'ready_for_pickup': return 2;
      case 'picked_up':        return 2;
      case 'out_for_delivery': return 3;
      case 'delivered':        return 4;
      default:                 return 0;
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'pending':          return '🕐';
      case 'confirmed':        return '✅';
      case 'preparing':        return '👨‍🍳';
      case 'ready_for_pickup': return '🛵';
      case 'picked_up':        return '📦';
      case 'out_for_delivery': return '🚀';
      case 'delivered':        return '🎉';
      case 'cancelled':        return '❌';
      default:                 return '🕐';
    }
  }

  String _statusMessage(String status) {
    switch (status) {
      case 'pending':          return 'Waiting for restaurant to confirm…';
      case 'confirmed':        return 'Your order has been confirmed!';
      case 'preparing':        return 'The restaurant is preparing your food.';
      case 'ready_for_pickup': return 'Ready! Waiting for a delivery agent.';
      case 'picked_up':        return _resolveRestaurants().length > 1
          ? 'Agent is collecting from restaurants.'
          : 'Agent has picked up your order.';
      case 'out_for_delivery': return 'Your order is on the way! 🚴';
      case 'delivered':        return 'Delivered! Enjoy your meal 😋';
      case 'cancelled':        return 'This order was cancelled.';
      default:                 return 'Tracking your order…';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'delivered':        return _green;
      case 'cancelled':        return _red;
      case 'out_for_delivery':
      case 'picked_up':        return _primary;
      default:                 return _orange;
    }
  }

  // ── Local foreground notification for status changes ────────────────────────
  static const _localNotifTitles = {
    'pending':          '🕐 Order Placed',
    'confirmed':        '✅ Order Confirmed',
    'preparing':        '👨‍🍳 Preparing Your Order',
    'ready_for_pickup': '🛵 Ready for Pickup',
    'picked_up':        '📦 Order Picked Up',
    'out_for_delivery': '🚀 Out for Delivery',
    'delivered':        '🎉 Order Delivered!',
    'cancelled':        '❌ Order Cancelled',
  };
  static const _localNotifBodies = {
    'pending':          'Waiting for the restaurant to confirm.',
    'confirmed':        'Your order has been confirmed!',
    'preparing':        'The kitchen is preparing your meal.',
    'ready_for_pickup': 'Ready! Looking for a delivery agent.',
    'picked_up':        'A delivery agent has picked up your order.',
    'out_for_delivery': 'Your order is on its way!',
    'delivered':        'Your order has arrived. Enjoy! 😋',
    'cancelled':        'Your order was cancelled.',
  };

  void _fireLocalStatusNotification(String status) {
    final title = _localNotifTitles[status];
    final body  = _localNotifBodies[status];
    if (title == null || body == null) return;
    LocalNotificationService.showNotification(
      id:    status.hashCode,
      title: title,
      body:  body,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    final status    = _order['status'] as String? ?? 'pending';
    final otp       = _order['deliveryOtp'] as String? ?? '';
    final restaurants = _resolveRestaurants();
    final multiRest = restaurants.length > 1;
    final restName  = multiRest
        ? '${restaurants.length} restaurants'
        : (_order['restaurantName'] as String? ?? 'Restaurant');
    final orderId   = widget.orderId.substring(0, 6).toUpperCase();
    final delivered = status == 'delivered';
    final cancelled = status == 'cancelled';
    final agentActive = status == 'out_for_delivery' || status == 'picked_up';

    final restLat  = (_order['restaurantLat'] as num? ?? 0).toDouble();
    final restLng  = (_order['restaurantLng'] as num? ?? 0).toDouble();
    final custLat  = (_order['customerLat']   as num? ?? 0).toDouble();
    final custLng  = (_order['customerLng']   as num? ?? 0).toDouble();
    final agentLat = (_order['agentLat']      as num? ?? 0).toDouble();
    final agentLng = (_order['agentLng']      as num? ?? 0).toDouble();

    final hasRest  = restLat  != 0.0 || restLng  != 0.0;
    final hasCust  = custLat  != 0.0 || custLng  != 0.0;
    final hasAgent = agentLat != 0.0 || agentLng != 0.0;

    final mapCenter = hasAgent
        ? LatLng(agentLat, agentLng)
        : hasCust
            ? LatLng(custLat, custLng)
            : hasRest
                ? LatLng(restLat, restLng)
                : const LatLng(12.9716, 77.5946);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.42,
          child: Stack(children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(initialCenter: mapCenter, initialZoom: 14),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.foodfeast.app',
                ),

                // ── Blue route polyline — always shown when available ──────
                if (_polyline.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: _polyline,
                      color: _primary,
                      strokeWidth: 4.5,
                    ),
                  ]),

                MarkerLayer(markers: [
                  if (hasAgent && agentActive)
                    Marker(
                      point: LatLng(agentLat, agentLng),
                      width: 48, height: 48,
                      child: _AgentMarker(),
                    ),
                  // Show all restaurant markers
                  ...(() {
                    const pinColors = [
                      Color(0xFFFF9500),
                      Color(0xFFAF52DE),
                      Color(0xFFFF2D55),
                      Color(0xFF5856D6),
                      Color(0xFFFF6B35),
                    ];
                    final rests = _resolveRestaurants();
                    final pickedIds = (_order['pickedRestaurantIds'] as List?)
                        ?.map((e) => e.toString())
                        .toSet() ?? {};
                    return rests.asMap().entries.map((e) {
                      final i   = e.key;
                      final r   = e.value;
                      final lat = (r['lat'] as num?)?.toDouble() ?? 0.0;
                      final lng = (r['lng'] as num?)?.toDouble() ?? 0.0;
                      if (lat == 0.0 && lng == 0.0) return null;
                      final id      = r['id']?.toString() ?? 'rest_$i';
                      final isPicked = pickedIds.contains(id);
                      final color   = pinColors[i % pinColors.length];
                      return Marker(
                        point:  LatLng(lat, lng),
                        width:  36,
                        height: 36,
                        child:  _PinMarker(
                          icon:  isPicked
                              ? Icons.check_circle_rounded
                              : Icons.restaurant_rounded,
                          color: isPicked
                              ? const Color(0xFF8E8E93)
                              : color,
                        ),
                      );
                    }).whereType<Marker>().toList();
                  })(),
                  if (hasCust)
                    Marker(
                      point: LatLng(custLat, custLng),
                      width: 36, height: 36,
                      child: _PinMarker(icon: Icons.home_rounded, color: _green),
                    ),
                ]),
              ],
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  _CircleBtn(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                    ),
                    child: Text('Order #$orderId',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: _dark)),
                  ),
                  const Spacer(),
                  _CircleBtn(
                    icon: Icons.my_location_rounded,
                    onTap: () => _mapCtrl.move(mapCenter, 14),
                  ),
                ]),
              ),
            ),

            if (_etaSeconds > 0)
              Positioned(
                bottom: 12, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _dark,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.delivery_dining_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _routeViaRestaurant
                            ? (multiRest
                                ? 'Picking from ${restaurants.where((r) { final id = r['id']?.toString() ?? ''; final pickedIds = (_order['pickedRestaurantIds'] as List?)?.map((e) => e.toString()).toSet() ?? {}; return !pickedIds.contains(id); }).length} restaurant(s) · ${_formatEta(_etaSeconds)}'
                                : 'Collecting food · ${_formatEta(_etaSeconds)}')
                            : 'Arriving in ${_formatEta(_etaSeconds)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(_statusEmoji(status), style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_statusMessage(status),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(status))),
                      const SizedBox(height: 2),
                      Text(restName,
                          style: const TextStyle(fontSize: 12, color: _grey)),
                    ]),
                  ),
                ]),
                if (!cancelled) ...[
                  const SizedBox(height: 16),
                  _Stepper(currentStep: _stepIndex(status)),
                ],
              ])),

              const SizedBox(height: 12),

              if (otp.isNotEmpty && !delivered && !cancelled)
                _card(Column(children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.lock_rounded, color: _orange, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Delivery OTP',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1C1C1E))),
                        Text('Show this to the delivery agent at your door',
                            style: TextStyle(fontSize: 11, color: _grey)),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: otp));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('OTP copied!'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.copy_rounded, size: 13, color: _primary),
                          SizedBox(width: 4),
                          Text('Copy',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _primary,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: Text(
                      otp.split('').join('  '),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: Color(0xFFE65100)),
                    ),
                  ),
                ])),

              if (delivered)
                _card(const Row(children: [
                  Icon(Icons.check_circle_rounded, color: _green, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Delivery Complete!',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _green)),
                      Text('We hope you enjoyed your meal 😋',
                          style: TextStyle(fontSize: 12, color: _grey)),
                    ]),
                  ),
                ])),

              const SizedBox(height: 12),

              // ── Agent info card (shown once agent is assigned) ────────────
              if (agentActive || status == 'delivered') ...[
                Builder(builder: (ctx) {
                  final agentName  = _order['agentName']  as String? ?? '';
                  final agentPhone = _order['agentPhone'] as String? ?? '';
                  if (agentName.isEmpty && agentPhone.isEmpty) return const SizedBox.shrink();
                  return _card(Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delivery_dining_rounded, color: _primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Your Delivery Agent',
                          style: TextStyle(fontSize: 11, color: _grey)),
                      const SizedBox(height: 2),
                      Text(agentName.isNotEmpty ? agentName : 'Agent',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1C1E))),
                      if (agentPhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(agentPhone,
                            style: const TextStyle(fontSize: 12, color: _grey)),
                      ],
                    ])),
                    if (agentPhone.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: agentPhone));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Phone number copied!'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.phone_rounded, size: 13, color: _primary),
                            SizedBox(width: 4),
                            Text('Copy',
                                style: TextStyle(
                                    fontSize: 11, color: _primary,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                  ]));
                }),
                const SizedBox(height: 12),
              ],

              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Order Details',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E))),
                const SizedBox(height: 12),
                ...((_order['items'] as List?) ?? []).map((item) {
                  final m     = item as Map<String, dynamic>;
                  final name  = m['name']     as String? ?? 'Item';
                  final qty   = (m['quantity'] as num? ?? 1).toInt();
                  final price = (m['price']    as num? ?? 0).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(color: _grey, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('$name × $qty',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)))),
                      Text('₹${(price * qty).toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _primary)),
                    ]),
                  );
                }),
                const Divider(height: 16, color: Color(0xFFF0F0F5)),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  Text(
                    '₹${((_order['grandTotal'] ?? _order['total'] ?? 0) as num).toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _primary)),
                ]),
              ])),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _card(Widget child) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: child);
}

class _Stepper extends StatelessWidget {
  final int currentStep;
  const _Stepper({required this.currentStep});

  static const _primary = Color(0xFF0077B6);
  static const _grey    = Color(0xFF6E6E73);
  static const _labels  = ['Placed', 'Preparing', 'On the Way', 'Delivered'];
  static const _icons   = [
    Icons.receipt_long_rounded,
    Icons.soup_kitchen_rounded,
    Icons.delivery_dining_rounded,
    Icons.check_circle_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 3,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: done ? _primary : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }
        final idx    = i ~/ 2;
        final done   = idx < currentStep;
        final active = idx == currentStep - 1 || (currentStep == 0 && idx == 0);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: active ? 32 : 26, height: active ? 32 : 26,
            decoration: BoxDecoration(
              color: done || active ? _primary : const Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: Icon(_icons[idx],
                size: active ? 16 : 13,
                color: done || active ? Colors.white : _grey),
          ),
          const SizedBox(height: 4),
          Text(_labels[idx],
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: done || active ? _primary : _grey),
              textAlign: TextAlign.center),
        ]);
      }),
    );
  }
}

class _AgentMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0077B6).withOpacity(0.18),
        ),
      ),
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0077B6),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 14),
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
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
    ),
    child: Icon(icon, color: Colors.white, size: 18),
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
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Icon(icon, size: 18, color: const Color(0xFF1C1C1E)),
    ),
  );
}