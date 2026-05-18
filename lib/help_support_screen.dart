// ─────────────────────────────────────────────
// help_support_screen.dart — FoodFeast
//
// Sections:
//   1. FAQ accordion (app-specific answers)
//   2. Order Issues — pick a real order, describe problem → writes to Firestore
//   3. Refund Request — pick a delivered order → refund ticket
//   4. Report a Problem — category + description → Firestore
//   5. Contact Us — message form → Firestore support_messages
//   6. App Feedback — star rating + comment → Firestore
//
// Firestore collections written:
//   support_tickets/{id}   — order issues & refund requests
//   problem_reports/{id}   — report a problem
//   support_messages/{id}  — contact us messages
//   app_feedback/{id}      — star ratings & comments
// ─────────────────────────────────────────────
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fcm_service.dart'; // ← notify admin on new support requests

class HelpSupportScreen extends StatefulWidget {
  /// Pass [initialTab] to open a specific tab on launch.
  /// 0=FAQs  1=Order Issues  2=Refund  3=Report  4=Contact Us  5=My Tickets
  final int initialTab;
  const HelpSupportScreen({super.key, this.initialTab = 0});
  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen>
    with SingleTickerProviderStateMixin {
  // ── Brand colours (match profile_screen) ─────
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);
  static const _red   = Color(0xFFFF3B30);
  static const _grey  = Color(0xFF6E6E73);

  late final TabController _tab;
  final _db  = FirebaseFirestore.instance;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  String? get _userEmail => FirebaseAuth.instance.currentUser?.email;
  String? get _userName  => FirebaseAuth.instance.currentUser?.displayName;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 5),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // A key so child tabs can show snackbars safely even after this
  // State or a child tab has been disposed — fixes the
  // "setState called after dispose" error that appeared after every submit.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  // ── shared snackbar ───────────────────────────
  void _snack(String msg, {Color color = _green}) {
    _messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Help & Support',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: _blue,
          unselectedLabelColor: _grey,
          indicatorColor: _blue,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12.5),
          unselectedLabelStyle: const TextStyle(fontSize: 12.5),
          tabs: const [
            Tab(text: 'FAQs'),
            Tab(text: 'Order Issues'),
            Tab(text: 'Refund'),
            Tab(text: 'Report'),
            Tab(text: 'Contact Us'),
            Tab(text: 'My Tickets'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _FaqTab(),
          _OrderIssueTab(uid: _uid, db: _db, snack: _snack,
              userName: _userName, userEmail: _userEmail),
          _RefundTab(uid: _uid, db: _db, snack: _snack,
              userName: _userName, userEmail: _userEmail),
          _ReportTab(uid: _uid, db: _db, snack: _snack,
              userName: _userName, userEmail: _userEmail),
          _ContactTab(uid: _uid, db: _db, snack: _snack,
              userName: _userName, userEmail: _userEmail),
          _MyTicketsTab(uid: _uid, db: _db, userName: _userName, snack: _snack),
        ],
      ),
    ),   // Scaffold
    );   // ScaffoldMessenger
  }
}

// ═══════════════════════════════════════════════
// 1. FAQ TAB
// ═══════════════════════════════════════════════
class _FaqTab extends StatefulWidget {
  @override
  State<_FaqTab> createState() => _FaqTabState();
}

class _FaqTabState extends State<_FaqTab> {
  int _open = -1;

