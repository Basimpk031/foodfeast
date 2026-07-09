// ─────────────────────────────────────────────
// orders_screen.dart — FoodFeast
// Updated: cancel order (before 'preparing')
//          calorie/macro reduction on cancel
//          cancellation policy note in order details
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'calorie_tracker.dart';
import 'order_tracking_screen.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  static const _red = Color(0xFF0077B6);

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':         return const Color(0xFF007AFF);
      case 'preparing':         return const Color(0xFF5856D6);
      case 'ready_for_pickup':  return const Color(0xFFFF6B00);
      case 'picked_up':         return const Color(0xFF0077B6);
      case 'out_for_delivery':  return const Color(0xFF0077B6);
      case 'delivered':         return const Color(0xFF34C759);
      case 'cancelled':         return _red;
      default:                  return const Color(0xFF6E6E73); // pending
    }
  }

  String _statusEmoji(String s) {
    switch (s) {
      case 'confirmed':         return '✅';
      case 'preparing':         return '👨‍🍳';
      case 'ready_for_pickup':  return '🛵';
      case 'picked_up':         return '📦';
      case 'out_for_delivery':  return '🚀';
      case 'delivered':         return '🎉';
      case 'cancelled':         return '❌';
      default:                  return '🕐'; // pending
    }
  }

  String _fmt(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'My Orders',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1C1C1E)),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Please login to see orders'))
          : StreamBuilder<QuerySnapshot>(
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

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('😕', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text('Error: ${snapshot.error}',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF6E6E73))),
                      ],
                    ),
                  );
                }

                // Sort client-side by createdAt descending
                final docs = List<QueryDocumentSnapshot>.from(
                    snapshot.data?.docs ?? []);
                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTs = aData['createdAt'];
                  final bTs = bData['createdAt'];
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  try {
                    return (bTs as dynamic)
                        .toDate()
                        .compareTo((aTs as dynamic).toDate());
                  } catch (_) {
                    return 0;
                  }
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('📦', style: TextStyle(fontSize: 64)),
                        SizedBox(height: 16),
                        Text('No orders yet',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E))),
                        SizedBox(height: 8),
                        Text('Your orders will appear here',
                            style: TextStyle(
                                fontSize: 14, color: Color(0xFF6E6E73))),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc  = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return _OrderCard(
                      orderId: doc.id,
                      data: data,
                      statusColor: _statusColor,
                      statusEmoji: _statusEmoji,
                      fmt: _fmt,
                    );
                  },
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Order Card — expandable with cancel support + policy note
// ─────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final Color Function(String) statusColor;
  final String Function(String) statusEmoji;
  final String Function(dynamic) fmt;

  const _OrderCard({
    required this.orderId,
    required this.data,
    required this.statusColor,
    required this.statusEmoji,
    required this.fmt,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  bool _expanded       = false;
  bool _cancelling     = false;
  bool _submittingRefund = false;

  bool get _canCancel {
    final status = widget.data['status'] ?? 'pending';
    return status == 'pending' || status == 'confirmed';
  }

  bool get _canRequestRefund {
    final status        = widget.data['status']        ?? '';
    final paymentMethod = widget.data['paymentMethod'] ?? '';
    final alreadyRequested = widget.data['refundRequested'] == true;
    return status == 'delivered' &&
        paymentMethod != 'COD' &&
        !alreadyRequested;
  }

  Future<void> _showRefundSheet() async {
    String? selectedReason;
    final accountCtrl = TextEditingController();
    const reasons = [
      'Wrong item delivered',
      'Item missing',
      'Poor quality',
      'Other',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (_, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 24,
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Request a Refund',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 4),
                  const Text('Our team will review and contact you within 24 hrs.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6E6E73))),
                  const SizedBox(height: 18),

                  // Reason dropdown
                  const Text('Reason',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    hint: const Text('Select a reason',
                        style: TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF2F2F7),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    items: reasons
                        .map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setSheet(() => selectedReason = v),
                  ),
                  const SizedBox(height: 16),

                  // Refund account field
                  const Text('Refund Account (UPI ID or Bank Account)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: accountCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. name@upi or account number',
                      hintStyle: const TextStyle(
                          fontSize: 13, color: Color(0xFF6E6E73)),
                      filled: true,
                      fillColor: const Color(0xFFF2F2F7),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9500),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: _submittingRefund
                          ? null
                          : () async {
                              if (selectedReason == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Please select a reason.'),
                                      behavior: SnackBarBehavior.floating),
                                );
                                return;
                              }
                              if (accountCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Please enter your refund account.'),
                                      behavior: SnackBarBehavior.floating),
                                );
                                return;
                              }
                              Navigator.pop(sheetCtx);
                              setState(() => _submittingRefund = true);
                              try {
                                final db  = FirebaseFirestore.instance;
                                final uid = FirebaseAuth.instance.currentUser?.uid;
                                final name = FirebaseAuth.instance.currentUser?.displayName ?? 'User';
                                final grandTotal = (widget.data['grandTotal'] ?? widget.data['total'] ?? 0) as num;

                                await db.collection('support_tickets').add({
                                  'type':           'refund_request',
                                  'issueType':      'Refund Request',
                                  'refundReason':   selectedReason,
                                  'refundAccount':  accountCtrl.text.trim(),
                                  'orderAmount':    grandTotal.toDouble(),
                                  'orderId':        widget.orderId,
                                  'restaurantName': widget.data['restaurantName'] ?? '',
                                  'userName':       name,
                                  'userId':         uid,
                                  'status':         'open',
                                  'createdAt':      FieldValue.serverTimestamp(),
                                });

                                await db
                                    .collection('orders')
                                    .doc(widget.orderId)
                                    .update({'refundRequested': true});

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Refund request submitted. Admin will contact you.'),
                                      backgroundColor: _green,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to submit: $e'),
                                      backgroundColor: _red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _submittingRefund = false);
                              }
                            },
                      child: _submittingRefund
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Text('Submit Refund Request',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    accountCtrl.dispose();
  }

  String _statusDisplayLabel(String s) {
    switch (s) {
      case 'pending':          return 'Pending';
      case 'confirmed':        return 'Confirmed';
      case 'preparing':        return 'Preparing';
      case 'ready_for_pickup': return 'Ready for Pickup';
      case 'picked_up':        return 'Picked Up';
      case 'out_for_delivery': return 'On the Way';
      case 'delivered':        return 'Delivered';
      case 'cancelled':        return 'Cancelled';
      default: return s[0].toUpperCase() + s.substring(1);
    }
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
      // 1. Update order status
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
          calories: newCal,
          protein:  newPro,
          carbs:    newCarb,
          fat:      newFat,
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
    final isBundle    = widget.data['isBundle'] == true;
    final bundleName  = widget.data['bundleName'] as String? ?? '';
    final calories    = widget.data['totalCalories'] ?? 0;
    final protein     = (widget.data['totalProtein'] ?? 0).toDouble();
    final carbs       = (widget.data['totalCarbs']   ?? 0).toDouble();
    final fat         = (widget.data['totalFat']     ?? 0).toDouble();
    final statusColor = widget.statusColor(status);

    // ── Restaurant name(s): always show ALL restaurants in the order ──
    String restName;
    final rawRestName = widget.data['restaurantName'] as String? ?? '';
    if (rawRestName.isNotEmpty) {
      // New orders: already has all names joined e.g. "Pizza Hub, Burger King"
      restName = rawRestName;
    } else {
      // Old orders: derive from items
      final names = items
          .map((i) => (i as Map<String, dynamic>)['restaurantName'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      restName = names.isEmpty ? '' : names.join(', ');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 4))
          ],
          border: Border.all(color: const Color(0xFFF0F0F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row ──────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(children: [
              Text(widget.statusEmoji(status),
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Order ID + Bundle badge
                  Row(children: [
                    Text(
                        'Order #${widget.orderId.substring(0, 6).toUpperCase()}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1C1E))),
                    if (isBundle) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('📦', style: TextStyle(fontSize: 9)),
                          const SizedBox(width: 3),
                          Text(
                            bundleName.isNotEmpty ? bundleName : 'Bundle',
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF8B5CF6)),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  // Restaurant name(s) with store icon
                  if (restName.isNotEmpty)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.storefront_rounded,
                          size: 12, color: _red),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(restName,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _red)),
                      ),
                    ]),
                  if (widget.fmt(widget.data['createdAt']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(widget.fmt(widget.data['createdAt']),
                          style: const TextStyle(
                              fontSize: 10.5, color: Color(0xFFAEAEB2))),
                    ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    _statusDisplayLabel(status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text('₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _red)),
              ]),
            ]),
          ),
        ),

        // ── Expand / collapse indicator ──────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: const Color(0xFF6E6E73)),
              const SizedBox(width: 4),
              Text(_expanded ? 'Hide details' : 'View details',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E6E73),
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ),

        // ── Expanded details ─────────────────────
        if (_expanded) ...[
          const Divider(height: 1, indent: 14, endIndent: 14),

          // Items list
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(
                children: items.map<Widget>((item) {
                  final iMap    = item as Map<String, dynamic>;
                  final iName   = iMap['name'] ?? '';
                  final iQty    = iMap['quantity'] ?? 1;
                  // ✅ Use portionPrice (the actually-selected portion price)
                  // when present; fall back to price for non-portion items.
                  final _pp = iMap['portionPrice'];
                  final iPrice = (_pp != null && (_pp as num) > 0)
                      ? (_pp as num).toDouble()
                      : (iMap['price'] ?? 0).toDouble();
                  final iPortion = iMap['portion'];
                  final iCal    = iMap['calories'] ?? 0;
                  final iPro    = (iMap['protein'] ?? 0).toDouble();
                  final iCarbs  = (iMap['carbs'] ?? 0).toDouble();
                  final iFat    = (iMap['fat'] ?? 0).toDouble();
                  final isVeg   = iMap['isVeg'] ?? true;
                  final iRestName = iMap['restaurantName'] as String? ?? '';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: isVeg
                                    ? const Color(0xFF34C759)
                                    : _red,
                                width: 1.5),
                            borderRadius: BorderRadius.circular(2)),
                        child: Center(
                            child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: isVeg
                                        ? const Color(0xFF34C759)
                                        : _red,
                                    shape: BoxShape.circle))),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                        Text(
                            iQty > 1
                                ? '$iQty× $iName${iPortion != null && iPortion.isNotEmpty ? ' ($iPortion)' : ''}'
                                : '$iName${iPortion != null && iPortion.isNotEmpty ? ' ($iPortion)' : ''}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1C1C1E))),
                        if (iRestName.isNotEmpty)
                          Text(
                            iRestName,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6E6E73)),
                          ),
                        if (iCal > 0 || iPro > 0)
                          Wrap(spacing: 5, children: [
                            if (iCal > 0)
                              _miniChip(
                                  '🔥 ${iCal}kcal', const Color(0xFFFF9500)),
                            if (iPro > 0)
                              _miniChip('P:${iPro.toStringAsFixed(0)}g',
                                  const Color(0xFF007AFF)),
                            if (iCarbs > 0)
                              _miniChip('C:${iCarbs.toStringAsFixed(0)}g',
                                  const Color(0xFF34C759)),
                            if (iFat > 0)
                              _miniChip(
                                  'F:${iFat.toStringAsFixed(0)}g', _red),
                          ]),
                      ])),
                      Text('₹${(iPrice * iQty).toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E))),
                    ]),
                  );
                }).toList(),
              ),
            ),

          // Nutrition summary
          if (calories > 0 || protein > 0) ...[
            const Divider(
                height: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F0F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF9F0),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                  if (calories > 0)
                    _nutrCell('🔥', '${calories}kcal', 'Calories',
                        const Color(0xFFFF9500)),
                  if (protein > 0)
                    _nutrCell('💪', '${protein.toStringAsFixed(0)}g', 'Protein',
                        const Color(0xFF007AFF)),
                  if (carbs > 0)
                    _nutrCell('🌾', '${carbs.toStringAsFixed(0)}g', 'Carbs',
                        const Color(0xFF34C759)),
                  if (fat > 0)
                    _nutrCell('🥑', '${fat.toStringAsFixed(0)}g', 'Fat', _red),
                ]),
              ),
            ),
          ],

          // ── Cancellation policy note — always visible in expanded view ──
          // (except for already delivered/cancelled orders)
          if (status != 'delivered' && status != 'cancelled') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFFFCC02).withOpacity(0.6),
                        width: 1.2)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('📋',
                      style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Cancellation Policy: Orders can be cancelled free of charge '
                      'only while status is Pending or Confirmed. '
                      'Cancellations after the order moves to Preparing or later '
                      'are not allowed, or will incur a 100% cancellation fee.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF7A5800),
                          height: 1.5),
                    ),
                  ),
                ]),
              ),
            ),
          ],

          // ── Track Order button + OTP (active orders only) ────────────
          if (status != 'cancelled' && status != 'delivered')
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Column(children: [
                // Track Order button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0077B6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderTrackingScreen(
                            orderId: widget.orderId),
                      ),
                    ),
                    icon: const Icon(Icons.location_on_rounded,
                        color: Colors.white, size: 18),
                    label: const Text('Track Order',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                ),

                // OTP chip — only shown when agent is on the way
                Builder(builder: (ctx) {
                  final otp = widget.data['deliveryOtp'] as String? ?? '';
                  final showOtp = otp.isNotEmpty &&
                      (status == 'out_for_delivery' ||
                          status == 'picked_up');
                  if (!showOtp) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: const Color(0xFFFFB74D)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.lock_rounded,
                            color: Color(0xFFE65100), size: 18),
                        const SizedBox(width: 10),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Delivery OTP',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1C1C1E))),
                          Text(
                            otp.split('').join('  '),
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 6,
                                color: Color(0xFFE65100)),
                          ),
                        ]),
                        const Spacer(),
                        const Text('Show to\nagent',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6E6E73))),
                      ]),
                    ),
                  );
                }),
              ]),
            ),

          // ── Cancel button (active only for pending/confirmed) ──────────
          if (_canCancel && status != 'cancelled')
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: _cancelling ? null : _cancelOrder,
                  icon: _cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: _red, strokeWidth: 2))
                      : const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(_cancelling ? 'Cancelling...' : 'Cancel Order',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),

          // ── Greyed-out / disabled cancel button for preparing+ ──────────
          if (!_canCancel && status != 'cancelled' && status != 'delivered')
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFBDBDBD),
                      side: const BorderSide(
                          color: Color(0xFFE0E0E0), width: 1.5),
                      backgroundColor: const Color(0xFFF5F5F5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  // Button is intentionally disabled (null onPressed)
                  onPressed: null,
                  icon: const Icon(Icons.cancel_outlined,
                      size: 18, color: Color(0xFFBDBDBD)),
                  label: const Text('Cancel Order',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFBDBDBD))),
                ),
              ),
            ),

          const SizedBox(height: 14),

          // ── Request Refund button (delivered, non-COD, not already requested) ──
          if (_canRequestRefund)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF9500),
                      side: const BorderSide(
                          color: Color(0xFFFF9500), width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed:
                      _submittingRefund ? null : _showRefundSheet,
                  icon: _submittingRefund
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Color(0xFFFF9500), strokeWidth: 2))
                      : const Icon(Icons.assignment_return_outlined,
                          size: 18),
                  label: Text(
                      _submittingRefund
                          ? 'Submitting...'
                          : 'Request Refund',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            )
          else
            const SizedBox(height: 0),
        ],
      ]),
    );
  }

  Widget _miniChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color)),
      );

  Widget _nutrCell(
          String emoji, String value, String label, Color color) =>
      Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF6E6E73))),
      ]);
}