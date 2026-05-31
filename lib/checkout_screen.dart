// checkout_screen.dart — FoodFeast
// ───────────────────────────────────────────────────────────────────
// RAZORPAY FIXES applied in this version:
//
//   [FIX-1] Removed custom MethodChannel intercept entirely.
//           The intercept was conflicting with razorpay_flutter's own
//           channel handler, causing double-fires on success and
//           missed callbacks on some Android OEM ROMs.
//           We now register all three official listeners:
//             EVENT_PAYMENT_SUCCESS → _onPaymentSuccess
//             EVENT_PAYMENT_ERROR   → _onPaymentError   ← was missing
//             EVENT_EXTERNAL_WALLET → _onExternalWallet
//           PaymentFailureResponse.fromMap crash is avoided by wrapping
//           the open() call in a try/catch and catching PlatformException.
//
//   [FIX-2] Phone number sanitisation before Razorpay prefill.
//           Firestore stores '+91XXXXXXXXXX'; Razorpay's contact field
//           expects a plain 10-digit string or E.164. Sending '+91...'
//           was causing "Invalid contact" silent failures on some
//           Razorpay SDK versions. We now strip any leading '+91' or
//           '91' (if 12 digits) before passing to the SDK.
//
//   [FIX-3] Amount precision.
//           _grand contains floating-point tax arithmetic. Multiplying
//           directly by 100 and rounding can give ±1 paise depending
//           on IEEE-754 rounding. We now round to 2 decimal places
//           first, then multiply, ensuring the paise value is exact.
//
//   [FIX-4] _pendingOrderId null-guard (carried over from previous fix).
//           _finaliseOrder captures the field into a local variable
//           before any await to avoid race conditions.
//
//   [FIX-5] _onPaymentSuccess is kept sync (not async) so the Razorpay
//           event system can call it without swallowing exceptions.
//           Heavy work is done in _finaliseOrder with .catchError().
//
//   [FIX-6] dispose() now calls _razorpay.clear() only (no channel
//           handler to remove), keeping teardown clean.
// ───────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'cart_provider.dart';
import 'calorie_tracker.dart';
import 'fcm_service.dart';
import 'location_service.dart';
import 'order_tracking_screen.dart';

// ─────────────────────────────────────────────
// Payload — passed from Cart or Bundle screen
// ─────────────────────────────────────────────
class CheckoutPayload {
  final List<Map<String, dynamic>> items;
  final double totalPrice;
  final int totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final String restaurantName;
  final String? restaurantId; // [FIX] used to fetch GPS coords at order creation
  final String source;
  final String? bundleId;
  final String? bundleName;

  const CheckoutPayload({
    required this.items,
    required this.totalPrice,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.restaurantName,
    this.restaurantId,
    this.source = 'cart',
    this.bundleId,
    this.bundleName,
  });
}

// ─────────────────────────────────────────────
// CheckoutScreen
// ─────────────────────────────────────────────
class CheckoutScreen extends StatefulWidget {
  final CheckoutPayload payload;
  final VoidCallback? onOrderSuccess;
  /// When non-null, the code is pre-filled and auto-applied on page load.
  /// Set by OffersSection when the user taps "Go to Checkout — Auto Apply".
  final String? initialPromoCode;

