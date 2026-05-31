// ─────────────────────────────────────────────
// fcm_service.dart — FoodFeast
//
// Handles:
//   1. Saving device FCM token to Firestore when a user logs in
//   2. Sending push notifications to a specific FCM token
//      using the FCM v1 HTTP API + service account from
//      assets/service_account.json (no Cloud Functions needed)
//
// USAGE — save token (call from restaurant dashboard initState):
//   await FcmService.saveToken();
//
// USAGE — send push (call from checkout after order placed):
//   await FcmService.sendPushToToken(
//     fcmToken: token,
//     title: '🛎️ New Order!',
//     body: 'Rahul ordered Burger x2 • ₹320',
//     data: {'orderId': 'abc123', 'type': 'new_order'},
//   );
// ─────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as gauth;

class FcmService {
  FcmService._();

  // Subscription handle — prevents duplicate listeners if saveToken() is
  // called more than once (e.g. dashboard hot-restart or multiple initState).
  static StreamSubscription<String>? _tokenRefreshSub;

  // ── 1. Save this device's FCM token to Firestore ─────────────────
  static Future<void> saveToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('[FCM] saveToken called. uid=$uid');
      if (uid == null) {
        debugPrint('[FCM] saveToken: no logged-in user, skipping.');
        return;
      }

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

