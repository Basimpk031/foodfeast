// ─────────────────────────────────────────────
// local_notification_service.dart — FoodFeast
//
// Shows heads-up (popup) notifications on the Android
// notification bar even when the app is in the foreground.
//
// SETUP — call once from main.dart:
//   await LocalNotificationService.init();
//
// SHOW — call when FCM message arrives in foreground:
//   LocalNotificationService.showFromRemoteMessage(message);
//
// ETA / ARRIVAL shortcuts (new):
//   LocalNotificationService.showEtaAlert(etaMinutes: 5, destName: 'John');
//   LocalNotificationService.showArrivalAlert(destName: 'John');
//   LocalNotificationService.showRerouteAlert(newEta: '12 min');
//   LocalNotificationService.showCustomerArrival(restaurantName: 'Burger Barn');
// ─────────────────────────────────────────────

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  // ── Channel: order alerts (restaurant / agent) ─────────────────────────────
  static const _orderChannel = AndroidNotificationChannel(
    'foodfeast_orders',
    'Order Alerts',
    description: 'New order notifications for restaurant owners',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // ── Channel: navigation / ETA alerts (agent) ──────────────────────────────
  static const _navChannel = AndroidNotificationChannel(
    'foodfeast_navigation',
    'Navigation Alerts',
    description: 'Turn-by-turn navigation, ETA, and arrival alerts for delivery agents',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // ── Channel: delivery updates (customer) ───────────────────────────────────
  static const _deliveryChannel = AndroidNotificationChannel(
    'foodfeast_delivery',
    'Delivery Updates',
    description: 'Live delivery status and arrival notifications for customers',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // ── Stable notification IDs ────────────────────────────────────────────────
  static const _idEta        = 2000;
  static const _idArrival    = 2001;
  static const _idReroute    = 2002;
  static const _idCustArrival= 3000;

  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Register all three channels
    await androidImpl?.createNotificationChannel(_orderChannel);
    await androidImpl?.createNotificationChannel(_navChannel);
    await androidImpl?.createNotificationChannel(_deliveryChannel);

    // Initialise the plugin
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
  }

  // ─── FCM foreground passthrough ───────────────────────────────────────────
  /// Call this inside FirebaseMessaging.onMessage.listen(...)
  static Future<void> showFromRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await showNotification(
      id:        notification.hashCode,
      title:     notification.title ?? '',
      body:      notification.body  ?? '',
      channelId: _orderChannel.id,
    );
  }

  // ─── Generic show ─────────────────────────────────────────────────────────
  /// Low-level helper — prefer the named shortcuts below when possible.
  /// Pass [description] to show expanded big-text style in the notification drawer.
  static Future<void> showNotification({
    required int    id,
    required String title,
    required String body,
    String?         channelId,    // defaults to _orderChannel
    String?         description,  // optional expanded text shown in drawer
  }) async {
    final chId   = channelId ?? _orderChannel.id;
    final chName = _channelName(chId);

    // Use BigTextStyleInformation when a description is provided so Android
    // expands the notification to show the full detail text.
    final styleInfo = (description != null && description.isNotEmpty)
        ? BigTextStyleInformation(
            description,
            contentTitle: title,
            summaryText: body,
          )
        : null;

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          chId,
          chName,
          importance:      Importance.max,
          priority:        Priority.high,
          playSound:       true,
          enableVibration: true,
          icon:            '@mipmap/ic_launcher',
          styleInformation: styleInfo,
        ),
      ),
    );
  }

  // ─── Navigation / ETA shortcuts ───────────────────────────────────────────

  /// Agent: "You'll reach <destName> in ~<N> min" (fires when ETA ≤ threshold).
  static Future<void> showEtaAlert({
    required int    etaMinutes,
    required String destName,
  }) async {
    await showNotification(
      id:          _idEta,
      title:       '📍 Almost there!',
      body:        "You'll reach $destName in ~$etaMinutes min.",
      channelId:   _navChannel.id,
      description: "You are approximately $etaMinutes minute${etaMinutes == 1 ? '' : 's'} away from $destName's location. "
                   "Slow down and follow the route carefully. Once you arrive, "
                   "confirm the delivery and hand the order to the customer.",
    );
  }

  /// Agent: fires when haversine distance to destination ≤ arrival radius.
  static Future<void> showArrivalAlert({required String destName}) async {
    await showNotification(
      id:          _idArrival,
      title:       '✅ Arrived at Destination',
      body:        "You have reached $destName's location. Complete the delivery!",
      channelId:   _navChannel.id,
      description: "You have reached $destName's delivery address. "
                   "Please hand over the order, confirm delivery in the app, "
                   "and collect any cash payment if applicable. Safe travels on your next trip!",
    );
  }

  /// Agent: fires when traffic reroute produces a new ETA.
  static Future<void> showRerouteAlert({required String newEta}) async {
    await showNotification(
      id:          _idReroute,
      title:       '🔄 Route Updated',
      body:        'Traffic detected — your route has been updated. New ETA: $newEta',
      channelId:   _navChannel.id,
      description: 'Due to traffic or road conditions, your navigation route has been recalculated. '
                   'Your new estimated arrival time is $newEta. '
                   'Please follow the updated route shown on the map.',
    );
  }

  // ─── Customer delivery shortcuts ──────────────────────────────────────────

  /// Customer: fires when order status transitions to 'delivered'.
  static Future<void> showCustomerArrival({
    required String restaurantName,
  }) async {
    await showNotification(
      id:          _idCustArrival,
      title:       '🎉 Your order has arrived!',
      body:        'Your delivery from $restaurantName is here. Enjoy your meal!',
      channelId:   _deliveryChannel.id,
      description: 'Your order from $restaurantName has been successfully delivered to your doorstep. '
                   'We hope you enjoy your meal! '
                   'If anything is missing or incorrect, please reach out via Help & Support.',
    );
  }

  // ─── Internal ─────────────────────────────────────────────────────────────
  static String _channelName(String id) {
    switch (id) {
      case 'foodfeast_navigation': return _navChannel.name;
      case 'foodfeast_delivery':   return _deliveryChannel.name;
      default:                     return _orderChannel.name;
    }
  }
}