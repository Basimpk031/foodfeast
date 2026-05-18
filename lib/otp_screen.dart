// ─────────────────────────────────────────────
// otp_screen.dart — FoodFeast OTP (Fixed)
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  const OtpScreen(
      {super.key, required this.phoneNumber, required this.verificationId});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with TickerProviderStateMixin {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  int _resendSeconds = 30;
  late AnimationController _btnCtrl;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  static const _red = Color(0xFF0077B6);

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _startResendTimer();
  }

  void _startResendTimer() async {
    for (int i = 30; i >= 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _resendSeconds = i);
    }
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verifyOtp() async {
    if (_otp.length < 6) {
      _shakeCtrl.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter the complete 6-digit OTP'),
          backgroundColor: _red));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = PhoneAuthProvider.credential(
          verificationId: widget.verificationId, smsCode: _otp);

      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Save user to Firestore if new user
      if (userCred.additionalUserInfo?.isNewUser == true) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCred.user!.uid)
            .set({
          'phone': widget.phoneNumber,
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
          'uid': userCred.user!.uid,
          'name': '',
          'email': '',
        });
      }

      // Navigate to HomeScreen, clear all previous routes
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _shakeCtrl.forward(from: 0);
      if (mounted) {
        String message = 'Invalid OTP. Please try again.';
        if (e.code == 'invalid-verification-code') {
          message = 'The OTP you entered is incorrect.';
        } else if (e.code == 'session-expired') {
          message = 'OTP has expired. Please request a new one.';
        } else {
          message = e.message ?? message;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(message), backgroundColor: _red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: _red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) c.dispose();
    for (var f in _focusNodes) f.dispose();
    _btnCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
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
              child: const Icon(Icons.phone_android_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 24),
            const Text(
              'Verify your\nnumber 📲',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E),
                  height: 1.2,
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'We sent a 6-digit OTP to\n${widget.phoneNumber}',
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF6E6E73), height: 1.5),
            ),
            const SizedBox(height: 36),
            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (_, child) {
                final progress = _shakeCtrl.value;
                final offset = _shakeCtrl.isAnimating
                    ? 8 *
                        (progress < 0.5 ? progress * 2 : (1 - progress) * 2) *
                        (progress < 0.25 || progress > 0.75 ? 1 : -1)
                    : 0.0;
                return Transform.translate(
                    offset: Offset(offset, 0), child: child);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _buildOtpBox(i)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: _resendSeconds > 0
                  ? Text('Resend OTP in $_resendSeconds s',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF6E6E73)))
                  : GestureDetector(
                      onTap: () {
                        setState(() => _resendSeconds = 30);
                        _startResendTimer();
                        // Resend logic via login screen phone OTP flow
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Please go back and request a new OTP'),
                            backgroundColor: _red,
                          ),
                        );
                      },
                      child: const Text('Resend OTP',
                          style: TextStyle(
                              fontSize: 13,
                              color: _red,
                              fontWeight: FontWeight.w700)),
                    ),
            ),
            const SizedBox(height: 32),
            _buildVerifyButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBox(int i) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextField(
        controller: _controllers[i],
        focusNode: _focusNodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1C1C1E)),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E5EA), width: 1.5)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFE5E5EA), width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _red, width: 2)),
        ),
        onChanged: (val) {
          if (val.isNotEmpty && i < 5) {
            _focusNodes[i + 1].requestFocus();
          }
          if (val.isEmpty && i > 0) {
            _focusNodes[i - 1].requestFocus();
          }
          setState(() {});
        },
      ),
    );
  }

  Widget _buildVerifyButton() {
    return GestureDetector(
      onTapDown: (_) => _btnCtrl.forward(),
      onTapUp: (_) {
        _btnCtrl.reverse();
        _verifyOtp();
      },
      onTapCancel: () => _btnCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _btnCtrl,
        builder: (_, __) => Transform.scale(
          scale: 1 - _btnCtrl.value * 0.03,
          child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0077B6), Color(0xFF00B4D8)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF0077B6)
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
                  : const Text('Verify OTP',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}
