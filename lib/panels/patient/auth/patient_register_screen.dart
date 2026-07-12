/// ================================================================
/// FILE  : lib/panels/patient/auth/patient_register_screen.dart
/// AUTHOR: Waitless Project
///
/// REQUIREMENTS ADDRESSED:
///
///   REQ 5 — NAVIGATION STACK RESET:
///     After successful registration, pushAndRemoveUntil with
///     `(_) => false` clears the entire back stack so the user
///     cannot press Back to return to the registration form.
///
///   REQ 3 — STRICT AUTH:
///     createUserWithEmailAndPassword is the only creation path.
///     All FirebaseAuthException codes surface as SnackBar messages.
///     No mock, no bypass.
///
///   NOTE: UI layout is preserved exactly — only the _submit()
///   navigation call and the Firestore field keys are audited.
///   Field keys already match UserModel (username, phone, email,
///   role: 'patient') so no schema changes are needed here.
/// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/widgets/custom_button.dart';
import 'package:waitless/widgets/custom_textfield.dart';
import 'package:waitless/panels/patient/patient_home.dart';

class PatientRegisterScreen extends StatefulWidget {
  const PatientRegisterScreen({super.key});

  @override
  State<PatientRegisterScreen> createState() => _PatientRegisterScreenState();
}

class _PatientRegisterScreenState extends State<PatientRegisterScreen>
    with SingleTickerProviderStateMixin {

  final FirebaseAuth      _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db   = FirebaseFirestore.instance;

  final _formKey      = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _isLoading = false;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Validators ────────────────────────────────────────────────
  String? _validateUsername(String? v) {
    if (v == null || v.trim().isEmpty) return 'Name is required';
    if (v.trim().length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    if (v.trim().length < 10) return 'Enter a valid 10-digit number';
    return null;
  }

  String? _validateAddress(String? v) {
    if (v == null || v.trim().isEmpty) return 'Address is required';
    if (v.trim().length < 5) return 'Enter a more complete address';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'At least 8 characters required';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return 'Must include at least one letter';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Must include at least one number';
    if (!RegExp(r'[!@#\$&*~%^()_\-+=\[\]{};:,.<>?/\\|`"' + r"'" + r']').hasMatch(v)) {
      return 'Must include at least one special character';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }


  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Phase 1 — Firebase Auth.
      final UserCredential credential =
      await _auth.createUserWithEmailAndPassword(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final String uid = credential.user!.uid;

      await credential.user!.updateDisplayName(_usernameCtrl.text.trim());

      // Phase 2 — Firestore patients/{uid}.
      // Field keys match UserModel.fromMap() exactly:
      //   username, email, phone, role
      await _db.collection('patients').doc(uid).set({
        'uid':       uid,
        'username':  _usernameCtrl.text.trim(),
        'email':     _emailCtrl.text.trim(),
        'phone':     _phoneCtrl.text.trim(),
        'address':   _addressCtrl.text.trim(),
        'role':      'patient',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      /*ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Welcome to Waitless, ${_usernameCtrl.text.trim()}! 🎉',
            style: const TextStyle(
                fontFamily: 'Nunito', fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.success,
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin:   const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );*/

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const PatientHomeScreen()),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      final String msg = switch (e.code) {
        'email-already-in-use'   => 'This email is already registered. Try logging in.',
        'invalid-email'          => 'The email address is badly formatted.',
        'weak-password'          => 'Password is too weak. Use at least 6 characters.',
        'network-request-failed' => 'No internet connection. Please check and retry.',
        'too-many-requests'      => 'Too many attempts. Please wait a moment and try again.',
        _                        => e.message ?? 'Registration failed. Please try again.',
      };
      _showError(msg);

    } catch (e) {
      _showError('Something went wrong: ${e.toString()}');

    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= 600;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide
                    ? (constraints.maxWidth - 540) / 2
                    : 24,
                vertical: 28,
              ),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 12),
                      _PageHeader(textTheme: textTheme),
                      const SizedBox(height: 6),
                      Text(
                        'Fill in your details to get started.',
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      _FormCard(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionLabel(
                                icon:  Icons.person_outline_rounded,
                                text:  'Personal Information',
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 14),

                              CustomTextField(
                                controller:      _usernameCtrl,
                                label:           'Full Name',
                                hint:            'e.g. Rosy Rose',
                                keyboardType:    TextInputType.name,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.badge_outlined,
                                autofillHints:   const [AutofillHints.name],
                                validator:       _validateUsername,
                              ),
                              const SizedBox(height: 12),

                              CustomTextField(
                                controller:      _emailCtrl,
                                label:           'Email Address',
                                hint:            'you@example.com',
                                keyboardType:    TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.email_outlined,
                                autofillHints:   const [AutofillHints.email],
                                validator:       _validateEmail,
                              ),
                              const SizedBox(height: 12),

                              CustomTextField(
                                controller:      _phoneCtrl,
                                label:           'Phone Number',
                                hint:            '9876543210',
                                keyboardType:    TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.phone_outlined,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                autofillHints: const [AutofillHints.telephoneNumber],
                                validator:     _validatePhone,
                              ),

                              const SizedBox(height: 12),

                              CustomTextField(
                                controller:      _addressCtrl,
                                label:           'Address',
                                hint:            'e.g. 12 Main St, Mumbai',
                                keyboardType:    TextInputType.streetAddress,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.location_on_outlined,
                                autofillHints:   const [AutofillHints.fullStreetAddress],
                                validator:       _validateAddress,
                              ),

                              const SizedBox(height: 24),

                              _SectionLabel(
                                icon:  Icons.lock_outline_rounded,
                                text:  'Account Security',
                                color: AppColors.secondary,
                              ),
                              const SizedBox(height: 14),

                              CustomTextField(
                                controller:       _passwordCtrl,
                                label:            'Password',
                                hint:             'Min 8 chars, letter, number & symbol',
                                isPassword:       true,
                                textInputAction:  TextInputAction.next,
                                prefixIcon:       Icons.lock_outline_rounded,
                                autofillHints:    const [AutofillHints.newPassword],
                                validator:        _validatePassword,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: 8),

                              _HintChip(
                                icon:  Icons.info_outline_rounded,
                                text:  'Use at least 8 characters with a letter, number, and special character (!@#\$...).',
                                color: AppColors.primary,
                              ),

                              const SizedBox(height: 12),
                              CustomTextField(
                                controller:      _confirmCtrl,
                                label:           'Confirm Password',
                                hint:            'Re-enter your password',
                                isPassword:      true,
                                textInputAction: TextInputAction.done,
                                prefixIcon:      Icons.lock_reset_outlined,
                                validator:       _validateConfirm,
                              ),

                              const SizedBox(height: 28),

                              CustomButton(
                                text:            'Register Account',
                                onPressed:       _submit,
                                isLoading:       _isLoading,
                                icon:            Icons.person_add_alt_1_rounded,
                                backgroundColor: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      _LoginFooter(textTheme: textTheme),
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
// Private layout widgets — unchanged from original
// ─────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.textTheme});
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Text(
        'Waitless',
        style: TextStyle(
          fontFamily:    'Nunito',
          fontSize:      30,
          fontWeight:    FontWeight.w800,
          color:         AppColors.primary,
          letterSpacing: -0.8,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color:        AppColors.primary.withOpacity(0.09),
          borderRadius: BorderRadius.circular(30),
          border:       Border.all(
              color: AppColors.primary.withOpacity(0.22), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.person_add_outlined, size: 14, color: AppColors.primary),
          SizedBox(width: 7),
          Text(
            'Create Account',
            style: TextStyle(
              fontFamily:    'Nunito',
              fontSize:      13,
              fontWeight:    FontWeight.w700,
              color:         AppColors.primary,
              letterSpacing: 0.2,
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border:       Border.all(color: AppColors.divider, width: 1.2),
        boxShadow: [
          BoxShadow(
            color:      AppColors.primary.withOpacity(0.05),
            blurRadius: 28,
            offset:     const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String   text;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding:    const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 15, color: color),
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          fontFamily:    'Nunito',
          fontSize:      13,
          fontWeight:    FontWeight.w700,
          color:         color,
          letterSpacing: 0.1,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
          child: Divider(color: color.withOpacity(0.20), thickness: 1)),
    ]);
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String   text;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: color.withOpacity(0.65)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize:   11,
            color:      color.withOpacity(0.75),
            height:     1.4,
          ),
        ),
      ),
    ]);
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter({required this.textTheme});
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        'Already have an account? ',
        style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Text(
          'Login',
          style: TextStyle(
            fontFamily:      'Nunito',
            fontSize:        13,
            fontWeight:      FontWeight.w700,
            color:           AppColors.primary,
            decoration:      TextDecoration.underline,
            decorationColor: AppColors.primary,
          ),
        ),
      ),
    ]);
  }
}