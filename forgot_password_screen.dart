// ─────────────────────────────────────────────
// forgot_password_screen.dart — FoodFeast
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  late AnimationController _btnCtrl;

  static const _red = Color(0xFF0077B6);

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (_emailCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter your email address'),
          backgroundColor: _red));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailCtrl.text.trim());
      setState(() => _emailSent = true);
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message ?? 'Something went wrong'),
          backgroundColor: _red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF1C1C1E)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: _emailSent ? _buildSuccessView() : _buildFormView(),
      ),
    );
  }

  Widget _buildFormView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _red,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: _red.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2)
            ],
          ),
          child: const Icon(Icons.lock_reset_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(height: 24),
        const Text(
          'Forgot\nPassword? 🔑',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C1C1E),
              height: 1.2,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 10),
        const Text(
          'No worries! Enter your email and\nwe\'ll send you a reset link.',
          style: TextStyle(
              fontSize: 14, color: Color(0xFF6E6E73), height: 1.5),
        ),
        const SizedBox(height: 36),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Email Address',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E))),
              const SizedBox(height: 10),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1C1E)),
                decoration: InputDecoration(
                  hintText: 'Enter your registered email',
                  hintStyle: const TextStyle(
                      fontSize: 13.5, color: Color(0xFFAEAEB2)),
                  prefixIcon: const Icon(Icons.alternate_email_rounded,
                      size: 20, color: _red),
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
                          const BorderSide(color: _red, width: 1.8)),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 14, horizontal: 14),
                ),
              ),
              const SizedBox(height: 20),
              _buildSendButton(),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                      text: '← Back to ',
                      style: TextStyle(
                          fontSize: 13.5, color: Color(0xFF6E6E73))),
                  TextSpan(
                      text: 'Login',
                      style: TextStyle(
                          fontSize: 13.5,
                          color: _red,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8EF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_read_rounded,
                color: Color(0xFF34C759), size: 50),
          ),
          const SizedBox(height: 28),
          const Text('Email Sent! 🎉',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 12),
          Text(
            'We\'ve sent a password reset link to\n${_emailCtrl.text.trim()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF6E6E73), height: 1.6),
          ),
          const SizedBox(height: 8),
          const Text('Check your spam folder if you don\'t see it.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFFAEAEB2))),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0077B6), Color(0xFF00B4D8)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _red.withOpacity(0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 6))
                ],
              ),
              child: const Text('Back to Login',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTapDown: (_) => _btnCtrl.forward(),
      onTapUp: (_) {
        _btnCtrl.reverse();
        _sendResetEmail();
      },
      onTapCancel: () => _btnCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _btnCtrl,
        builder: (_, __) => Transform.scale(
          scale: 1 - _btnCtrl.value * 0.03,
          child: Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0077B6), Color(0xFF00B4D8)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: _red
                        .withOpacity(0.45 + _btnCtrl.value * 0.3),
                    blurRadius: 20 + _btnCtrl.value * 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Send Reset Link',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}