  static const _faqs = [
    (
      q: 'How do I track my order?',
      a: 'Go to Profile → Order History. Tap on any order to expand it and see the current status: Confirmed, Preparing, Out for Delivery, or Delivered.',
    ),
    (
      q: 'Can I cancel my order?',
      a: 'Yes — but only while the status is Pending or Confirmed. Once a restaurant starts Preparing your order, cancellation is no longer possible. To cancel, open Order History, expand the order, and tap "Cancel Order".',
    ),
    (
      q: 'My payment was deducted but no order was placed. What should I do?',
      a: 'This can happen if the app closed mid-payment. Please wait 10–15 minutes; most payments auto-reverse. If the amount is not refunded within 5–7 business days, raise a Refund Request from the "Refund" tab and we will investigate.',
    ),
    (
      q: 'How long does delivery take?',
      a: 'Most orders are delivered in 30–45 minutes depending on your location and the restaurant\'s workload. You can see the estimated delivery time on the restaurant page.',
    ),
    (
      q: 'What payment methods are accepted?',
      a: 'FoodFeast accepts UPI (GPay, PhonePe, Paytm), Debit/Credit Cards, Net Banking via Razorpay, and Cash on Delivery for eligible orders.',
    ),
    (
      q: 'How do I apply a promo code?',
      a: 'At checkout on the Payment step, tap "Have a promo code?" and enter your code. Valid codes will show the discount immediately before you confirm payment.',
    ),
    (
      q: 'Can I change my delivery address after placing an order?',
      a: 'Address changes are not possible after an order is confirmed. Please ensure your address is correct before placing the order. For urgent cases, contact us via the "Contact Us" tab.',
    ),
    (
      q: 'Why was my order automatically cancelled?',
      a: 'Orders may be auto-cancelled if the restaurant is unable to accept it (e.g., closed, out of stock) or if a payment could not be verified. You will receive a notification and any deducted amount will be refunded within 5–7 days.',
    ),
    (
      q: 'How do I update my calorie goal?',
      a: 'Go to Profile → Calorie Targets section. Based on your BMI, recommended calorie targets are shown. Tap "Apply Recommended" to set the goal, or go to Health Goals → Edit to set a custom value.',
    ),
    (
      q: 'How do I delete my account?',
      a: 'Account deletion is permanent and removes all your order history, saved addresses, and nutrition data. To request deletion, contact us through the "Contact Us" tab with the subject "Account Deletion Request".',
    ),
    (
      q: 'I received the wrong item. What should I do?',
      a: 'We\'re sorry! Please report this using the "Order Issues" tab within 24 hours of delivery. Select your order, choose "Wrong item delivered", describe the issue, and submit. Our team will respond within 24 hours.',
    ),
    (
      q: 'Can I schedule a delivery for later?',
      a: 'Yes! During checkout on the Delivery Slot step, you can choose from available time slots for the same day instead of selecting "ASAP".',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _faqs.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _header();
        final faq = _faqs[i - 1];
        final isOpen = _open == i - 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOpen
                  ? const Color(0xFF0077B6).withOpacity(0.4)
                  : const Color(0xFFE5E5EA),
              width: isOpen ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () =>
                  setState(() => _open = isOpen ? -1 : i - 1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0077B6).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('Q',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0077B6))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(faq.q,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isOpen
                                  ? const Color(0xFF0077B6)
                                  : const Color(0xFF1C1C1E))),
                    ),
                    Icon(
                      isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF6E6E73),
                      size: 20,
                    ),
                  ]),
                  if (isOpen) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFF0F0F0)),
                    const SizedBox(height: 12),
                    Row(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34C759).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('A',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF34C759))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(faq.a,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF3C3C43),
                                height: 1.55)),
                      ),
                    ]),
                  ],
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF023E8A), Color(0xFF0077B6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(children: [
      const Text('🙋', style: TextStyle(fontSize: 32)),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('Frequently Asked Questions',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          SizedBox(height: 3),
          Text('Tap any question to see the answer',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
    ]),
  );
}

// ═══════════════════════════════════════════════
// 2. ORDER ISSUE TAB
// ═══════════════════════════════════════════════
class _OrderIssueTab extends StatefulWidget {
  final String? uid;
  final FirebaseFirestore db;
  final void Function(String, {Color color}) snack;
  final String? userName;
  final String? userEmail;
  const _OrderIssueTab(
      {required this.uid,
      required this.db,
      required this.snack,
      this.userName,
      this.userEmail});
  @override
  State<_OrderIssueTab> createState() => _OrderIssueTabState();
}

class _OrderIssueTabState extends State<_OrderIssueTab> {
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _red   = Color(0xFFFF3B30);

  String? _selectedOrderId;
  String? _selectedRestaurant;
  String  _issueType = 'Order not arrived';
  final   _descCtrl  = TextEditingController();
  bool    _submitting = false;

  static const _issueTypes = [
    'Order not arrived',
    'Wrong item delivered',
    'Missing items',
    'Order cancelled automatically',
    'Food quality issue',
    'Delivery partner issue',
    'Other',
  ];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedOrderId == null) {
      widget.snack('Please select an order', color: _red);
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      widget.snack('Please describe the issue', color: _red);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.db.collection('support_tickets').add({
        'type':           'order_issue',
        'userId':         widget.uid,
        'userName':       widget.userName ?? '',
        'userEmail':      widget.userEmail ?? '',
        'orderId':        _selectedOrderId,
        'restaurantName': _selectedRestaurant ?? '',
        'issueType':      _issueType,
        'description':    _descCtrl.text.trim(),
        'status':         'open',
        'createdAt':      FieldValue.serverTimestamp(),
      });
      // ── Notify admin ──────────────────────────────────────────────
      FcmService.notifyAdmin(
        title: '🎫 New Order Issue',
        body: '${widget.userName ?? 'A user'} reported: $_issueType'
            '${_selectedRestaurant != null ? ' · $_selectedRestaurant' : ''}',
        data: {'type': 'support_ticket', 'ticketType': 'order_issue'},
      );
      widget.snack(
          'Issue reported! We\'ll respond within 24 hours ✅');
      setState(() {
        _selectedOrderId   = null;
        _selectedRestaurant = null;
        _issueType = 'Order not arrived';
        _descCtrl.clear();
      });
    } catch (e) {
      widget.snack('Failed to submit: $e', color: _red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Builds the inline form that appears below the selected order.
  Widget _inlineForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: Color(0xFFE5E5EA)),
        const SizedBox(height: 12),

        // Issue type
        _label('Issue Type *'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: _issueTypes.map((t) {
          final sel = _issueType == t;
          return GestureDetector(
            onTap: () => setState(() => _issueType = t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _blue : const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: sel ? _blue : const Color(0xFFE5E5EA),
                    width: sel ? 1.5 : 1),
              ),
              child: Text(t,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color:
                          sel ? Colors.white : const Color(0xFF3C3C43))),
            ),
          );
        }).toList()),
        const SizedBox(height: 14),

        // Description
        _label('Describe the Issue *'),
        const SizedBox(height: 8),
        TextField(
          controller: _descCtrl,
          maxLines: 4,
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF1C1C1E)),
          decoration:
              _inputDec('Tell us exactly what happened...'),
        ),
        const SizedBox(height: 14),

        // Submit
        _submitBtn(
            'Submit Issue Report', _blue, _submit, _submitting),
        const SizedBox(height: 10),
        _infoBox('🕐',
            'Our support team reviews all issues within 24 hours. '
            'For urgent matters please call us.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        _sectionHeader('📦', 'Report an Order Issue',
            'Select the affected order and describe what went wrong.'),
        const SizedBox(height: 16),

        // ── Order picker — form fields appear inline below selection ──
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _label('Select Order *'),
          const SizedBox(height: 10),
          if (widget.uid == null)
            const Text('Please log in to see your orders.',
                style: TextStyle(color: Color(0xFF6E6E73)))
          else
            _OrderPicker(
              uid: widget.uid!,
              db: widget.db,
              selectedId: _selectedOrderId,
              onSelected: (id, rest, {double? amount}) =>
                  setState(() {
                // Tapping the already-selected order deselects it
                if (_selectedOrderId == id) {
                  _selectedOrderId    = null;
                  _selectedRestaurant = null;
                } else {
                  _selectedOrderId    = id;
                  _selectedRestaurant = rest;
                }
              }),
              inlineFormBuilder:
                  _selectedOrderId != null ? _inlineForm : null,
            ),
        ])),

        const SizedBox(height: 16),
        // ── My submitted tickets ──────────────────
        if (widget.uid != null)
          _MyTickets(
              uid: widget.uid!, db: widget.db, type: 'order_issue'),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════
