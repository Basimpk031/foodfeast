// ─────────────────────────────────────────────────────────────────────────────
// customer_tracking_screen.dart — FoodFeast
//
// Shown to the customer while their order is out for delivery.
// Features:
//   ✅ Live agent position from Firestore (real-time stream)
//   ✅ flutter_map (OpenStreetMap, no API key)
//   ✅ OSRM route drawn agent → customer
//   ✅ ETA chip (recomputed every 30 s)
//   ✅ Order status banner (picked up / out for delivery / arrived)
//   ✅ Order summary card (items, total, OTP hint)
//   ✅ Arrival notification for customer via LocalNotificationService
// ─────────────────────────────────────────────────────────────────────────────
//
// Usage — navigate from order detail or home:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => CustomerTrackingScreen(orderId: 'abc123'),
//   ));
//
// Firestore order document expected fields (same schema as DeliveryAgentDashboard):
//   agentLat, agentLng, agentLastSeen,
//   customerLat, customerLng, customerAddress,
//   restaurantName, customerName, status,
//   items (List), totalAmount, deliveryOtp
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'local_notification_service.dart';

const _kOsrmBase = 'https://router.project-osrm.org/route/v1/driving';

// ─────────────────────────────────────────────────────────────────────────────
class CustomerTrackingScreen extends StatefulWidget {
  final String orderId;

  const CustomerTrackingScreen({super.key, required this.orderId});

  @override
  State<CustomerTrackingScreen> createState() => _CustomerTrackingScreenState();
}

class _CustomerTrackingScreenState extends State<CustomerTrackingScreen> {
  static const _primary  = Color(0xFF0077B6);
  static const _green    = Color(0xFF34C759);
  static const _orange   = Color(0xFFFF9500);
  static const _darkText = Color(0xFF1C1C1E);
  static const _greyText = Color(0xFF6E6E73);

  // ── Map ────────────────────────────────────────────────────────────────────
  final _mapCtrl = MapController();

  // ── Order data ─────────────────────────────────────────────────────────────
  Map<String, dynamic>? _order;
  bool _loadingOrder = true;

  // ── Agent live position ────────────────────────────────────────────────────
  LatLng? _agentPos;
  LatLng? _customerPos;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _polyline   = [];
  int          _etaSeconds = 0;
  double       _distanceM  = 0;
  bool         _routeFetched = false;

  // ── Arrival guard ──────────────────────────────────────────────────────────
  bool _arrivalNotified = false;

  // ── Timers / subscriptions ─────────────────────────────────────────────────
  StreamSubscription? _orderSub;
  Timer?              _etaTimer;
  int                 _secondsSinceRouteUpdate = 0;
  static const _kRouteRefreshInterval = 30;

  @override
  void initState() {
    super.initState();
    _subscribeOrder();
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _etaTimer?.cancel();
    super.dispose();
  }

  // ── Subscribe to order Firestore document ──────────────────────────────────
  void _subscribeOrder() {
    _orderSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists || !mounted) return;

      final data = {'id': snap.id, ...?snap.data()};

      // Parse agent + customer positions
      final agentLat  = (data['agentLat']    as num?)?.toDouble();
      final agentLng  = (data['agentLng']    as num?)?.toDouble();
      final custLat   = (data['customerLat'] as num?)?.toDouble();
      final custLng   = (data['customerLng'] as num?)?.toDouble();

      final newAgentPos    = (agentLat  != null && agentLng  != null)
          ? LatLng(agentLat,  agentLng)
          : null;
      final newCustomerPos = (custLat   != null && custLng   != null)
          ? LatLng(custLat,   custLng)
          : null;

      setState(() {
        _order       = data;
        _agentPos    = newAgentPos;
        _customerPos = newCustomerPos;
        _loadingOrder = false;
      });

      // Initial route fetch
      if (!_routeFetched && newAgentPos != null && newCustomerPos != null) {
        _routeFetched = true;
        await _fetchRoute(newAgentPos, newCustomerPos);
        _startEtaTicker();
      }