  const CheckoutScreen({
    super.key,
    required this.payload,
    this.onOrderSuccess,
    this.initialPromoCode,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with WidgetsBindingObserver {
  static const _blue   = Color(0xFF0077B6);
  static const _green  = Color(0xFF34C759);
  static const _red    = Color(0xFFFF3B30);
  static const _orange = Color(0xFFFF9500);

  final Razorpay _razorpay = Razorpay();

  int _step = 0;

  // Address
  final _addrCtrl     = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _pincodeCtrl  = TextEditingController();
  String _addrType    = 'Home';
  List<Map<String, dynamic>> _savedAddresses = [];
  int _selectedAddrIdx = -1;
  bool _loadingAddr    = true;

  // Slot
  final _slots = const [
    'ASAP (~30 min)',
    '12:00 – 1:00 PM',
    '1:00 – 2:00 PM',
    '6:00 – 7:00 PM',
    '7:00 – 8:00 PM',
    '8:00 – 9:00 PM',
  ];
  int _slotIdx = 0;

  // Promo
  final _promoCtrl    = TextEditingController();
  String? _appliedPromo;
  double _discount    = 0;
  bool _checkingPromo = false;

  // Payment
  String _payMethod = 'razorpay';

  // State
  bool _placing = false;
  String? _pendingOrderId;
  String? _pendingOtp;

  // Prefill data for Razorpay — populated in _placeOrder before .open()
  String _prefillName  = '';
  String _prefillEmail = '';
  String _prefillPhone = '';

  // Ordering mode
  String _orderingMode = 'personal';
  late Set<int> _myItems;

  // Per-item personal quantity in group mode
  // Key = item index, Value = how many of that item I'm eating (0..item['quantity'])
  late Map<int, int> _myQuantities;

  // ── Location ──────────────────────────────────
  // Stores the GPS-confirmed / map-picked delivery location.
  // When set, its address is pre-filled into _addrCtrl and its
  // lat/lng is saved alongside the order in Firestore.
  AppLocation? _deliveryLocation;
  bool _fetchingLocation = false;

  // Cached restaurant reference lat/lng used for the 7 km delivery radius
  // check. Populated once in initState from payload items or Firestore so
  // that _distanceOfAddress always measures restaurant → door, never
  // phone-GPS → door.
  double? _restaurantRefLat;
  double? _restaurantRefLng;

  /// Auto-fill address from GPS / map pick
  Future<void> _useMyLocation({bool fromMap = false}) async {
    AppLocation? loc;
    if (fromMap) {
      loc = await Navigator.push<AppLocation?>(
        context,
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(
            initialLocation: LocationService.instance.current,
            title: 'Choose Delivery Location',
          ),
        ),
      );
    } else {
      setState(() => _fetchingLocation = true);
      loc = await LocationService.instance.fetchCurrentLocation();
      setState(() => _fetchingLocation = false);
      if (loc == null && mounted) {
        _snack(LocationService.instance.error ??
            'Could not fetch location.', _orange);
      }
    }
    if (loc != null && mounted) {
      setState(() {
        _deliveryLocation = loc;
        _addrCtrl.text    = loc!.address;
        // Attempt to parse pincode (last chunk of digits in address)
        final pin = RegExp(r'\b\d{6}\b').firstMatch(loc.address);
        if (pin != null) _pincodeCtrl.text = pin.group(0)!;
        _selectedAddrIdx = -1; // switch to "new address" mode
      });
    }
  }

  // ── Computed ──────────────────────────────────
  double get _subtotal => widget.payload.totalPrice;

  // Personal nutrition sums — uses _myQuantities in group mode
  int get _myCalories {
    if (_orderingMode == 'personal') return widget.payload.totalCalories;
    return widget.payload.items.asMap().entries
        .where((e) => _myItems.contains(e.key))
        .fold(0, (s, e) {
      final qty = _myQuantities[e.key] ?? (e.value['quantity'] as num? ?? 1).toInt();
      return s + ((e.value['calories'] as num? ?? 0) * qty).toInt();
    });
  }

  double get _myProtein {
    if (_orderingMode == 'personal') return widget.payload.totalProtein;
    return widget.payload.items.asMap().entries
        .where((e) => _myItems.contains(e.key))
        .fold(0.0, (s, e) {
      final qty = _myQuantities[e.key] ?? (e.value['quantity'] as num? ?? 1).toInt();
      return s + ((e.value['protein'] as num? ?? 0) * qty).toDouble();
    });
  }

  double get _myCarbs {
    if (_orderingMode == 'personal') return widget.payload.totalCarbs;
    return widget.payload.items.asMap().entries
        .where((e) => _myItems.contains(e.key))
        .fold(0.0, (s, e) {
      final qty = _myQuantities[e.key] ?? (e.value['quantity'] as num? ?? 1).toInt();
      return s + ((e.value['carbs'] as num? ?? 0) * qty).toDouble();
    });
  }

  double get _myFat {
    if (_orderingMode == 'personal') return widget.payload.totalFat;
    return widget.payload.items.asMap().entries
        .where((e) => _myItems.contains(e.key))
        .fold(0.0, (s, e) {
      final qty = _myQuantities[e.key] ?? (e.value['quantity'] as num? ?? 1).toInt();
      return s + ((e.value['fat'] as num? ?? 0) * qty).toDouble();
    });
  }

  double get _delivery  => _subtotal >= 299 ? 0 : 40;
  double get _tax       => (_subtotal - _discount) * 0.05;
  double get _grand     => _subtotal - _discount + _delivery + _tax;

  // [FIX-3] Round to 2dp before converting to paise to avoid IEEE-754 drift
  int get _grandPaise => (double.parse(_grand.toStringAsFixed(2)) * 100).round();

  // ⚠️  REPLACE THIS with your actual key from https://dashboard.razorpay.com
  // Test key starts with  rzp_test_...
  // Live key starts with  rzp_live_...
  static const _razorpayKey = 'rzp_test_SrwAwq325gG7Is';

  // Tracks whether Razorpay sheet is open so lifecycle resume can reset spinner
  bool _razorpayOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRazorpay();
    _loadSavedAddresses();
    _myItems = Set<int>.from(
        List.generate(widget.payload.items.length, (i) => i));
    _myQuantities = {
      for (int i = 0; i < widget.payload.items.length; i++)
        i: (widget.payload.items[i]['quantity'] as num? ?? 1).toInt()
    };


    // ── Pre-load restaurant reference location for 7 km radius check ────
    // This ensures _distanceOfAddress always measures restaurant → door,
    // even when cart/bundle items do not carry an embedded restaurantLocation.
    _loadRestaurantRefLocation();
    // ── Auto-apply promo from Offers section ────────────────────────────
    if (widget.initialPromoCode != null &&
        widget.initialPromoCode!.isNotEmpty) {
      _promoCtrl.text = widget.initialPromoCode!;
      // Short delay so the page has finished building before we call setState
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _applyPromo();
      });
    }
  }

  // ── [FIX-1] Razorpay setup — use official listeners only ──────────
  //
  // The previous version intercepted the raw MethodChannel to work around
  // a PaymentFailureResponse.fromMap crash. This caused conflicts:
  //   • On success: both the channel intercept AND the EVENT_PAYMENT_SUCCESS
  //     listener fired, doubling the _finaliseOrder call.
  //   • On some Android OEM ROMs: the channel intercept swallowed the message
  //     before the plugin could read it, resulting in no callback at all.
  //
  // Fix: remove the channel intercept. Register all three official listeners.
  // Wrap _razorpay.open() in try/catch to handle the PlatformException that
  // the plugin throws for cancellation/error on older SDK versions.
  void _initRazorpay() {
    _razorpay.clear();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,   _onPaymentError);   // [FIX-1] was missing
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  void _handlePaymentCancelled(String message) {
    _razorpayOpen = false;
    if (_pendingOrderId != null) {
      FirebaseFirestore.instance
          .collection('orders')
          .doc(_pendingOrderId)
          .update({'status': 'cancelled', 'paymentStatus': 'failed'})
          .catchError((_) {});
      _pendingOrderId = null;
    }
    if (mounted) {
      setState(() => _placing = false);
      _snack(message, _orange);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app resumes from background (Razorpay sheet closed by pressing
    // X or back), reset the spinner if no payment completed.
    if (state == AppLifecycleState.resumed && _razorpayOpen) {
      _razorpayOpen = false;
      // Small delay so Razorpay's own callback fires first (if any)
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _placing) {
          _handlePaymentCancelled('Payment cancelled. Please try again.');
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _razorpay.clear(); // [FIX-6] no channel handler to remove anymore
    _addrCtrl.dispose();
    _landmarkCtrl.dispose();
    _pincodeCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  // [FIX-5] Keep sync — Razorpay event system does not await async handlers
  void _onPaymentSuccess(PaymentSuccessResponse response) {
    _razorpayOpen = false;
    _finaliseOrder(
      paymentId:     response.paymentId ?? '',
      paymentStatus: 'paid',
      method:        'Razorpay',
    ).catchError((Object e, StackTrace st) {
      debugPrint('_finaliseOrder error after Razorpay success: $e\n$st');
      if (mounted) {
        setState(() => _placing = false);
        _snack(
          'Payment received but order update failed. '
          'Contact support with payment ID: ${response.paymentId ?? "unknown"}',
          _orange,
        );
      }
    });
  }

  // [FIX-1] Proper error handler now registered on the Razorpay instance
  void _onPaymentError(PaymentFailureResponse response) {
    _razorpayOpen = false;
    final message = (response.message?.isNotEmpty == true)
        ? response.message!
        : 'Payment failed. Please try again.';
    _handlePaymentCancelled(message);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _snack('External wallet: ${response.walletName}', _blue);
  }

  Future<void> _loadSavedAddresses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _loadingAddr = false); return; }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final raw = doc.data()?['savedAddresses'];
      if (raw is List) {
        _savedAddresses = raw.cast<Map<String, dynamic>>();
        if (_savedAddresses.isNotEmpty) _selectedAddrIdx = 0;
      }
    } catch (_) {}
    setState(() => _loadingAddr = false);
  }

  // ── Edit a saved address ───────────────────────────────────────────
  Future<void> _editAddress(int index) async {
    final a = _savedAddresses[index];

    // Pre-fill controllers from the saved address
    final editAddrCtrl     = TextEditingController(text: a['address'] ?? '');
    final editLandmarkCtrl = TextEditingController();
    final editPincodeCtrl  = TextEditingController(text: a['pincode'] ?? '');
    String editType        = a['type'] ?? 'Home';
    AppLocation? editLoc   = (a['lat'] != null && a['lng'] != null)
        ? AppLocation(
            lat:       (a['lat'] as num).toDouble(),
            lng:       (a['lng'] as num).toDouble(),
            address:   a['address'] ?? '',
            shortName: a['type'] ?? 'Saved')
        : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Handle ───────────────────────────────────
                  Center(
                    child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                            color: const Color(0xFFE5E5EA),
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  const Text('Edit Address',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 16),

                  // ── Address type chips ──────────────────────
                  Row(
                    children: ['Home', 'Work', 'Other'].map((t) {
                      final sel = editType == t;
                      return GestureDetector(
                        onTap: () => setModal(() => editType = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                              color: sel ? _blue : const Color(0xFFF0F0F5),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(t,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white
                                      : const Color(0xFF6E6E73))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // ── Address field ────────────────────────────
                  _field('Street / Flat / Area *', editAddrCtrl,
                      hint: 'e.g. 42B, HSR Layout',
                      icon: Icons.location_on_outlined),
                  const SizedBox(height: 12),
                  _field('Landmark (optional)', editLandmarkCtrl,
                      hint: 'e.g. Near Apollo Hospital',
                      icon: Icons.place_outlined),
                  const SizedBox(height: 12),
                  _field('Pincode', editPincodeCtrl,
                      hint: '560001',
                      icon: Icons.pin_drop_outlined,
                      keyboardType: TextInputType.number,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ]),
                  const SizedBox(height: 14),

                  // ── Pick on map button ───────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: _blue.withOpacity(0.5), width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final loc = await Navigator.push<AppLocation?>(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => MapPickerScreen(
                              initialLocation: editLoc,
                              title: 'Update Location on Map',
                            ),
                          ),
                        );
                        if (loc != null) {
                          setModal(() {
                            editLoc = loc;
                            editAddrCtrl.text = loc.address;
                            final pin =
                                RegExp(r'\b\d{6}\b').firstMatch(loc.address);
                            if (pin != null) {
                              editPincodeCtrl.text = pin.group(0)!;
                            }
                          });
                        }
                      },
                      icon: Icon(
                          editLoc != null
                              ? Icons.edit_location_alt_rounded
                              : Icons.map_rounded,
                          color: _blue,
                          size: 18),
                      label: Text(
                        editLoc != null
                            ? 'Change Location on Map'
                            : 'Pick Location on Map',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _blue),
                      ),
                    ),
                  ),
                  if (editLoc != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: _green.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded,
                            color: _green, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(editLoc!.shortName,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1C1C1E)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Save button ──────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        if (editAddrCtrl.text.trim().isEmpty) return;
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        final updated = Map<String, dynamic>.from(
                            _savedAddresses[index]);
                        updated['address'] = editAddrCtrl.text.trim();
                        updated['pincode'] = editPincodeCtrl.text.trim();
                        updated['type']    = editType;
                        if (editLoc != null) {
                          updated['lat'] = editLoc!.lat;
                          updated['lng'] = editLoc!.lng;
                        }

                        final newList = List<Map<String, dynamic>>.from(
                            _savedAddresses);
                        newList[index] = updated;

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .update({'savedAddresses': newList});

                        if (mounted) {
                          setState(() {
                            _savedAddresses = newList;
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
                  const SizedBox(height: 12),

                  // ── Delete button ────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: _red.withOpacity(0.5), width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;
                        final newList = List<Map<String, dynamic>>.from(
                            _savedAddresses)
                          ..removeAt(index);
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .update({'savedAddresses': newList});
                        if (mounted) {
                          setState(() {
                            _savedAddresses = newList;
                            if (_selectedAddrIdx >= newList.length) {
                              _selectedAddrIdx =
                                  newList.isEmpty ? -1 : newList.length - 1;
                            }
                          });
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: Icon(Icons.delete_outline_rounded,
                          color: _red, size: 18),
                      label: Text('Remove Address',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _red)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // FIX: defer dispose until after the sheet is fully removed from the tree.
    // Calling dispose() immediately after showModalBottomSheet returns can fire
    // while Flutter's focus/keyboard system still holds a reference to these
    // controllers (e.g. after "Change Location on Map" push/pop), causing:
    //   "A TextEditingController was used after being disposed."
    WidgetsBinding.instance.addPostFrameCallback((_) {
      editAddrCtrl.dispose();
      editLandmarkCtrl.dispose();
      editPincodeCtrl.dispose();
    });
  }

  // ═══════════════════════════════════════════════
  // PROMO — one-time per user enforcement
  // ═══════════════════════════════════════════════
  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _snack('Please log in to apply a promo', _red); return; }

    setState(() => _checkingPromo = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('coupons')
          .where('code', isEqualTo: code)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        setState(() { _appliedPromo = null; _discount = 0; _checkingPromo = false; });
        _snack('Invalid or expired promo code', _red);
        return;
      }

      final doc  = snap.docs.first;
      final data = doc.data();

      // ── Check expiry ────────────────────────────────────────────────────
      final expiryTs = data['expiryDate'];
      if (expiryTs != null) {
        final expiry = (expiryTs as Timestamp).toDate();
        if (DateTime.now().isAfter(expiry)) {
          setState(() { _appliedPromo = null; _discount = 0; _checkingPromo = false; });
          _snack('This coupon has expired', _red);
          return;
        }
      }

      // ── Check if user already used this coupon ──────────────────────────
      final usedBy = List<String>.from(data['usedBy'] as List? ?? []);
      if (usedBy.contains(user.uid)) {
        setState(() { _appliedPromo = null; _discount = 0; _checkingPromo = false; });
        _snack('You\'ve already used this coupon — each code works once per account', _red);
        return;
      }

      final type        = data['type'] ?? 'percent';
      final value       = (data['value'] as num).toDouble();
      final minOrder    = (data['minOrder'] as num? ?? 0).toDouble();
      final maxDiscount = (data['maxDiscount'] as num? ?? 0).toDouble();

      if (minOrder > 0 && _subtotal < minOrder) {
        setState(() { _appliedPromo = null; _discount = 0; _checkingPromo = false; });
        _snack('Min order ₹${minOrder.toStringAsFixed(0)} required', _red);
        return;
      }

      double calculated = type == 'percent'
          ? _subtotal * (value / 100)
          : value;
      if (maxDiscount > 0 && calculated > maxDiscount) calculated = maxDiscount;
      if (calculated > _subtotal) calculated = _subtotal;

      setState(() {
        _appliedPromo  = code;
        _discount      = calculated;
        _checkingPromo = false;
      });
      _snack('Promo applied! You save ₹${_discount.toStringAsFixed(0)} 🎉', _green);
    } catch (e) {
      setState(() { _appliedPromo = null; _discount = 0; _checkingPromo = false; });
      _snack('Could not validate code. Please try again.', _red);
    }
  }

  // ── Restaurant reference location loader ──────────────────────────
  /// Populates [_restaurantRefLat] / [_restaurantRefLng] exactly once.
  ///
  /// Priority:
  ///   1. `restaurantLocation` embedded in any payload item (fastest — no Firestore read).
  ///   2. Fetch `location` from `restaurants/{restaurantId}` in Firestore.
  ///
  /// The phone's live GPS is intentionally NOT used as a fallback, because
  /// that was the root cause of the bypass: the check became
  /// "how far is the delivery address from the user's phone?" which is always
  /// ~0 km when the user is filling in checkout at their current location.
  Future<void> _loadRestaurantRefLocation() async {
    // 1. Try embedded restaurantLocation on any item.
    for (final item in widget.payload.items) {
      final locMap = item['restaurantLocation'] as Map<String, dynamic>?;
      if (locMap != null) {
        final lat = (locMap['lat'] as num?)?.toDouble();
        final lng = (locMap['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          if (mounted) setState(() { _restaurantRefLat = lat; _restaurantRefLng = lng; });
          return;
        }
      }
    }

    // 2. Fetch from Firestore using payload.restaurantId (or first item's restaurantId).
    final rId = (widget.payload.restaurantId?.isNotEmpty == true)
        ? widget.payload.restaurantId!
        : widget.payload.items
            .map((i) => i['restaurantId'] as String? ?? '')
            .firstWhere((id) => id.isNotEmpty, orElse: () => '');

    if (rId.isEmpty) return; // No restaurant ID at all — can't enforce radius.

    try {
      final doc = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(rId)
          .get();
      final locMap = doc.data()?['location'] as Map<String, dynamic>?;
      final lat = (locMap?['lat'] as num?)?.toDouble();
      final lng = (locMap?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null && mounted) {
        setState(() { _restaurantRefLat = lat; _restaurantRefLng = lng; });
      }
    } catch (e) {
      debugPrint('[Checkout] _loadRestaurantRefLocation failed for $rId: $e');
    }
  }

  // ── 7 km delivery radius check ────────────────────────────────────
  /// Returns the Haversine distance (km) between a delivery address and the
  /// restaurant reference point ([_restaurantRefLat] / [_restaurantRefLng]).
  ///
  /// Returns `null` only if the restaurant location could not be resolved
  /// (Firestore fetch failed AND no embedded location).  In that case the
  /// caller skips the radius guard — consistent with the "fail open" policy
  /// used elsewhere.
  ///
  /// ⚠️  We intentionally do NOT fall back to [LocationService.instance.current]
  /// (the phone GPS) here.  Using the phone's live GPS as the reference makes
  /// the check measure "delivery address vs phone location", which is always
  /// ~0 km when the user is typing at their current location — completely
  /// defeating the 7 km restaurant delivery radius.
  double? _distanceOfAddress(Map<String, dynamic> addr) {
    final addrLat = (addr['lat'] as num?)?.toDouble();
    final addrLng = (addr['lng'] as num?)?.toDouble();
    if (addrLat == null || addrLng == null) return null;

    // Use the pre-loaded restaurant reference location.
    final refLat = _restaurantRefLat;
    final refLng = _restaurantRefLng;

    // Reference not yet loaded or unavailable — skip the guard (fail open).
    if (refLat == null || refLng == null) return null;

    const R = 6371.0;
    final dLat = (addrLat - refLat) * (pi / 180);
    final dLng = (addrLng - refLng) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(refLat * pi / 180) *
            cos(addrLat * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Distance (km) between a GPS-picked [AppLocation] and the restaurant.
  double? _distanceOfLocation(AppLocation loc) {
    return _distanceOfAddress({'lat': loc.lat, 'lng': loc.lng});
  }

  bool _validate() {
    switch (_step) {
      case 0:
        if (_selectedAddrIdx == -1) {
          // Manual address — require text + pincode
          if (_addrCtrl.text.trim().isEmpty) {
            _snack('Please enter delivery address', _red);
            return false;
          }
          if (_pincodeCtrl.text.trim().length != 6) {
            _snack('Enter a valid 6-digit pincode', _red);
            return false;
          }
          // [FIX] Require a GPS pin for manual addresses so customerLat/Lng
          // are never 0,0 in the order doc (which blocks the agent's live map).
          if (_deliveryLocation == null) {
            _snack(
              'Please pin your location on the map so the agent can find you.',
              _orange,
            );
            return false;
          }
          // ── 7 km radius guard for GPS-picked / new address ─────────────
          final distNew = _distanceOfLocation(_deliveryLocation!);
          if (distNew != null && distNew > 7.0) {
            _snack(
              'Your delivery location is ${distNew.toStringAsFixed(1)} km away — '
              'we only deliver within 7 km of the restaurant.',
              _red,
            );
            return false;
          }
        } else {
          // Saved address selected — check it has GPS coords stored
          final saved = _savedAddresses[_selectedAddrIdx];
          final savedLat = (saved['lat'] as num?)?.toDouble() ?? 0.0;
          final savedLng = (saved['lng'] as num?)?.toDouble() ?? 0.0;
          if (savedLat == 0.0 && savedLng == 0.0) {
            _snack(
              'This saved address has no GPS pin. '
              'Please edit it and pick your location on the map.',
              _orange,
            );
            return false;
          }
          // ── 7 km radius guard ──────────────────────────────────────────
          final dist = _distanceOfAddress(saved);
          if (dist != null && dist > 7.0) {
            _snack(
              'This address is ${dist.toStringAsFixed(1)} km away — '
              'we only deliver within 7 km of the restaurant.',
              _red,
            );
            return false;
          }
        }
        return true;
      default: return true;
    }
  }

  // [FIX-2] Sanitise phone number for Razorpay contact field
  // Razorpay expects a plain 10-digit number, NOT '+91XXXXXXXXXX'
  String _sanitisePhone(String raw) {
    // Remove all spaces
    String phone = raw.replaceAll(' ', '');
    // Strip leading '+91' (13 chars with +)
    if (phone.startsWith('+91') && phone.length == 13) {
      return phone.substring(3);
    }
    // Strip leading '91' if 12 digits
    if (phone.startsWith('91') && phone.length == 12) {
      return phone.substring(2);
    }
    return phone;
  }

  Future<void> _placeOrder() async {
    if (_placing) return; // prevent double-tap / re-entrant call
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _snack('Please log in', _red); return; }
    setState(() => _placing = true);

    try {
      final userDoc  = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      final userName  = (userData['name'] as String?)?.isNotEmpty == true
          ? userData['name'] as String
          : (user.displayName ?? 'Customer');
      final userEmail = user.email ?? (userData['email'] as String? ?? '');
      final rawPhone  = user.phoneNumber ?? (userData['phone'] as String? ?? '');

      // Store sanitised values for Razorpay prefill
      _prefillName  = userName;
      _prefillEmail = userEmail;
      _prefillPhone = _sanitisePhone(rawPhone); // [FIX-2]

      final deliveryAddress = _selectedAddrIdx >= 0 && _savedAddresses.isNotEmpty
          ? '${_savedAddresses[_selectedAddrIdx]['address']}'
          : '${_addrCtrl.text.trim()}, '
            '${_landmarkCtrl.text.trim()}, '
            '${_pincodeCtrl.text.trim()} ($_addrType)';

      final p = widget.payload;

      // ── Derive unique restaurant IDs and names ──────────────────────
      final restaurantId = (p.restaurantId?.isNotEmpty == true)
          ? p.restaurantId!
          : p.items
              .map((i) => i['restaurantId'] as String? ?? '')
              .firstWhere((id) => id.isNotEmpty, orElse: () => '');

      // GPS coords fetched below after perRestaurantMap is built
      double restLat = 0.0;
      double restLng = 0.0;

      // [FIX] Generate 4-digit delivery OTP
      final otp = (1000 + Random().nextInt(9000)).toString();

      // All unique restaurant names joined (for display everywhere)
      final allRestaurantNames = p.items
          .map((i) => i['restaurantName'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .join(', ');

      // All unique restaurant IDs (for owner portal filtering)
      final allRestaurantIds = p.items
          .map((i) => i['restaurantId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      // ── Per-restaurant item split + subtotal ────────────────────────
      // Each restaurant owner sees only their items and correct subtotal
      final Map<String, Map<String, dynamic>> perRestaurantMap = {};
      for (final item in p.items) {
        final rId   = item['restaurantId'] as String? ?? '';
        final rName = item['restaurantName'] as String? ?? '';
        if (rId.isEmpty) continue;
        perRestaurantMap.putIfAbsent(rId, () => {
          'restaurantId':   rId,
          'restaurantName': rName,
          'subtotal':       0.0,
        });
        final price = (item['price'] as num? ?? 0).toDouble();
        final qty   = (item['quantity'] as num? ?? 1).toInt();
        perRestaurantMap[rId]!['subtotal'] =
            (perRestaurantMap[rId]!['subtotal'] as double) + price * qty;
      }
      // Convert to plain list of maps (no nested Lists — Firestore safe)
      final perRestaurant = perRestaurantMap.values.toList();

      // ── Fetch GPS coords for ALL unique restaurants ─────────────────
      // Build restaurants array: [{id, name, lat, lng}, ...] for multi-stop map
      final List<Map<String, dynamic>> restaurantsList = [];
      for (final entry in perRestaurantMap.entries) {
        final rId   = entry.key;
        final rName = entry.value['restaurantName'] as String? ?? '';
        double rLat = 0.0;
        double rLng = 0.0;
        try {
          final restDoc = await FirebaseFirestore.instance
              .collection('restaurants')
              .doc(rId)
              .get();
          final locMap = restDoc.data()?['location'] as Map<String, dynamic>?;
          rLat = (locMap?['lat'] as num?)?.toDouble() ?? 0.0;
          rLng = (locMap?['lng'] as num?)?.toDouble() ?? 0.0;
        } catch (e) {
          debugPrint('[Checkout] Could not fetch location for $rId: $e');
        }
        restaurantsList.add({'id': rId, 'name': rName, 'lat': rLat, 'lng': rLng});
        // Legacy single-restaurant fields = first restaurant
        if (restaurantsList.length == 1) {
          restLat = rLat;
          restLng = rLng;
        }
      }

      final orderRef = await FirebaseFirestore.instance
          .collection('orders')
          .add({
        'userId':             user.uid,
        'userName':           userName,
        'customerName':       userName, // [FIX] agent dashboard reads 'customerName', not 'userName'
        'restaurantName':     allRestaurantNames,
        if (restaurantId.isNotEmpty) 'restaurantId': restaurantId,
        'restaurantLat':      restLat,
        'restaurantLng':      restLng,
        // Multi-restaurant array — delivery map uses this for all stops
        'restaurants':        restaurantsList,
        'deliveryOtp':        otp,
        // List of all restaurant IDs for owner portal array-contains query
        'restaurantIds':      allRestaurantIds,
        // Per-restaurant breakdown for owner portal correct totals
        'perRestaurant':      perRestaurant,
        'items':              p.items,
        'source':             p.source,
        if (p.bundleId   != null) 'bundleId':   p.bundleId,
        if (p.bundleName != null) 'bundleName': p.bundleName,
        'subtotal':           p.totalPrice,
        'promoCode':          _appliedPromo ?? '',
        'promoDiscount':      _discount,
        'deliveryFee':        _delivery,
        'taxes':              _tax,
        'grandTotal':         _grand,
        'deliveryAddress':    deliveryAddress,
        'customerAddress':    deliveryAddress, // [FIX] agent card reads 'customerAddress'
        'deliverySlot':       _slots[_slotIdx],
        'paymentMethod':      _payMethod == 'cod' ? 'COD' : 'Razorpay',
        'paymentStatus':      _payMethod == 'cod' ? 'pending_cod' : 'pending_payment',
        'status':             'pending',
        'totalCalories':      p.totalCalories,
        'totalProtein':       p.totalProtein,
        'totalCarbs':         p.totalCarbs,
        'totalFat':           p.totalFat,
        // ── GPS delivery location (if user used location pick) ──
        if (_deliveryLocation != null)
          'deliveryLocation': {
            'lat':     _deliveryLocation!.lat,
            'lng':     _deliveryLocation!.lng,
            'address': _deliveryLocation!.address,
          },

        // [FIX] Write flat customerLat/customerLng fields that the delivery
        // agent dashboard reads directly from the order doc. Previously only
        // deliveryLocation:{lat,lng} was written, so the agent always got 0,0
        // and showed "Customer delivery location not set".
        //
        // Priority: GPS-picked location → saved address coords → 0.0 fallback.
        'customerLat': _deliveryLocation?.lat ??
            (_selectedAddrIdx >= 0 && _selectedAddrIdx < _savedAddresses.length
                ? (_savedAddresses[_selectedAddrIdx]['lat'] as num?)?.toDouble() ?? 0.0
                : 0.0),
        'customerLng': _deliveryLocation?.lng ??
            (_selectedAddrIdx >= 0 && _selectedAddrIdx < _savedAddresses.length
                ? (_savedAddresses[_selectedAddrIdx]['lng'] as num?)?.toDouble() ?? 0.0
                : 0.0),
        // [FIX] Embed customer FCM token so delivery agent can push-notify
        // the customer without reading users/{uid} (permission-denied for agents).
        'customerFcmToken':   userData['fcmToken'] as String? ?? '',
        'createdAt':          FieldValue.serverTimestamp(),
      });

      _pendingOrderId = orderRef.id;
      _pendingOtp     = otp;

      // Save new address if entered manually
      if (_selectedAddrIdx == -1 && _addrCtrl.text.trim().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'savedAddresses': [
            ..._savedAddresses,
            {
              'address': '${_addrCtrl.text.trim()}, '
                  '${_landmarkCtrl.text.trim()}, '
                  '${_pincodeCtrl.text.trim()}',
              'type':    _addrType,
              'pincode': _pincodeCtrl.text.trim(),
              // ── Save GPS coords if user used location pick ──
              if (_deliveryLocation != null) ...{
                'lat': _deliveryLocation!.lat,
                'lng': _deliveryLocation!.lng,
              },
            }
          ]
        });
      }

      // Mark coupon as used (fire-and-forget — safe to fail)
      if (_appliedPromo != null) {
        FirebaseFirestore.instance
            .collection('coupons')
            .where('code', isEqualTo: _appliedPromo)
            .limit(1)
            .get()
            .then((snap) {
          if (snap.docs.isNotEmpty) {
            FirebaseFirestore.instance
                .collection('coupons')
                .doc(snap.docs.first.id)
                .update({
              'usedBy':     FieldValue.arrayUnion([user.uid]),
              'usageCount': FieldValue.increment(1),
            });
          }
        }).catchError((_) {});
      }

      if (_payMethod == 'cod') {
        await _finaliseOrder(
            paymentId: '', paymentStatus: 'cod', method: 'COD');
        return;
      }
    } catch (e, st) {
      // Only Firestore / address errors land here.
      // _razorpay.open() is called OUTSIDE this try block because
      // Razorpay internally throws PlatformExceptions for its own
      // navigation that must not be caught here.
      debugPrint('_placeOrder setup error: $e\n$st');
      if (mounted) setState(() => _placing = false);
      _snack('Something went wrong. Please try again.', _red);
      return;
    }

    // ── [FIX-1] Open Razorpay sheet ──────────────────────────────────
    // Wrap in try/catch: older razorpay_flutter versions throw a
    // PlatformException here on some Android devices for cancellation.
    _razorpayOpen = true;
    // [FIX-7] Explicitly type the map and cast amount to int.
    // Razorpay SDK silently ignores the open() call on some Android versions
    // if the amount value is not a strict Dart int.
    final int amountPaise = _grandPaise;
    debugPrint('[Razorpay] open() called — amount=$amountPaise paise, contact=$_prefillPhone');
    try {
      _razorpay.open(<String, dynamic>{
        'key':         _razorpayKey,
        'amount':      amountPaise,
        'name':        'FoodFeast',
        'description': 'Order from ${widget.payload.restaurantName}',
        'currency':    'INR',
        'prefill': <String, String>{
          'name':    _prefillName,
          'email':   _prefillEmail,
          'contact': _prefillPhone,
        },
        'theme': <String, String>{'color': '#0077B6'},
      });
    } on PlatformException catch (e) {
      // Razorpay SDK threw during open (e.g. activity not available)
      debugPrint('Razorpay open PlatformException: $e');
      _handlePaymentCancelled('Could not open payment. Please try again.');
    } catch (e) {
      debugPrint('Razorpay open error: $e');
      _handlePaymentCancelled('Could not open payment. Please try again.');
    }
  }

  Future<void> _finaliseOrder({
    required String paymentId,
    required String paymentStatus,
    required String method,
  }) async {
    // [FIX-4] Capture into local variable before any await to avoid race conditions
    final orderId = _pendingOrderId;
    if (orderId == null) {
      debugPrint(
          '_finaliseOrder: _pendingOrderId is null — aborting. '
          'paymentId=$paymentId');
      if (mounted) {
        setState(() => _placing = false);
        _snack(
          'Order ID missing. Payment was received (ID: $paymentId). '
          'Please contact support.',
          _red,
        );
      }
      return;
    }

    try {
      final p    = widget.payload;
      final user = FirebaseAuth.instance.currentUser!;

      // 1. Mark order as pending (restaurant must accept it)
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update({
        'status':        'pending',
        'paymentStatus': paymentStatus,
        'paymentId':     paymentId,
        'paymentMethod': method,
      });

      await CalorieTracker.instance.addOrderNutrition(
        calories: _myCalories,
        protein:  _myProtein,
        carbs:    _myCarbs,
        fat:      _myFat,
      );

      if (p.source == 'cart') CartProvider.instance.clearCart();
      widget.onOrderSuccess?.call();

      // 2. Notify each restaurant owner separately (fire-and-forget)
      // Build per-restaurant map: restaurantId → {items, subtotal}
      final Map<String, Map<String, dynamic>> perRestaurantMap = {};
      for (final item in p.items) {
        final rId = item['restaurantId'] as String? ?? '';
        if (rId.isEmpty) continue;
        perRestaurantMap.putIfAbsent(rId, () => {
          'items': <Map<String, dynamic>>[],
          'subtotal': 0.0,
        });
        (perRestaurantMap[rId]!['items'] as List).add(item);
        final price = (item['price'] as num? ?? 0).toDouble();
        final qty   = (item['quantity'] as num? ?? 1).toInt();
        perRestaurantMap[rId]!['subtotal'] =
            (perRestaurantMap[rId]!['subtotal'] as double) + price * qty;
      }

      if (perRestaurantMap.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final userName =
            (userDoc.data()?['name'] as String?)?.isNotEmpty == true
                ? userDoc.data()!['name'] as String
                : (user.displayName ?? 'A customer');

        // Send a separate notification to each restaurant
        for (final entry in perRestaurantMap.entries) {
          _sendRestaurantOwnerNotification(
            restaurantId:     entry.key,
            orderId:          orderId,
            userName:         userName,
            restaurantItems:  List<Map<String, dynamic>>.from(entry.value['items'] as List),
            restaurantSubtotal: entry.value['subtotal'] as double,
            deliverySlot:     _slots[_slotIdx],
          );
        }
      }

      if (mounted) {
        setState(() => _placing = false);
        _showSuccessDialog(orderId: orderId, otp: _pendingOtp ?? '');
      }
    } catch (e) {
      debugPrint('_finaliseOrder Firestore error: $e');
      if (mounted) {
        setState(() => _placing = false);
        _snack('Order confirmed but failed to update records.', _red);
      }
    }
  }

  // ── Send push + write Firestore notification for one restaurant ────
  void _sendRestaurantOwnerNotification({
    required String restaurantId,
    required String orderId,
    required String userName,
    required List<Map<String, dynamic>> restaurantItems,
    required double restaurantSubtotal,
    required String deliverySlot,
  }) {
    // Only show items belonging to this restaurant
    final itemSummary = restaurantItems.map((item) {
      final name = item['name'] as String? ?? 'Item';
      final qty  = (item['quantity'] as num? ?? 1).toInt();
      return qty > 1 ? '$name x$qty' : name;
    }).join(', ');

    final title = '🛎️ New Order Received!';
    final body  = '$userName ordered: $itemSummary  •  ₹${restaurantSubtotal.toStringAsFixed(0)}';

    FirebaseFirestore.instance
        .collection('restaurants')
        .doc(restaurantId)
        .get()
        .then((restaurantSnap) async {
      final ownerUid = restaurantSnap.data()?['ownerUid'] as String?;
      if (ownerUid == null || ownerUid.isEmpty) {
        debugPrint('_sendRestaurantOwnerNotification: no ownerUid on '
            'restaurant $restaurantId — skipping.');
        return;
      }

      // ── 1. Write to Firestore (in-app notifications feed) ─────────
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUid':    ownerUid,
        'orderId':      orderId,
        'restaurantId': restaurantId,
        'title':        title,
        'body':         body,
        'type':         'new_order',
        'isRead':       false,
        'deliverySlot': deliverySlot,
        'sentAt':       FieldValue.serverTimestamp(),
      });

      // ── 2. Send FCM push to restaurant owner's device ─────────────
      // Read FCM token from the restaurant doc (publicly readable by any
      // signed-in user). Reading from users/{ownerUid} would fail with
      // [permission-denied] because Firestore rules only allow a user to
      // read their own user doc — a customer cannot read the owner's doc.
      // FcmService.saveToken() writes ownerFcmToken here whenever the
      // restaurant owner opens the app, so this is always up-to-date.
      final fcmToken = restaurantSnap.data()?['ownerFcmToken'] as String?;

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('[FCM] No ownerFcmToken on restaurant $restaurantId — '
            'restaurant owner has not opened the app recently.');
        return;
      }

      await FcmService.sendPushToToken(
        fcmToken: fcmToken,
        title:    title,
        body:     body,
        data: {
          'orderId':      orderId,
          'restaurantId': restaurantId,
          'type':         'new_order',
        },
      );
    }).catchError((Object e) {
      debugPrint('_sendRestaurantOwnerNotification error: $e');
    });
  }

  void _showSuccessDialog({required String orderId, required String otp}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final p = widget.payload;
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: SingleChildScrollView(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                    color: _green.withOpacity(0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded,
                    color: _green, size: 48),
              ),
              const SizedBox(height: 18),
              const Text('Order Confirmed! 🎉',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 4),
              Text('Order #${orderId.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFF6E6E73))),
              const SizedBox(height: 4),
              Text('📍 ${_slots[_slotIdx]}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: _blue,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // OTP card
              if (otp.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: Column(children: [
                    const Text('🔐 Delivery OTP',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E))),
                    const SizedBox(height: 6),
                    Text(
                      otp.split('').join('  '),
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 8,
                          color: Color(0xFFE65100)),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Share with agent at your door.\nAlways visible on the tracking screen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: _blue),
                    ),
                  ]),
                ),

              const SizedBox(height: 16),
              _dialogRow('Subtotal', '₹${_subtotal.toStringAsFixed(0)}'),
              if (_discount > 0)
                _dialogRow('Promo ($_appliedPromo)',
                    '− ₹${_discount.toStringAsFixed(0)}',
                    valueColor: _green),
              _dialogRow(
                  'Delivery',
                  _delivery == 0
                      ? 'FREE'
                      : '₹${_delivery.toStringAsFixed(0)}',
                  valueColor: _delivery == 0 ? _green : null),
              _dialogRow('Taxes (5%)', '₹${_tax.toStringAsFixed(0)}'),
              const Divider(height: 18),
              _dialogRow('Total Paid', '₹${_grand.toStringAsFixed(0)}',
                  bold: true),
              const SizedBox(height: 16),
              if (p.totalCalories > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF9F0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFFFE0B2))),
                  child: Column(children: [
                    const Text('🔥 Added to Today\'s Nutrition Log',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E))),
                    const SizedBox(height: 10),
                    Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _macroCell('🔥', 'Cal', '$_myCalories',
                              _orange),
                          _macroCell('💪', 'Protein',
                              '${_myProtein.toStringAsFixed(0)}g',
                              const Color(0xFF007AFF)),
                          _macroCell('🌾', 'Carbs',
                              '${_myCarbs.toStringAsFixed(0)}g',
                              _green),
                          _macroCell('🥑', 'Fat',
                              '${_myFat.toStringAsFixed(0)}g', _blue),
                        ]),
                  ]),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0),
                  onPressed: () {
                    // Pop the success dialog + the entire CheckoutScreen so
                    // pressing Back from OrderTracking goes to Home (or the
                    // screen that launched checkout), not back to checkout.
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => OrderTrackingScreen(orderId: orderId),
                      ),
                      (route) => route.isFirst,
                    );
                  },
                  icon: const Icon(Icons.location_on_rounded,
                      color: Colors.white, size: 18),
                  label: const Text('Track My Order',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 44,
                child: TextButton(
                  onPressed: () => Navigator.of(context)..pop()..pop(),
                  child: const Text('Close',
                      style: TextStyle(
                          color: _blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
          ), // SingleChildScrollView
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Checkout',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E))),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _StepBar(current: _step),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0.05, 0),
                            end: Offset.zero)
                        .animate(anim),
                    child: child)),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _buildStep(),
              ),
            ),
          ),
        ),
        _buildBottomBar(),
      ]),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _buildAddress();
      case 1: return _buildSlot();
      case 2: return _buildPayment();
      case 3: return _buildReview();
      default: return const SizedBox.shrink();
    }
  }

  // ─── Step 0: Address ────────────────────────
  Widget _buildAddress() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('📍 Delivery Address'),
      const SizedBox(height: 14),
      if (_loadingAddr)
        const Center(child: CircularProgressIndicator())
      else ...[
        if (_savedAddresses.isNotEmpty) ...[
          _label('Saved addresses'),
          const SizedBox(height: 8),
          ..._savedAddresses.asMap().entries.map((e) {
            final sel = _selectedAddrIdx == e.key;
            final a   = e.value;
            final hasCoords = a['lat'] != null && a['lng'] != null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    final dist = _distanceOfAddress(a);
                    if (dist != null && dist > 7.0) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Row(children: [
                          const Icon(Icons.location_off_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cannot deliver here — this address is '
                              '${dist.toStringAsFixed(1)} km away '
                              '(max 7 km from the restaurant).',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ]),
                        backgroundColor: _red,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 4),
                      ));
                      return;
                    }
                    setState(() => _selectedAddrIdx = e.key);
                  },
                  child: _selectable(
                    selected: sel,
                    child: Row(children: [
                      Icon(
                          a['type'] == 'Work'
                              ? Icons.work_rounded
                              : a['type'] == 'Other'
                                  ? Icons.location_on_rounded
                                  : Icons.home_rounded,
                          color: sel ? _blue : const Color(0xFF6E6E73),
                          size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(a['type'] ?? 'Address',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: sel
                                        ? _blue
                                        : const Color(0xFF1C1C1E))),
                            const SizedBox(height: 2),
                            Text(a['address'] ?? '',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6E6E73)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            // ── Distance badge ─────────────────────
                            Builder(builder: (_) {
                              final dist = _distanceOfAddress(a);
                              if (dist == null) return const SizedBox.shrink();
                              final tooFar = dist > 7.0;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(children: [
                                  Icon(
                                    tooFar
                                        ? Icons.location_off_rounded
                                        : Icons.check_circle_outline_rounded,
                                    size: 11,
                                    color: tooFar ? _red : _green,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    tooFar
                                        ? '${dist.toStringAsFixed(1)} km — outside delivery range'
                                        : '${dist.toStringAsFixed(1)} km — in range ✓',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: tooFar ? _red : _green,
                                    ),
                                  ),
                                ]),
                              );
                            }),
                          ])),
                      // ── Edit button ────────────────────────
                      GestureDetector(
                        onTap: () => _editAddress(e.key),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              color: _blue, size: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (sel)
                        const Icon(Icons.check_circle_rounded,
                            color: _blue, size: 18),
                    ]),
                  ),
                ),
                // ── Mini map preview when this address is selected ──
                if (sel && hasCoords) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 140,
                      child: Stack(children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                                (a['lat'] as num).toDouble(),
                                (a['lng'] as num).toDouble()),
                            initialZoom: 15,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none, // read-only
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.foodfeast.app',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: LatLng(
                                    (a['lat'] as num).toDouble(),
                                    (a['lng'] as num).toDouble()),
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_pin,
                                    color: Color(0xFFFF3B30), size: 36),
                              ),
                            ]),
                          ],
                        ),
                        // Tap overlay — opens full map picker to repin
                        Positioned(
                          bottom: 8, right: 8,
                          child: GestureDetector(
                            onTap: () => _editAddress(e.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 8)
                                ],
                              ),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_location_alt_rounded,
                                        size: 13, color: _blue),
                                    SizedBox(width: 4),
                                    Text('Edit',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: _blue)),
                                  ]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            );
          }),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _selectedAddrIdx = -1),
            child: _selectable(
              selected: _selectedAddrIdx == -1,
              child: Row(children: [
                Icon(Icons.add_location_alt_rounded,
                    color: _selectedAddrIdx == -1
                        ? _blue
                        : const Color(0xFF6E6E73),
                    size: 20),
                const SizedBox(width: 10),
                Text('Add a new address',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedAddrIdx == -1
                            ? _blue
                            : const Color(0xFF1C1C1E))),
              ]),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_selectedAddrIdx == -1)
          _card(Column(children: [
            // ── Location quick-fill buttons ────────────────
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: _fetchingLocation
                      ? null
                      : () => _useMyLocation(fromMap: false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _blue.withOpacity(0.25), width: 1.2),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      if (_fetchingLocation)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: _blue, strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.my_location_rounded,
                            color: _blue, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _fetchingLocation ? 'Detecting…' : 'Use GPS',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _blue),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _useMyLocation(fromMap: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFE5E5EA), width: 1.2),
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.map_rounded,
                          color: Color(0xFF1C1C1E), size: 16),
                      SizedBox(width: 6),
                      Text('Pick on Map',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E))),
                    ]),
                  ),
                ),
              ),
            ]),
            // Show confirmed location badge if set
            if (_deliveryLocation != null) ...[
              const SizedBox(height: 10),
              Builder(builder: (_) {
                final dist = _distanceOfLocation(_deliveryLocation!);
                final tooFar = dist != null && dist > 7.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tooFar
                            ? _red.withOpacity(0.06)
                            : _green.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: tooFar
                                ? _red.withOpacity(0.3)
                                : _green.withOpacity(0.3),
                            width: 1),
                      ),
                      child: Row(children: [
                        Icon(
                          tooFar
                              ? Icons.location_off_rounded
                              : Icons.check_circle_rounded,
                          color: tooFar ? _red : _green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '📍 ${_deliveryLocation!.shortName}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: tooFar
                                        ? _red
                                        : const Color(0xFF1C1C1E)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (dist != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  tooFar
                                      ? '${dist.toStringAsFixed(1)} km — outside delivery range (max 7 km)'
                                      : '${dist.toStringAsFixed(1)} km from restaurant — in range ✓',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: tooFar ? _red : _green,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ]),
                    ),
                    if (tooFar) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: _orange.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: _orange.withOpacity(0.3)),
                        ),
                        child: const Row(children: [
                          Icon(Icons.info_outline_rounded,
                              color: _orange, size: 14),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Choose a location closer to the restaurant, '
                              'or update your delivery address on the home screen.',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: _orange,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ],
                );
              }),
            ],
            const SizedBox(height: 14),
            // ── Address type chips ──────────────────────────
            Row(
                children: ['Home', 'Work', 'Other'].map((t) {
              final sel = _addrType == t;
              return GestureDetector(
                onTap: () => setState(() => _addrType = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: sel ? _blue : const Color(0xFFF0F0F5),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(t,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? Colors.white
                              : const Color(0xFF6E6E73))),
                ),
              );
            }).toList()),
            const SizedBox(height: 14),
            _field('Street / Flat / Area *', _addrCtrl,
                hint: 'e.g. 42B, HSR Layout, 7th Sector',
                icon: Icons.location_on_outlined),
            const SizedBox(height: 12),
            _field('Landmark (optional)', _landmarkCtrl,
                hint: 'e.g. Near Apollo Hospital',
                icon: Icons.place_outlined),
            const SizedBox(height: 12),
            _field('Pincode *', _pincodeCtrl,
                hint: '560001',
                icon: Icons.pin_drop_outlined,
                keyboardType: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ]),
          ])),
      ],
    ]);
  }

  // ─── Step 1: Slot ────────────────────────────
  Widget _buildSlot() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('🕐 Choose Delivery Slot'),
      const SizedBox(height: 14),
      ..._slots.asMap().entries.map((e) => GestureDetector(
            onTap: () => setState(() => _slotIdx = e.key),
            child: _selectable(
              selected: _slotIdx == e.key,
              child: Row(children: [
                Icon(
                    e.key == 0
                        ? Icons.flash_on_rounded
                        : Icons.schedule_rounded,
                    color: _slotIdx == e.key
                        ? _blue
                        : const Color(0xFF6E6E73),
                    size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(e.value,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _slotIdx == e.key
                                ? _blue
                                : const Color(0xFF1C1C1E)))),
                if (_slotIdx == e.key)
                  const Icon(Icons.check_circle_rounded,
                      color: _blue, size: 18),
              ]),
            ),
          )),
    ]);
  }

  // ─── Step 2: Payment ────────────────────────
  Widget _buildPayment() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('💳 Payment Method'),
      const SizedBox(height: 14),

      GestureDetector(
        onTap: () => setState(() => _payMethod = 'razorpay'),
        child: _selectable(
          selected: _payMethod == 'razorpay',
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: const Color(0xFF002970).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.payment_rounded,
                  color: Color(0xFF002970), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                  Text('UPI / Card / NetBanking / Wallets',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  Text('Powered by Razorpay — safe & instant',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFF6E6E73))),
                ])),
            if (_payMethod == 'razorpay')
              const Icon(Icons.check_circle_rounded,
                  color: _blue, size: 20),
          ]),
        ),
      ),
      const SizedBox(height: 10),

      GestureDetector(
        onTap: () => setState(() => _payMethod = 'cod'),
        child: _selectable(
          selected: _payMethod == 'cod',
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: _green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.payments_rounded,
                  color: _green, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                  Text('Cash on Delivery',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  Text('Pay when your order arrives',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFF6E6E73))),
                ])),
            if (_payMethod == 'cod')
              const Icon(Icons.check_circle_rounded,
                  color: _blue, size: 20),
          ]),
        ),
      ),

      const SizedBox(height: 20),
      _header('🏷️ Promo Code'),
      const SizedBox(height: 10),
      _card(Row(children: [
        Expanded(
          child: TextField(
            controller: _promoCtrl,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: Color(0xFF1C1C1E)),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Enter promo code',
              hintStyle: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFFAEAEB2),
                  letterSpacing: 0),
              prefixIcon: const Icon(Icons.local_offer_outlined,
                  size: 18, color: _blue),
              filled: true,
              fillColor: const Color(0xFFF5F5F7),
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFFE5E5EA))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFFE5E5EA))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _blue, width: 1.8)),
              suffixIcon: _appliedPromo != null
                  ? const Icon(Icons.check_circle_rounded,
                      color: _green, size: 20)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _checkingPromo ? null : _applyPromo,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
                color: _blue,
                borderRadius: BorderRadius.circular(12)),
            child: _checkingPromo
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Apply',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ])),
      if (_appliedPromo != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: _green, size: 14),
          const SizedBox(width: 6),
          Text(
              '"$_appliedPromo" — you save ₹${_discount.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 12,
                  color: _green,
                  fontWeight: FontWeight.w600)),
        ]),
      ],
    ]);
  }

  // ─── Step 3: Review ──────────────────────────
  Widget _buildReview() {
    final p = widget.payload;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('📋 Order Summary'),
      const SizedBox(height: 14),

      // Items list
      _card(Column(
          children: p.items
              .map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      if ((item['imageUrl'] as String? ?? '').isNotEmpty)
                        ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                                item['imageUrl'] as String,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _imgBox(44)))
                      else
                        _imgBox(44),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            Text(
                              '${item['name']}'
                              '${(item['portion'] as String?)?.isNotEmpty == true ? ' (${item['portion']})' : ''}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1C1C1E)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                            Text('Qty: ${item['quantity']}',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF6E6E73))),
                          ])),
                      Text(
                          '₹${((item['price'] as num? ?? 0) * (item['quantity'] as num? ?? 1)).toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _blue)),
                    ]),
                  ))
              .toList())),
      const SizedBox(height: 12),

      // Delivery & payment summary
      _card(Column(children: [
        _reviewRow(
            Icons.location_on_rounded,
            'Delivering to',
            _selectedAddrIdx >= 0 && _savedAddresses.isNotEmpty
                ? '${_savedAddresses[_selectedAddrIdx]['type']}: '
                    '${_savedAddresses[_selectedAddrIdx]['address']}'
                : '${_addrCtrl.text}, ${_pincodeCtrl.text}'),
        const Divider(height: 18, color: Color(0xFFF0F0F5)),
        _reviewRow(
            Icons.schedule_rounded, 'Delivery slot', _slots[_slotIdx]),
        const Divider(height: 18, color: Color(0xFFF0F0F5)),
        _reviewRow(Icons.payment_rounded, 'Payment',
            _payMethod == 'cod' ? 'Cash on Delivery' : 'Online (Razorpay)'),
      ])),
      const SizedBox(height: 12),

      // Bill
      _card(Column(children: [
        _billRow('Subtotal', '₹${_subtotal.toStringAsFixed(0)}'),
        if (_discount > 0)
          _billRow('Promo ($_appliedPromo)',
              '− ₹${_discount.toStringAsFixed(0)}',
              color: _green),
        _billRow(
            'Delivery fee',
            _delivery == 0 ? 'FREE' : '₹${_delivery.toStringAsFixed(0)}',
            color: _delivery == 0 ? _green : null),
        _billRow('Taxes (5%)', '₹${_tax.toStringAsFixed(0)}'),
        const Divider(height: 20),
        _billRow('Total', '₹${_grand.toStringAsFixed(0)}', bold: true),
      ])),

      // Ordering mode
      const SizedBox(height: 16),
      _header('👥 Who is this order for?'),
      const SizedBox(height: 10),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _modeChip('personal', '🙋 Just Me', 'Track all items'),
          const SizedBox(width: 10),
          _modeChip('group', '👨‍👩‍👧‍👦 Group Order', "Pick what I'm eating"),
        ]),

        // Per-item quantity steppers in group mode
        if (_orderingMode == 'group') ...[
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF0F0F5)),
          const SizedBox(height: 10),
          const Text('Select items YOU are eating & adjust quantity:',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E6E73))),
          const SizedBox(height: 8),
          ...p.items.asMap().entries.map((e) {
            final idx    = e.key;
            final item   = e.value;
            final isMine = _myItems.contains(idx);
            final maxQty = (item['quantity'] as num? ?? 1).toInt();
            final myQty  = _myQuantities[idx] ?? maxQty;
            final cal    = ((item['calories'] as num? ?? 0) * myQty).toInt();

            return GestureDetector(
              onTap: () => setState(() {
                if (isMine) {
                  _myItems.remove(idx);
                  _myQuantities[idx] = 0;
                } else {
                  _myItems.add(idx);
                  _myQuantities[idx] = maxQty;
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isMine
                      ? _blue.withOpacity(0.06)
                      : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isMine ? _blue : const Color(0xFFE5E5EA),
                      width: isMine ? 1.8 : 1),
                ),
                child: Column(children: [
                  Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: isMine ? _blue : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: isMine
                                ? _blue
                                : const Color(0xFFCCCCCC),
                            width: 1.5),
                      ),
                      child: isMine
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    if ((item['imageUrl'] as String? ?? '').isNotEmpty)
                      ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                              item['imageUrl'] as String,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _imgBox(36)))
                    else
                      _imgBox(36),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          Text(
                            '${item['name']}'
                            '${(item['portion'] as String?)?.isNotEmpty == true ? ' (${item['portion']})' : ''}',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isMine
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFF9E9E9E)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('Total qty ordered: $maxQty',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF6E6E73))),
                        ])),
                    if (isMine && cal > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: _orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('🔥 $cal',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _orange)),
                      ),
                  ]),

                  // Quantity stepper
                  if (isMine) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Text('My qty:',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6E6E73),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          if (myQty <= 1) return;
                          setState(() => _myQuantities[idx] = myQty - 1);
                        },
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: myQty <= 1
                                ? const Color(0xFFF0F0F5)
                                : _blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: myQty <= 1
                                    ? const Color(0xFFE0E0E0)
                                    : _blue.withOpacity(0.4)),
                          ),
                          child: Icon(Icons.remove_rounded,
                              size: 16,
                              color: myQty <= 1
                                  ? const Color(0xFFCCCCCC)
                                  : _blue),
                        ),
                      ),
                      Container(
                        width: 44,
                        alignment: Alignment.center,
                        child: Text('$myQty',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1C1C1E))),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (myQty >= maxQty) return;
                          setState(() => _myQuantities[idx] = myQty + 1);
                        },
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: myQty >= maxQty
                                ? const Color(0xFFF0F0F5)
                                : _blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: myQty >= maxQty
                                    ? const Color(0xFFE0E0E0)
                                    : _blue.withOpacity(0.4)),
                          ),
                          child: Icon(Icons.add_rounded,
                              size: 16,
                              color: myQty >= maxQty
                                  ? const Color(0xFFCCCCCC)
                                  : _blue),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('of $maxQty',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFAEAEB2))),
                    ]),
                  ],
                ]),
              ),
            );
          }),

          // Quick-select helpers
          const SizedBox(height: 4),
          Row(children: [
            GestureDetector(
              onTap: () => setState(() {
                _myItems = Set.from(
                    List.generate(p.items.length, (i) => i));
                for (int i = 0; i < p.items.length; i++) {
                  _myQuantities[i] =
                      (p.items[i]['quantity'] as num? ?? 1).toInt();
                }
              }),
              child: const Text('Select all',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: _blue,
                      fontWeight: FontWeight.w600)),
            ),
            const Text(' · ',
                style: TextStyle(color: Color(0xFFCCCCCC))),
            GestureDetector(
              onTap: () => setState(() {
                _myItems = {};
                for (int i = 0; i < p.items.length; i++) {
                  _myQuantities[i] = 0;
                }
              }),
              child: const Text('Clear all',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF6E6E73),
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
      ])),

      // Nutrition summary
      if (p.totalCalories > 0) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF9F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE0B2))),
          child: Column(children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      _orderingMode == 'personal'
                          ? '🔥 Nutrition in this order'
                          : '🔥 My nutrition (${_myItems.length} '
                            'item${_myItems.length == 1 ? '' : 's'})',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  if (_orderingMode == 'group')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('Only these log to stats',
                          style: TextStyle(
                              fontSize: 10,
                              color: _blue,
                              fontWeight: FontWeight.w600)),
                    ),
                ]),
            const SizedBox(height: 12),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _macroCell(
                      '🔥', 'Cal', '$_myCalories', _orange),
                  _macroCell('💪', 'Protein',
                      '${_myProtein.toStringAsFixed(0)}g',
                      const Color(0xFF007AFF)),
                  _macroCell('🌾', 'Carbs',
                      '${_myCarbs.toStringAsFixed(0)}g', _green),
                  _macroCell('🥑', 'Fat',
                      '${_myFat.toStringAsFixed(0)}g', _blue),
                ]),
            if (_orderingMode == 'group' && _myItems.isEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                  '⚠️ No items selected — nothing will be logged.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFFF9500),
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 80),
    ]);
  }

  Widget _modeChip(String mode, String title, String subtitle) {
    final selected = _orderingMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _orderingMode = mode;
          if (mode == 'personal') {
            _myItems = Set.from(
                List.generate(widget.payload.items.length, (i) => i));
            for (int i = 0; i < widget.payload.items.length; i++) {
              _myQuantities[i] =
                  (widget.payload.items[i]['quantity'] as num? ?? 1)
                      .toInt();
            }
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? _blue.withOpacity(0.07)
                : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? _blue : const Color(0xFFE5E5EA),
                width: selected ? 1.8 : 1),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? _blue : const Color(0xFF1C1C1E))),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6E6E73))),
          ]),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isLast = _step == 3;
    final btnLabel = isLast
        ? (_payMethod == 'cod'
            ? 'Place Order (COD) • ₹${_grand.toStringAsFixed(0)}'
            : 'Pay ₹${_grand.toStringAsFixed(0)} via Razorpay')
        : ['Go to Slot →', 'Go to Payment →', 'Review Order →'][_step];

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, -4))
          ]),
      child: Row(children: [
        if (_step > 0) ...[
          GestureDetector(
            onTap: () => setState(() => _step--),
            child: Container(
              width: 48, height: 52,
              decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: const Color(0xFFE5E5EA))),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  size: 18, color: Color(0xFF1C1C1E)),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (!_validate()) return;
              if (isLast) {
                _placeOrder();
              } else {
                setState(() => _step++);
              }
            },
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF0077B6), Color(0xFF00B4D8)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: _blue.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]),
              child: Center(
                child: _placing
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text(btnLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Helpers ──────────────────────────────────
  Widget _header(String t) => Text(t,
      style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1C1C1E)));

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12.5,
          color: Color(0xFF6E6E73),
          fontWeight: FontWeight.w600));

  Widget _card(Widget child) => Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ]),
      child: child);

  Widget _selectable({
    required bool selected,
    required Widget child,
    EdgeInsets margin = const EdgeInsets.only(bottom: 8),
  }) =>
      AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: margin,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: selected ? _blue.withOpacity(0.06) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected ? _blue : const Color(0xFFE5E5EA),
                  width: selected ? 2 : 1)),
          child: child);

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String hint = '',
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? formatters,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF1C1C1E)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                fontSize: 13, color: Color(0xFFAEAEB2)),
            prefixIcon: icon != null
                ? Icon(icon, size: 18, color: _blue)
                : null,
            filled: true,
            fillColor: const Color(0xFFF5F5F7),
            contentPadding: const EdgeInsets.symmetric(
                vertical: 12, horizontal: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E5EA))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E5EA))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: _blue, width: 1.8)),
          ),
        ),
      ]);

  Widget _reviewRow(IconData icon, String label, String value) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: _blue),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6E6E73))),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E))),
            ])),
      ]);

  Widget _billRow(String label, String value,
          {Color? color, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: bold
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFF6E6E73),
                      fontWeight:
                          bold ? FontWeight.w700 : FontWeight.w400)),
              Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          bold ? FontWeight.w800 : FontWeight.w600,
                      color: color ?? const Color(0xFF1C1C1E))),
            ]),
      );

  Widget _dialogRow(String label, String value,
          {Color? valueColor, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6E6E73))),
              Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          bold ? FontWeight.w800 : FontWeight.w600,
                      color: valueColor ?? const Color(0xFF1C1C1E))),
            ]),
      );

  Widget _macroCell(
          String emoji, String label, String value, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF6E6E73))),
      ]);

  Widget _imgBox(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: _blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(Icons.fastfood_rounded,
          color: _blue, size: size * 0.45));

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3)));
  }
}

// ─────────────────────────────────────────────
// Step indicator bar
// ─────────────────────────────────────────────
class _StepBar extends StatelessWidget {
  final int current;
  const _StepBar({required this.current});
  static const _blue   = Color(0xFF0077B6);
  static const _labels = ['Address', 'Slot', 'Payment', 'Review'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: List.generate(8, (i) {
          if (i.isOdd) {
            final done = (i ~/ 2) < current;
            return Expanded(
                child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 3,
              decoration: BoxDecoration(
                  color: done ? _blue : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(2)),
            ));
          }
          final idx    = i ~/ 2;
          final done   = idx < current;
          final active = idx == current;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: active ? 28 : 22,
              height: active ? 28 : 22,
              decoration: BoxDecoration(
                  color: done || active ? _blue : const Color(0xFFE5E5EA),
                  shape: BoxShape.circle),
              child: Center(
                  child: done
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 13)
                      : Text('${idx + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF9E9E9E)))),
            ),
            const SizedBox(height: 3),
            Text(_labels[idx],
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? _blue : const Color(0xFF9E9E9E))),
          ]);
        }),
      ),
    );
  }
}