// 3. REFUND TAB
// ═══════════════════════════════════════════════
class _RefundTab extends StatefulWidget {
  final String? uid;
  final FirebaseFirestore db;
  final void Function(String, {Color color}) snack;
  final String? userName;
  final String? userEmail;
  const _RefundTab(
      {required this.uid,
      required this.db,
      required this.snack,
      this.userName,
      this.userEmail});
  @override
  State<_RefundTab> createState() => _RefundTabState();
}

class _RefundTabState extends State<_RefundTab> {
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);
  static const _red   = Color(0xFFFF3B30);

  String? _selectedOrderId;
  String? _selectedRestaurant;
  double? _selectedAmount;
  String  _refundReason = 'Payment deducted, order not placed';
  final   _detailCtrl = TextEditingController();
  final   _upiCtrl    = TextEditingController();
  bool    _submitting  = false;

  static const _reasons = [
    'Payment deducted, order not placed',
    'Order cancelled by restaurant',
    'Duplicate payment',
    'Wrong amount charged',
    'Order auto-cancelled',
    'Other',
  ];

  @override
  void dispose() {
    _detailCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedOrderId == null) {
      widget.snack('Please select an order', color: _red);
      return;
    }
    if (_upiCtrl.text.trim().isEmpty) {
      widget.snack('Please enter your UPI / bank details', color: _red);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.db.collection('support_tickets').add({
        'type':            'refund_request',
        'userId':          widget.uid,
        'userName':        widget.userName ?? '',
        'userEmail':       widget.userEmail ?? '',
        'orderId':         _selectedOrderId,
        'restaurantName':  _selectedRestaurant ?? '',
        'orderAmount':     _selectedAmount ?? 0,
        'refundReason':    _refundReason,
        'details':         _detailCtrl.text.trim(),
        'refundAccount':   _upiCtrl.text.trim(),
        'status':          'open',
        'createdAt':       FieldValue.serverTimestamp(),
      });
      // ── Notify admin ──────────────────────────────────────────────
      FcmService.notifyAdmin(
        title: '💰 Refund Request',
        body: '${widget.userName ?? 'A user'} requests refund'
            '${_selectedAmount != null ? ' ₹${_selectedAmount!.toStringAsFixed(0)}' : ''}'
            ': $_refundReason',
        data: {'type': 'support_ticket', 'ticketType': 'refund_request'},
      );
      widget.snack('Refund request submitted! 5–7 business days ✅');
      setState(() {
        _selectedOrderId    = null;
        _selectedRestaurant = null;
        _selectedAmount     = null;
        _refundReason = 'Payment deducted, order not placed';
        _detailCtrl.clear();
        _upiCtrl.clear();
      });
    } catch (e) {
      widget.snack('Failed to submit: $e', color: _red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Builds the inline refund form shown below the selected order.
  Widget _inlineRefundForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: Color(0xFFE5E5EA)),
        const SizedBox(height: 12),

        // Order total badge
        if (_selectedAmount != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _orng.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _orng.withOpacity(0.3), width: 1.2),
            ),
            child: Row(children: [
              const Icon(Icons.currency_rupee_rounded,
                  color: _orng, size: 16),
              const SizedBox(width: 6),
              Text(
                'Order total: ₹${_selectedAmount!.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _orng),
              ),
            ]),
          ),
          const SizedBox(height: 14),
        ],

        // Reason for Refund
        _label('Reason for Refund *'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8,
            children: _reasons.map((r) {
          final sel = _refundReason == r;
          return GestureDetector(
            onTap: () => setState(() => _refundReason = r),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _blue : const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: sel ? _blue : const Color(0xFFE5E5EA),
                    width: sel ? 1.5 : 1),
              ),
              child: Text(r,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: sel
                          ? Colors.white
                          : const Color(0xFF3C3C43))),
            ),
          );
        }).toList()),
        const SizedBox(height: 14),

        // Additional Details
        _label('Additional Details'),
        const SizedBox(height: 8),
        TextField(
          controller: _detailCtrl,
          maxLines: 3,
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF1C1C1E)),
          decoration:
              _inputDec('Any additional info about the payment issue...'),
        ),
        const SizedBox(height: 14),

        // Refund account
        _label('Refund Account (UPI ID / Bank details) *'),
        const SizedBox(height: 8),
        TextField(
          controller: _upiCtrl,
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF1C1C1E)),
          decoration:
              _inputDec('e.g. yourname@upi or bank account info'),
        ),
        const SizedBox(height: 8),
        _infoBox('ℹ️',
            'For UPI payments, refunds are sent to the original payment source automatically. Provide details only if auto-refund fails.'),
        const SizedBox(height: 14),

        // Submit
        _submitBtn(
            'Submit Refund Request', _orng, _submit, _submitting),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        _sectionHeader('💳', 'Request a Refund',
            'Refunds are processed within 5–7 business days.'),
        const SizedBox(height: 16),

        // ── Order picker — form fields appear inline below selection ──
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _label('Select Order *'),
          const SizedBox(height: 10),
          if (widget.uid == null)
            const Text('Please log in.',
                style: TextStyle(color: Color(0xFF6E6E73)))
          else
            _OrderPicker(
              uid: widget.uid!,
              db: widget.db,
              selectedId: _selectedOrderId,
              onSelected: (id, rest, {double? amount}) =>
                  setState(() {
                // Tapping already-selected order deselects it
                if (_selectedOrderId == id) {
                  _selectedOrderId    = null;
                  _selectedRestaurant = null;
                  _selectedAmount     = null;
                } else {
                  _selectedOrderId    = id;
                  _selectedRestaurant = rest;
                  _selectedAmount     = amount;
                }
              }),
              inlineFormBuilder:
                  _selectedOrderId != null ? _inlineRefundForm : null,
            ),
        ])),

        const SizedBox(height: 16),
        if (widget.uid != null)
          _MyTickets(
              uid: widget.uid!, db: widget.db, type: 'refund_request'),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════
