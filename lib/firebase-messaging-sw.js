// ─────────────────────────────────────────────────────────────────────────────
// firebase-messaging-sw.js
//
// ⚠️  IMPORTANT: Place this file in your project's  web/  folder, NOT in lib/.
//     Flutter's web build copies everything from web/ to the build output root,
//     which is the only place the browser can register a service worker.
//
//     File path in your project:
//       your_app/
//         web/
//           firebase-messaging-sw.js   ← this file
//           index.html
//
// ⚠️  Replace every "YOUR_..." placeholder below with values from:
//     Firebase Console → Project Settings → General → Your apps → Web app config
// ─────────────────────────────────────────────────────────────────────────────

// Use compat SDKs — required for service workers (no ES module support in SW)
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

// ── Your Firebase web config ──────────────────────────────────────────────────
// Copy these values from:
//   Firebase Console → Project Settings → General → Your apps → (web app) → Config
firebase.initializeApp({
  apiKey:            "YOUR_API_KEY",
  authDomain:        "YOUR_PROJECT_ID.firebaseapp.com",
  projectId:         "YOUR_PROJECT_ID",
  storageBucket:     "YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId:             "YOUR_APP_ID",
});

const messaging = firebase.messaging();

// ── Background message handler ────────────────────────────────────────────────
// Fires when a push arrives while the tab is in the background / closed.
// FCM automatically shows a notification for messages that contain a
// `notification` payload, so this handler is for data-only messages or
// for customising the notification appearance.
messaging.onBackgroundMessage((payload) => {
  console.log("[SW] Background message received:", payload);

  const title = payload.notification?.title ?? "FoodFeast";
  const body  = payload.notification?.body  ?? "";

  self.registration.showNotification(title, {
    body,
    icon:  "/icons/Icon-192.png",   // adjust path if your icons are elsewhere
    badge: "/icons/Icon-192.png",
    data:  payload.data ?? {},
  });
});

// ── Notification click handler ────────────────────────────────────────────────
// When the user taps the system notification, open / focus the app tab.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((windowClients) => {
        // If the app is already open, focus it
        for (const client of windowClients) {
          if ("focus" in client) return client.focus();
        }
        // Otherwise open a new tab
        if (clients.openWindow) return clients.openWindow("/");
      })
  );
});
