/// ================================================================
/// FILE  : lib/panels/doctor/auth/doc_register_screen.dart
/// AUTHOR: Waitless Project
///
/// REQUIREMENTS ADDRESSED:
///
///   REQ 2 — DOCTOR PROFILE SYNC (clinicName):
///     The registration form now collects the clinic's NAME via a
///     dedicated _clinicNameCtrl. On submit this value is written
///     to Firestore under the key 'clinicName' — the EXACT field
///     name the frontend bindings (DoctorModel, DbService) expect.
///
///     This single field is the canonical name displayed in:
///       • The Doctor's own Profile tab (My Profile).
///       • Every ClinicCard shown in the Patient search results
///         (DbService.getClinics() reads 'clinicName' for display).
///
///     It is also synced to Firebase Auth's displayName so that
///     currentUser.displayName works without a Firestore read.
///
///   REQ 5 — NAVIGATION STACK RESET:
///     After successful registration, pushAndRemoveUntil with
///     `(_) => false` clears the entire back stack. The user
///     cannot press Back to return to the registration form.
///
///   REQ 6 — CLINIC PROFILE PHOTO + AVG TIME PER PATIENT (NEW):
///     Two new optional/required fields collected on this screen:
///       • _clinicPhotoUrlCtrl → Firestore 'clinicPhotoUrl'.
///         A plain pasted image URL (no Firebase Storage upload),
///         which keeps the backend on the free Spark plan.
///       • _avgTimePerPatientCtrl → Firestore 'avgTimePerPatient'.
///         Minutes-per-patient pacing used later on the patient
///         side to estimate live wait times.
/// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/core/theme.dart';
import 'package:waitless/widgets/custom_button.dart';
import 'package:waitless/widgets/custom_textfield.dart';
import 'package:waitless/panels/doctor/doc_home.dart';
import 'package:waitless/models/doctor_model.dart'; // NEW — for defaultClinicPhotoUrl

class DoctorRegisterScreen extends StatefulWidget {
  const DoctorRegisterScreen({super.key});

  @override
  State<DoctorRegisterScreen> createState() => _DoctorRegisterScreenState();
}