// 4. REPORT TAB
// ═══════════════════════════════════════════════
class _ReportTab extends StatefulWidget {
  final String? uid;
  final FirebaseFirestore db;
  final void Function(String, {Color color}) snack;
  final String? userName;
  final String? userEmail;
  const _ReportTab(
      {required this.uid,
      required this.db,
      required this.snack,
      this.userName,
      this.userEmail});
  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> {
  static const _blue = Color(0xFF0077B6);
  static const _red  = Color(0xFFFF3B30);

  String _category = 'Wrong restaurant info';
  final _restCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  bool  _submitting = false;

  static const _categories = [
    'Wrong restaurant info',
    'Incorrect menu / price',
    'Food safety issue',
    'Rude delivery partner',
    'App bug / technical issue',
    'Fraud or suspicious activity',
    'Other',
  ];

  @override
  void dispose() {
    _restCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) {
      widget.snack('Please describe the problem', color: _red);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.db.collection('problem_reports').add({
        'userId':          widget.uid,
        'userName':        widget.userName ?? '',
        'userEmail':       widget.userEmail ?? '',
        'category':        _category,
        'restaurantName':  _restCtrl.text.trim(),
        'description':     _descCtrl.text.trim(),
        'status':          'open',
        'createdAt':       FieldValue.serverTimestamp(),
      });
      // ── Notify admin ──────────────────────────────────────────────
      FcmService.notifyAdmin(
        title: '🚨 Problem Report',
        body: '${widget.userName ?? 'A user'} reported: $_category'
            '${_restCtrl.text.trim().isNotEmpty ? ' · ${_restCtrl.text.trim()}' : ''}',
        data: {'type': 'problem_report'},
      );
      widget.snack('Problem reported. Thank you! 🙏');
      setState(() {
        _category = 'Wrong restaurant info';
        _restCtrl.clear();
        _descCtrl.clear();
      });
    } catch (e) {
      widget.snack('Failed to submit: $e', color: _red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        _sectionHeader('🚨', 'Report a Problem',
            'Help us improve FoodFeast by reporting issues.'),
        const SizedBox(height: 16),

        // ── Category ──────────────────────────────
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _label('Problem Category *'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8,
              children: _categories.map((c) {
            final sel = _category == c;
            return GestureDetector(
              onTap: () => setState(() => _category = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _blue : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? _blue : const Color(0xFFE5E5EA),
                      width: sel ? 1.5 : 1),
                ),
                child: Text(c,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : const Color(0xFF3C3C43))),
              ),
            );
          }).toList()),
        ])),
        const SizedBox(height: 12),

        // ── Restaurant name (optional) ────────────
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _label('Restaurant Name (if applicable)'),
          const SizedBox(height: 10),
          TextField(
            controller: _restCtrl,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration: _inputDec('e.g. Ambur Biriyani'),
          ),
        ])),
        const SizedBox(height: 12),

        // ── Description ───────────────────────────
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _label('Describe the Problem *'),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            maxLines: 5,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration:
                _inputDec('Please be as specific as possible...'),
          ),
        ])),
        const SizedBox(height: 20),

        _submitBtn('Submit Report', _red, _submit, _submitting),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════
// 5. CONTACT US TAB
// ═══════════════════════════════════════════════
class _ContactTab extends StatefulWidget {
  final String? uid;
  final FirebaseFirestore db;
  final void Function(String, {Color color}) snack;
  final String? userName;
  final String? userEmail;
  const _ContactTab(
      {required this.uid,
      required this.db,
      required this.snack,
      this.userName,
      this.userEmail});
  @override
  State<_ContactTab> createState() => _ContactTabState();
}

class _ContactTabState extends State<_ContactTab> {
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _red   = Color(0xFFFF3B30);

  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _msgCtrl     = TextEditingController();
  String _topic      = 'General Enquiry';
  bool _submitting   = false;

