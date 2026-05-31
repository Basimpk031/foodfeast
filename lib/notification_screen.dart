// ─────────────────────────────────────────────
// notification_screen.dart — FoodFeast
// • Reads notifications from Firestore 'notifications' collection
// • Marks notifications as read per-user in 'notificationReads/{uid}'
// • Unread badge count is exposed via NotificationService
// • Tap a notification → rich detail bottom sheet with full description
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'help_support_screen.dart';

// ─────────────────────────────────────────────
// NotificationService  (singleton)
// ─────────────────────────────────────────────
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final instance = NotificationService._();

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  void updateCount(int count) {
    if (_unreadCount != count) {
      _unreadCount = count;
      notifyListeners();
    }
  }

  void startListening(String uid) {
    FirebaseFirestore.instance
        .collection('notificationReads')
        .doc(uid)
        .snapshots()
        .listen((_) => _refreshCount(uid));

    FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((_) => _refreshCount(uid));

    _refreshCount(uid);
  }

  Future<void> _refreshCount(String uid) async {
    try {
      final readsSnap = await FirebaseFirestore.instance
          .collection('notificationReads')
          .doc(uid)
          .get();
      final readData = (readsSnap.data() as Map<String, dynamic>?) ?? {};

      final notifSnap = await FirebaseFirestore.instance
          .collection('notifications')
          .orderBy('sentAt', descending: true)
          .limit(50)
          .get();

      final relevant = notifSnap.docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        final target = data['targetUid'] as String?;
        return target == null || target.isEmpty || target == uid;
      });

      final unread = relevant.where((d) => readData[d.id] != true).length;
      updateCount(unread);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────
// _NotifStyle — per-type visual config
// ─────────────────────────────────────────────
class _NotifStyle {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String label;

  const _NotifStyle({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.label,
  });
}

_NotifStyle _styleFor(String type, {bool isRead = false}) {
  const grey = Color(0xFF8E8E93);
  const greyBg = Color(0xFFF2F2F7);

  final styles = <String, _NotifStyle>{
    'order_status': _NotifStyle(
      icon: Icons.receipt_long_rounded,
      color: isRead ? grey : const Color(0xFF0077B6),
      bgColor: isRead ? greyBg : const Color(0xFFE8F4FB),
      label: 'Order Update',
    ),
    'agent_proximity': _NotifStyle(
      icon: Icons.delivery_dining_rounded,
      color: isRead ? grey : const Color(0xFF00A86B),
      bgColor: isRead ? greyBg : const Color(0xFFE6F7F1),
      label: 'Delivery',
    ),
    'admin_reply': _NotifStyle(
      icon: Icons.support_agent_rounded,
      color: isRead ? grey : const Color(0xFF0077B6),
      bgColor: isRead ? greyBg : const Color(0xFFE8F4FB),
      label: 'Support',
    ),
    'coupon': _NotifStyle(
      icon: Icons.local_offer_rounded,
      color: isRead ? grey : const Color(0xFFCC9000),
      bgColor: isRead ? greyBg : const Color(0xFFFFF8E1),
      label: 'Offer',
    ),
    'promo': _NotifStyle(
      icon: Icons.celebration_rounded,
      color: isRead ? grey : const Color(0xFFE85D04),
      bgColor: isRead ? greyBg : const Color(0xFFFFF0E8),
      label: 'Promo',
    ),
    'new_order': _NotifStyle(
      icon: Icons.shopping_bag_rounded,
      color: isRead ? grey : const Color(0xFF6C63FF),
      bgColor: isRead ? greyBg : const Color(0xFFF0EEFF),
      label: 'New Order',
    ),
  };

  return styles[type] ??
      _NotifStyle(
        icon: Icons.campaign_rounded,
        color: isRead ? grey : const Color(0xFF0077B6),
        bgColor: isRead ? greyBg : const Color(0xFFE8F4FB),
        label: 'Notification',
      );
}

