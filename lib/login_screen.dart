// ─────────────────────────────────────────────
// login_screen.dart — FoodFeast (Fixed)
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final AnimationController _waveController;
  late final AnimationController _btnPulseController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  final GlobalKey _feastKey = GlobalKey();

  static const _red = Color(0xFF0077B6);
  static const _bg = Color(0xFFFAFAFA);
  static const _surface = Colors.white;
  static const _textDark = Color(0xFF1C1C1E);
  static const _textMid = Color(0xFF6E6E73);
  static const _border = Color(0xFFE5E5EA);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _waveController =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat();
    _btnPulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));

    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _slideController, curve: Curves.easeOutCubic));

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _fadeController.forward();
        _slideController.forward();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _waveController.dispose();
    _btnPulseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final input = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (input.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter email/phone and password'),
          backgroundColor: _red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String emailToUse = input;

      final isPhone = RegExp(r'^\+?[0-9]{7,15}$').hasMatch(input);
      if (isPhone) {
        final formatted = input.startsWith('+') ? input : '+91$input';
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: formatted)
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('No account found with this phone number.'),
                backgroundColor: _red));
          }
          return;
        }

        emailToUse = (query.docs.first.data()['email'] as String?) ?? '';

        if (emailToUse.isEmpty) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:
                    Text('No email linked to this phone. Contact support.'),
                backgroundColor: _red));
          }
          return;
        }
      }

      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: emailToUse, password: password);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String msg = 'Login failed';
        if (e.code == 'user-not-found' || e.code == 'invalid-credential')
          msg = 'No account found or wrong password.';
        else if (e.code == 'wrong-password')
          msg = 'Incorrect password. Please try again.';
        else if (e.code == 'invalid-email')
          msg = 'Invalid email address.';
        else if (e.code == 'too-many-requests')
          msg = 'Too many attempts. Try again later.';
        else
          msg = e.message ?? msg;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg), backgroundColor: _red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Login error: $e'), backgroundColor: _red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isGoogleLoading = false);
        return;
      }

      // ── STEP 1: Check Firestore by email BEFORE touching Firebase Auth ──
      // This prevents creating a ghost Firebase Auth account for unregistered
      // Google users. We look up the users collection using the Google email.
      final googleEmail = googleUser.email;
      final fs = FirebaseFirestore.instance;

      final preCheck = await fs
          .collection('users')
          .where('email', isEqualTo: googleEmail)
          .limit(1)
          .get();

      if (preCheck.docs.isEmpty) {
        // Not registered in Firestore — block before any Firebase Auth call
        await googleSignIn.signOut();
        if (mounted) {
          setState(() => _isGoogleLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '⚠️ You need to sign up first before using Google Sign-In.'),
            backgroundColor: _red,
            duration: Duration(seconds: 4),
          ));
        }
        return;
      }

      // ── STEP 2: User exists — proceed with Firebase Auth ───────────────
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final uid = userCred.user!.uid;

      // ── STEP 3: Double-check all collections with the real UID ─────────
      final results = await Future.wait([
        fs.collection('users').doc(uid).get(),
        fs
            .collection('restaurants')
            .where('ownerUid', isEqualTo: uid)
            .limit(1)
            .get(),
        fs.collection('admins').doc(uid).get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final restaurantSnap = results[1] as QuerySnapshot;
      final adminDoc = results[2] as DocumentSnapshot;

      final isRegistered = userDoc.exists ||
          restaurantSnap.docs.isNotEmpty ||
          adminDoc.exists;

      if (!isRegistered) {
        // UID not found in any collection — sign out and block
        await FirebaseAuth.instance.signOut();
        await googleSignIn.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '⚠️ You need to sign up first before using Google Sign-In.'),
            backgroundColor: _red,
            duration: Duration(seconds: 4),
          ));
        }
        return;
      }

      // ── STEP 4: Verified — AuthGate handles routing ────────────────────
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Google Sign-In failed: ${e.toString()}'),
          backgroundColor: _red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          _WaveHeader(controller: _waveController),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 200),
                      _buildLogo(),
                      const SizedBox(height: 32),
                      _buildCard(),
                      const SizedBox(height: 24),
                      _buildDivider(),
                      const SizedBox(height: 20),
                      _buildSocialButtons(),
                      const SizedBox(height: 28),
                      _buildSignupRow(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _red.withOpacity(0.30),
                blurRadius: 28,
                spreadRadius: 4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/icon/app_icon.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _WaveAwareFeastText(
          waveController: _waveController,
          feastKey: _feastKey,
        ),
        const SizedBox(height: 6),
        const Text('Eat smart • Track calories 🔥',
            style: TextStyle(
                fontSize: 13.5, color: _textMid, letterSpacing: 0.1)),
      ],
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 30,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Welcome back 👋',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                  letterSpacing: -0.3)),
          const SizedBox(height: 4),
          const Text('Sign in to continue ordering',
              style: TextStyle(fontSize: 13.5, color: _textMid)),
          const SizedBox(height: 24),
          _buildTextField(
              controller: _emailController,
              label: 'Email or Phone Number',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePassword,
            suffix: IconButton(
              icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: _textMid),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen())),
              style: TextButton.styleFrom(
                  foregroundColor: _red,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Forgot Password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 20),
          _buildLoginButton(),
        ],
      ),
    );
  }

  Widget _buildTextField(
      {required TextEditingController controller,
      required String label,
      required IconData icon,
      TextInputType? keyboardType,
      bool obscure = false,
      Widget? suffix}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(
          fontSize: 15, color: _textDark, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14, color: _textMid),
        prefixIcon: Icon(icon, size: 20, color: _red),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _border, width: 1.2)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _border, width: 1.2)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _red, width: 1.8)),
      ),
    );
  }

  Widget _buildLoginButton() {
    return GestureDetector(
      onTapDown: (_) => _btnPulseController.forward(),
      onTapUp: (_) async {
        await _btnPulseController.reverse();
        _handleLogin();
      },
      onTapCancel: () => _btnPulseController.reverse(),
      child: AnimatedBuilder(
        animation: _btnPulseController,
        builder: (_, child) {
          final scale = 1.0 - _btnPulseController.value * 0.03;
          final glowOpacity = 0.45 + _btnPulseController.value * 0.3;
          return Transform.scale(
            scale: scale,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_red, Color(0xFF00B4D8)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: _red.withOpacity(glowOpacity),
                      blurRadius: 20 + _btnPulseController.value * 16,
                      spreadRadius: 1 + _btnPulseController.value * 3,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Login',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 20),
                        ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDivider() {
    return Row(children: [
      const Expanded(child: Divider(color: _border, thickness: 1)),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('or continue with',
              style: const TextStyle(fontSize: 12.5, color: _textMid))),
      const Expanded(child: Divider(color: _border, thickness: 1)),
    ]);
  }

  Widget _buildSocialButtons() {
    return _SocialButton(
      label: _isGoogleLoading ? 'Signing in...' : 'Continue with Google',
      icon: Icons.g_mobiledata_rounded,
      isLoading: _isGoogleLoading,
      onTap: _isGoogleLoading ? null : _handleGoogleSignIn,
    );
  }

  Widget _buildSignupRow() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("Don't have an account? ",
          style: TextStyle(fontSize: 13.5, color: _textMid)),
      GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
        child: const Text('Sign Up',
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: _red)),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
// _WaveAwareFeastText
// ─────────────────────────────────────────────
class _WaveAwareFeastText extends StatelessWidget {
  final AnimationController waveController;
  final GlobalKey feastKey;

  static const double _waveH = 280.0;
  static const double _waveBase = 50.0;
  static const double _waveAmp = 18.0;
  static const double _textH = 42.0;

  const _WaveAwareFeastText({
    required this.waveController,
    required this.feastKey,
  });

  double _waveBottomY(double targetX, double screenW, double t) {
    final h = _waveH;
    final si = math.sin(t * 2 * math.pi);
    final co = math.cos(t * 2 * math.pi);

    final p0 = Offset(0, h - _waveBase);
    final p1 = Offset(screenW * 0.25, h - 80 + si * _waveAmp);
    final p2 = Offset(screenW * 0.75, h - 20 + co * _waveAmp);
    final p3 = Offset(screenW, h - _waveBase);

    double bestT = 0.0;
    double bestDist = double.infinity;
    for (int i = 0; i <= 200; i++) {
      final u = i / 200.0;
      final mu = 1 - u;
      final bx = mu * mu * mu * p0.dx +
          3 * mu * mu * u * p1.dx +
          3 * mu * u * u * p2.dx +
          u * u * u * p3.dx;
      final d = (bx - targetX).abs();
      if (d < bestDist) {
        bestDist = d;
        bestT = u;
      }
    }

    final mu = 1 - bestT;
    return mu * mu * mu * p0.dy +
        3 * mu * mu * bestT * p1.dy +
        3 * mu * bestT * bestT * p2.dy +
        bestT * bestT * bestT * p3.dy;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;

    return AnimatedBuilder(
      animation: waveController,
      builder: (ctx, _) {
        double textTopY = double.infinity;
        final ro = feastKey.currentContext?.findRenderObject();
        if (ro is RenderBox && ro.hasSize) {
          textTopY = ro.localToGlobal(Offset.zero).dy;
        }

        final waveY = _waveBottomY(screenW / 2, screenW, waveController.value);

        double coveredPx = 0.0;
        if (textTopY != double.infinity) {
          coveredPx = (waveY - textTopY).clamp(0.0, _textH);
        }

        final clipTop = _textH - coveredPx;

        return SizedBox(
          key: feastKey,
          height: _textH,
          child: Stack(
            children: [
              _buildRichText(feastColor: const Color(0xFF0077B6)),
              if (coveredPx > 0)
                ClipRect(
                  clipper: _BottomFillClipper(clipTop: clipTop),
                  child: _buildRichText(feastColor: Colors.white),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRichText({required Color feastColor}) {
    return RichText(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'Food',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C1C1E),
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: 'Feast',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: feastColor,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomFillClipper extends CustomClipper<Rect> {
  final double clipTop;
  const _BottomFillClipper({required this.clipTop});

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, clipTop, size.width, size.height);

  @override
  bool shouldReclip(_BottomFillClipper old) => old.clipTop != clipTop;
}

// ─────────────────────────────────────────────
// WAVE HEADER
// ─────────────────────────────────────────────
class _WaveHeader extends StatelessWidget {
  final AnimationController controller;
  const _WaveHeader({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => ClipPath(
        clipper: _WaveClipper(controller.value),
        child: Container(
          height: 280,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [
                  Color(0xFF023E8A),
                  Color(0xFF0077B6),
                  Color(0xFF00B4D8)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: Stack(children: [
            Positioned(
                top: -30,
                right: -30,
                child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.07)))),
            Positioned(
                top: 40,
                left: -50,
                child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.05)))),
            const Positioned(
                top: 50,
                left: 30,
                child: Text('🍔', style: TextStyle(fontSize: 28))),
            const Positioned(
                top: 30,
                right: 50,
                child: Text('🍕', style: TextStyle(fontSize: 24))),
            const Positioned(
                top: 90,
                right: 20,
                child: Text('🌮', style: TextStyle(fontSize: 20))),
            const Positioned(
                top: 100,
                left: 80,
                child: Text('🍜', style: TextStyle(fontSize: 22))),
          ]),
        ),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  final double animValue;
  _WaveClipper(this.animValue);

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 50);
    path.cubicTo(
        size.width * 0.25,
        size.height - 80 + math.sin(animValue * 2 * math.pi) * 18,
        size.width * 0.75,
        size.height - 20 + math.cos(animValue * 2 * math.pi) * 18,
        size.width,
        size.height - 50);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => old.animValue != animValue;
}

// ─────────────────────────────────────────────
// SOCIAL BUTTON
// ─────────────────────────────────────────────
class _SocialButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  const _SocialButton(
      {required this.label,
      required this.icon,
      this.onTap,
      this.isLoading = false});

  @override
  State<_SocialButton> createState() => _SocialButtonState();
}

class _SocialButtonState extends State<_SocialButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const _red = Color(0xFF0077B6);
  static const _border = Color(0xFFE5E5EA);
  static const _textDark = Color(0xFF1C1C1E);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) _ctrl.forward();
      },
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final scale = 1.0 - _ctrl.value * 0.04;
          final glow = _ctrl.value;
          return Transform.scale(
            scale: scale,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: glow > 0.1 ? _red.withOpacity(glow) : _border,
                    width: 1.5),
                boxShadow: glow > 0.1
                    ? [
                        BoxShadow(
                            color: _red.withOpacity(0.25 * glow),
                            blurRadius: 14,
                            spreadRadius: 1)
                      ]
                    : [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
              ),
              child: widget.isLoading
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: _red, strokeWidth: 2)))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.icon, size: 20, color: _red),
                        const SizedBox(width: 8),
                        Text(widget.label,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: _textDark)),
                      ]),
            ),
          );
        },
      ),
    );
  }
}