  // App Feedback state
  int    _starRating   = 0;
  final  _feedbackCtrl = TextEditingController();
  bool   _submittingFb = false;

  static const _topics = [
    'General Enquiry',
    'Account Deletion Request',
    'Partnership / Business',
    'Media / Press',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text  = widget.userName  ?? '';
    _emailCtrl.text = widget.userEmail ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _msgCtrl.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _msgCtrl.text.trim().isEmpty) {
      widget.snack('Please fill in all required fields', color: _red);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.db.collection('support_messages').add({
        'userId':    widget.uid,
        'name':      _nameCtrl.text.trim(),
        'email':     _emailCtrl.text.trim(),
        'topic':     _topic,
        'subject':   _subjectCtrl.text.trim(),
        'message':   _msgCtrl.text.trim(),
        'status':    'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });
      // ── Notify admin ──────────────────────────────────────────────
      FcmService.notifyAdmin(
        title: '✉️ New Support Message',
        body: '${_nameCtrl.text.trim()} · $_topic'
            '${_subjectCtrl.text.trim().isNotEmpty ? ': ${_subjectCtrl.text.trim()}' : ''}',
        data: {'type': 'support_message'},
      );
      widget.snack('Message sent! We\'ll reply to your email soon ✅');
      setState(() {
        _subjectCtrl.clear();
        _msgCtrl.clear();
        _topic = 'General Enquiry';
      });
    } catch (e) {
      widget.snack('Failed to send: $e', color: _red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitFeedback() async {
    if (_starRating == 0) {
      widget.snack('Please select a star rating', color: _red);
      return;
    }
    setState(() => _submittingFb = true);
    try {
      await widget.db.collection('app_feedback').add({
        'userId':    widget.uid,
        'userName':  widget.userName ?? '',
        'rating':    _starRating,
        'comment':   _feedbackCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      widget.snack('Thanks for your feedback! 🌟');
      setState(() {
        _starRating = 0;
        _feedbackCtrl.clear();
      });
    } catch (e) {
      widget.snack('Failed to submit: $e', color: _red);
    } finally {
      if (mounted) setState(() => _submittingFb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        _sectionHeader('💬', 'Contact Us',
            'Send us a message and we\'ll reply to your email.'),
        const SizedBox(height: 16),

        // ── Contact info cards ─────────────────────
        Row(children: [
          Expanded(child: _contactInfoTile(
            Icons.email_outlined, 'Email', 'support@foodfeast.in', _blue)),
          const SizedBox(width: 10),
          Expanded(child: _contactInfoTile(
            Icons.access_time_rounded, 'Hours', 'Mon–Sun\n9 AM – 9 PM', _green)),
        ]),
        const SizedBox(height: 16),

        // ── Message form ───────────────────────────
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _label('Your Name *'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration: _inputDec('Full name'),
          ),
          const SizedBox(height: 12),

          _label('Email Address *'),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration: _inputDec('you@example.com'),
          ),
          const SizedBox(height: 12),

          _label('Topic'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _topics.map((t) {
            final sel = _topic == t;
            return GestureDetector(
              onTap: () => setState(() => _topic = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? _blue : const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: sel ? _blue : const Color(0xFFE5E5EA),
                      width: sel ? 1.5 : 1),
                ),
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : const Color(0xFF3C3C43))),
              ),
            );
          }).toList()),
          const SizedBox(height: 12),

          _label('Subject'),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectCtrl,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration: _inputDec('Brief subject line'),
          ),
          const SizedBox(height: 12),

          _label('Message *'),
          const SizedBox(height: 8),
          TextField(
            controller: _msgCtrl,
            maxLines: 5,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration: _inputDec('Write your message here...'),
          ),
        ])),
        const SizedBox(height: 20),

        _submitBtn('Send Message', _blue, _sendMessage, _submitting),

        // ── Divider ───────────────────────────────
        const SizedBox(height: 28),
        Row(children: [
          const Expanded(child: Divider(color: Color(0xFFE5E5EA))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('App Feedback',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600)),
          ),
          const Expanded(child: Divider(color: Color(0xFFE5E5EA))),
        ]),
        const SizedBox(height: 16),

        // ── App feedback ───────────────────────────
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _label('Rate the App'),
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                return GestureDetector(
                  onTap: () => setState(() => _starRating = i + 1),
                  child: AnimatedScale(
                    scale: _starRating == i + 1 ? 1.25 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        i < _starRating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: const Color(0xFFFFCC02),
                        size: 38,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (_starRating > 0) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                ['', 'Terrible 😢', 'Poor 😕', 'Okay 😐',
                 'Good 😊', 'Excellent 🤩'][_starRating],
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: [
                      Colors.transparent,
                      _red,
                      const Color(0xFFFF9500),
                      const Color(0xFFFFCC02),
                      _green,
                      _blue,
                    ][_starRating]),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _label('Comments (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackCtrl,
            maxLines: 3,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF1C1C1E)),
            decoration:
                _inputDec('What do you love? What can we improve?'),
          ),
          const SizedBox(height: 16),
          _submitBtn(
              'Submit Feedback', _green, _submitFeedback, _submittingFb),
        ])),
      ]),
    );
  }

  Widget _contactInfoTile(
      IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E5EA)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6E6E73))),
            Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════
