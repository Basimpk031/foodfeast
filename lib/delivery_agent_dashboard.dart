// ─────────────────────────────────────────────────────────────────────────────
// delivery_agent_dashboard.dart — FoodFeast
//
// Fully working delivery agent screen:
//   ✅ Online / Offline toggle  (Firestore: users/{uid}/isOnline)
//   ✅ Incoming order stream     (orders where assignedAgentId == agentId
//                                 AND status == 'ready_for_pickup')
//   ✅ Active delivery stream    (orders where assignedAgentId == agentId
//                                 AND status IN [picked_up, out_for_delivery])
//   ✅ Step-by-step flow         (Picked Up → Out for Delivery → Delivered)
//   ✅ OTP verification at delivery
//   ✅ Live location streaming   (updates Firestore every 10 s while online)
//   ✅ Earnings summary
//   ✅ Live map button → DeliveryMapScreen
//   ✅ FIX: Optimistic local lock prevents blink when accepting orders online
//   ✅ FIX: AppBar logout button pixel overflow fixed
//   ✅ NEW: Customer phone number shown (tries 6 field names)
//   ✅ NEW: All ordered item names + quantities + restaurant shown on both cards
//   ✅ FIX: Item price shows qty × unit price (not raw unit price)
//   ✅ FIX: totalAmount tries multiple field names
//   ✅ NEW: COD vs Online Paid badge shown on both incoming and active order cards
//   ✅ NEW: COD remittance card — total cash agent must send to admin
//   ✅ FIX: COD stream moved into state class (no StreamBuilder) to fix
//           window.dart:99 assertion errors
//
// Firestore order document expected fields:
//   id, customerName,
//   customerPhone | userPhone | contactPhone | phone | mobileNumber | mobile,
//   restaurantName, restaurantLat, restaurantLng,
//   customerLat, customerLng, customerAddress,
//   items (List<Map>: name/itemName/title, quantity/qty,
//                     price/unitPrice/itemPrice,
//                     restaurantName/restaurant/restaurantId)
//   totalAmount | total | orderTotal | grandTotal,
//   paymentMethod, paymentStatus,
//   status, assignedAgentId, deliveryOtp, createdAt
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'dart:math' show sin, cos, sqrt, asin, pi;
import 'delivery_map_screen.dart';
import 'location_filter.dart'; // formatDistance
import 'fcm_service.dart';
import 'local_notification_service.dart';
import 'finance_dashboard_screen.dart';

// ─── colours ────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF0077B6);
const _kDark    = Color(0xFF1A1A2E);
const _kGreen   = Color(0xFF34C759);
const _kOrange  = Color(0xFFFF9500);
const _kRed     = Color(0xFFFF3B30);
const _kGrey    = Color(0xFF6E6E73);

// ─── order status constants ──────────────────────────────────────────────────
const _sReady     = 'ready_for_pickup';
const _sPicked    = 'picked_up';
const _sOutDel    = 'out_for_delivery';
const _sDelivered = 'delivered';
const _kAgentRadiusKm = 5.0;

// ─────────────────────────────────────────────────────────────────────────────
class DeliveryAgentDashboard extends StatefulWidget {
  final String agentId;
  const DeliveryAgentDashboard({super.key, required this.agentId});

  @override
  State<DeliveryAgentDashboard> createState() => _DeliveryAgentDashboardState();
}

class _DeliveryAgentDashboardState extends State<DeliveryAgentDashboard> {
  // ── agent state ────────────────────────────────────────────────────────────
  String _agentName  = '';
  String _agentPhone = '';
  bool   _isOnline   = false;
  final Set<String> _proximityAlerted = {};
  double _earnings    = 0.0;
  int    _totalOrders = 0;
  bool   _loading     = true;
  bool   _toggling    = false;

  // ── location streaming ─────────────────────────────────────────────────────
  Timer?    _locationTimer;
  Position? _lastPosition;

  // ── Firestore subscriptions ────────────────────────────────────────────────
  StreamSubscription? _incomingSub;
  StreamSubscription? _activeSub;
  StreamSubscription? _codSub; // ← COD subscription (state-driven, no StreamBuilder)

  List<Map<String, dynamic>> _incomingOrders = [];
  Map<String, dynamic>?      _activeOrder;

  // ── COD remittance state ───────────────────────────────────────────────────
  double _codTotal      = 0.0;
  int    _codOrderCount = 0;
  bool   _codReady      = false;

  // ── Optimistic lock ────────────────────────────────────────────────────────
  final Set<String> _acceptingOrders = {};

  // ── Phone cache: userId → phone ───────────────────────────────────────────
  final Map<String, String> _userPhoneCache = {};

  // ── Step-advance lock ──────────────────────────────────────────────────────
  String? _advancingOrderId;
  String? _advancingToStatus;

