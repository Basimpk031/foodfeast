import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'login_screen.dart';
import 'home_screen.dart';
import 'admin_screen.dart';
import 'restaurant_screen.dart';
import 'fcm_service.dart';
import 'local_notification_service.dart';
import 'calorie_tracker.dart';
import 'agent_pending_screen.dart';
import 'delivery_agent_dashboard.dart';
import 'splash_screen.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FoodFeastBootstrap());
}

// ─────────────────────────────────────────────────────────────────────────────
// Shows splash immediately, runs all Firebase init in background.
// Once init is done AND the splash animation is done → navigate to app.
// Both gates must pass before the user sees anything after the bar finishes.
// ─────────────────────────────────────────────────────────────────────────────
class FoodFeastBootstrap extends StatefulWidget {
  const FoodFeastBootstrap({super.key});
  @override
  State<FoodFeastBootstrap> createState() => _FoodFeastBootstrapState();
}

class _FoodFeastBootstrapState extends State<FoodFeastBootstrap> {
  User? _initialUser;
  bool  _firebaseDone   = false;
  bool  _animationDone  = false;

  @override
  void initState() {
    super.initState();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final results = await Future.wait([
      LocalNotificationService.init(),
      FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => null,
          ),
    ]);

    final user = results[1] as User?;
    if (user != null) {
      await CalorieTracker.instance.loadTodayData(uid: user.uid);
    }

    if (mounted) {
      setState(() {
        _initialUser  = user;
        _firebaseDone = true;
      });
      _maybeNavigate();
    }
  }

  // Called by SplashScreen when its animation finishes
  void _onAnimationDone() {
    if (!mounted) return;
    setState(() => _animationDone = true);
    _maybeNavigate();
  }

  // Only swap to the real app when BOTH are ready
  void _maybeNavigate() {
    if (_firebaseDone && _animationDone) {
      setState(() {}); // triggers rebuild → shows FoodFeastApp
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_firebaseDone && _animationDone) {
      return FoodFeastApp(initialUser: _initialUser);
    }

    // Show splash and pass the callback so it can tell us when it's done
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(onAnimationDone: _onAnimationDone),
    );
  }
}

class FoodFeastApp extends StatelessWidget {
  final User? initialUser;
  const FoodFeastApp({super.key, required this.initialUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoodFeast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0077B6)),
        useMaterial3: true,
      ),
      home: AuthGate(initialUser: initialUser),
    );
  }
}

class AuthGate extends StatefulWidget {
  final User? initialUser;
  const AuthGate({super.key, required this.initialUser});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _uid;
  String? _role;
  String? _restaurantId;
  bool    _loading    = false;
  bool    _loadFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialUser != null) {
      _loadRole(widget.initialUser!.uid);
    }
  }

  Future<void> _loadRole(String uid) async {
    if (_loading) return;
    if (_uid == uid && _role != null && !_loadFailed) return;

    setState(() { _loading = true; _loadFailed = false; });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data() as Map<String, dynamic>?;

      if (data == null) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final retryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final retryData = retryDoc.data() as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _uid          = uid;
            _role         = (retryData?['role'] as String?)?.trim() ?? 'user';
            _restaurantId = (retryData?['restaurantId'] as String?) ?? '';
            _loading      = false;
            _loadFailed   = false;
          });
        }
        return;
      }

      if (mounted) {
        final resolvedRole = (data['role'] as String?)?.trim() ?? 'user';
        setState(() {
          _uid          = uid;
          _role         = resolvedRole;
          _restaurantId = (data['restaurantId'] as String?) ?? '';
          _loading      = false;
          _loadFailed   = false;
        });
        if (resolvedRole == 'user') {
          LocationService.instance.loadSaved().then((_) {
            if (LocationService.instance.current == null) {
              LocationService.instance.fetchCurrentLocation();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('AuthGate _loadRole error: $e');
      if (mounted) {
        setState(() {
          _uid        = uid;
          _role       = null;
          _loading    = false;
          _loadFailed = true;
        });
      }
    }
  }

  Widget _buildScreen() {
    final role = _role ?? 'user';
    switch (role) {
      case 'admin':
        return const AdminDashboard();
      case 'restaurant':
      case 'restaurant_owner':
        final rid = _restaurantId ?? '';
        if (rid.isEmpty) return _MissingRestaurantScreen(uid: _uid ?? '');
        return RestaurantDashboard(restaurantId: rid);
      case 'delivery_agent':
        return DeliveryAgentDashboard(agentId: _uid!);
      case 'delivery_agent_pending':
      case 'delivery_agent_rejected':
        return const AgentPendingScreen();
      default:
        return const HomeScreen();
    }
  }

  // Lightweight loading shown only if Firestore role fetch is slow
  // (Firebase init is already done at this point — this is rare)
  static const _loadingWidget = Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: CircularProgressIndicator(color: Color(0xFFFF0000)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingWidget;
        }

        final user = snapshot.data;

        if (user != null) {
          if (_uid == user.uid && _role != null && !_loadFailed) {
            return _buildScreen();
          }
          if (!_loading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadRole(user.uid);
            });
          }
          return _loadingWidget;
        }

        if (_uid != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              CalorieTracker.instance.reset();
              setState(() {
                _uid          = null;
                _role         = null;
                _restaurantId = null;
                _loading      = false;
                _loadFailed   = false;
              });
            }
          });
        }
        return const LoginScreen();
      },
    );
  }
}

class _MissingRestaurantScreen extends StatelessWidget {
  final String uid;
  const _MissingRestaurantScreen({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🏪', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 24),
              const Text(
                'Restaurant Not Assigned',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Your account is set up but no restaurant has been linked yet.\n\nPlease contact the admin to assign your restaurant.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF6E6E73), height: 1.6),
              ),
              const SizedBox(height: 8),
              Text(
                'UID: $uid',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFAEAEB2), fontFamily: 'monospace'),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0077B6)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                onPressed: () async => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_rounded, color: Color(0xFF0077B6)),
                label: const Text('Sign Out',
                    style: TextStyle(
                        color: Color(0xFF0077B6), fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}