// Order Picker — shared by Issue & Refund tabs
// StatefulWidget with a cached stream so parent
// setState() calls never re-subscribe and cause
// the glitch / flicker seen before.
// [inlineFormBuilder] renders extra widgets directly
// below the selected order row (inline layout).
// ═══════════════════════════════════════════════
class _OrderPicker extends StatefulWidget {
  final String uid;
  final FirebaseFirestore db;
  final String? selectedId;
  final void Function(String id, String restaurant, {double? amount})
      onSelected;
  /// Optional builder: returns widgets shown inline
  /// below the selected order row.
  final Widget Function()? inlineFormBuilder;

  const _OrderPicker({
    required this.uid,
    required this.db,
    required this.selectedId,
    required this.onSelected,
    this.inlineFormBuilder,
  });

  @override
  State<_OrderPicker> createState() => _OrderPickerState();
}

class _OrderPickerState extends State<_OrderPicker> {
  // Cache the stream so it is never re-created on parent rebuild.
  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.db
        .collection('orders')
        .where('userId', isEqualTo: widget.uid)
        .snapshots();
  }

  String _fmt(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting ||
            snap.data == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                  color: Color(0xFF0077B6)),
            ),
          );
        }
        final docs = List<QueryDocumentSnapshot>.from(
            snap.data?.docs ?? []);
        // Sort newest first
        docs.sort((a, b) {
          final aTs =
              (a.data() as Map<String, dynamic>)['createdAt'];
          final bTs =
              (b.data() as Map<String, dynamic>)['createdAt'];
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
          return const Text('No orders found.',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF6E6E73)));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final rest =
                data['restaurantName'] as String? ?? 'Unknown';
            final status =
                data['status'] as String? ?? 'pending';
            final total = (data['grandTotal'] ??
                data['total'] ??
                0) as num;
            final date = _fmt(data['createdAt']);
            final isSelected = widget.selectedId == doc.id;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => widget.onSelected(doc.id, rest,
                      amount: total.toDouble()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0077B6).withOpacity(0.06)
                          : const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF0077B6)
                            : const Color(0xFFE5E5EA),
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Row(children: [
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF0077B6), size: 18)
                      else
                        const Icon(
                            Icons.radio_button_unchecked_rounded,
                            color: Color(0xFFAEAEB2),
                            size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          Text(
                            '#${doc.id.substring(0, 6).toUpperCase()} · $rest',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1C1C1E)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${total.toStringAsFixed(0)} · $status · $date',
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF6E6E73)),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
                // ── Inline form fields appear right below
                // the selected order, inside the same card ──
                if (isSelected && widget.inlineFormBuilder != null)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: widget.inlineFormBuilder!(),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════
// My Submitted Tickets — shows user's own tickets
// ═══════════════════════════════════════════════
class _MyTickets extends StatelessWidget {
  final String uid;
  final FirebaseFirestore db;
  final String type;
  const _MyTickets(
      {required this.uid, required this.db, required this.type});

  Color _statusColor(String s) {
    switch (s) {
      case 'open':       return const Color(0xFFFF9500);
      case 'in_review':  return const Color(0xFF007AFF);
      case 'resolved':   return const Color(0xFF34C759);
      case 'rejected':   return const Color(0xFFFF3B30);
      default:           return const Color(0xFF6E6E73);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':       return 'Open';
      case 'in_review':  return 'In Review';
      case 'resolved':   return 'Resolved';
      case 'rejected':   return 'Rejected';
      default:           return s;
    }
  }

  String _fmt(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('support_tickets')
          .where('userId', isEqualTo: uid)
          .where('type', isEqualTo: type)
          .snapshots(),
      builder: (_, snap) {
        final docs = List<QueryDocumentSnapshot>.from(
            snap.data?.docs ?? []);
        if (docs.isEmpty) return const SizedBox.shrink();

        docs.sort((a, b) {
          final aTs =
              (a.data() as Map<String, dynamic>)['createdAt'];
          final bTs =
              (b.data() as Map<String, dynamic>)['createdAt'];
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

        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 10),
            child: Text('My Previous Tickets',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
          ),
          ...docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? 'open';
            final color = _statusColor(status);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFE5E5EA)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      data['issueType'] ??
                          data['refundReason'] ??
                          'Ticket',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '#${doc.id.substring(0, 8).toUpperCase()} · ${_fmt(data['createdAt'])}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6E6E73)),
                    ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusLabel(status),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ]),
            );
          }),
        ]);
      },
    );
  }
}

// ═══════════════════════════════════════════════
// 6. MY TICKETS TAB
// Shows all tickets submitted by the current user across
// support_tickets, problem_reports, and support_messages.
// Each ticket is expandable and shows the full conversation
// thread (user messages + admin replies). User can reply.
// ═══════════════════════════════════════════════
class _MyTicketsTab extends StatefulWidget {
  final String? uid;
  final FirebaseFirestore db;
  final String? userName;
  final void Function(String msg, {Color color}) snack;
  const _MyTicketsTab({
    required this.uid,
    required this.db,
    this.userName,
    required this.snack,
  });
  @override
  State<_MyTicketsTab> createState() => _MyTicketsTabState();
}

class _MyTicketsTabState extends State<_MyTicketsTab> {
  static const _blue = Color(0xFF0077B6);

  final List<Map<String, dynamic>> _tickets = [];
  final List<StreamSubscription<QuerySnapshot>> _subs = [];
  final Map<String, List<QueryDocumentSnapshot>> _cache = {};
  bool _loading = true;

