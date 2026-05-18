// ─────────────────────────────────────────────
// notification_screen.dart — FoodFeast
// • Reads notifications from Firestore 'notifications' collection
// • Marks notifications as read per-user in 'notificationReads/{uid}'
// • Unread badge count is exposed via NotificationService
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'help_support_screen.dart'; // FIX: needed for "Go to Help & Support" deep-link

// ─────────────────────────────────────────────
// NotificationService  (singleton — import this
// from home_screen.dart to get unread count)
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

  // Call this once from HomeScreen.initState so the badge shows immediately
  // without waiting for the user to open NotificationScreen.
  void startListening(String uid) {
    // Listen to reads doc
    FirebaseFirestore.instance
        .collection('notificationReads')
        .doc(uid)
        .snapshots()
        .listen((_) => _refreshCount(uid));

    // Listen to notifications collection
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
// NotificationScreen
// ─────────────────────────────────────────────
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  static const _blue = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFB800);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── Mark a single notification as read ──────
  Future<void> _markRead(String notifId) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('notificationReads')
        .doc(uid)
        .set({notifId: true}, SetOptions(merge: true));
  }

  // ── Mark ALL as read ────────────────────────
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

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view notifications.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
        actions: [
          // ── Mark all read button ──
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notificationReads')
                .doc(uid)
                .snapshots(),
            builder: (context, readSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .orderBy('sentAt', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (context, notifSnap) {
                  final readData =
                      (readSnap.data?.data() as Map<String, dynamic>?) ?? {};
                  final allDocs = notifSnap.data?.docs ?? [];
                  // Same filter: broadcast + personal
                  final docs = allDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final target = data['targetUid'] as String?;
                    return target == null || target.isEmpty || target == uid;
                  }).toList();
                  final hasUnread =
                      docs.any((d) => readData[d.id] != true);
                  if (!hasUnread) return const SizedBox.shrink();
                  return TextButton(
                    onPressed: () =>
                        _markAllRead(docs.map((d) => d.id).toList()),
                    child: const Text('Mark all read',
                        style: TextStyle(
                            color: _blue,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  );
                },
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E5EA)),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notificationReads')
            .doc(uid)
            .snapshots(),
        builder: (context, readSnap) {
          final readData =
              (readSnap.data?.data() as Map<String, dynamic>?) ?? {};

          // ── Fetch ALL notifications:
          //    1. Broadcast (no targetUid field, or targetUid == null)
          //    2. Personal (targetUid == this user's uid)
          // We do two queries and merge them client-side since Firestore
          // doesn't support OR on different fields in one query.
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

              // Show broadcast notifications (no targetUid) AND personal ones
              final allDocs = notifSnap.data?.docs ?? [];
              final docs = allDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final target = data['targetUid'] as String?;
                // Show if broadcast (null/empty targetUid) OR addressed to this user
                return target == null || target.isEmpty || target == uid;
              }).toList();

              // ── Update global unread count ──
              final unread =
                  docs.where((d) => readData[d.id] != true).length;
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => NotificationService.instance.updateCount(unread));

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            color: _blue.withOpacity(0.08),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.notifications_off_outlined,
                            size: 38, color: _blue),
                      ),
                      const SizedBox(height: 16),
                      const Text('No notifications yet',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E))),
                      const SizedBox(height: 6),
                      const Text("You're all caught up!",
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF6E6E73))),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final isRead = readData[doc.id] == true;
                  final sentAt =
                      (data['sentAt'] as Timestamp?)?.toDate();
                  final linkedCoupon =
                      data['linkedCoupon'] as String?;
                  final notifType =
                      data['type'] as String? ?? '';
                  final isAdminReply = notifType == 'admin_reply';

                  return GestureDetector(
                    onTap: () {
                      _markRead(doc.id);
                      // Deep-link to Help & Support → My Tickets tab
                      if (isAdminReply) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const _SupportReplyDetailScreen(),
                          ),
                        );
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isRead
                            ? Colors.white
                            : _blue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isRead
                              ? const Color(0xFFE5E5EA)
                              : _blue.withOpacity(0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        // ── Icon ──
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                              color: isRead
                                  ? const Color(0xFFF5F5F7)
                                  : (isAdminReply
                                      ? const Color(0xFF0077B6).withOpacity(0.1)
                                      : _blue.withOpacity(0.1)),
                              borderRadius: BorderRadius.circular(12)),
                          child: Icon(
                            isAdminReply
                                ? Icons.support_agent_rounded
                                : Icons.campaign_rounded,
                            size: 22,
                            color: isRead
                                ? const Color(0xFF6E6E73)
                                : (isAdminReply ? const Color(0xFF0077B6) : _blue),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // ── Content ──
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  data['title'] ?? '',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isRead
                                          ? FontWeight.w600
                                          : FontWeight.w800,
                                      color: const Color(0xFF1C1C1E)),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                      color: _blue,
                                      shape: BoxShape.circle),
                                ),
                            ]),
                            const SizedBox(height: 4),
                            Text(
                              data['body'] ?? '',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6E6E73),
                                  height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              if (isAdminReply) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: _blue.withOpacity(0.10),
                                      borderRadius:
                                          BorderRadius.circular(6)),
                                  child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.support_agent_rounded,
                                            size: 11,
                                            color: Color(0xFF0077B6)),
                                        SizedBox(width: 4),
                                        Text('Tap to view reply',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0077B6))),
                                      ]),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (linkedCoupon != null) ...[
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: _gold.withOpacity(0.12),
                                      borderRadius:
                                          BorderRadius.circular(6)),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                            Icons.local_offer_rounded,
                                            size: 11,
                                            color: Color(0xFFCC9000)),
                                        const SizedBox(width: 4),
                                        Text(linkedCoupon,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    Color(0xFFCC9000))),
                                      ]),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (sentAt != null)
                                Text(
                                  _timeAgo(sentAt),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFAEAEB2)),
                                ),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Deep-link screen: opens Help & Support on
// the "My Tickets" tab (index 5) so the user
// can read the admin reply and reply back.
// ─────────────────────────────────────────────
class _SupportReplyDetailScreen extends StatelessWidget {
  const _SupportReplyDetailScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Support Reply',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1C1C1E))),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: const Color(0xFF0077B6).withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.support_agent_rounded,
                    size: 36, color: Color(0xFF0077B6)),
              ),
              const SizedBox(height: 20),
              const Text('Admin has replied to your ticket!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 8),
              const Text(
                'Go to Help & Support → My Tickets tab to read the reply and respond.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6E6E73),
                    height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0077B6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    // FIX: was only calling Navigator.pop — never navigating.
                    // Now pops this detail screen AND pushes HelpSupportScreen
                    // directly on the My Tickets tab (index 5).
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const HelpSupportScreen(initialTab: 5),
                      ),
                    );
                  },
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
          ),
        ),
      ),
    );
  }
}