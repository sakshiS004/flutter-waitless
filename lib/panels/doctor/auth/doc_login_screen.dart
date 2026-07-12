/// ================================================================
/// FILE  : lib/panels/doctor/auth/doc_login_screen.dart
/// AUTHOR: Waitless Project
///
/// REQUIREMENTS ADDRESSED:
///
///   REQ 3 — STRICT AUTH LOGIC:
///     _submit() calls signInWithEmailAndPassword() directly on
///     FirebaseAuth. The stub delay and TODO comments are removed.
///     There is no guest path. If the password does not match the
///     Firebase Auth record the SDK throws FirebaseAuthException
///     and the catch block shows a SnackBar — login is blocked.
///
///   REQ 5 — NAVIGATION STACK RESET:
///     After a successful login, Navigator.pushAndRemoveUntil with
///     `(_) => false` clears every route below DocHomeScreen.
///     Hardware Back cannot return to the login screen.
///
///   REQ 1 — PERSISTENCE:
///     The user does not need to log in again on app restart because
///     main.dart's _AuthGate stream listener routes them directly
///     to DocHomeScreen. This screen is only shown when no session
///     exists.
/// ================================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/widgets/custom_button.dart';
import 'package:waitless/widgets/custom_textfield.dart';
import 'package:waitless/panels/doctor/auth/doc_register_screen.dart';
import 'package:waitless/panels/doctor/doc_home.dart';

class DocLoginScreen extends StatefulWidget {
  const DocLoginScreen({super.key});

  @override
  State<DocLoginScreen> createState() => _DocLoginScreenState();
}