  static const _collections = [
    'support_tickets',
    'problem_reports',
    'support_messages',
  ];

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    final uid = widget.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    int responded = 0;
    for (final col in _collections) {
      _cache[col] = [];
      final sub = widget.db
          .collection(col)
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
        _cache[col] = snap.docs;
        responded++;
        if (mounted) {
          setState(() {
            if (responded >= _collections.length) _loading = false;
            _rebuildTickets();
          });
        }
      }, onError: (_) {
        responded++;
        if (mounted) setState(() {
          if (responded >= _collections.length) _loading = false;
        });
      });
      _subs.add(sub);
    }
  }

  void _rebuildTickets() {
    _tickets.clear();
    for (final col in _collections) {
      for (final doc in _cache[col] ?? []) {
        _tickets.add({
          'collection': col,
          'id':         doc.id,
          'data':       doc.data() as Map<String, dynamic>,
        });
      }
    }
    _tickets.sort((a, b) {
      final aTs = (a['data'] as Map)['createdAt'];
      final bTs = (b['data'] as Map)['createdAt'];
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      try {
        return (bTs as Timestamp).compareTo(aTs as Timestamp);
      } catch (_) { return 0; }
    });
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid == null) {
      return const Center(
        child: Text('Please log in to view your tickets.',
            style: TextStyle(color: Color(0xFF6E6E73))),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _blue, strokeWidth: 2),
      );
    }
    if (_tickets.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
                color: _blue.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Icons.confirmation_number_outlined,
                size: 34, color: _blue),
          ),
          const SizedBox(height: 16),
          const Text('No tickets yet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 6),
          const Text('Submit a request from any other tab',
              style: TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
        ]),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _sectionHeader('🎫', 'My Support Tickets',
            'View and reply to your open tickets with admin.'),
        const SizedBox(height: 16),
        ..._tickets.map((entry) => _TicketCard(
          key: ValueKey('${entry['collection']}:${entry['id']}'),
          collection: entry['collection'] as String,
          docId:      entry['id']         as String,
          data:       entry['data']        as Map<String, dynamic>,
          db:         widget.db,
          userName:   widget.userName ?? 'You',
          snack:      widget.snack,
        )),
      ],
    );
  }
}

// ── Individual ticket card — self-contained StatefulWidget ────────────
// Owns its own TextEditingController, sending flag, and expansion state
// so the parent's setState() rebuilds never cause assertion errors.
class _TicketCard extends StatefulWidget {
  final String collection;
  final String docId;
  final Map<String, dynamic> data;
  final FirebaseFirestore db;
  final String userName;
  final void Function(String msg, {Color color}) snack;

  const _TicketCard({
    super.key,
    required this.collection,
    required this.docId,
    required this.data,
    required this.db,
    required this.userName,
    required this.snack,
  });

  @override
  State<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<_TicketCard> {
  static const _blue  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);
  static const _orng  = Color(0xFFFF9500);
  static const _red   = Color(0xFFFF3B30);

