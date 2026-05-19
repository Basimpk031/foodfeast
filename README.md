# 🍔 FoodFeast

A full-featured **food ordering mobile app** built with Flutter & Firebase. FoodFeast delivers a complete end-to-end food ordering experience — from browsing restaurants to real-time delivery tracking — powered by an AI recommendation engine.

---

## 📱 Screenshots

<!-- Add your screenshots here. Example:
<p float="left">
  <img src="screenshots/splash.png" width="200"/>
  <img src="screenshots/home.png" width="200"/>
  <img src="screenshots/cart.png" width="200"/>
  <img src="screenshots/tracking.png" width="200"/>
</p>
-->

> 📸 _Screenshots coming soon_

---

## ✨ Features

### 👤 User
- 🔐 Login / Signup with Firebase Auth (Email & Phone Number)
- 🏠 Home feed with restaurants, offers & bundles
- 🤖 **AI-powered food recommendations** based on BMI, calorie goals & diet preferences
- 🔍 Search & filter restaurants by location
- 🛒 Cart management with real-time updates
- 💳 Secure payments via **Razorpay**
- 📦 Real-time order tracking with live delivery map
- 🔔 Push notifications via Firebase Cloud Messaging (FCM)
- ❤️ Favourites & ratings
- 🧮 Calorie tracker with daily macro goals
- 👤 Profile management

### 🚴 Delivery Agent
- 📋 Agent dashboard with pending & active orders
- 🗺️ Live delivery map with route navigation
- ✅ Order acceptance & status updates

### 🛠️ Admin
- 📊 Admin panel for managing restaurants, menus & orders
- 💰 Finance dashboard with revenue stats
- 📈 Stats & analytics screen
- 🎁 Offers & bundle management
- 🎧 Help & support management

---

## 🧠 AI Recommendation Engine

FoodFeast includes a **hybrid recommendation system** that combines:
- **Rule-based filtering** — uses BMI, calorie budget, diet preferences, and activity level to score food items
- **Collaborative filtering** — finds items ordered by similar users (same BMI category & diet preference) and boosts their ranking
- **Smart portion suggestions** — recommends portion sizes based on remaining daily calorie budget

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Authentication | Firebase Auth |
| Database | Cloud Firestore |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Payments | Razorpay |
| Maps | flutter_map + latlong2 |
| Location | GPS / Location Service |
| State Management | Provider |
| Backend | Firebase (Firestore + Auth + FCM) |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `>=3.0.0`
- Dart SDK
- Firebase project set up
- Android Studio / VS Code

### Installation

```bash
# Clone the repository
git clone https://github.com/Basimpk031/foodfeast.git
cd foodfeast

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Firebase Setup
1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable **Authentication**, **Firestore**, and **Cloud Messaging**
3. Download `google-services.json` (Android) and place it in `android/app/`
4. Update `lib/firebase_options.dart` with your project config

### Razorpay Setup
1. Create an account at [razorpay.com](https://razorpay.com)
2. Get your **Test API Key**
3. Add it to your environment config (never commit keys directly)

---

## 📁 Project Structure

```
lib/
├── main.dart                      # App entry point & Firebase init
├── splash_screen.dart             # Animated splash screen
├── login_screen.dart              # Login & FireBase auth
├── signup_screen.dart             # User registration
├── home_screen.dart               # Main home feed
├── restaurant_screen.dart         # Restaurant listing
├── restaurant_detail_screen.dart  # Menu & restaurant details
├── cart_screen.dart               # Shopping cart
├── checkout_screen.dart           # Checkout & Razorpay payment
├── order_tracking_screen.dart     # Live order tracking
├── delivery_map_screen.dart       # Map view for delivery
├── ai_recommendation_engine.dart  # AI food recommender
├── calorie_tracker.dart           # Daily calorie & macro tracker
├── admin_screen.dart              # Admin dashboard
├── delivery_agent_dashboard.dart  # Delivery agent panel
├── finance_dashboard_screen.dart  # Revenue & finance stats
├── profile_screen.dart            # User profile
├── notification_screen.dart       # Push notifications
└── ...
```

---

## 👨‍💻 Author

**Basim**
- GitHub: [@Basimpk031](https://github.com/Basimpk031)
- Email: basim7963@gmail.com

---

## 📄 License

This project is for educational and portfolio purposes.