// ─────────────────────────────────────────────
// NotificationScreen
// ─────────────────────────────────────────────
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  static const _blue = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFB800);

  late final AnimationController _headerAnim;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    super.dispose();
  }

  Future<void> _markRead(String notifId) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('notificationReads')
        .doc(uid)
        .set({notifId: true}, SetOptions(merge: true));
  }

  Future<void> _markAllRead(List<String> ids) async {
    final uid = _uid;
    if (uid == null) return;
    final Map<String, dynamic> batch = {for (final id in ids) id: true};
    await FirebaseFirestore.instance
        .collection('notificationReads')
        .doc(uid)
        .set(batch, SetOptions(merge: true));
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _fullDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month]} ${dt.day}, ${dt.year}  ·  $h:$m $ampm';
  }

  // ── Open rich detail bottom sheet on tap ──────────────────────────
  void _openDetail(
      BuildContext context, Map<String, dynamic> data, bool isRead) {
    final type = data['type'] as String? ?? '';
    final style = _styleFor(type, isRead: false);
    final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
    final linkedCoupon = data['linkedCoupon'] as String?;
    final description = data['description'] as String?;
    final isAdminReply = type == 'admin_reply';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotifDetailSheet(
        data: data,
        style: style,
        sentAt: sentAt,
        linkedCoupon: linkedCoupon,
        description: description,
        isAdminReply: isAdminReply,
        fullDate: sentAt != null ? _fullDate(sentAt) : '',
        onGoToSupport: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const HelpSupportScreen(initialTab: 5),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view notifications.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notificationReads')
            .doc(uid)
            .snapshots(),
        builder: (context, readSnap) {
          final readData =
              (readSnap.data?.data() as Map<String, dynamic>?) ?? {};

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .orderBy('sentAt', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, notifSnap) {
              if (notifSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: _blue));
              }

              final allDocs = notifSnap.data?.docs ?? [];
              final docs = allDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final target = data['targetUid'] as String?;
                return target == null || target.isEmpty || target == uid;
              }).toList();

              final unread =
                  docs.where((d) => readData[d.id] != true).length;
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => NotificationService.instance.updateCount(unread));

              return CustomScrollView(
                slivers: [
                  // ── Gradient SliverAppBar ──────────────────────────
                  SliverAppBar(
                    expandedHeight: 120,
                    pinned: true,
                    backgroundColor: _blue,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    actions: [
                      if (docs.any((d) => readData[d.id] != true))
                        TextButton.icon(
                          onPressed: () =>
                              _markAllRead(docs.map((d) => d.id).toList()),
                          icon: const Icon(Icons.done_all_rounded,
                              color: Colors.white70, size: 16),
                          label: const Text('Mark all read',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(width: 4),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('         Notifications',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: _gold,
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text('$unread new',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF005F8E), Color(0xFF0099CC)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Opacity(
                            opacity: 0.08,
                            child: Icon(Icons.notifications_rounded,
                                size: 140, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Empty state ────────────────────────────────────
                  if (docs.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                  color: _blue.withOpacity(0.08),
                                  shape: BoxShape.circle),
                              child: const Icon(
                                  Icons.notifications_off_outlined,
                                  size: 44,
                                  color: _blue),
                            ),
                            const SizedBox(height: 20),
                            const Text('All caught up!',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1C1C1E))),
                            const SizedBox(height: 6),
                            const Text("No notifications yet.",
                                style: TextStyle(
                                    fontSize: 14, color: Color(0xFF6E6E73))),
                          ],
                        ),
                      ),
                    ),

                  // ── Notification list ──────────────────────────────
                  if (docs.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final doc = docs[i];
                            final data =
                                doc.data() as Map<String, dynamic>;
                            final isRead = readData[doc.id] == true;
                            final sentAt =
                                (data['sentAt'] as Timestamp?)?.toDate();
                            final linkedCoupon =
                                data['linkedCoupon'] as String?;
                            final type = data['type'] as String? ?? '';
                            final isAdminReply = type == 'admin_reply';
                            final style = _styleFor(type, isRead: isRead);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _NotifCard(
                                data: data,
                                isRead: isRead,
                                sentAt: sentAt,
                                linkedCoupon: linkedCoupon,
                                isAdminReply: isAdminReply,
                                style: style,
                                timeAgo: sentAt != null
                                    ? _timeAgo(sentAt)
                                    : '',
                                onTap: () async {
                                  await _markRead(doc.id);
                                  if (context.mounted) {
                                    _openDetail(context, data, isRead);
                                  }
                                },
                              ),
                            );
                          },
                          childCount: docs.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _NotifCard — list item widget
// ─────────────────────────────────────────────
class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? sentAt;
  final String? linkedCoupon;
  final bool isAdminReply;
  final _NotifStyle style;
  final String timeAgo;
  final VoidCallback onTap;

  static const _gold = Color(0xFFFFB800);

  const _NotifCard({
    required this.data,
    required this.isRead,
    required this.sentAt,
    required this.linkedCoupon,
    required this.isAdminReply,
    required this.style,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : style.bgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isRead
                  ? const Color(0xFFE5E5EA)
                  : style.color.withOpacity(0.25),
              width: isRead ? 1 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isRead
                    ? Colors.black.withOpacity(0.03)
                    : style.color.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Type icon ──
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: style.bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: style.color.withOpacity(0.2), width: 1),
              ),
              child: Icon(style.icon, size: 22, color: style.color),
            ),
            const SizedBox(width: 12),

            // ── Content ──
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Title row
                Row(children: [
                  Expanded(
                    child: Text(
                      data['title'] ?? '',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isRead ? FontWeight.w600 : FontWeight.w800,
                          color: const Color(0xFF1C1C1E)),
                    ),
                  ),
                  if (!isRead)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(left: 6, top: 2),
                      decoration: BoxDecoration(
                          color: style.color, shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 4),

                // Body preview (2 lines max)
                Text(
                  data['body'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: isRead
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFF3A3A3C),
                      height: 1.45),
                ),
                const SizedBox(height: 8),

                // Chips + time row
                Row(children: [
                  // Type chip
                  _Chip(
                    label: style.label,
                    color: style.color,
                    bgColor: style.bgColor,
                    icon: style.icon,
                  ),
                  const SizedBox(width: 6),

                  // Admin reply chip
                  if (isAdminReply)
                    _Chip(
                      label: 'Tap to view',
                      color: const Color(0xFF0077B6),
                      bgColor: const Color(0xFFE8F4FB),
                      icon: Icons.open_in_new_rounded,
                    ),

                  // Coupon chip
                  if (linkedCoupon != null) ...[
                    if (isAdminReply) const SizedBox(width: 6),
                    _Chip(
                      label: linkedCoupon!,
                      color: const Color(0xFFCC9000),
                      bgColor: const Color(0xFFFFF8E1),
                      icon: Icons.local_offer_rounded,
                    ),
                  ],

                  const Spacer(),
                  Text(
                    timeAgo,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFAEAEB2)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _Chip — small coloured label
// ─────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _Chip({
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// _NotifDetailSheet — rich bottom sheet shown on tap
// ─────────────────────────────────────────────
class _NotifDetailSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final _NotifStyle style;
  final DateTime? sentAt;
  final String? linkedCoupon;
  final String? description;
  final bool isAdminReply;
  final String fullDate;
  final VoidCallback onGoToSupport;

  const _NotifDetailSheet({
    required this.data,
    required this.style,
    required this.sentAt,
    required this.linkedCoupon,
    required this.description,
    required this.isAdminReply,
    required this.fullDate,
    required this.onGoToSupport,
  });

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final orderStatus = data['orderStatus'] as String?;
    final orderId = data['orderId'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 4),

          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // ── Hero icon + type label ──────────────────────────
                Center(
                  child: Column(children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: style.bgColor,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: style.color.withOpacity(0.18),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: Icon(style.icon, size: 34, color: style.color),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: style.bgColor,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(style.label.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: style.color,
                              letterSpacing: 0.8)),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Title ──────────────────────────────────────────
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1E),
                        height: 1.3)),
                const SizedBox(height: 6),

                // ── Timestamp ─────────────────────────────────────
                if (fullDate.isNotEmpty)
                  Center(
                    child: Text(fullDate,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFAEAEB2),
                            fontWeight: FontWeight.w500)),
                  ),
                const SizedBox(height: 20),

                // ── Divider ───────────────────────────────────────
                Container(height: 1, color: const Color(0xFFF2F2F7)),
                const SizedBox(height: 20),

                // ── Body message ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFFE5E5EA), width: 1),
                  ),
                  child: Text(body,
                      style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1C1C1E),
                          height: 1.6)),
                ),
                const SizedBox(height: 16),

                // ── Description (rich) ────────────────────────────
                if (description != null && description!.isNotEmpty) ...[
                  Row(children: [
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: style.color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Details',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3A3A3C))),
                  ]),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          style.bgColor,
                          style.bgColor.withOpacity(0.4)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: style.color.withOpacity(0.15), width: 1),
                    ),
                    child: Text(description!,
                        style: TextStyle(
                            fontSize: 14,
                            color: style.color
                                .withOpacity(isAdminReply ? 0.85 : 0.9),
                            height: 1.65,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Order status badge ─────────────────────────────
                if (orderStatus != null) ...[
                  _DetailRow(
                    icon: Icons.local_shipping_rounded,
                    label: 'Status',
                    value: _prettyStatus(orderStatus),
                    color: style.color,
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Order ID ──────────────────────────────────────
                if (orderId != null && orderId.isNotEmpty) ...[
                  _DetailRow(
                    icon: Icons.tag_rounded,
                    label: 'Order ID',
                    value: '#${orderId.substring(0, orderId.length.clamp(0, 8)).toUpperCase()}',
                    color: style.color,
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Coupon chip ───────────────────────────────────
                if (linkedCoupon != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFFFB800).withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.local_offer_rounded,
                          size: 20, color: Color(0xFFCC9000)),
                      const SizedBox(width: 10),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Coupon Code',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF8E8E93),
                                    fontWeight: FontWeight.w600)),
                            Text(linkedCoupon!,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFCC9000),
                                    letterSpacing: 1.2)),
                          ]),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── CTA button (admin reply) ────────────────────────
                if (isAdminReply) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: style.color,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: onGoToSupport,
                      icon: const Icon(Icons.help_outline_rounded,
                          size: 18, color: Colors.white),
                      label: const Text('Go to Help & Support',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _prettyStatus(String s) {
    return s
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }
}

// ─────────────────────────────────────────────
// _DetailRow — labelled row inside detail sheet
// ─────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8E8E93),
                fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E))),
      ]),
    );
  }
}
