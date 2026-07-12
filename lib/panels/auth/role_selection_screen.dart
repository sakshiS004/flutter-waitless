import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../widgets/custom_button.dart';
import '../patient/auth/patient_login_screen.dart' as patient;
import '../doctor/auth/doc_login_screen.dart' as doctor;

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _goToPatient() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const patient.PatientLoginScreen()),
  );

  void _goToDoctor() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const doctor.DocLoginScreen()),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),

                // ── Logo ─────────────────────────────────────────────────────
                _AppLogo(),

                const SizedBox(height: 28),

                // ── Headline ─────────────────────────────────────────────────
                Text(
                  'Welcome to Waitless',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Skip the wait. Choose how you\'re joining.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 44),

                // ── Patient Card ─────────────────────────────────────────────
                _RoleCard(
                  icon: Icons.person_outline_rounded,
                  accentColor: AppColors.primary,
                  lightColor: const Color(0xFFE8F0FE),
                  title: 'I\'m a Patient',
                  description:
                  'Book appointments, join virtual queues, and track your visit status in real time.',
                  perks: const [
                    'Real-time queue tracking',
                    'Appointment management',
                    'Medical history access',
                  ],
                  button: CustomButton(
                    text: 'Continue as Patient',
                    onPressed: _goToPatient,
                    icon: Icons.arrow_forward_rounded,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Divider ──────────────────────────────────────────────────
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.divider)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'or',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textHint),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.divider)),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Doctor Card ──────────────────────────────────────────────
                _RoleCard(
                  icon: Icons.medical_services,
                  accentColor: AppColors.secondary,
                  lightColor: const Color(0xFFE0F2F1),
                  title: 'I\'m a Doctor',
                  description:
                  'Manage your clinic queue, view patient lists, and keep appointments on schedule.',
                  perks: const [
                    'Live queue dashboard',
                    'Patient record access',
                    'Schedule & slot control',
                  ],
                  button: CustomButton(
                    text: 'Continue as Doctor',
                    onPressed: _goToDoctor,
                    icon: Icons.arrow_forward_rounded,
                    backgroundColor: AppColors.secondary,
                  ),
                ),

                const SizedBox(height: 36),

                // ── Trust footer ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shield_outlined,
                        size: 14, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Text(
                      'Your data is encrypted and never shared',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.textHint),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AppLogo
// ─────────────────────────────────────────────────────────────────────────────

class _AppLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.30),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.local_hospital_rounded,
            color: AppColors.white,
            size: 38,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Waitless',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoleCard
// ─────────────────────────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.accentColor,
    required this.lightColor,
    required this.title,
    required this.description,
    required this.perks,
    required this.button,
  });

  final IconData icon;
  final Color accentColor;
  final Color lightColor;
  final String title;
  final String description;
  final List<String> perks;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Coloured header band ────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: lightColor,
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: AppColors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 16),

                // ── Perks ─────────────────────────────────────────────────
                ...perks.map(
                      (perk) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          perk,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                button,
              ],
            ),
          ),
        ],
      ),
    );
  }
}