class _DocLoginScreenState extends State<DocLoginScreen>
    with SingleTickerProviderStateMixin {

  // ── Firebase ──────────────────────────────────────────────────
  // REQ 3: Direct FirebaseAuth instance — no mock, no bypass.
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  // ── Form ──────────────────────────────────────────────────────
  final _formKey            = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // ── Entrance animation ────────────────────────────────────────
  late final AnimationController _animController;
  late final Animation<Offset>   _slideAnim;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Validators ────────────────────────────────────────────────
  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$')
        .hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // SUBMIT
  //
  // REQ 3 — Strict Auth: Only signInWithEmailAndPassword is used.
  //   No stub delay. No guest access. If credentials are wrong,
  //   FirebaseAuthException is thrown and the user sees an error.
  //
  // REQ 5 — Stack Reset: pushAndRemoveUntil with `(_) => false`
  //   removes every route so Back cannot return to this screen.
  //
  // Role lookup: After login we check Firestore to confirm the UID
  //   belongs to a doctor document. If a patient accidentally uses
  //   the Doctor login, they are shown an error and signed out.
  // ──────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // REQ 3 — Real Firebase sign-in, password MUST match Auth record.
      final UserCredential cred = await _auth.signInWithEmailAndPassword(
        email:    _emailController.text.trim(),
        password: _passwordController.text,
      );

      final String uid = cred.user!.uid;

      // Verify this UID belongs to a doctor document.
      // Prevents a patient account from accessing the doctor dashboard.
      final doc = await _db.collection('doctors').doc(uid).get();
      if (!doc.exists) {
        // Wrong portal — sign them back out and show error.
        await _auth.signOut();
        _showError(
          'No doctor account found for this email.\n'
              'Please use the Patient login or register as a Doctor.',
        );
        return;
      }

      if (!mounted) return;

      // REQ 5 — Navigate and clear the entire back stack.
      // Hardware Back cannot return to the login screen after this.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DocHomeScreen()),
            (_) => false,
      );

    } on FirebaseAuthException catch (e) {
      // REQ 3: All Firebase error codes surface as user-friendly messages.
      // There is no silent fallback or bypass.
      final String msg = switch (e.code) {
        'user-not-found'         => 'No account found for this email.',
        'wrong-password'         => 'Incorrect password. Please try again.',
        'invalid-credential'     => 'Invalid email or password.',
        'user-disabled'          => 'This account has been disabled.',
        'too-many-requests'      => 'Too many attempts. Please wait and retry.',
        'network-request-failed' => 'No internet. Check your connection.',
        _                        => e.message ?? 'Login failed. Please try again.',
      };
      _showError(msg);

    } catch (e) {
      _showError('Unexpected error: ${e.toString()}');

    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Navigation helpers ────────────────────────────────────────
  void _goToForgotPassword() {
    // TODO: Navigator.push → DocForgotPasswordScreen
  }

  void _goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DoctorRegisterScreen()),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
              fontFamily: 'Nunito', fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal:
                isWide ? (constraints.maxWidth - 520) / 2 : 24,
                vertical: 32,
              ),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 24),
                      const _Wordmark(),
                      const SizedBox(height: 40),

                      _RoleBadge(
                        icon:       Icons.medical_services,
                        label:      'Doctor Portal',
                        color:      AppColors.secondary,
                        lightColor: const Color(0xFFE0F2F1),
                      ),

                      const SizedBox(height: 20),
                      Text(
                        'Login to your account',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Welcome back, Doctor. Your patients are waiting.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),

                      _LoginCard(
                        accentColor: AppColors.secondary,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomTextField(
                                controller:       _emailController,
                                label:            'Email Address',
                                hint:             'doctor@hospital.com',
                                keyboardType:     TextInputType.emailAddress,
                                textInputAction:  TextInputAction.next,
                                prefixIcon:       Icons.email_outlined,
                                autofillHints:    const [AutofillHints.email],
                                validator:        _validateEmail,
                              ),
                              const SizedBox(height: 16),

                              CustomTextField(
                                controller:      _passwordController,
                                label:           'Password',
                                hint:            'Enter your password',
                                isPassword:      true,
                                textInputAction: TextInputAction.done,
                                prefixIcon:      Icons.lock_outline_rounded,
                                autofillHints:   const [AutofillHints.password],
                                validator:       _validatePassword,
                                onFieldSubmitted: (_) => _submit(),
                              ),

                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _goToForgotPassword,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.secondary,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // REQ 3: Login button calls only real Firebase Auth.
                              CustomButton(
                                text:            'Login',
                                onPressed:       _submit,
                                isLoading:       _isLoading,
                                icon:            Icons.login_rounded,
                                backgroundColor: AppColors.secondary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),
                      _RegisterRow(
                        accentColor: AppColors.secondary,
                        onTap:       _goToRegister,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Private widgets — layout only, no logic changes
// ─────────────────────────────────────────────────────────────────

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Waitless',
        style: TextStyle(
          fontFamily:    'Nunito',
          fontSize:      32,
          fontWeight:    FontWeight.w800,
          color:         AppColors.primary,
          letterSpacing: -0.8,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.lightColor,
  });
  final IconData icon;
  final String   label;
  final Color    color;
  final Color    lightColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color:        lightColor,
        borderRadius: BorderRadius.circular(30),
        border:       Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily:    'Nunito',
            fontSize:      13,
            fontWeight:    FontWeight.w700,
            color:         color,
            letterSpacing: 0.2,
          ),
        ),
      ]),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.child, required this.accentColor});
  final Widget child;
  final Color  accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border:       Border.all(color: AppColors.divider, width: 1.2),
        boxShadow: [
          BoxShadow(
            color:      accentColor.withOpacity(0.06),
            blurRadius: 24,
            offset:     const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RegisterRow extends StatelessWidget {
  const _RegisterRow({required this.accentColor, required this.onTap});
  final Color        accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        "Don't have an account? ",
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textSecondary),
      ),
      GestureDetector(
        onTap: onTap,
        child: Text(
          'Register',
          style: TextStyle(
            fontFamily:      'Nunito',
            fontSize:        13,
            fontWeight:      FontWeight.w700,
            color:           accentColor,
            decoration:      TextDecoration.underline,
            decorationColor: accentColor,
          ),
        ),
      ),
    ]);
  }
}