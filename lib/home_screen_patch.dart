// ═══════════════════════════════════════════════════════════════════
// PATCH 1 of 3 — home_screen.dart
//
// Changes made:
//   1. Import notification_screen.dart
//   2. Listen to NotificationService for unread badge on bell icon
//   3. Bell icon navigates to NotificationScreen
//   4. FCM + local notification setup via NotificationSetup helper
//      (add to pubspec: firebase_messaging & flutter_local_notifications)
// ═══════════════════════════════════════════════════════════════════

// ─── pubspec.yaml additions ────────────────────────────────────────
// dependencies:
//   firebase_messaging: ^14.9.4
//   flutter_local_notifications: ^17.2.1+2
//
// AndroidManifest.xml  (inside <application>):
//   <service
//       android:name="com.google.firebase.messaging.FirebaseMessagingService"
//       android:exported="false">
//     <intent-filter>
//       <action android:name="com.google.firebase.MESSAGING_EVENT"/>
//     </intent-filter>
//   </service>
//
// Info.plist (iOS):  request notification permissions via Xcode capabilities.
// ──────────────────────────────────────────────────────────────────

// ══════════════════════════════════════════════
// STEP A — New imports to add at the top of home_screen.dart
// ══════════════════════════════════════════════
/*
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_screen.dart';
*/

// ══════════════════════════════════════════════
// STEP B — Paste this entire helper class anywhere
//           OUTSIDE _HomeScreenState, e.g. just above HomeScreen
// ══════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Background message handler — must be top-level
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs on Android
  debugPrint('BG FCM: ${message.notification?.title}');
}

class NotificationSetup {
  NotificationSetup._();
  static final instance = NotificationSetup._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    // ── Local notification channel (Android) ──
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Android 13+ runtime permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // ── FCM setup ─────────────────────────────
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Save FCM token to user's Firestore doc so backend/admin can send targeted
    final token = await messaging.getToken();
    _saveFcmToken(token);
    messaging.onTokenRefresh.listen(_saveFcmToken);

    // Foreground messages → show local notification
    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n != null) _showLocal(n.title ?? 'FoodFeast', n.body ?? '');
    });

    _ready = true;
  }

  void _saveFcmToken(String? token) {
    if (token == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  Future<void> _showLocal(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'foodfeast_channel',
      'FoodFeast Notifications',
      channelDescription: 'Order updates and promotions',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}

// ══════════════════════════════════════════════
// STEP C — In _HomeScreenState.initState(), add:
//
//   @override
//   void initState() {
//     super.initState();
//     CalorieTracker.instance.loadTodayData();
//     _loadPhotoUrl();
//     NotificationSetup.instance.init();   // ← ADD THIS LINE
//   }
// ══════════════════════════════════════════════

// ══════════════════════════════════════════════
// STEP D — Replace _buildHeader() with this version.
//   It adds an unread badge on the bell and navigates to NotificationScreen.
// ══════════════════════════════════════════════
//
// (Copy-paste the method below, replacing the existing _buildHeader())

/*
Widget _buildHeader() {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(
            text: const TextSpan(children: [
          TextSpan(
              text: 'Food',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          TextSpan(
              text: 'Feast',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _red)),
        ])),
        Row(children: const [
          Icon(Icons.location_on_rounded, color: _red, size: 14),
          SizedBox(width: 3),
          Text('Chhindwara, MP',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E))),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF1C1C1E), size: 16),
        ]),
      ]),
      Row(children: [

        // ── NOTIFICATION BELL WITH BADGE ──────────────────
        AnimatedBuilder(
          animation: NotificationService.instance,
          builder: (_, __) {
            final count = NotificationService.instance.unreadCount;
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationScreen(),
                  ),
                );
              },
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: const Icon(Icons.notifications_outlined,
                      color: Color(0xFF1C1C1E), size: 22),
                ),
                if (count > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                          color: _red,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5)),
                      child: Center(
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
              ]),
            );
          },
        ),
        // ── END BELL ──────────────────────────────────────

        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => setState(() => _selectedIndex = 4),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _red.withOpacity(0.15),
                boxShadow: [
                  BoxShadow(
                      color: _red.withOpacity(0.2), blurRadius: 6)
                ]),
            child: ClipOval(
              child: _photoUrl.isNotEmpty
                  ? Image.network(_photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                          child: Text(_userInitials,
                              style: const TextStyle(
                                  color: _red,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13))))
                  : Center(
                      child: Text(_userInitials,
                          style: const TextStyle(
                              color: _red,
                              fontWeight: FontWeight.w700,
                              fontSize: 13))),
            ),
          ),
        ),
      ]),
    ]),
  );
}
*/

// ══════════════════════════════════════════════
// STEP E — Admin sends FCM push alongside Firestore write
//
// In admin_screen.dart, inside _sendNotification() in _NotificationManagerState,
// AFTER the FirebaseFirestore.instance.collection('notifications').add({...}) call,
// add this HTTP call (or use firebase_messaging on the backend).
//
// The simplest zero-backend approach: use FCM's legacy HTTP v1 API from admin.
// Below is the Dart HTTP snippet you can paste into admin_screen.dart.
// Replace <YOUR_SERVER_KEY> with the key from:
//   Firebase Console → Project Settings → Cloud Messaging → Server Key
//
// Add to admin pubspec.yaml:  http: ^1.2.1
// Add import:  import 'package:http/http.dart' as http;
//
// Then paste this method into _NotificationManagerState:
/*
  Future<void> _sendFcmToAll({
    required String title,
    required String body,
  }) async {
    const serverKey = '<YOUR_SERVER_KEY>'; // replace
    await http.post(
      Uri.parse('https://fcm.googleapis.com/fcm/send'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'key=$serverKey',
      },
      body: jsonEncode({
        'to': '/topics/all_users',
        'notification': {'title': title, 'body': body},
        'data': {'click_action': 'FLUTTER_NOTIFICATION_CLICK'},
      }),
    );
  }
*/
//
// Then in _sendNotification(), after the Firestore add, call:
//   await _sendFcmToAll(title: _titleCtrl.text.trim(), body: _bodyCtrl.text.trim());
//
// And in the app (home_screen.dart initState after NotificationSetup.instance.init()):
//   await FirebaseMessaging.instance.subscribeToTopic('all_users');
// ══════════════════════════════════════════════