class _DoctorRegisterScreenState extends State<DoctorRegisterScreen>
    with SingleTickerProviderStateMixin {

  // ── Firebase ──────────────────────────────────────────────────
  final FirebaseAuth      _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db   = FirebaseFirestore.instance;

  // ── Form ──────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  // ── Text controllers ──────────────────────────────────────────

  // REQ 2: _clinicNameCtrl is the NEW field.
  // Its value becomes 'clinicName' in Firestore — the field that
  // DoctorModel.fromMap() reads and DbService.getClinics() orders by.
  final _clinicNameCtrl = TextEditingController();

  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _doctorNameCtrl = TextEditingController();

  // REQ 6 (NEW): Clinic profile photo URL — optional, plain link.
  final _clinicPhotoUrlCtrl = TextEditingController();

  // REQ 6 (NEW): Average minutes per patient — defaults to '10' so
  // the field isn't blank on first render.
  final _avgTimePerPatientCtrl = TextEditingController(text: '10');

  // ── Dropdown state ────────────────────────────────────────────
  String? _specialization;
  static const List<String> _specializations = [
    'MBBS', 'Orthopedic', 'Dermatologist',
  ];

  String? _weeklyOff;
  static const List<String> _weekdays = [
    'Monday', 'Tuesday', 'Wednesday',
    'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  // ── Time picker state ─────────────────────────────────────────
  TimeOfDay? _openingTime;
  TimeOfDay? _closingTime;

  // ── UI state ──────────────────────────────────────────────────
  bool _isLoading = false;

  // ── Animation ─────────────────────────────────────────────────
  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
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
    _clinicNameCtrl.dispose(); // REQ 2: dispose new controller
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _doctorNameCtrl.dispose();
    _clinicPhotoUrlCtrl.dispose();       // NEW
    _avgTimePerPatientCtrl.dispose();    // NEW
    super.dispose();
  }

  // ── Validators ────────────────────────────────────────────────

  // REQ 2: Validate clinic name (required for profile display).
  String? _validateClinicName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Clinic name is required';
    if (v.trim().length < 3) return 'At least 3 characters required';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
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

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    if (v.trim().length < 10) return 'Enter a valid 10-digit number';
    return null;
  }

  String? _validateLocation(String? v) {
    if (v == null || v.trim().isEmpty) return 'Clinic city / area is required';
    return null;
  }

  String? _validateDoctorName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Doctor name is required';
    if (v.trim().length < 2) return 'At least 2 characters required';
    return null;
  }

  // REQ 6 (NEW): Optional field — leaving it blank is fine, the
  // model default (DoctorModel.defaultClinicPhotoUrl) is used
  // instead. If the doctor DOES type something, it must at least
  // look like an http(s) URL.
  String? _validateClinicPhotoUrl(String? v) {
    if (v == null || v.trim().isEmpty) return null; // optional
    final uri = Uri.tryParse(v.trim());
    final looksValid = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!looksValid) return 'Enter a valid image URL (https://...)';
    return null;
  }

  // REQ 6 (NEW): Required, numeric, kept within a sane clinical
  // range so the wait-time estimate later stays meaningful.
  String? _validateAvgTimePerPatient(String? v) {
    if (v == null || v.trim().isEmpty) return 'Average time is required';
    final parsed = int.tryParse(v.trim());
    if (parsed == null) return 'Enter a whole number of minutes';
    if (parsed < 1) return 'Must be at least 1 minute';
    if (parsed > 180) return 'Must be 180 minutes or less';
    return null;
  }

  // ── Time picker ───────────────────────────────────────────────
  Future<void> _pickTime({required bool isOpening}) async {
    final TimeOfDay initialTime = isOpening
        ? (_openingTime ?? const TimeOfDay(hour: 9,  minute: 0))
        : (_closingTime ?? const TimeOfDay(hour: 18, minute: 0));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isOpening ? 'SELECT OPENING TIME' : 'SELECT CLOSING TIME',
      builder: (context, child) => Theme(
        data: AppTheme.lightTheme.copyWith(
          colorScheme: AppTheme.lightTheme.colorScheme.copyWith(
            primary: isOpening ? AppColors.primary : AppColors.secondary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        if (isOpening) _openingTime = picked; else _closingTime = picked;
      });
    }
  }

  String _formatTime(TimeOfDay t) {
    final h  = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m  = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  // ──────────────────────────────────────────────────────────────
  // SUBMIT
  //
  // REQ 2 — DOCTOR PROFILE SYNC:
  //   _clinicNameCtrl.text is written to Firestore as 'clinicName'.
  //   This is the SINGLE SOURCE OF TRUTH for:
  //     • Doctor profile display name (Profile tab).
  //     • Patient clinic search card title (getClinics() stream).
  //     • Firebase Auth displayName (for no-Firestore name reads).
  //
  // REQ 5 — STACK RESET:
  //   pushAndRemoveUntil(`(_) => false`) after successful creation.
  //
  // REQ 6 — NEW: clinicPhotoUrl + avgTimePerPatient are written
  //   alongside the existing fields in the same set() call.
  // ──────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_specialization == null) {
      _showError('Please select your specialization'); return;
    }
    if (_openingTime == null) {
      _showError('Please select an opening time'); return;
    }
    if (_closingTime == null) {
      _showError('Please select a closing time'); return;
    }
    if (_weeklyOff == null) {
      _showError('Please select your weekly off day'); return;
    }

    setState(() => _isLoading = true);

    try {
      // Phase 1 — Firebase Auth account.
      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final String uid = cred.user!.uid;

      // REQ 2: Sync clinicName to Firebase Auth displayName so
      // currentUser.displayName works anywhere without Firestore.
      await cred.user!.updateDisplayName(_clinicNameCtrl.text.trim());

      // Phase 2 — Firestore document in `doctors/{uid}`.
      //
      // REQ 2: 'clinicName' is the Firestore field key used by:
      //   • DoctorModel.fromMap()  → model for Doctor Profile tab.
      //   • DbService.getClinics() → clinic list for Patient search.
      //   Both read 'clinicName' — this write is the origin of that data.
      //
      // Field keys match DoctorModel.toMap() / fromMap() exactly.
      await _db.collection('doctors').doc(uid).set({
        'uid':            uid,
        'email':          _emailCtrl.text.trim(),
        'doctorName':     _doctorNameCtrl.text.trim(),
        'clinicName':     _clinicNameCtrl.text.trim(),
        'phone':          _phoneCtrl.text.trim(),
        'location':       _locationCtrl.text.trim(),
        'specialization': _specialization,
        'openTime':       _formatTime(_openingTime!),    // matches DoctorModel
        'closeTime':      _formatTime(_closingTime!),    // matches DoctorModel
        'offDay':         _weeklyOff,                    // matches DoctorModel
        'description':    '',
        'role':           'doctor',
        'createdAt':      FieldValue.serverTimestamp(),
        'isVerified':     false,
        // REQ 6 (NEW) — falls back to the model's shared placeholder
        // constant when the doctor left the URL field blank.
        'clinicPhotoUrl': _clinicPhotoUrlCtrl.text.trim().isNotEmpty
            ? _clinicPhotoUrlCtrl.text.trim()
            : DoctorModel.defaultClinicPhotoUrl,
        // REQ 6 (NEW) — safe parse with a fallback to 10, matching
        // the DoctorModel default, in case validation was bypassed.
        'avgTimePerPatient': int.tryParse(_avgTimePerPatientCtrl.text.trim()) ?? 10,
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DocHomeScreen()),
            (_) => false,
      );

    } on FirebaseAuthException catch (e) {
      final String msg = switch (e.code) {
        'email-already-in-use'   => 'This email is already registered. Please log in instead.',
        'invalid-email'          => 'The email address format is invalid.',
        'weak-password'          => 'Password is too weak. Follow the rules above.',
        'network-request-failed' => 'No internet. Check your connection and retry.',
        'too-many-requests'      => 'Too many attempts. Please wait and try again.',
        _                        => e.message ?? 'Registration failed. Try again.',
      };
      _showError(msg);

    } catch (e) {
      _showError('Unexpected error: ${e.toString()}');

    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Welcome, ${_clinicNameCtrl.text.trim()}! Registration successful',
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
                      const SizedBox(height: 8),
                      const _ScreenHeader(),
                      const SizedBox(height: 6),
                      Text(
                        'Complete your profile to start receiving patients.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),

                      _Card(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // ── SECTION A: Account Credentials ────────
                              _SectionLabel(
                                icon:  Icons.lock_person_outlined,
                                text:  'Account Credentials',
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 14),

                              CustomTextField(
                                controller:      _emailCtrl,
                                label:           'Email Address',
                                hint:            'doctor@hospital.com',
                                keyboardType:    TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.email_outlined,
                                autofillHints:   const [AutofillHints.email],
                                validator:       _validateEmail,
                              ),
                              const SizedBox(height: 12),

                              CustomTextField(
                                controller:      _passwordCtrl,
                                label:           'Password',
                                hint:            'Min 8 chars, number & symbol',
                                isPassword:      true,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.lock_outline_rounded,
                                autofillHints:   const [AutofillHints.newPassword],
                                validator:       _validatePassword,
                              ),

                              const SizedBox(height: 8),

                              _InfoChip(
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
                                onFieldSubmitted: (_) => _submit(),
                              ),

                              const SizedBox(height: 24),

                              // ── SECTION B: Clinic Identity ────────────
                              // REQ 2: This section collects clinicName —
                              // the field that drives all name display in the app.
                              _SectionLabel(
                                icon:  Icons.local_hospital_outlined,
                                text:  'Clinic Identity',
                                color: AppColors.secondary,
                              ),
                              const SizedBox(height: 14),

                              CustomTextField(
                                controller:      _doctorNameCtrl,
                                label:           'Doctor\'s Full Name',
                                hint:            'e.g. Dr. Anjali Sharma',
                                keyboardType:    TextInputType.name,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.person_outlined,
                                validator:       _validateDoctorName,
                              ),
                              const SizedBox(height: 12),

                              // REQ 2: clinicName field — saved as Firestore
                              // 'clinicName'. Used in Profile + Patient Search.
                              CustomTextField(
                                controller:      _clinicNameCtrl,
                                label:           'Clinic Name',
                                hint:            'e.g. City Care Clinic',
                                keyboardType:    TextInputType.name,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.business_outlined,
                                validator:       _validateClinicName,
                              ),
                              const SizedBox(height: 8),

                              _InfoChip(
                                icon:  Icons.info_outline_rounded,
                                text:  'This name appears on your profile and in '
                                    'patient search results.',
                                color: AppColors.secondary,
                              ),

                              const SizedBox(height: 24),

                              // ── SECTION C: Contact & Location ─────────
                              _SectionLabel(
                                icon:  Icons.location_on_outlined,
                                text:  'Contact & Location',
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 14),

                              CustomTextField(
                                controller:      _phoneCtrl,
                                label:           'Clinic Phone Number',
                                hint:            '9876543210',
                                keyboardType:    TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.phone_outlined,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                validator: _validatePhone,
                              ),
                              const SizedBox(height: 12),

                              CustomTextField(
                                controller:      _locationCtrl,
                                label:           'Clinic City / Area',
                                hint:            'e.g. Andheri West, Mumbai',
                                keyboardType:    TextInputType.streetAddress,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.place_outlined,
                                validator:       _validateLocation,
                              ),
                              const SizedBox(height: 8),

                              _InfoChip(
                                icon:  Icons.info_outline_rounded,
                                text:  'Used so patients can find you via '
                                    '"Near Me" search.',
                                color: AppColors.secondary,
                              ),

                              const SizedBox(height: 24),

                              // ── SECTION D: Professional Details ───────
                              _SectionLabel(
                                icon:  Icons.medical_information_outlined,
                                text:  'Professional Details',
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 14),

                              _AppDropdown<String>(
                                value:       _specialization,
                                label:       'Specialization',
                                hint:        'Select your specialization',
                                prefixIcon:  Icons.school_outlined,
                                items:       _specializations,
                                toLabel:     (s) => s,
                                accentColor: AppColors.primary,
                                onChanged:   (v) =>
                                    setState(() => _specialization = v),
                              ),

                              const SizedBox(height: 24),

                              // ── SECTION E: Clinic Schedule ─────────────
                              _SectionLabel(
                                icon:  Icons.schedule_outlined,
                                text:  'Clinic Schedule',
                                color: AppColors.secondary,
                              ),
                              const SizedBox(height: 14),

                              Row(children: [
                                Expanded(
                                  child: _TimeTile(
                                    label:       'Opening Time',
                                    icon:        Icons.wb_sunny_outlined,
                                    time:        _openingTime,
                                    accentColor: AppColors.primary,
                                    formatFn:    _formatTime,
                                    onTap:       () => _pickTime(isOpening: true),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TimeTile(
                                    label:       'Closing Time',
                                    icon:        Icons.nightlight_outlined,
                                    time:        _closingTime,
                                    accentColor: AppColors.secondary,
                                    formatFn:    _formatTime,
                                    onTap:       () => _pickTime(isOpening: false),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 12),

                              _AppDropdown<String>(
                                value:       _weeklyOff,
                                label:       'Weekly Off Day',
                                hint:        'Select closed day',
                                prefixIcon:  Icons.event_busy_outlined,
                                items:       _weekdays,
                                toLabel:     (d) => d,
                                accentColor: AppColors.secondary,
                                onChanged:   (v) =>
                                    setState(() => _weeklyOff = v),
                              ),

                              const SizedBox(height: 24),

                              // ── SECTION F: Clinic Profile (NEW) ───────
                              _SectionLabel(
                                icon:  Icons.image_outlined,
                                text:  'Clinic Profile',
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 14),

                              // NEW — Clinic Profile Photo URL. A plain
                              // link field (no image picker / no
                              // Firebase Storage upload) so the backend
                              // stays on the free Spark plan.
                              CustomTextField(
                                controller:      _clinicPhotoUrlCtrl,
                                label:           'Clinic Profile Photo URL (optional)',
                                hint:            'https://example.com/clinic-photo.jpg',
                                keyboardType:    TextInputType.url,
                                textInputAction: TextInputAction.next,
                                prefixIcon:      Icons.image_outlined,
                                validator:       _validateClinicPhotoUrl,
                              ),
                              const SizedBox(height: 8),
                              _InfoChip(
                                icon:  Icons.info_outline_rounded,
                                text:  'Paste a direct image link. Leave blank to '
                                    'use a default placeholder photo.',
                                color: AppColors.primary,
                              ),

                              const SizedBox(height: 16),

                              // NEW — Average Time Per Patient (minutes).
                              // Drives the patient-facing wait-time
                              // estimate only; never changes queue order.
                              CustomTextField(
                                controller:      _avgTimePerPatientCtrl,
                                label:           'Average Time Per Patient (minutes)',
                                hint:            'e.g. 10',
                                keyboardType:    TextInputType.number,
                                textInputAction: TextInputAction.done,
                                prefixIcon:      Icons.timer_outlined,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                validator:       _validateAvgTimePerPatient,
                              ),
                              const SizedBox(height: 8),
                              _InfoChip(
                                icon:  Icons.info_outline_rounded,
                                text:  'Used to estimate patient wait times in '
                                    'the live queue.',
                                color: AppColors.secondary,
                              ),

                              const SizedBox(height: 28),

                              CustomButton(
                                text:            'Register Account',
                                onPressed:       _submit,
                                isLoading:       _isLoading,
                                icon:            Icons.how_to_reg_rounded,
                                backgroundColor: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      const _LoginLink(),
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
// Private widgets — layout only (unchanged from original)
// ─────────────────────────────────────────────────────────────────

class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader();

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
      const SizedBox(height: 2),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color:        AppColors.secondary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(
              color: AppColors.secondary.withOpacity(0.25), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.medical_services, size: 14, color: AppColors.secondary),
          SizedBox(width: 6),
          Text(
            'Doctor Registration',
            style: TextStyle(
              fontFamily:    'Nunito',
              fontSize:      13,
              fontWeight:    FontWeight.w700,
              color:         AppColors.secondary,
              letterSpacing: 0.2,
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
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
          child: Divider(color: color.withOpacity(0.18), thickness: 1)),
    ]);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
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
      Icon(icon, size: 13, color: color.withOpacity(0.7)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize:   11,
            color:      color.withOpacity(0.8),
            height:     1.4,
          ),
        ),
      ),
    ]);
  }
}

class _AppDropdown<T> extends StatelessWidget {
  const _AppDropdown({
    required this.value,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    required this.items,
    required this.toLabel,
    required this.accentColor,
    required this.onChanged,
  });
  final T?               value;
  final String           label;
  final String           hint;
  final IconData         prefixIcon;
  final List<T>          items;
  final String Function(T) toLabel;
  final Color            accentColor;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value:      value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText:  label,
        hintText:   hint,
        prefixIcon: Icon(prefixIcon, size: 20, color: AppColors.textSecondary),
        filled:     true,
        fillColor:  const Color(0xFFF0F4FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   BorderSide(color: accentColor, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   const BorderSide(color: AppColors.error, width: 1.4),
        ),
      ),
      items: items
          .map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(toLabel(item),
              style: const TextStyle(
                fontFamily:  'Nunito',
                fontSize:    15,
                fontWeight:  FontWeight.w500,
                color:       AppColors.textPrimary,
              ))))
          .toList(),
      validator: (v) => v == null ? 'Please select an option' : null,
      onChanged: onChanged,
      icon:          Icon(Icons.keyboard_arrow_down_rounded,
          color: accentColor, size: 22),
      dropdownColor: AppColors.white,
      borderRadius:  BorderRadius.circular(14),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.icon,
    required this.time,
    required this.accentColor,
    required this.formatFn,
    required this.onTap,
  });
  final String     label;
  final IconData   icon;
  final TimeOfDay? time;
  final Color      accentColor;
  final String Function(TimeOfDay) formatFn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isSet = time != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSet
              ? accentColor.withOpacity(0.07)
              : const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSet ? accentColor.withOpacity(0.35) : AppColors.divider,
            width: 1.2,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily:    'Nunito',
                  fontSize:      10,
                  fontWeight:    FontWeight.w700,
                  color:         accentColor,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            isSet ? formatFn(time!) : 'Tap to set',
            style: TextStyle(
              fontFamily:  'Nunito',
              fontSize:    15,
              fontWeight:  FontWeight.w700,
              color:       isSet ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ]),
      ),
    );
  }
}

class _LoginLink extends StatelessWidget {
  const _LoginLink();

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        'Already have an account? ',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textSecondary),
      ),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Text(
          'Login',
          style: TextStyle(
            fontFamily:      'Nunito',
            fontSize:        13,
            fontWeight:      FontWeight.w700,
            color:           AppColors.secondary,
            decoration:      TextDecoration.underline,
            decorationColor: AppColors.secondary,
          ),
        ),
      ),
    ]);
  }
}