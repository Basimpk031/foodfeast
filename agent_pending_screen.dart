// ─────────────────────────────────────────────
// agent_pending_screen.dart — FoodFeast
// Shown to delivery agents who have applied but
// not yet been approved by admin.
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AgentPendingScreen extends StatefulWidget {
  const AgentPendingScreen({super.key});

  @override
  State<AgentPendingScreen> createState() => _AgentPendingScreenState();
}

class _AgentPendingScreenState extends State<AgentPendingScreen>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF0077B6);

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  String _agentName  = '';
  String _vehicleType = '';
  String _appliedAt   = '';
  bool   _loading    = true;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _loadAgentData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgentData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        final ts = data['appliedAt'];
        String appliedStr = '';
        if (ts != null) {
          try {
            final dt = (ts as dynamic).toDate() as DateTime;
            appliedStr =
                '${dt.day}/${dt.month}/${dt.year}';
          } catch (_) {}
        }
        setState(() {
          _agentName   = data['name'] ?? '';
          _vehicleType = data['vehicleType'] ?? '';
          _appliedAt   = appliedStr;
          _loading     = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _primary))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const SizedBox(height: 32),

                    // ── Animated hourglass icon ───────────────
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) => Transform.scale(
                        scale: _pulse.value,
                        child: child,
                      ),
                      child: Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _primary.withOpacity(0.1),
                          border: Border.all(
                              color: _primary.withOpacity(0.3), width: 2.5),
                        ),
                        child: const Center(
                          child: Text('⏳',
                              style: TextStyle(fontSize: 48)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Title ─────────────────────────────────
                    const Text(
                      'Application Under Review',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1C1C1E),
                          letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Our team is reviewing your delivery partner application. '
                      'You\'ll get a notification as soon as it\'s approved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6E6E73),
                          height: 1.6),
                    ),
                    const SizedBox(height: 32),

                    // ── Application details card ──────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
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
                        children: [
                          const Text('Your Application',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1C1C1E))),
                          const SizedBox(height: 14),
                          _detailRow(Icons.person_outline_rounded,
                              'Name', _agentName),
                          const SizedBox(height: 10),
                          _detailRow(Icons.two_wheeler_rounded,
                              'Vehicle', _vehicleType),
                          if (_appliedAt.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _detailRow(Icons.calendar_today_rounded,
                                'Applied on', _appliedAt),
                          ],
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9500).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(children: [
                              Icon(Icons.hourglass_top_rounded,
                                  size: 16,
                                  color: Color(0xFFFF9500)),
                              SizedBox(width: 8),
                              Text('Pending Admin Approval',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFFF9500))),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── What happens next ─────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _primary.withOpacity(0.15), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('What happens next?',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1C1C1E))),
                          const SizedBox(height: 12),
                          _stepRow('1', 'Admin reviews your application',
                              'Usually within 24–48 hours'),
                          const SizedBox(height: 10),
                          _stepRow('2', 'You get notified',
                              'A push notification will be sent to your phone'),
                          const SizedBox(height: 10),
                          _stepRow('3', 'Log in and start delivering',
                              'Your dashboard will be ready to use'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),

                    // ── Sign out ──────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: _primary.withOpacity(0.5), width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout_rounded,
                            color: _primary, size: 18),
                        label: const Text('Sign Out',
                            style: TextStyle(
                                color: _primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 16, color: _primary),
      const SizedBox(width: 10),
      Text('$label: ',
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6E6E73),
              fontWeight: FontWeight.w500)),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1C1C1E),
                fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  Widget _stepRow(String step, String title, String subtitle) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: _primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(step,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6E6E73))),
        ]),
      ),
    ]);
  }
}
