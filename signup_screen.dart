// ─────────────────────────────────────────────
// signup_screen.dart — FoodFeast
// Updated: Onboarding flow after customer signup
//          Delivery Partner signup toggle
//          Pending approval flow for delivery agents
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart' show AuthGate;
import 'fcm_service.dart';
import 'onboarding_screen.dart'; // ← NEW: onboarding import
import 'cloudinary_image_picker.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  // ── Page controller ──
  final _pageCtrl = PageController();
  int _currentPage = 0;

  // ── Signup type ──
  bool _isAgentSignup = false;
  String _vehicleType = 'bike';

  // ── Page 1: Basic account ──
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms  = false;
  final _photoUrlCtrl  = TextEditingController();

  // ── Page 2: Health profile (customer only) ──
  final _ageCtrl         = TextEditingController();
  final _heightCtrl      = TextEditingController();
  final _weightCtrl      = TextEditingController();
  final _goalCaloriesCtrl = TextEditingController();
  String _gender        = 'Male';
  String _activityLevel = 'Moderate';

  bool _isLoading = false;
  bool _isCheckingEmail = false;
  String? _emailError;          // inline error shown under email field
  late AnimationController _btnCtrl;

  static const _primary = Color(0xFF0077B6);
  static const _bg      = Color(0xFFFAFAFA);

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _ageCtrl.addListener(_autoCalcCalories);
    _heightCtrl.addListener(_autoCalcCalories);
    _weightCtrl.addListener(_autoCalcCalories);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _goalCaloriesCtrl.dispose();
    _photoUrlCtrl.dispose();
    _btnCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── BMI helpers ───────────────────────────────────────────────────
  double? _calcBMI() {
    final h = double.tryParse(_heightCtrl.text);
    final w = double.tryParse(_weightCtrl.text);
    if (h == null || w == null || h <= 0) return null;
    final hM = h / 100;
    return w / (hM * hM);
  }

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25.0) return 'Normal';
    if (bmi < 30.0) return 'Overweight';
    return 'Obese';
  }

  Color _bmiColor(double bmi) {
    if (bmi < 18.5) return const Color(0xFF0077B6);
    if (bmi < 25.0) return const Color(0xFF00B894);
    if (bmi < 30.0) return const Color(0xFFFFA726);
    return const Color(0xFF023E8A);
  }

  int _suggestCalories() {
    final age = int.tryParse(_ageCtrl.text) ?? 25;
    final h   = double.tryParse(_heightCtrl.text) ?? 170;
    final w   = double.tryParse(_weightCtrl.text) ?? 70;
    double bmr;
    if (_gender == 'Male') {
      bmr = 10 * w + 6.25 * h - 5 * age + 5;
    } else if (_gender == 'Female') {
      bmr = 10 * w + 6.25 * h - 5 * age - 161;
    } else {
      bmr = 10 * w + 6.25 * h - 5 * age - 78;
    }
    final multiplier = _activityLevel == 'Light'
        ? 1.375
        : _activityLevel == 'Moderate'
            ? 1.55
            : 1.725;
    return (bmr * multiplier).round();
  }

  void _autoCalcCalories() {
    _goalCaloriesCtrl.text = _suggestCalories().toString();
  }

  // ── Email duplicate pre-check ─────────────────────────────────────
  /// Returns true if the email is free to use, false if already taken.
  /// Shows an inline error + dialog when taken.
  Future<bool> _checkEmailAvailable() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return true; // let normal validation catch this

    setState(() {
      _isCheckingEmail = true;
      _emailError = null;
    });

    try {
      final methods = await FirebaseAuth.instance
          .fetchSignInMethodsForEmail(email);

      if (methods.isNotEmpty) {
        // Email already registered
        setState(() {
          _emailError =
              'This email is already registered. Please login instead.';
          _isCheckingEmail = false;
        });

        if (mounted) _showEmailTakenDialog(email);
        return false;
      }

      setState(() => _isCheckingEmail = false);
      return true;
    } on FirebaseAuthException catch (e) {
      setState(() {
        _emailError = e.code == 'invalid-email'
            ? 'Please enter a valid email address.'
            : null;
        _isCheckingEmail = false;
      });
      if (_emailError != null) _snack(_emailError!);
      return false;
    } catch (_) {
      setState(() => _isCheckingEmail = false);
      return true; // let Firebase handle it downstream
    }
  }

  void _showEmailTakenDialog(String email) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F3),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFFFD0D0), width: 1.5),
              ),
              child: const Icon(Icons.email_outlined,
                  color: Color(0xFFD32F2F), size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Email Already Registered',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 10),
            Text(
              '$email is already linked to an account.\n\nPlease log in, or use a different email to create a new account.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF6E6E73),
                  height: 1.55),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(context); // go back to login screen
                },
                child: const Text('Go to Login',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Clear email so user can type a different one
                _emailCtrl.clear();
                setState(() => _emailError = null);
              },
              child: const Text('Use a Different Email',
                  style: TextStyle(
                      color: _primary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Validation ────────────────────────────────────────────────────
  bool _validatePage1() {
    setState(() => _emailError = null); // clear any previous inline error
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.trim().isEmpty) {
      _snack('Please fill in all required fields');
      return false;
    }
    if (!_agreedToTerms) {
      _snack('Please agree to Terms & Conditions');
      return false;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      _snack('Passwords do not match');
      return false;
    }
    if (_passwordCtrl.text.length < 6) {
      _snack('Password must be at least 6 characters');
      return false;
    }
    return true;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: _primary));
  }

  // ── AGENT SIGNUP ──────────────────────────────────────────────────
  Future<void> _signUpAsAgent() async {
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim());

      await cred.user!.updateDisplayName(_nameCtrl.text.trim());

      final phone = _phoneCtrl.text.trim();
      final formattedPhone = phone.isEmpty ? '' : '+91$phone';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
        'name':          _nameCtrl.text.trim(),
        'email':         _emailCtrl.text.trim(),
        'phone':         formattedPhone,
        'photoUrl':      _photoUrlCtrl.text.trim(),
        'role':          'delivery_agent_pending',
        'vehicleType':   _vehicleType,
        'isOnline':      false,
        'activeOrderId': null,
        'currentLocation': null,
        'earnings':      0.0,
        'fcmToken':      '',
        'appliedAt':     FieldValue.serverTimestamp(),
        'uid':           cred.user!.uid,
      });

      // Notify admin about new application
      try {
        await FcmService.notifyAdmin(
          title: '🛵 New Delivery Partner Application',
          body:  '${_nameCtrl.text.trim()} wants to join as a delivery agent',
          data:  {'type': 'agent_application', 'uid': cred.user!.uid},
        );
      } catch (_) {
        // Non-fatal — admin notification is best-effort
      }

      // Sign out immediately — they can't use the app until approved
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Text('🎉 ', style: TextStyle(fontSize: 24)),
              Text('Application Submitted!',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
            content: const Text(
              'Your delivery partner application is under review.\n\n'
              'You will receive a notification once the admin approves your account.\n\n'
              'This usually takes 24–48 hours.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () =>
                    Navigator.popUntil(context, (r) => r.isFirst),
                child:
                    const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'email-already-in-use') {
          setState(() => _emailError =
              'This email is already registered. Please login instead.');
          _showEmailTakenDialog(_emailCtrl.text.trim());
        } else if (e.code == 'invalid-email') {
          setState(() =>
              _emailError = 'Please enter a valid email address.');
          _snack(_emailError!);
        } else if (e.code == 'weak-password') {
          _snack('Password is too weak. Use at least 6 characters.');
        } else {
          _snack(e.message ?? 'Sign up failed');
        }
      }
    } catch (e) {
      if (mounted) _snack('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  Future<void> _signUpAsCustomer() async {
    if (_ageCtrl.text.trim().isEmpty ||
        _heightCtrl.text.trim().isEmpty ||
        _weightCtrl.text.trim().isEmpty) {
      _snack('Please fill in your health details');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim());

      await cred.user!.updateDisplayName(_nameCtrl.text.trim());
      if (_photoUrlCtrl.text.trim().isNotEmpty) {
        await cred.user!.updatePhotoURL(_photoUrlCtrl.text.trim());
      }

      final phone         = _phoneCtrl.text.trim();
      final formattedPhone = phone.isEmpty ? '' : '+91$phone';
      final bmi           = _calcBMI();
      final goalCal       = int.tryParse(_goalCaloriesCtrl.text) ?? _suggestCalories();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
        'name':            _nameCtrl.text.trim(),
        'email':           _emailCtrl.text.trim(),
        'phone':           formattedPhone,
        'photoUrl':        _photoUrlCtrl.text.trim(),
        'role':            'user',
        'age':             int.tryParse(_ageCtrl.text) ?? 0,
        'height':          double.tryParse(_heightCtrl.text) ?? 0,
        'weight':          double.tryParse(_weightCtrl.text) ?? 0,
        'gender':          _gender,
        'activityLevel':   _activityLevel,
        'goalCalories':    goalCal,
        'bmi':             bmi,
        'dietPreferences': ['Balanced'],
        'createdAt':       FieldValue.serverTimestamp(),
        'uid':             cred.user!.uid,
      });

      // ── NEW: Navigate to onboarding instead of AuthGate directly ──
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const OnboardingScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'email-already-in-use') {
          setState(() => _emailError =
              'This email is already registered. Please login instead.');
          _showEmailTakenDialog(_emailCtrl.text.trim());
        } else if (e.code == 'invalid-email') {
          setState(() =>
              _emailError = 'Please enter a valid email address.');
          _snack(_emailError!);
        } else if (e.code == 'weak-password') {
          _snack('Password is too weak. Use at least 6 characters.');
        } else {
          _snack(e.message ?? 'Sign up failed');
        }
      }
    } catch (e) {
      if (mounted) _snack('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 190,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF023E8A),
                    Color(0xFF0077B6),
                    Color(0xFF00B4D8)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildStepIndicator(),
                Expanded(
                  child: PageView(
                    controller: _pageCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) =>
                        setState(() => _currentPage = i),
                    children: [
                      _buildPage1(),
                      if (!_isAgentSignup) _buildPage2(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_currentPage == 0) {
                Navigator.pop(context);
              } else {
                _pageCtrl.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut);
              }
            },
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _currentPage == 0 ? 'Create Account' : 'Health Profile',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.3),
          ),
        ],
      ),
    );
  }

  // ── Step indicator ────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    if (_isAgentSignup) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
        child: Row(children: [_stepDot(0, 'Account')]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        children: [
          _stepDot(0, 'Account'),
          Expanded(
              child: Container(
                  height: 2,
                  color: _currentPage >= 1
                      ? _primary
                      : Colors.white.withOpacity(0.3))),
          _stepDot(1, 'Health'),
        ],
      ),
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentPage == step;
    final isDone   = _currentPage > step;
    return Column(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? const Color(0xFF34C759)
                : isActive
                    ? Colors.white
                    : Colors.white.withOpacity(0.3),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded,
                    size: 18, color: Colors.white)
                : Text('${step + 1}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isActive ? _primary : Colors.white70)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: isActive ? Colors.white : Colors.white60,
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }

  // ── PAGE 1: Account Details ───────────────────────────────────────
  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          // Signup type toggle
          _card(children: [
            const Text('Sign up as',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isAgentSignup = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isAgentSignup
                          ? _primary
                          : const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: !_isAgentSignup
                              ? _primary
                              : const Color(0xFFE5E5EA),
                          width: 1.5),
                    ),
                    child: Column(children: [
                      const Text('🧑‍🍳',
                          style: TextStyle(fontSize: 20)),
                      const SizedBox(height: 4),
                      Text('Customer',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: !_isAgentSignup
                                  ? Colors.white
                                  : const Color(0xFF6E6E73))),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isAgentSignup = true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isAgentSignup
                          ? _primary
                          : const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _isAgentSignup
                              ? _primary
                              : const Color(0xFFE5E5EA),
                          width: 1.5),
                    ),
                    child: Column(children: [
                      const Text('🛵',
                          style: TextStyle(fontSize: 20)),
                      const SizedBox(height: 4),
                      Text('Delivery\nPartner',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _isAgentSignup
                                  ? Colors.white
                                  : const Color(0xFF6E6E73))),
                    ]),
                  ),
                ),
              ),
            ]),
            // Vehicle type (only for agents)
            if (_isAgentSignup) ...[
              const SizedBox(height: 14),
              const Text('Vehicle Type',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.two_wheeler_rounded,
                      color: _primary, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF7F7F7),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E5EA))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E5EA))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: _primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 14),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'bike', child: Text('🏍️  Bike')),
                  DropdownMenuItem(
                      value: 'scooter', child: Text('🛵  Scooter')),
                  DropdownMenuItem(
                      value: 'bicycle', child: Text('🚲  Bicycle')),
                  DropdownMenuItem(
                      value: 'foot', child: Text('🚶  On Foot')),
                ],
                onChanged: (v) => setState(() => _vehicleType = v!),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE0B2)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: Color(0xFFFF9500)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your application will be reviewed by admin before you can start delivering.',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFF8D6E00)),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 16),

          // Profile photo
          Center(
            child: CloudinaryImagePicker(
              controller: _photoUrlCtrl,
              size: 72,
              circular: true,
              compact: true,
              accentColor: _primary,
              placeholderIcon: Icons.person_rounded,
            ),
          ),
          const SizedBox(height: 16),

          _card(children: [
            _field(_nameCtrl, 'Full Name', Icons.person_outline_rounded),
            const SizedBox(height: 12),
            // Email with inline duplicate-account error
            _fieldWithError(
              ctrl: _emailCtrl,
              label: 'Email Address',
              icon: Icons.alternate_email_rounded,
              type: TextInputType.emailAddress,
              errorText: _emailError,
              onChanged: (_) {
                if (_emailError != null) {
                  setState(() => _emailError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            // Phone with +91
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1C1C1E)),
              decoration: InputDecoration(
                labelText: 'Phone Number',
                counterText: '',
                labelStyle: const TextStyle(
                    fontSize: 13.5, color: Color(0xFF6E6E73)),
                prefixIcon: const Icon(Icons.phone_outlined,
                    size: 20, color: _primary),
                prefix: const Text('+91 ',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1C1E))),
                filled: true,
                fillColor: const Color(0xFFF7F7F7),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                        color: Color(0xFFE5E5EA), width: 1.2)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(
                        color: Color(0xFFE5E5EA), width: 1.2)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide:
                        const BorderSide(color: _primary, width: 1.8)),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 14),
              ),
            ),
            const SizedBox(height: 12),
            _field(_passwordCtrl, 'Password', Icons.lock_outline_rounded,
                obscure: _obscurePass,
                suffix: IconButton(
                  icon: Icon(
                      _obscurePass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: const Color(0xFF6E6E73)),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                )),
            const SizedBox(height: 12),
            _field(_confirmCtrl, 'Confirm Password',
                Icons.lock_outline_rounded,
                obscure: _obscureConfirm,
                suffix: IconButton(
                  icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: const Color(0xFF6E6E73)),
                  onPressed: () => setState(
                      () => _obscureConfirm = !_obscureConfirm),
                )),
            const SizedBox(height: 14),
            Row(children: [
              Checkbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v!),
                activeColor: _primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 12.5, color: Color(0xFF6E6E73)),
                    children: [
                      TextSpan(text: 'I agree to the '),
                      TextSpan(
                          text: 'Terms & Conditions',
                          style: TextStyle(
                              color: _primary,
                              fontWeight: FontWeight.w700)),
                      TextSpan(text: ' and '),
                      TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                              color: _primary,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 20),

          if (_isAgentSignup)
            _buildSignUpButton(
              label: 'Submit Application',
              icon: Icons.send_rounded,
              onTap: () async {
                if (_validatePage1()) {
                  final available = await _checkEmailAvailable();
                  if (available) _signUpAsAgent();
                }
              },
            )
          else
            _primaryButton(
              label: 'Next: Health Profile',
              icon: Icons.arrow_forward_rounded,
              onTap: () async {
                if (_validatePage1()) {
                  final available = await _checkEmailAvailable();
                  if (available && mounted) {
                    _pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut);
                  }
                }
              },
            ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Already have an account? ',
                style: TextStyle(
                    fontSize: 13.5, color: Color(0xFF6E6E73))),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Text('Login',
                  style: TextStyle(
                      fontSize: 13.5,
                      color: _primary,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── PAGE 2: Health Profile ────────────────────────────────────────
  Widget _buildPage2() {
    final bmi = _calcBMI();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gender
          _card(children: [
            const Text('Gender',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 10),
            Row(
                children: ['Male', 'Female', 'Other'].map((g) {
              final isSelected = _gender == g;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _gender = g);
                    _autoCalcCalories();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _primary
                          : const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected
                              ? _primary
                              : const Color(0xFFE5E5EA),
                          width: 1.5),
                    ),
                    child: Center(
                      child: Text(g,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF6E6E73))),
                    ),
                  ),
                ),
              );
            }).toList()),
          ]),
          const SizedBox(height: 14),

          // Body measurements
          _card(children: [
            const Text('Body Measurements',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _field(_ageCtrl, 'Age', Icons.cake_outlined,
                      type: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(
                  child: _field(_heightCtrl, 'Height (cm)',
                      Icons.height_rounded,
                      type: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(
                  child: _field(_weightCtrl, 'Weight (kg)',
                      Icons.monitor_weight_outlined,
                      type: TextInputType.number)),
            ]),
            if (bmi != null) ...[
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bmiColor(bmi).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _bmiColor(bmi).withOpacity(0.3),
                      width: 1.5),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                        color: _bmiColor(bmi).withOpacity(0.15),
                        shape: BoxShape.circle),
                    child: Icon(Icons.monitor_heart_outlined,
                        color: _bmiColor(bmi), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                          'BMI: ${bmi.toStringAsFixed(1)} (${_bmiCategory(bmi)})',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _bmiColor(bmi)),
                        ),
                        Text(
                          'Suggested goal: ${_suggestCalories()} kcal/day',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6E6E73)),
                        ),
                      ])),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 14),

          // Activity level
          _card(children: [
            const Text('Activity Level',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E))),
            const SizedBox(height: 10),
            Row(
                children: ['Light', 'Moderate', 'Active'].map((a) {
              final isSelected = _activityLevel == a;
              final icons = {
                'Light': '🚶',
                'Moderate': '🏃',
                'Active': '💪'
              };
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _activityLevel = a);
                    _autoCalcCalories();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _primary
                          : const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected
                              ? _primary
                              : const Color(0xFFE5E5EA),
                          width: 1.5),
                    ),
                    child: Column(children: [
                      Text(icons[a]!,
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(a,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF6E6E73))),
                    ]),
                  ),
                ),
              );
            }).toList()),
          ]),
          const SizedBox(height: 14),

          // Goal calories
          _card(children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Daily Calorie Goal',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: _primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Auto-suggested',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _primary)),
                  ),
                ]),
            const SizedBox(height: 4),
            const Text('You can override this to set your own goal',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF6E6E73))),
            const SizedBox(height: 12),
            _field(_goalCaloriesCtrl, 'Goal Calories (kcal)',
                Icons.local_fire_department_rounded,
                type: TextInputType.number),
          ]),
          const SizedBox(height: 24),

          _buildSignUpButton(
            label: 'Create Account',
            icon: Icons.check_circle_outline_rounded,
            onTap: _signUpAsCustomer,
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────
  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children),
    );
  }

  Widget _primaryButton(
      {required String label,
      required IconData icon,
      required Future<void> Function() onTap}) {
    return GestureDetector(
      onTap: _isCheckingEmail ? null : onTap,
      child: AnimatedOpacity(
        opacity: _isCheckingEmail ? 0.75 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity, height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF023E8A), Color(0xFF0077B6)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: _primary.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6))
            ],
          ),
          child: _isCheckingEmail
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.2),
                    ),
                    SizedBox(width: 10),
                    Text('Checking email…',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Icon(icon, color: Colors.white, size: 18),
                  ]),
        ),
      ),
    );
  }

  Widget _buildSignUpButton(
      {required String label,
      required IconData icon,
      required Future<void> Function() onTap}) {
    return GestureDetector(
      onTapDown: (_) => _btnCtrl.forward(),
      onTapUp: (_) {
        _btnCtrl.reverse();
        onTap();
      },
      onTapCancel: () => _btnCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _btnCtrl,
        builder: (_, __) => Transform.scale(
          scale: 1 - _btnCtrl.value * 0.03,
          child: Container(
            width: double.infinity, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF023E8A), Color(0xFF0077B6)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color:
                        _primary.withOpacity(0.45 + _btnCtrl.value * 0.3),
                    blurRadius: 20 + _btnCtrl.value * 16,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? type, bool obscure = false, Widget? suffix}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 13.5, color: Color(0xFF6E6E73)),
        prefixIcon: Icon(icon, size: 20, color: _primary),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide:
                const BorderSide(color: Color(0xFFE5E5EA), width: 1.2)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide:
                const BorderSide(color: Color(0xFFE5E5EA), width: 1.2)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _primary, width: 1.8)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
    );
  }

  /// Like [_field] but shows a red inline error banner below the field
  /// when [errorText] is non-null. Also fires [onChanged] so the
  /// parent can clear the error as the user edits.
  Widget _fieldWithError({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType? type,
    bool obscure = false,
    Widget? suffix,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: ctrl,
          keyboardType: type,
          obscureText: obscure,
          onChanged: onChanged,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1C1C1E)),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(
                fontSize: 13.5,
                color: hasError
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFF6E6E73)),
            prefixIcon: Icon(icon,
                size: 20,
                color: hasError ? const Color(0xFFD32F2F) : _primary),
            suffixIcon: hasError
                ? const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFD32F2F), size: 20)
                : suffix,
            filled: true,
            fillColor: hasError
                ? const Color(0xFFFFF5F5)
                : const Color(0xFFF7F7F7),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(
                    color: Color(0xFFE5E5EA), width: 1.2)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(
                    color: hasError
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFFE5E5EA),
                    width: hasError ? 1.8 : 1.2)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(
                    color: hasError
                        ? const Color(0xFFD32F2F)
                        : _primary,
                    width: 1.8)),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 7, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 14, color: Color(0xFFD32F2F)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          errorText,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFFD32F2F),
                              height: 1.4,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}