      // Check arrival
      _checkArrival(data['status'] as String? ?? '');
    });
  }

  // ── OSRM route ─────────────────────────────────────────────────────────────
  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    final url = Uri.parse(
      '$_kOsrmBase/'
      '${from.longitude},${from.latitude};'
      '${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200 || !mounted) return;

      final json   = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = json['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final route = routes.first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      if (!mounted) return;
      setState(() {
        _polyline   = coords;
        _etaSeconds = (route['duration'] as num).toInt();
        _distanceM  = (route['distance'] as num).toDouble();
      });

      // Pan map to fit both markers
      _fitBounds(from, to);
    } catch (_) {}
  }

  void _fitBounds(LatLng a, LatLng b) {
    final bounds = LatLngBounds(a, b);
    _mapCtrl.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  // ── Countdown + route refresh ──────────────────────────────────────────────
  void _startEtaTicker() {
    _etaTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _etaSeconds = max(0, _etaSeconds - 1));

      _secondsSinceRouteUpdate++;
      if (_secondsSinceRouteUpdate >= _kRouteRefreshInterval) {
        _secondsSinceRouteUpdate = 0;
        if (_agentPos != null && _customerPos != null) {
          _fetchRoute(_agentPos!, _customerPos!);
        }
      }
    });
  }

  // ── Check if agent has arrived ─────────────────────────────────────────────
  void _checkArrival(String status) {
    if (_arrivalNotified) return;
    if (status == 'delivered' || status == 'arrived') {
      _arrivalNotified = true;
      LocalNotificationService.showNotification(
        id:    3000,
        title: '🎉 Your order has arrived!',
        body:  'Your delivery from ${_order?['restaurantName'] ?? 'the restaurant'} is here. Enjoy your meal!',
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatDuration(int s) {
    if (s <= 0) return 'Arriving now';
    if (s < 60) return '$s sec';
    final m = s ~/ 60;
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    return '${h}h ${m % 60}min';
  }

  String _formatDistance(double m) {
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'out_for_delivery': return _green;
      case 'picked_up':       return _orange;
      case 'delivered':       return _green;
      default:                return _greyText;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'out_for_delivery': return '🛵 Out for delivery';
      case 'picked_up':        return '📦 Order picked up';
      case 'delivered':        return '✅ Delivered';
      default:                 return 'Preparing your order';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loadingOrder) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    final status       = _order?['status'] as String? ?? '';
    final restaurantName = _order?['restaurantName'] as String? ?? 'Restaurant';
    final items        = (_order?['items'] as List?)?.length ?? 0;
    final total        = (_order?['totalAmount'] as num?)?.toDouble() ?? 0;
    final otp          = _order?['deliveryOtp'] as String? ?? '';

    return Scaffold(
      body: Stack(children: [
        // ── Map ────────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _customerPos ?? const LatLng(12.9716, 77.5946),
            initialZoom:   14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.foodfeast.app',
            ),

            // Route polyline
            if (_polyline.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points:      _polyline,
                  color:       _primary,
                  strokeWidth: 5,
                ),
              ]),

            // Markers
            MarkerLayer(markers: [
              // Agent (rider)
              if (_agentPos != null)
                Marker(
                  point:  _agentPos!,
                  width:  52,
                  height: 52,
                  child:  _RiderMarker(),
                ),

              // Customer (you)
              if (_customerPos != null)
                Marker(
                  point:  _customerPos!,
                  width:  44,
                  height: 44,
                  child:  _CustomerMarker(),
                ),
            ]),
          ],
        ),

        // ── Top: back + ETA ───────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              _CircleBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const Spacer(),
              if (!_loadingOrder && _etaSeconds > 0)
                _EtaBadge(
                  label: _formatDuration(_etaSeconds),
                  sublabel: _formatDistance(_distanceM),
                ),
              const SizedBox(width: 8),
              _CircleBtn(
                icon: Icons.my_location_rounded,
                onTap: () {
                  if (_customerPos != null) _mapCtrl.move(_customerPos!, 15);
                },
              ),
            ]),
          ),
        ),

        // ── Bottom sheet: order info ───────────────────────────────────────
        DraggableScrollableSheet(
          initialChildSize: 0.30,
          minChildSize:     0.18,
          maxChildSize:     0.55,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
            ),
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Status banner
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _statusColor(status).withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.circle,
                        size: 10, color: _statusColor(status)),
                    const SizedBox(width: 10),
                    Text(_statusLabel(status),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _statusColor(status))),
                  ]),
                ),
                const SizedBox(height: 16),

                // Restaurant + items
                Row(children: [
                  const Icon(Icons.restaurant_rounded,
                      size: 18, color: _orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(restaurantName,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _darkText)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text('$items item${items == 1 ? '' : 's'} · ₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 13, color: _greyText)),
                const SizedBox(height: 16),

                // ETA row
                if (_etaSeconds > 0)
                  Row(children: [
                    const Icon(Icons.access_time_rounded,
                        size: 16, color: _primary),
                    const SizedBox(width: 8),
                    Text('Estimated arrival: ${_formatDuration(_etaSeconds)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _darkText)),
                  ]),

                if (status == 'delivered') ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text('🎉 Your order has been delivered!',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _green)),
                  ),
                ],

                // OTP hint (only show before delivered)
                if (otp.isNotEmpty && status != 'delivered') ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: _greyText),
                    const SizedBox(width: 8),
                    const Text('Delivery OTP: ',
                        style: TextStyle(
                            fontSize: 13, color: _greyText)),
                    Text(otp,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _primary,
                            letterSpacing: 4)),
                  ]),
                  const SizedBox(height: 4),
                  const Text(
                    'Share this with the delivery agent to confirm delivery.',
                    style: TextStyle(fontSize: 11, color: _greyText),
                  ),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Rider marker (scooter emoji style) ──────────────────────────────────────
class _RiderMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0077B6).withOpacity(0.15),
            ),
          ),
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0077B6),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6)
              ],
            ),
            child: const Icon(Icons.delivery_dining_rounded,
                color: Colors.white, size: 18),
          ),
        ],
      );
}

// ─── Customer marker (home pin) ───────────────────────────────────────────────
class _CustomerMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF34C759),
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
      );
}

// ─── ETA badge ────────────────────────────────────────────────────────────────
class _EtaBadge extends StatelessWidget {
  final String label;
  final String sublabel;

  const _EtaBadge({required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0077B6))),
          Text(sublabel,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF6E6E73))),
        ]),
      );
}

// ─── Shared circle button ─────────────────────────────────────────────────────
class _CircleBtn extends StatelessWidget {
  final IconData icon;
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