  // Controller lives here — never created during parent build()
  late final TextEditingController _replyCtrl;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _replyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'open':      return _orng;
      case 'in_review': return _blue;
      case 'resolved':  return _green;
      case 'read':      return _green;
      default:          return _orng;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':      return 'Open';
      case 'in_review': return 'In Review';
      case 'resolved':  return 'Resolved';
      case 'read':      return 'Read';
      default:          return s.replaceAll('_', ' ');
    }
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month}/${dt.year} '
          '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  String get _ticketTitle {
    return widget.data['issueType']    as String? ??
           widget.data['refundReason'] as String? ??
           widget.data['category']     as String? ??
           widget.data['subject']      as String? ??
           'Ticket';
  }

  String get _collectionLabel {
    switch (widget.collection) {
      case 'support_tickets':  return 'Support Ticket';
      case 'problem_reports':  return 'Problem Report';
      case 'support_messages': return 'Contact Us';
      default:                 return widget.collection;
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.db
          .collection(widget.collection)
          .doc(widget.docId)
          .collection('messages')
          .add({
        'sender':    'user',
        'text':      text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await widget.db
          .collection(widget.collection)
          .doc(widget.docId)
          .update({'status': 'open'});
      _replyCtrl.clear();
      if (mounted) widget.snack('Reply sent ✅');
    } catch (e) {
      if (mounted) widget.snack('Failed: $e', color: _red);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data          = widget.data;
    final status        = data['status']       as String? ?? 'open';
    final color         = _statusColor(status);
    final isRefund      = data['type'] == 'refund_request';
    final refundAccount = data['refundAccount'] as String?;
    final orderId       = data['orderId']       as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2))],
      ),
      // No initiallyExpanded, no onExpansionChanged setState —
      // PageStorageKey handles open/closed state automatically.
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(
            isRefund
                ? Icons.currency_rupee_rounded
                : Icons.support_agent_rounded,
            color: color, size: 18),
        ),
        title: Text(
          _ticketTitle,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E)),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_collectionLabel,
                style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2))),
            if (orderId != null && orderId.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Order: $orderId',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFAEAEB2))),
            ],
            const SizedBox(height: 3),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_statusLabel(status),
                    style: TextStyle(fontSize: 10.5,
                        fontWeight: FontWeight.w700, color: color)),
              ),
              const SizedBox(width: 8),
              Text(_fmtTs(data['createdAt']),
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFFAEAEB2))),
            ]),
          ],
        ),
        children: [
          // ── Refund account reminder ──────────────────────────────
          if (isRefund && refundAccount != null && refundAccount.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _orng.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _orng.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    size: 14, color: _orng),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Refund to: $refundAccount',
                      style: const TextStyle(fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3C3C43))),
                ),
              ]),
            ),
            const SizedBox(height: 10),
          ],

          // ── Conversation thread ──────────────────────────────────
          _UserConversationThread(
            collection:  widget.collection,
            docId:       widget.docId,
            initialDesc: data['description'] as String? ??
                         data['message']     as String? ?? '',
            createdAt:   data['createdAt'],
            userName:    widget.userName,
            fmtTs:       _fmtTs,
          ),
          const SizedBox(height: 12),

          // ── User reply box ───────────────────────────────────────
          if (status != 'resolved') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _blue.withOpacity(0.18)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Add a reply',
                    style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: _blue)),
                const SizedBox(height: 8),
                TextField(
                  controller: _replyCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
                  decoration: _inputDec('Type your follow-up message…'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: _sending ? null : _sendReply,
                    icon: _sending
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            size: 15, color: Colors.white),
                    label: Text(_sending ? 'Sending…' : 'Send Reply',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green.withOpacity(0.25)),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 15, color: _green),
                SizedBox(width: 6),
                Text('This ticket has been resolved.',
                    style: TextStyle(fontSize: 12.5,
                        color: _green, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ── User-side conversation thread ─────────────────────────────────────
// Same chat-bubble layout as admin side but labels flipped.
class _UserConversationThread extends StatelessWidget {
  final String collection;
  final String docId;
  final String initialDesc;
  final dynamic createdAt;
  final String userName;
  final String Function(dynamic) fmtTs;

  const _UserConversationThread({
    required this.collection,
    required this.docId,
    required this.initialDesc,
    required this.createdAt,
    required this.userName,
    required this.fmtTs,
  });

  static const _blue = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .collection('messages')
          // FIX: removed .orderBy('createdAt') — requires a Firestore composite
          // index on the sub-collection that is never auto-created, causing the
          // StreamBuilder to silently return an empty list (replies invisible).
          // We sort client-side below instead.
          .snapshots(),
      builder: (ctx, snap) {
        // FIX: surface Firestore errors so index issues become visible
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Could not load messages: ${snap.error}',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFFF3B30))),
          );
        }

        // FIX: sort client-side by createdAt ascending
        final msgs = List<QueryDocumentSnapshot>.from(
            snap.data?.docs ?? []);
        msgs.sort((a, b) {
          final aTs = (a.data() as Map<String, dynamic>)['createdAt'];
          final bTs = (b.data() as Map<String, dynamic>)['createdAt'];
          if (aTs == null) return -1;
          if (bTs == null) return 1;
          try {
            return (aTs as Timestamp).compareTo(bTs as Timestamp);
          } catch (_) {
            return 0;
          }
        });

        return Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Initial user message
          if (initialDesc.isNotEmpty) ...[
            _bubble(
              sender:  userName,
              text:    initialDesc,
              ts:      fmtTs(createdAt),
              isAdmin: false,
            ),
            const SizedBox(height: 6),
          ],
          ...msgs.map((m) {
            final d     = m.data() as Map<String, dynamic>;
            final isAdm = d['sender'] == 'admin';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _bubble(
                sender:  isAdm ? '🛡️ Support Team' : userName,
                text:    d['text'] as String? ?? '',
                ts:      fmtTs(d['createdAt']),
                isAdmin: isAdm,
              ),
            );
          }),
        ]);
      },
    );
  }

  Widget _bubble({
    required String sender,
    required String text,
    required String ts,
    required bool isAdmin,
  }) {
    return Align(
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isAdmin
              ? _blue.withOpacity(0.07)
              : const Color(0xFFF0F8FF),
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(12),
            topRight:    const Radius.circular(12),
            bottomLeft:  Radius.circular(isAdmin ? 0 : 12),
            bottomRight: Radius.circular(isAdmin ? 12 : 0),
          ),
          border: Border.all(
            color: isAdmin
                ? _blue.withOpacity(0.2)
                : const Color(0xFF0077B6).withOpacity(0.15),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(sender,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isAdmin ? _blue : const Color(0xFF3C3C43))),
          const SizedBox(height: 3),
          Text(text,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF1C1C1E), height: 1.4)),
          const SizedBox(height: 4),
          Text(ts,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFFAEAEB2))),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Shared helper widgets & utilities
// ═══════════════════════════════════════════════
Widget _sectionHeader(String emoji, String title, String sub) {
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF023E8A), Color(0xFF0077B6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 32)),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 3),
          Text(sub,
              style:
                  const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
    ]),
  );
}

Widget _card({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 3))
      ],
    ),
    child: child,
  );
}

Widget _label(String text) => Text(text,
    style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1C1C1E)));

InputDecoration _inputDec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle:
          const TextStyle(fontSize: 13, color: Color(0xFFAEAEB2)),
      filled: true,
      fillColor: const Color(0xFFF5F5F7),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E5EA))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF0077B6), width: 1.8)),
    );

Widget _submitBtn(
    String label, Color color, VoidCallback onTap, bool loading) {
  return SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      onPressed: loading ? null : onTap,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5))
          : Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
    ),
  );
}

Widget _infoBox(String emoji, String text) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F8FF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: const Color(0xFF0077B6).withOpacity(0.2)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text(emoji, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF3C3C43),
                  height: 1.5))),
    ]),
  );
}