  // ── OTP dialog state ───────────────────────────────────────────────────────
  final _otpCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAgent();
    _subscribeCodStream();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _incomingSub?.cancel();
    _activeSub?.cancel();
    _codSub?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── COD stream — always active, updates state fields ─────────────────────
  void _subscribeCodStream() {
    _codSub = FirebaseFirestore.instance
        .collection('orders')
        .where('assignedAgentId', isEqualTo: widget.agentId)
        .where('status', isEqualTo: _sDelivered)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;

      final codDocs = snap.docs.where((d) {
        final data   = d.data();
        final method = (data['paymentMethod'] as String? ?? '').toLowerCase();
        final pstatus = (data['paymentStatus'] as String? ?? '').toLowerCase();
        return method.contains('cod') ||
            method.contains('cash') ||
            pstatus.contains('cod') ||
            pstatus.contains('pending');
      }).toList();

      double total = 0;
      for (final doc in codDocs) {
        final o = doc.data();
        const keys = ['grandTotal', 'totalAmount', 'total', 'orderTotal', 'amount'];
        for (final k in keys) {
          final v = o[k];
          if (v is num && v > 0) {
            total += v.toDouble();
            break;
          }
        }
      }

      setState(() {
        _codTotal      = total;
        _codOrderCount = codDocs.length;
        _codReady      = true;
      });
    });
  }

  // ── Load agent document ───────────────────────────────────────────────────
  Future<void> _loadAgent() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.agentId)
          .get();
      final d = doc.data();
      if (d != null && mounted) {
        setState(() {
          _agentName   = d['name']         ?? '';
          _agentPhone  = d['phone']        ?? '';
          _isOnline    = d['isOnline']     ?? false;
          _earnings    = (d['earnings']    as num? ?? 0).toDouble();
          _totalOrders = (d['totalOrders'] as num? ?? 0).toInt();
          _loading     = false;
        });
        if (_isOnline) {
          unawaited(_subscribeOrders());
          _startLocationStreaming();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Online / Offline toggle ───────────────────────────────────────────────
  Future<void> _toggleOnline() async {
    if (_toggling) return;
    setState(() => _toggling = true);

    final newVal = !_isOnline;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.agentId)
          .update({'isOnline': newVal});
      setState(() => _isOnline = newVal);

      if (newVal) {
        unawaited(_subscribeOrders());
        _startLocationStreaming();
      } else {
        _unsubscribeOrders();
        _stopLocationStreaming();
      }
    } catch (_) {}

    setState(() => _toggling = false);
  }

  // ── One-shot GPS fetch before first snapshot ──────────────────────────────
  Future<void> _fetchPositionNow() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      _lastPosition = pos;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ── Haversine: agent GPS → restaurant coords ──────────────────────────────
  double? _agentDistToRestKm(Map<String, dynamic> order) {
    final pos = _lastPosition;
    if (pos == null) return null;
    final rLat = (order['restaurantLat'] as num?)?.toDouble();
    final rLng = (order['restaurantLng'] as num?)?.toDouble();
    if (rLat == null || rLng == null) return null;
    const R    = 6371.0;
    final dLat = (rLat - pos.latitude)  * (pi / 180);
    final dLng = (rLng - pos.longitude) * (pi / 180);
    final a    = sin(dLat / 2) * sin(dLat / 2) +
        cos(pos.latitude  * (pi / 180)) * cos(rLat * (pi / 180)) *
        sin(dLng / 2) * sin(dLng / 2);
    return 2 * R * asin(sqrt(a));
  }

  // ── Order subscriptions ───────────────────────────────────────────────────
  Future<void> _subscribeOrders() async {
    final col = FirebaseFirestore.instance.collection('orders');

    await _fetchPositionNow();

    _incomingSub = col
        .where('status', isEqualTo: _sReady)
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;

      final orders = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where((o) => !_acceptingOrders.contains(o['id']))
          .where((o) {
            final dist = _agentDistToRestKm(o);
            if (dist == null) return true;
            return dist <= _kAgentRadiusKm;
          })
          .toList();

      await _prefetchPhones(orders);

      if (!mounted) return;
      setState(() {
        _incomingOrders = orders.map((o) => _injectPhone(o)).toList();
      });
    });

    _activeSub = col
        .where('assignedAgentId', isEqualTo: widget.agentId)
        .where('status', whereIn: [_sPicked, _sOutDel])
        .limit(1)
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;

      Map<String, dynamic>? order;
      if (snap.docs.isNotEmpty) {
        order = {'id': snap.docs.first.id, ...snap.docs.first.data()};
        await _prefetchPhones([order]);
        order = _injectPhone(order);
      }

      if (!mounted) return;
      setState(() {
        _activeOrder = order;

        if (_activeOrder != null) {
          _acceptingOrders.remove(_activeOrder!['id']);
        }

        if (_advancingOrderId != null &&
            _activeOrder != null &&
            _activeOrder!['id'] == _advancingOrderId &&
            _activeOrder!['status'] == _advancingToStatus) {
          _advancingOrderId  = null;
          _advancingToStatus = null;
        }
      });
    });
  }

  Future<void> _prefetchPhones(List<Map<String, dynamic>> orders) async {
    final uncached = orders
        .map((o) => o['userId'] as String? ?? '')
        .where((uid) => uid.isNotEmpty && !_userPhoneCache.containsKey(uid))
        .toSet();

    if (uncached.isEmpty) return;

    await Future.wait(uncached.map((uid) async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data  = doc.data();
        final phone = (data?['phone'] as String?)?.trim() ?? '';
        _userPhoneCache[uid] = phone.isNotEmpty ? phone : 'N/A';
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          try {
            final snap = await FirebaseFirestore.instance
                .collection('users')
                .where('uid', isEqualTo: uid)
                .limit(1)
                .get();
            if (snap.docs.isNotEmpty) {
              final phone =
                  (snap.docs.first.data()['phone'] as String?)?.trim() ?? '';
              _userPhoneCache[uid] = phone.isNotEmpty ? phone : 'N/A';
            } else {
              _userPhoneCache[uid] = 'N/A';
            }
          } catch (_) {
            _userPhoneCache[uid] = 'N/A';
          }
        } else {
          _userPhoneCache[uid] = 'N/A';
        }
      } catch (_) {
        _userPhoneCache[uid] = 'N/A';
      }
    }));
  }

  Map<String, dynamic> _injectPhone(Map<String, dynamic> order) {
    final uid   = order['userId'] as String? ?? '';
    final phone = _userPhoneCache[uid] ?? '';
    if (phone.isEmpty) return order;
    return {...order, '_customerPhone': phone};
  }

  void _unsubscribeOrders() {
    _incomingSub?.cancel();
    _activeSub?.cancel();
    _incomingSub = null;
    _activeSub   = null;
    setState(() {
      _incomingOrders    = [];
      _activeOrder       = null;
      _acceptingOrders.clear();
      _userPhoneCache.clear();
      _advancingOrderId  = null;
      _advancingToStatus = null;
    });
  }

  // ── Location streaming ─────────────────────────────────────────────────────
  void _startLocationStreaming() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) return;

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        _lastPosition = pos;

        final db    = FirebaseFirestore.instance;
        final batch = db.batch();

        batch.update(
          db.collection('users').doc(widget.agentId),
          {
            'lastLat':  pos.latitude,
            'lastLng':  pos.longitude,
            'lastSeen': FieldValue.serverTimestamp(),
          },
        );

        final activeId = _activeOrder?['id'] as String?;
        if (activeId != null && activeId.isNotEmpty) {
          batch.set(
            db.collection('orders').doc(activeId),
            {
              'agentLat':      pos.latitude,
              'agentLng':      pos.longitude,
              'agentLastSeen': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        await batch.commit();

        // ── Proximity alert ────────────────────────────────────────────────
        final activeId2 = _activeOrder?['id'] as String?;
        if (activeId2 != null && !_proximityAlerted.contains(activeId2)) {
          final activeStatus = _activeOrder?['status'] as String? ?? '';
          if (activeStatus == _sOutDel) {
            final custLat = (_activeOrder?['customerLat'] as num?)?.toDouble();
            final custLng = (_activeOrder?['customerLng'] as num?)?.toDouble();
            if (custLat != null && custLng != null) {
              const R = 6371.0;
              final dLat = (custLat - pos.latitude)  * (pi / 180);
              final dLng = (custLng - pos.longitude) * (pi / 180);
              final a2   = sin(dLat / 2) * sin(dLat / 2) +
                  cos(pos.latitude * (pi / 180)) * cos(custLat * (pi / 180)) *
                  sin(dLng / 2) * sin(dLng / 2);
              final distKm = 2 * R * asin(sqrt(a2));
              final etaMin = (distKm * 3).round();
              if (etaMin <= 5) {
                _proximityAlerted.add(activeId2);
                final customerId = _activeOrder?['userId'] as String? ?? '';
                if (customerId.isNotEmpty) {
                  final custTok =
                      _activeOrder?['customerFcmToken'] as String? ?? '';
                  unawaited(FcmService.sendAgentProximityAlert(
                    customerId:       customerId,
                    orderId:          activeId2,
                    etaMinutes:       etaMin,
                    agentName:        _agentName,
                    customerFcmToken: custTok,
                  ));
                }
                unawaited(LocalNotificationService.showEtaAlert(
                  etaMinutes: etaMin,
                  destName:
                      _activeOrder?['customerName'] as String? ?? 'customer',
                ));
              }
            }
          }
        }
      } catch (_) {}
    });
  }

  void _stopLocationStreaming() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  // ── Step forward ──────────────────────────────────────────────────────────
  Future<void> _advanceStep(Map<String, dynamic> order) async {
    final id     = order['id'] as String;
    final status = order['status'] as String? ?? '';

    if (_advancingOrderId != null) return;

    String nextStatus;
    if (status == _sReady) {
      nextStatus = _sPicked;
    } else if (status == _sPicked) {
      _openMap(order);
      return;
    } else if (status == _sOutDel) {
      _showOtpDialog(order);
      return;
    } else {
      return;
    }

    setState(() {
      _advancingOrderId  = id;
      _advancingToStatus = nextStatus;
    });

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(id)
          .update({'status': nextStatus});

      final customerId = order['userId'] as String? ?? '';
      final custToken  = order['customerFcmToken'] as String? ?? '';
      if (customerId.isNotEmpty) {
        unawaited(FcmService.sendOrderStatusNotification(
          customerId:       customerId,
          orderId:          id,
          status:           nextStatus,
          restaurantName:   order['restaurantName'] as String?,
          customerFcmToken: custToken,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _advancingOrderId  = null;
          _advancingToStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update order. Please try again.'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  // ── OTP dialog ────────────────────────────────────────────────────────────
  void _showOtpDialog(Map<String, dynamic> order) {
    _otpCtrl.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter Delivery OTP',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Ask the customer for the 4-digit OTP shown in their app.',
            style: TextStyle(color: _kGrey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF2F2F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _kGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final entered = _otpCtrl.text.trim();
              final correct = (order['deliveryOtp'] ?? '').toString();
              if (entered == correct) {
                Navigator.pop(context);
                await _markDelivered(order);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Wrong OTP. Try again.'),
                    backgroundColor: _kRed,
                  ),
                );
              }
            },
            child: const Text('Confirm',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Mark delivered + update earnings ─────────────────────────────────────
  Future<void> _markDelivered(Map<String, dynamic> order) async {
    final id     = order['id'] as String;
    // Agent always earns at least ₹30 — even when delivery is free for the customer.
    final rawFee = (order['deliveryFee'] as num? ?? 0).toDouble();
    final amount = rawFee > 0 ? rawFee : 30.0;

    final batch = FirebaseFirestore.instance.batch();

    batch.update(
      FirebaseFirestore.instance.collection('orders').doc(id),
      {
        'status':      _sDelivered,
        'deliveredAt': FieldValue.serverTimestamp(),
      },
    );

    batch.update(
      FirebaseFirestore.instance.collection('users').doc(widget.agentId),
      {
        'earnings':    FieldValue.increment(amount),
        'totalOrders': FieldValue.increment(1),
      },
    );

    await batch.commit();

    final customerId = order['userId'] as String? ?? '';
    final custToken  = order['customerFcmToken'] as String? ?? '';
    if (customerId.isNotEmpty) {
      unawaited(FcmService.sendOrderStatusNotification(
        customerId:       customerId,
        orderId:          id,
        status:           _sDelivered,
        restaurantName:   order['restaurantName'] as String?,
        customerFcmToken: custToken,
      ));
    }

    _proximityAlerted.remove(id);

    setState(() {
      _earnings    += amount;
      _totalOrders += 1;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Order delivered! +₹${amount.toStringAsFixed(0)} earned'),
          backgroundColor: _kGreen,
        ),
      );
    }
  }

  // ── Accept incoming order ─────────────────────────────────────────────────
  Future<void> _acceptOrder(Map<String, dynamic> order) async {
    final id = order['id'] as String;
    if (_acceptingOrders.contains(id)) return;

    final dist = _agentDistToRestKm(order);
    if (dist != null && dist > _kAgentRadiusKm) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '📍 Restaurant is ${formatDistance(dist)} away — outside your '
          '${_kAgentRadiusKm.toInt()} km pickup radius.',
        ),
        backgroundColor: _kRed,
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    setState(() => _acceptingOrders.add(id));

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(id)
          .update({
        'status':          _sPicked,
        'assignedAgentId': widget.agentId,
        'agentName':       _agentName,
        'agentPhone':      _agentPhone,
        'pickedAt':        FieldValue.serverTimestamp(),
      });

      final customerId = order['userId'] as String? ?? '';
      final custToken  = order['customerFcmToken'] as String? ?? '';
      if (customerId.isNotEmpty) {
        await FcmService.sendOrderStatusNotification(
          customerId:       customerId,
          orderId:          id,
          status:           _sPicked,
          restaurantName:   order['restaurantName'] as String?,
          customerFcmToken: custToken,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _acceptingOrders.remove(id));
        final isFirebase = e is FirebaseException;
        final msg = (isFirebase && e.code == 'permission-denied')
            ? '⚡ Order already taken by another agent.'
            : 'Failed to accept: ${_friendlyError(e)}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: _kRed,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  // ── Friendly error ────────────────────────────────────────────────────────
  String _friendlyError(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':  return 'Permission denied — check Firestore rules.';
        case 'not-found':          return 'Order not found — it may have been removed.';
        case 'unavailable':        return 'No connection. Check your internet.';
        case 'deadline-exceeded':  return 'Request timed out. Try again.';
        default:                   return '${e.code}: ${e.message}';
      }
    }
    return e.toString();
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    _stopLocationStreaming();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.agentId)
        .update({'isOnline': false}).catchError((_) {});
    await FirebaseAuth.instance.signOut();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: _kPrimary)));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _loadAgent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _heroCard(),
            const SizedBox(height: 16),
            _statsRow(),
            const SizedBox(height: 16),

            // ── COD Remittance Card (pure state, no StreamBuilder) ────────
            _codRemittanceCard(),

            if (_activeOrder != null) ...[
              _sectionLabel('🚴 Active Delivery'),
              const SizedBox(height: 8),
              _activeOrderCard(_activeOrder!),
              const SizedBox(height: 16),
            ],

            if (_isOnline && _incomingOrders.isNotEmpty) ...[
              _sectionLabel('📬 Incoming Orders (${_incomingOrders.length})'),
              const SizedBox(height: 8),
              ..._incomingOrders.map(_incomingOrderCard),
              const SizedBox(height: 16),
            ],

            if (_isOnline && _incomingOrders.isEmpty && _activeOrder == null)
              _waitingCard(),

            if (!_isOnline) _offlineCard(),

            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────
  AppBar _buildAppBar() => AppBar(
        backgroundColor: _kDark,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(children: [
          const SizedBox(width: 16),
          const Text('🛵 ', style: TextStyle(fontSize: 20)),
          RichText(
            text: const TextSpan(children: [
              TextSpan(
                  text: 'Food',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              TextSpan(
                  text: 'Feast',
                  style: TextStyle(
                      color: _kPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              TextSpan(
                  text: ' Partner',
                  style: TextStyle(
                      color: Color(0xFFFFB800),
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            tooltip: 'Sign Out',
            onPressed: _signOut,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
      );

  // ─── Hero / online card ───────────────────────────────────────────────────
  Widget _heroCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF023E8A), Color(0xFF0077B6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hi, $_agentName! 👋',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            _isOnline
                ? 'You\'re online — accepting deliveries'
                : 'You\'re offline. Tap below to go online.',
            style: const TextStyle(fontSize: 13, color: Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _toggling ? null : _toggleOnline,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 50,
              decoration: BoxDecoration(
                color: _isOnline ? _kGreen : const Color(0x2DFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _isOnline ? _kGreen : const Color(0x66FFFFFF),
                    width: 2),
              ),
              child: Center(
                child: _toggling
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              _isOnline
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: Colors.white,
                              size: 20),
                          const SizedBox(width: 8),
                          Text(
                              _isOnline ? 'Go Offline' : 'Go Online',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                        ]),
              ),
            ),
          ),
        ]),
      );

  // ─── Stats row ────────────────────────────────────────────────────────────
  Widget _statsRow() => Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FinanceDashboardScreen(
                  role:      FinanceRole.agent,
                  agentId:   widget.agentId,
                  agentName: _agentName,
                ),
              ),
            ),
            child: _statCard(
              '💰', 'Earnings', '₹${_earnings.toStringAsFixed(0)}', _kGreen,
              tappable: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard('📦', 'Delivered', '$_totalOrders', _kPrimary)),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard(
                _isOnline ? '🟢' : '⭕',
                'Status',
                _isOnline ? 'Online' : 'Offline',
                _isOnline ? _kGreen : _kGrey)),
      ]);

  Widget _statCard(
    String icon,
    String label,
    String value,
    Color color, {
    bool tappable = false,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: const Color(0x0D000000),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const Spacer(),
            if (tappable)
              Icon(Icons.chevron_right_rounded,
                  size: 15, color: color.withOpacity(0.5)),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: _kGrey)),
        ]),
      );

  // ─── Section label ────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
      );

  // ─── COD Remittance Card ──────────────────────────────────────────────────
  // Pure state-driven — no StreamBuilder. _codSub updates _codTotal and
  // _codOrderCount via setState, so this method just reads those fields.
  Widget _codRemittanceCard() {
    if (!_codReady || _codOrderCount == 0 || _codTotal == 0) {
      return const SizedBox.shrink();
    }

    final avg = _codTotal / _codOrderCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('💵 Cash to Remit'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8EC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFE08A), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0x14FF9500),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // ── Main row ──────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE08A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.money_rounded,
                    color: Color(0xFF856404), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text(
                    'Cash to Send to Admin',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF856404)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'from $_codOrderCount COD order${_codOrderCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFFAD8B3A)),
                  ),
                ]),
              ),
              Text(
                '₹${_codTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF856404)),
              ),
            ]),

            const SizedBox(height: 12),

            // ── Info strip ────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE08A).withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    size: 13, color: Color(0xFF856404)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Avg ₹${avg.toStringAsFixed(0)} per order · '
                    'Hand this amount to your admin.',
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF856404),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Active order card ────────────────────────────────────────────────────
  Widget _activeOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as String;

    final status =
        (orderId == _advancingOrderId && _advancingToStatus != null)
            ? _advancingToStatus!
            : (order['status'] as String? ?? '');

    final steps      = [_sReady, _sPicked, _sOutDel, _sDelivered];
    final stepIndex  = steps.indexOf(status);
    final stepLabels = ['Assigned', 'Picked Up', 'Out for Delivery', 'Delivered'];
    final stepIcons  = [
      Icons.assignment_rounded,
      Icons.storefront_rounded,
      Icons.directions_bike_rounded,
      Icons.check_circle_rounded,
    ];

    final nextLabel = status == _sPicked
        ? 'Open Map to Pick Up 🗺️'
        : status == _sOutDel
            ? 'Confirm Delivery (OTP)'
            : '';

    final customerPhone = _resolvePhone(order);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: const Color(0x0F000000),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0x0F0077B6),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(children: [
            const Icon(Icons.directions_bike_rounded,
                color: _kPrimary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${order['restaurantName'] ?? 'Restaurant'} → ${order['customerName'] ?? 'Customer'}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: _kDark, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '#${(order['id'] as String).substring(0, 6).toUpperCase()}',
              style: const TextStyle(
                  fontSize: 11, color: _kGrey, fontWeight: FontWeight.w600),
            ),
          ]),
        ),

        // Step indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: List.generate(stepLabels.length, (i) {
              final done   = i <= stepIndex;
              final active = i == stepIndex;
              return Expanded(
                child: Row(children: [
                  Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width:  active ? 32 : 26,
                      height: active ? 32 : 26,
                      decoration: BoxDecoration(
                        color: done ? _kPrimary : const Color(0xFFE5E5EA),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(stepIcons[i],
                          size: active ? 16 : 13,
                          color: done ? Colors.white : _kGrey),
                    ),
                    const SizedBox(height: 4),
                    Text(stepLabels[i],
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400,
                            color: done ? _kPrimary : _kGrey),
                        textAlign: TextAlign.center),
                  ]),
                  if (i < stepLabels.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 18),
                        color: i < stepIndex
                            ? _kPrimary
                            : const Color(0xFFE5E5EA),
                      ),
                    ),
                ]),
              );
            }),
          ),
        ),

        // ── Order details ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _infoRow(Icons.person_rounded, order['customerName'] ?? 'Customer'),
            const SizedBox(height: 6),
            _copyablePhoneRow(customerPhone),
            const SizedBox(height: 6),
            _infoRow(Icons.location_on_rounded,
                order['customerAddress'] ?? 'Customer address'),
            const SizedBox(height: 6),
            _infoRow(
              Icons.currency_rupee_rounded,
              '₹${_resolveTotalAmount(order).toStringAsFixed(0)}'
              ' · ${(order['items'] as List?)?.length ?? 0} items',
            ),
            const SizedBox(height: 10),
            _paymentRow(order),
            const SizedBox(height: 8),
            _codBadge(order),
            const SizedBox(height: 10),
            _itemsList(order),
          ]),
        ),

        const SizedBox(height: 14),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kPrimary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _openMap(order),
                icon: const Icon(Icons.map_rounded, color: _kPrimary, size: 18),
                label: const Text('Live Map',
                    style: TextStyle(
                        color: _kPrimary, fontWeight: FontWeight.w700)),
              ),
            ),
            if (nextLabel.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status == _sOutDel ? _kGreen : _kOrange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _advancingOrderId == orderId
                      ? null
                      : () => _advanceStep(order),
                  child: _advancingOrderId == orderId
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(
                          nextLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // ─── Incoming order card ──────────────────────────────────────────────────
  Widget _incomingOrderCard(Map<String, dynamic> order) {
    final customerPhone = _resolvePhone(order);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x66FF9500)),
        boxShadow: [
          BoxShadow(
              color: const Color(0x14FF9500),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🔔', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              order['restaurantName'] ?? 'Order',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x1EFF9500),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '₹${((order['deliveryFee'] as num? ?? 0) > 0 ? (order['deliveryFee'] as num).toDouble() : 30.0).toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 13,
                  color: _kOrange,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _infoRow(Icons.person_rounded, order['customerName'] ?? 'Customer'),
        const SizedBox(height: 4),
        _copyablePhoneRow(customerPhone),
        const SizedBox(height: 4),
        _infoRow(Icons.location_on_rounded,
            order['customerAddress'] ?? 'Delivery address'),
        const SizedBox(height: 10),
        _paymentRow(order),
        const SizedBox(height: 8),
        _codBadge(order),
        const SizedBox(height: 8),
        _itemsList(order),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => _acceptOrder(order),
            child: const Text('Accept & Pick Up',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ),
        ),
      ]),
    );
  }

  // ─── Field resolvers ──────────────────────────────────────────────────────

  String _resolvePhone(Map<String, dynamic> order) {
    const candidates = [
      '_customerPhone',
      'customerPhone', 'userPhone', 'contactPhone',
      'phone', 'mobileNumber', 'mobile',
    ];
    for (final key in candidates) {
      final v = order[key];
      if (v is String && v.trim().isNotEmpty && v.trim() != 'N/A') {
        return v.trim();
      }
    }
    return 'N/A';
  }

  double _resolveTotalAmount(Map<String, dynamic> order) {
    const candidates = [
      'totalAmount', 'total', 'orderTotal', 'grandTotal', 'amount',
    ];
    for (final key in candidates) {
      final v = order[key];
      if (v is num && v > 0) return v.toDouble();
    }
    return 0.0;
  }

  // ─── Items list ───────────────────────────────────────────────────────────
  Widget _itemsList(Map<String, dynamic> order) {
    final items = order['items'] as List?;
    if (items == null || items.isEmpty) return const SizedBox.shrink();

    final orderRestaurantName =
        (order['restaurantName'] as String?)?.trim() ?? '';

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final raw in items) {
      final m =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final restName =
          (m['restaurantName'] as String?)?.trim().isNotEmpty == true
              ? (m['restaurantName'] as String).trim()
              : (m['restaurant'] as String?)?.trim().isNotEmpty == true
                  ? (m['restaurant'] as String).trim()
                  : orderRestaurantName;
      grouped.putIfAbsent(restName, () => []).add(m);
    }

    final bool multiRestaurant =
        grouped.keys.where((k) => k.isNotEmpty).length > 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.receipt_long_rounded, size: 13, color: _kGrey),
            SizedBox(width: 5),
            Text('ORDER ITEMS',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kGrey,
                    letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 8),

          ...grouped.entries.expand((entry) {
            final restLabel = entry.key;
            final groupItems = entry.value;

            return [
              if (restLabel.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.storefront_rounded,
                        size: 12, color: _kPrimary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(restLabel,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _kPrimary),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
              ],

              ...groupItems.map((m) {
                final name =
                    (m['name'] as String?)?.trim().isNotEmpty == true
                        ? (m['name'] as String).trim()
                        : (m['itemName'] as String?)?.trim().isNotEmpty == true
                            ? (m['itemName'] as String).trim()
                            : (m['title'] as String?)?.trim().isNotEmpty == true
                                ? (m['title'] as String).trim()
                                : 'Item';

                final qtyNum = (m['quantity'] ?? m['qty'] ?? 1);
                final qty    = (qtyNum is num) ? qtyNum.toInt() : 1;

                final unitPriceRaw =
                    m['price'] ?? m['unitPrice'] ?? m['itemPrice'];
                final unitPrice =
                    unitPriceRaw is num ? unitPriceRaw.toDouble() : null;
                final lineTotal =
                    unitPrice != null ? qty * unitPrice : null;
                final priceLine =
                    lineTotal != null ? '₹${lineTotal.toStringAsFixed(0)}' : null;

                final showItemRestaurant =
                    !multiRestaurant && restLabel.isNotEmpty;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _kPrimary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text('${qty}×',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _kPrimary)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _kDark),
                                overflow: TextOverflow.ellipsis),
                            if (showItemRestaurant)
                              Text(restLabel,
                                  style: const TextStyle(
                                      fontSize: 10, color: _kGrey),
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (priceLine != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(priceLine,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _kDark,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                );
              }),

              if (multiRestaurant && entry.key != grouped.keys.last)
                const Divider(height: 10, thickness: 0.5),
            ];
          }),
        ],
      ),
    );
  }

  // ─── Waiting card ─────────────────────────────────────────────────────────
  Widget _waitingCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: const Color(0x0D000000),
                blurRadius: 14,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(children: [
          const Text('⏳', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 14),
          const Text('Waiting for Orders',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 8),
          const Text(
            'You\'re online and ready.\nNew orders will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _kGrey, height: 1.6),
          ),
        ]),
      );

  // ─── Offline card ─────────────────────────────────────────────────────────
  Widget _offlineCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: const Color(0x0D000000),
                blurRadius: 14,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(children: [
          const Text('😴', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 14),
          const Text('You\'re Offline',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 8),
          const Text(
            'Tap "Go Online" above to start\nreceiving delivery requests.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _kGrey, height: 1.6),
          ),
        ]),
      );

  // ─── Small info row helper ────────────────────────────────────────────────
  Widget _infoRow(IconData icon, String text) => Row(children: [
        Icon(icon, size: 14, color: _kGrey),
        const SizedBox(width: 6),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12.5, color: _kGrey),
                overflow: TextOverflow.ellipsis)),
      ]);

  // ─── Payment method row ───────────────────────────────────────────────────
  Widget _paymentRow(Map<String, dynamic> order) {
    final method = (order['paymentMethod'] as String? ?? '').trim();
    if (method.isEmpty) return const SizedBox.shrink();
    final isCod = method.toLowerCase().contains('cod') ||
        method.toLowerCase().contains('cash');
    return Row(children: [
      Icon(
        isCod ? Icons.money_rounded : Icons.credit_card_rounded,
        size: 14,
        color: isCod ? const Color(0xFFFF9500) : _kGreen,
      ),
      const SizedBox(width: 6),
      Text(method,
          style: TextStyle(
              fontSize: 12.5,
              color: isCod ? const Color(0xFFFF9500) : _kGreen,
              fontWeight: FontWeight.w700)),
    ]);
  }

  // ─── COD / Online-Paid badge ──────────────────────────────────────────────
  Widget _codBadge(Map<String, dynamic> order) {
    final method = (order['paymentMethod'] as String? ?? '').trim();
    final status = (order['paymentStatus'] as String? ?? '').trim();
    final isCod  = method.toLowerCase().contains('cod') ||
        method.toLowerCase().contains('cash') ||
        status.toLowerCase().contains('cod') ||
        status.toLowerCase().contains('pending');

    if (isCod) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE08A), width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.money_rounded, size: 15, color: Color(0xFF856404)),
          const SizedBox(width: 6),
          const Text('💵 Collect Cash on Delivery',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF856404))),
        ]),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFD4EDDA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8FD4A4), width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded,
              size: 15, color: Color(0xFF155724)),
          const SizedBox(width: 6),
          const Text('✅ Already Paid Online',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF155724))),
        ]),
      );
    }
  }

  // ─── Copyable phone row ───────────────────────────────────────────────────
  Widget _copyablePhoneRow(String phone) {
    final isValid = phone.isNotEmpty && phone != 'N/A';
    return Row(children: [
      const Icon(Icons.phone_rounded, size: 14, color: _kGrey),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          isValid ? phone : 'N/A',
          style: const TextStyle(fontSize: 12.5, color: _kGrey),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (isValid)
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: phone));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('📋 Phone number copied!'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.copy_rounded, size: 11, color: _kPrimary),
              SizedBox(width: 3),
              Text('Copy',
                  style: TextStyle(
                      fontSize: 10,
                      color: _kPrimary,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
    ]);
  }

  // ─── Open live map ────────────────────────────────────────────────────────
  void _openMap(Map<String, dynamic> order) {
    final custLat = (order['customerLat'] as num? ?? 0).toDouble();
    final custLng = (order['customerLng'] as num? ?? 0).toDouble();

    if (custLat == 0.0 && custLng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('📍 Customer delivery location not set. Contact admin.'),
          backgroundColor: _kOrange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final List<Map<String, dynamic>> restaurants;
    final raw = order['restaurants'];
    if (raw is List && raw.isNotEmpty) {
      restaurants =
          raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } else {
      final restLat = (order['restaurantLat'] as num? ?? 0).toDouble();
      final restLng = (order['restaurantLng'] as num? ?? 0).toDouble();
      if (restLat == 0.0 && restLng == 0.0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '📍 Restaurant location not set for this order. Contact admin.'),
            backgroundColor: _kOrange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      restaurants = [
        {
          'id':   'rest_0',
          'name': order['restaurantName'] ?? 'Restaurant',
          'lat':  restLat,
          'lng':  restLng,
        }
      ];
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryMapScreen(
          agentId:        widget.agentId,
          orderId:        order['id'] as String,
          restaurantLat:  (restaurants.first['lat'] as num).toDouble(),
          restaurantLng:  (restaurants.first['lng'] as num).toDouble(),
          restaurantName: restaurants.first['name'] as String? ?? 'Restaurant',
          customerLat:    custLat,
          customerLng:    custLng,
          customerName:   order['customerName'] ?? 'Customer',
          restaurants:    restaurants,
        ),
      ),
    );
  }
}