      // [FIX] On web, getToken() requires a VAPID key so the browser can
      // register the firebase-messaging-sw.js service worker correctly.
      // Without it the SW registration fails with the MIME-type error seen
      // in the console (Flutter serves an HTML 404 instead of the JS file).
      // Replace the string below with your actual Web Push certificate key
      // from Firebase Console → Project Settings → Cloud Messaging → Web Push certificates.
      const vapidKey = 'YOUR_VAPID_KEY_FROM_FIREBASE_CONSOLE'; // ← replace this
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? vapidKey : null,
      );
      debugPrint('[FCM] Device token: $token');

      if (token == null) {
        debugPrint('[FCM] ERROR: getToken() returned null. '
            'On web: ensure firebase-messaging-sw.js exists in web/ folder '
            'and VAPID key is set correctly. '
            'On Android: check google-services.json and Google Play Services.');
        return;
      }

      await _writeToken(uid, token);

      // Cancel any existing listener before registering a new one —
      // prevents duplicate writes if saveToken() is called more than once.
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null) return;
        await _writeToken(currentUid, newToken);
        debugPrint('[FCM] Token refreshed and re-saved for uid=$currentUid');
      });
    } catch (e, st) {
      debugPrint('[FCM] saveToken ERROR: $e\n$st');
    }
  }

  // Writes the FCM token to:
  //   1. users/{uid}                    — for the user's own reference
  //   2. restaurants/{restaurantId}     — as ownerFcmToken, readable by
  //      any signed-in customer without hitting permission-denied.
  //      (Firestore rules only allow users to read their OWN user doc, so
  //       checkout_screen.dart cannot read users/{ownerUid} directly.)
  static Future<void> _writeToken(String uid, String token) async {
    // Always update the user doc
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'fcmToken': token});
    debugPrint('[FCM] ✅ Token saved to users/$uid');

    // Also write to the restaurant doc if this user is a restaurant owner
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final restaurantId = userDoc.data()?['restaurantId'] as String?;
      if (restaurantId != null && restaurantId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(restaurantId)
            .update({'ownerFcmToken': token});
        debugPrint('[FCM] ✅ ownerFcmToken saved to restaurants/$restaurantId');
      }
    } catch (e) {
      // Non-fatal — user might not be a restaurant owner
      debugPrint('[FCM] _writeToken: could not update restaurant doc: $e');
    }
  }

  // ── 2. Get OAuth2 access token from service account ──────────────
  static Future<String?> _getAccessToken() async {
    try {
      debugPrint('[FCM] Loading service_account.json...');
      final jsonStr =
          await rootBundle.loadString('assets/service_account.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      debugPrint('[FCM] service_account.json loaded. '
          'project_id=${json['project_id']}, '
          'client_email=${json['client_email']}');

      final accountCredentials =
          gauth.ServiceAccountCredentials.fromJson(json);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      debugPrint('[FCM] Requesting OAuth2 access token...');
      final client =
          await gauth.clientViaServiceAccount(accountCredentials, scopes);
      final token = client.credentials.accessToken.data;
      client.close();
      debugPrint('[FCM] ✅ Access token obtained (length=${token.length})');
      return token;
    } catch (e, st) {
      debugPrint('[FCM] _getAccessToken ERROR: $e\n$st');
      return null;
    }
  }

  // ── 3. Send push notification via FCM v1 HTTP API ────────────────
  static Future<bool> sendPushToToken({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    debugPrint('[FCM] sendPushToToken called.');
    debugPrint('[FCM]   title=$title');
    debugPrint('[FCM]   body=$body');
    debugPrint('[FCM]   token=${fcmToken.substring(0, 20)}...');

    try {
      final jsonStr =
          await rootBundle.loadString('assets/service_account.json');
      final serviceJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      final projectId = serviceJson['project_id'] as String;
      debugPrint('[FCM] project_id=$projectId');

      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        debugPrint('[FCM] ERROR: could not get OAuth2 access token. '
            'Check service_account.json has firebase.messaging scope enabled '
            'in Google Cloud Console → IAM → Service Accounts.');
        return false;
      }

      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      );

      final payload = {
        'message': {
          'token': fcmToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'sound': 'default',
              'channel_id': 'foodfeast_orders',
              'notification_priority': 'PRIORITY_HIGH',
              'visibility': 'PUBLIC',
            },
          },
          'data': {
            ...data,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      };

      debugPrint('[FCM] POSTing to FCM API...');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      debugPrint('[FCM] FCM API response: ${response.statusCode}');
      debugPrint('[FCM] FCM API body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('[FCM] ✅ Push notification sent successfully!');
        return true;
      } else {
        debugPrint('[FCM] ❌ Push failed. '
            'Status=${response.statusCode}. '
            'Check: (1) FCM API enabled in Google Cloud Console, '
            '(2) service account has "Firebase Cloud Messaging Admin" role, '
            '(3) FCM token is fresh (restaurant app was opened recently).');
        return false;
      }
    } catch (e, st) {
      debugPrint('[FCM] sendPushToToken ERROR: $e\n$st');
      return false;
    }
  }

  // ── 4. Foreground message handler ────────────────────────────────
  static void setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message received: '
          'title=${message.notification?.title}');
    });
  }

  // ── 5. Save admin device token ────────────────────────────────────
  // Call this right after a successful admin login so the admin's phone
  // is always reachable. Stores the token at:
  //   users/{adminUid}/fcmToken   — general token field (reuses _writeToken)
  //   config/admin               — adminFcmToken, readable by all signed-in
  //                                users (needed by help_support_screen to
  //                                notify admin without knowing the admin UID)
  static Future<void> saveAdminToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Verify this user really is admin before writing to config/admin
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if ((userDoc.data() as Map<String, dynamic>?)?['role'] != 'admin') {
        debugPrint('[FCM] saveAdminToken: user is not admin, skipping.');
        return;
      }

      // Request permission + get token (reuses existing permission logic)
      await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? 'YOUR_VAPID_KEY_FROM_FIREBASE_CONSOLE' : null,
      );
      if (token == null) {
        debugPrint('[FCM] saveAdminToken: getToken() returned null.');
        return;
      }

      // Write to the standard user doc
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': token});

      // Write to a well-known config doc so any signed-in user can read it
      // without knowing the admin UID (Firestore rules: allow read if
      // request.auth != null).
      await FirebaseFirestore.instance
          .collection('config')
          .doc('admin')
          .set({'adminFcmToken': token, 'updatedAt': FieldValue.serverTimestamp()},
               SetOptions(merge: true));

      debugPrint('[FCM] ✅ Admin token saved. uid=$uid');

      // Keep refreshing on token rotation
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null) return;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUid)
            .update({'fcmToken': newToken});
        await FirebaseFirestore.instance
            .collection('config')
            .doc('admin')
            .set({'adminFcmToken': newToken, 'updatedAt': FieldValue.serverTimestamp()},
                 SetOptions(merge: true));
        debugPrint('[FCM] Admin token refreshed. uid=$currentUid');
      });
    } catch (e, st) {
      debugPrint('[FCM] saveAdminToken ERROR: $e\n$st');
    }
  }

  // ── 6. Notify the admin (called by help_support_screen) ──────────
  // Reads adminFcmToken from config/admin, then fires a push.
  static Future<void> notifyAdmin({
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('admin')
          .get();
      final adminToken =
          (configDoc.data() as Map<String, dynamic>?)?['adminFcmToken']
              as String?;
      if (adminToken == null || adminToken.isEmpty) {
        debugPrint('[FCM] notifyAdmin: no admin token in config/admin. '
            'Admin must log in on their device first.');
        return;
      }
      await sendPushToToken(
          fcmToken: adminToken, title: title, body: body, data: data);
    } catch (e, st) {
      debugPrint('[FCM] notifyAdmin ERROR: $e\n$st');
    }
  }

  // ── 7. Notify a specific user by their UID ────────────────────────
  // Reads users/{userId}/fcmToken from Firestore, then fires a push.
  // Called by admin_screen when the admin replies to a support ticket.
  static Future<void> sendPushToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final userToken =
          (userDoc.data() as Map<String, dynamic>?)?['fcmToken'] as String?;
      if (userToken == null || userToken.isEmpty) {
        debugPrint('[FCM] sendPushToUser: no fcmToken for userId=$userId');
        return;
      }
      await sendPushToToken(
          fcmToken: userToken, title: title, body: body, data: data);
    } catch (e, st) {
      debugPrint('[FCM] sendPushToUser ERROR: $e\n$st');
    }
  }

  // ── 8. Send order-status push + write Firestore notification doc ─────────
  // Call this every time order status advances (checkout, restaurant screen,
  // delivery agent dashboard). Reads the customer's fcmToken from their user
  // doc and fires a push, then writes a notification doc so the in-app
  // notification list also shows the update.
  //
  // statusMessages maps each status value to the human-readable body text.
  static const _statusTitles = {
    'pending':          '🕐 Order Placed',
    'confirmed':        '✅ Order Confirmed',
    'preparing':        '👨‍🍳 Preparing Your Order',
    'ready_for_pickup': '🛵 Ready for Pickup',
    'picked_up':        '📦 Order Picked Up',
    'out_for_delivery': '🚀 Out for Delivery',
    'delivered':        '🎉 Order Delivered!',
    'cancelled':        '❌ Order Cancelled',
  };
  static const _statusBodies = {
    'pending':          'We\'ve received your order and are waiting for the restaurant to confirm.',
    'confirmed':        'Your order has been confirmed by the restaurant!',
    'preparing':        'The kitchen is preparing your delicious meal.',
    'ready_for_pickup': 'Your order is ready! Waiting for a delivery agent.',
    'picked_up':        'A delivery agent has picked up your order.',
    'out_for_delivery': 'Your order is on the way — hang tight!',
    'delivered':        'Your order has arrived. Enjoy your meal! 😋',
    'cancelled':        'Your order has been cancelled.',
  };

  // ── Human-readable descriptions shown in the detail sheet ─────────────────
  static const _statusDescriptions = {
    'pending':
        'Your order has been successfully placed and is waiting for the restaurant to accept it. '
        'This usually takes just a minute or two. You\'ll get notified the moment they confirm!',
    'confirmed':
        'Great news — the restaurant has accepted your order! '
        'They\'ll start preparing your food very soon. Sit tight and get ready to enjoy.',
    'preparing':
        'The kitchen is hard at work preparing your meal fresh just for you. '
        'This is where the magic happens! You\'ll be notified once your order is ready for pickup.',
    'ready_for_pickup':
        'Your order is packed and ready to go! '
        'We\'re now assigning a nearby delivery agent to pick it up. '
        'Delivery is just around the corner.',
    'picked_up':
        'A delivery agent has collected your order and is heading your way. '
        'You can track the live location of your delivery from the order details screen.',
    'out_for_delivery':
        'Your food is on the move! Your delivery agent is en route to your location. '
        'Make sure you\'re available to receive it. Expected arrival is very soon.',
    'delivered':
        'Your order has been successfully delivered to your doorstep. '
        'We hope you enjoy your meal! '
        'If you have any issues, you can raise a support ticket from the Help & Support section.',
    'cancelled':
        'Unfortunately your order has been cancelled. '
        'If any payment was made, a refund will be initiated within 5–7 business days. '
        'Please contact support if you have any questions.',
  };

  static Future<void> sendOrderStatusNotification({
    required String customerId,
    required String orderId,
    required String status,
    String? restaurantName,
    // Pass the token straight from the order doc to avoid reading
    // users/{customerId} — agents get permission-denied on that collection.
    String? customerFcmToken,
  }) async {
    try {
      final title = _statusTitles[status] ?? 'Order Update';
      var body  = _statusBodies[status] ?? 'Your order status has changed.';
      if (restaurantName != null && restaurantName.isNotEmpty &&
          (status == 'confirmed' || status == 'preparing')) {
        body = '$restaurantName: $body';
      }

      // Use the embedded token when available; fall back to user-doc lookup
      // only when the caller is the customer themselves (e.g. restaurant screen).
      if (customerFcmToken != null && customerFcmToken.isNotEmpty) {
        await sendPushToToken(
          fcmToken: customerFcmToken,
          title: title,
          body: body,
          data: {'type': 'order_status', 'orderId': orderId, 'status': status},
        );
      } else {
        await sendPushToUser(
          userId: customerId,
          title: title,
          body: body,
          data: {'type': 'order_status', 'orderId': orderId, 'status': status},
        );
      }

      // Write in-app notification doc
      await writeNotificationForUser(
        userId: customerId,
        title: title,
        body: body,
        orderId: orderId,
        type: 'order_status',
        status: status,
        description: _statusDescriptions[status],
      );

      debugPrint('[FCM] ✅ Status notification sent: $status → userId=$customerId');
    } catch (e, st) {
      debugPrint('[FCM] sendOrderStatusNotification ERROR: $e\n$st');
    }
  }

  // ── 9. Send agent-proximity alert to customer ──────────────────────────────
  // Fires a push + writes a notification doc when the delivery agent is close
  // (called from DeliveryAgentDashboard location timer).
  static Future<void> sendAgentProximityAlert({
    required String customerId,
    required String orderId,
    required int    etaMinutes,
    String? agentName,
    String? customerFcmToken,
  }) async {
    try {
      final name  = (agentName != null && agentName.isNotEmpty) ? agentName : 'Your delivery agent';
      final title = '📍 $name is almost there!';
      final body  = etaMinutes <= 1
          ? '$name is arriving now!'
          : '$name will reach you in ~$etaMinutes min.';

      if (customerFcmToken != null && customerFcmToken.isNotEmpty) {
        await sendPushToToken(
          fcmToken: customerFcmToken,
          title: title,
          body: body,
          data: {'type': 'agent_proximity', 'orderId': orderId, 'eta': etaMinutes.toString()},
        );
      } else {
        await sendPushToUser(
          userId: customerId,
          title: title,
          body: body,
          data: {'type': 'agent_proximity', 'orderId': orderId, 'eta': etaMinutes.toString()},
        );
      }

      await writeNotificationForUser(
        userId: customerId,
        title: title,
        body: body,
        orderId: orderId,
        type: 'agent_proximity',
        description: etaMinutes <= 1
            ? 'Your delivery agent has arrived at your location! Please be ready to collect your order.'
            : 'Your delivery agent is only about $etaMinutes minutes away from your location. '
              'Please make sure you are available to receive the delivery.',
      );

      debugPrint('[FCM] ✅ Proximity alert sent → userId=$customerId eta=${etaMinutes}min');
    } catch (e, st) {
      debugPrint('[FCM] sendAgentProximityAlert ERROR: $e\n$st');
    }
  }

  // ── 10. Write a notification doc to Firestore ─────────────────────────────
  // Creates a doc in notifications/{auto-id} that NotificationScreen
  // will display for the specific user (targetUid).
  // Call this alongside sendPushToUser so the reply also appears in
  // the in-app notification list.
  static Future<void> writeNotificationForUser({
    required String userId,
    required String title,
    required String body,
    String? ticketId,
    String? collection,
    String? orderId,
    String? type,
    String? status,
    String? description,
  }) async {
    try {
      final doc = {
        'targetUid':   userId,
        'title':       title,
        'body':        body,
        'type':        type ?? 'admin_reply',
        'ticketId':    ticketId ?? '',
        'collection':  collection ?? 'support_tickets',
        'sentAt':      FieldValue.serverTimestamp(),
        'read':        false,
        if (description != null && description.isNotEmpty)
          'description': description,
      };
      if (orderId != null) doc['orderId'] = orderId;
      if (status  != null) doc['orderStatus'] = status;
      await FirebaseFirestore.instance.collection('notifications').add(doc);
      debugPrint('[FCM] ✅ Notification doc written for userId=$userId');
    } catch (e, st) {
      debugPrint('[FCM] writeNotificationForUser ERROR: $e\n$st');
    }
  }
}