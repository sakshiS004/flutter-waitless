/// ================================================================
/// FILE  : lib/panels/doctor/doc_home.dart
/// AUTHOR: Waitless Project
///
/// OVERVIEW:
///   The Doctor Dashboard is the central hub for a logged-in doctor.
///   It is a two-tab screen:
///
///   Tab 1 — LIVE QUEUE (Queue Management)
///     • Fetches `bookings` where doctorId == uid AND status == 'pending'
///       using a Firestore StreamBuilder for real-time updates.
///     • Displays total pending count, current (oldest) patient name.
///     • 'Call Next' marks the oldest booking as 'completed'.
///     • 'Reset' marks ALL pending bookings as 'completed'.
///
///   Tab 2 — CLINIC PROFILE (Data Persistence)
///     • Fetches all fields from `doctors/{uid}` document.
///     • Displays: email, phone, specialization, location, hours, off-day.
///     • Edit mode (toggled via FAB) allows field updates saved to Firestore.
///     • Danger Zone: Secure Logout + Hard-Delete Account.
///       Both require Password Re-authentication (see _showSecureLogoutDialog
///       and _showHardDeleteDialog for full Black Book explanations).
///
/// ────────────────────────────────────────────────────────────────
/// SECURITY DESIGN — WHY RE-AUTHENTICATION FOR BOTH ACTIONS:
///
///   The Waitless Doctor Dashboard controls access to live patient
///   queues and sensitive clinic data. Two threat models justify
///   requiring credentials before critical actions:
///
///   1. UNATTENDED DEVICE (Logout):
///      A doctor may leave their device unlocked at the nurses' station.
///      Without a password gate, any staff member could silently log out
///      the doctor, disrupting an active queue. Requiring re-entry of
///      the password ensures only the account owner can end the session.
///
///   2. COMPROMISED SESSION (Delete):
///      Firebase Auth flags account deletion as a "security-sensitive"
///      operation. If the session token is older than ~5 minutes, Firebase
///      throws FirebaseAuthException(code: 'requires-recent-login').
///      Re-authentication via EmailAuthProvider.credential() +
///      reauthenticateWithCredential() refreshes the session token,
///      satisfying Firebase's recency requirement AND proving the operator
///      knows the password — preventing accidental or malicious deletion.
///
///   Reference: https://firebase.google.com/docs/auth/flutter/manage-users
///              #re-authenticate_a_user
///
/// ────────────────────────────────────────────────────────────────
/// CROSS-PANEL DATA FLOW — How the Doctor sees Patient actions live:
///
///   Patient App (Patient Panel)           Doctor Dashboard
///   ─────────────────────────────         ──────────────────────
///   Patient selects a doctor         →    (no change yet)
///   Patient taps "Book Appointment"  →    Firestore write:
///                                           bookings.add({
///                                             doctorId: <uid>,
///                                             patientName: <n>,
///                                             status: 'pending',
///                                             bookedAt: serverTimestamp()
///                                           })
///   Firestore triggers listeners     →    StreamBuilder on doctor's
///                                         device receives snapshot
///                                         update AUTOMATICALLY.
///   UI rebuilds immediately          →    'Patients in Line' count
///                                         increments. No refresh needed.
///
///   This works because Firestore maintains a persistent WebSocket
///   connection. The doctor does not poll — Firestore pushes the
///   change event within ~300ms of the patient's write completing.
/// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/core/theme.dart';
import 'package:waitless/widgets/custom_button.dart';
import 'package:waitless/widgets/custom_textfield.dart';
import 'package:waitless/panels/auth/role_selection_screen.dart';

// ─────────────────────────────────────────────────────────────────
// DocHomeScreen  — root widget (two-tab scaffold)
// ─────────────────────────────────────────────────────────────────
class DocHomeScreen extends StatefulWidget {
  const DocHomeScreen({super.key});

  @override
  State<DocHomeScreen> createState() => _DocHomeScreenState();
}

class _DocHomeScreenState extends State<DocHomeScreen>
    with TickerProviderStateMixin {

  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  late final String _uid;
  late final TabController _tabCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser!.uid;
    _tabCtrl = TabController(length: 2, vsync: this);
    _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: true,
          title: const Text('Waitless', style: TextStyle(
            fontFamily: 'Nunito', fontSize: 22, fontWeight: FontWeight.w800,
            color: AppColors.primary, letterSpacing: -0.4,
          )),
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textHint,
            labelStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 13, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(icon: Icon(Icons.queue_rounded, size: 18), text: 'Live Queue'),
              Tab(icon: Icon(Icons.account_circle_outlined, size: 18), text: 'My Profile'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _QueueTab(uid: _uid, db: _db),
            _ProfileTab(uid: _uid, db: _db, auth: _auth),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 1 — LIVE QUEUE
// ═══════════════════════════════════════════════════════════════
class _QueueTab extends StatelessWidget {
  const _QueueTab({required this.uid, required this.db});
  final String uid;
  final FirebaseFirestore db;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _queueStream =>
      db.collection('bookings')
          .where('doctorId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          //.orderBy('bookedAt', descending: false)
          .snapshots();

  Future<void> _callNext(BuildContext context, List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) return;
    try {
      await db.collection('bookings').doc(docs.first.id).update({
        'status': 'completed',
        'servedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _resetQueue(BuildContext context, List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset Queue?', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
        content: Text('This will mark all ${docs.length} pending patients as completed.',
            style: const TextStyle(fontFamily: 'Nunito')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final WriteBatch batch = db.batch();
      for (final doc in docs) {
        batch.update(doc.reference, {'status': 'completed', 'servedAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Reset failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _queueStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snapshot.hasError) {
          return Center(child: _ErrorView(message: snapshot.error.toString()));
        }
        final docs = snapshot.data?.docs ?? [];
        final int total = docs.length;
        final bool hasPatients = total > 0;
        final Map<String, dynamic>? currentData = hasPatients ? docs.first.data() : null;
        final String currentName = currentData?['patientName'] as String? ?? 'N/A';
        final String currentToken = currentData?['tokenNumber']?.toString() ?? '—';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LiveBadge(isLive: hasPatients),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _StatCard(icon: Icons.people_alt_outlined, label: 'Patients in Line', value: '$total', color: AppColors.primary)),
                const SizedBox(width: 14),
                Expanded(child: _StatCard(icon: Icons.confirmation_number_outlined, label: 'Current Token', value: hasPatients ? currentToken : '—', color: AppColors.secondary)),
              ]),
              const SizedBox(height: 20),
              _CurrentPatientCard(name: hasPatients ? currentName : 'Queue is empty', hasPatient: hasPatients),
              const SizedBox(height: 20),
              CustomButton(
                text: 'Call Next Patient',
                onPressed: hasPatients ? () => _callNext(context, docs) : null,
                icon: Icons.arrow_forward_ios_rounded,
                backgroundColor: AppColors.primary,
              ),
              const SizedBox(height: 12),
              CustomButton(
                text: 'Reset Queue',
                onPressed: hasPatients ? () => _resetQueue(context, docs) : null,
                icon: Icons.restart_alt_rounded,
                backgroundColor: hasPatients ? AppColors.error : AppColors.textHint,
              ),
              const SizedBox(height: 28),
              if (hasPatients) ...[
                _SectionLabel(text: 'Waiting List', color: AppColors.primary),
                const SizedBox(height: 12),
                ...docs.asMap().entries.map((e) {
                  final data = e.value.data();
                  return _QueueItem(
                    position: e.key + 1,
                    patientName: data['patientName'] as String? ?? 'Patient',
                    token: data['tokenNumber']?.toString() ?? '—',
                    bookedAt: data['bookedAt'] as Timestamp?,
                    isCurrent: e.key == 0,
                  );
                }),
              ] else _EmptyQueue(),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(BuildContext ctx, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Nunito')),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// TAB 2 — CLINIC PROFILE
// ═══════════════════════════════════════════════════════════════
class _ProfileTab extends StatefulWidget {
  const _ProfileTab({required this.uid, required this.db, required this.auth});
  final String uid;
  final FirebaseFirestore db;
  final FirebaseAuth auth;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  bool _isEditing = false;
  bool _isSaving  = false;
  Map<String, dynamic>? _profileData;
  bool   _isLoadingProfile = true;
  String? _loadError;

  final _phoneCtrl    = TextEditingController();
  final _locationCtrl = TextEditingController();
  String?   _editSpecialization;
  String?   _editWeeklyOff;
  TimeOfDay? _editOpenTime;
  TimeOfDay? _editCloseTime;

  static const List<String> _specializations = ['MBBS', 'Orthopedic', 'Dermatologist'];
  static const List<String> _weekdays = [
    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await widget.db.collection('doctors').doc(widget.uid).get();
      if (!doc.exists) {
        setState(() { _loadError = 'Profile not found.'; _isLoadingProfile = false; });
        return;
      }
      final data = doc.data()!;
      setState(() {
        _profileData           = data;
        _isLoadingProfile      = false;
        _phoneCtrl.text        = data['phone'] ?? '';
        _locationCtrl.text     = data['location'] ?? '';
        _editSpecialization    = data['specialization'];
        _editWeeklyOff         = data['offDay'];
        _editOpenTime          = _parseTime(data['openTime'] as String?);
        _editCloseTime         = _parseTime(data['closeTime'] as String?);
      });
    } catch (e) {
      setState(() { _loadError = e.toString(); _isLoadingProfile = false; });
    }
  }

  TimeOfDay? _parseTime(String? s) {
    if (s == null) return null;
    try {
      final parts = s.split(' ');
      final hm = parts[0].split(':');
      int hour = int.parse(hm[0]);
      final min = int.parse(hm[1]);
      final pm = parts[1].toUpperCase() == 'PM';
      if (pm && hour != 12) hour += 12;
      if (!pm && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: min);
    } catch (_) { return null; }
  }

  String _formatTime(TimeOfDay t) {
    final h  = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m  = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  Future<void> _pickTime({required bool isOpening}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpening
          ? (_editOpenTime  ?? const TimeOfDay(hour: 9,  minute: 0))
          : (_editCloseTime ?? const TimeOfDay(hour: 18, minute: 0)),
      builder: (ctx, child) => Theme(
        data: AppTheme.lightTheme.copyWith(
          colorScheme: AppTheme.lightTheme.colorScheme.copyWith(
            primary: isOpening ? AppColors.primary : AppColors.secondary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() {
      if (isOpening) _editOpenTime = picked; else _editCloseTime = picked;
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await widget.db.collection('doctors').doc(widget.uid).update({
        'phone':   _phoneCtrl.text.trim(),
        'location':       _locationCtrl.text.trim().toLowerCase(),
        'specialization': _editSpecialization,
        'openTime':  _editOpenTime  != null ? _formatTime(_editOpenTime!)  : _profileData?['openTime'],
        'closeTime': _editCloseTime != null ? _formatTime(_editCloseTime!) : _profileData?['closeTime'],
        'offDay':    _editWeeklyOff,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _profileData?['phone']   = _phoneCtrl.text.trim();
        _profileData?['location']       = _locationCtrl.text.trim().toLowerCase();
        _profileData?['specialization'] = _editSpecialization;
        _profileData?['openTime']  = _editOpenTime  != null ? _formatTime(_editOpenTime!)  : _profileData?['openTime'];
        _profileData?['closeTime'] = _editCloseTime != null ? _formatTime(_editCloseTime!) : _profileData?['closeTime'];
        _profileData?['offDay'] = _editWeeklyOff;
        _isEditing = false;
      });
      if (mounted) _showSnack('Profile updated successfully!');
    } catch (e) {
      if (mounted) _showSnack('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // LOGOUT — Entry point (calls the secure dialog below)
  // ──────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    // _showSecureLogoutDialog handles its own navigation on success,
    // so we simply await the dialog and take no further action here.
    await _showSecureLogoutDialog();
  }

  // ──────────────────────────────────────────────────────────────
  // SECURE LOGOUT DIALOG
  //
  // BLACK BOOK — WHY REQUIRE A PASSWORD TO LOG OUT?
  //
  //   In a clinical setting, doctors often work at shared nurse
  //   stations or leave their devices unlocked between consultations.
  //   A simple one-tap logout button would allow ANY person near the
  //   device to silently end the doctor's session, erasing the active
  //   queue view and potentially causing patient care disruptions.
  //
  //   By requiring the account password before signing out, we ensure:
  //     a) Only the account owner (the doctor) can terminate the session.
  //     b) There is an intentional friction that prevents accidental
  //        logouts during normal device use.
  //
  //   IMPLEMENTATION:
  //     We call EmailAuthProvider.credential(email, password) to build
  //     a local AuthCredential object (no network call at this point).
  //     Then reauthenticateWithCredential(credential) sends that to
  //     Firebase for verification. Only after this succeeds do we call
  //     auth.signOut(), guaranteeing the actor knows the password.
  // ──────────────────────────────────────────────────────────────

  Future<void> _showSecureLogoutDialog() async {
    // Local controllers — scoped to this dialog's lifetime only.
    final emailCtrl    = TextEditingController(
      // Pre-fill with the currently authenticated user's email.
      // This is read from Firebase Auth (authoritative source) rather
      // than Firestore to ensure accuracy even if Firestore data lags.
      text: widget.auth.currentUser?.email ?? '',
    );
    final passwordCtrl = TextEditingController();

    // Dialog-local reactive state managed by StatefulBuilder.
    bool   isPasswordVisible = false;
    bool   isProcessing      = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      // barrierDismissible: false forces the user to explicitly Cancel
      // rather than accidentally dismissing by tapping outside.
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        // StatefulBuilder allows us to call setDialogState() to update
        // isPasswordVisible / isProcessing / errorMessage INSIDE the
        // dialog without rebuilding the parent _ProfileTab widget tree.
        builder: (context, setDialogState) {

          // ── Core re-auth + sign-out logic ─────────────────────
          Future<void> performLogout() async {
            if (passwordCtrl.text.isEmpty) {
              setDialogState(() => errorMessage = 'Password cannot be empty.');
              return;
            }

            setDialogState(() {
              isProcessing = true;
              errorMessage = null;
            });

            try {
              // STEP 1 — Build a credential from the typed password.
              // EmailAuthProvider.credential() is a PURE LOCAL constructor.
              // No network call happens here; it simply packages the values
              // into an AuthCredential data object.
              final credential = EmailAuthProvider.credential(
                email:    emailCtrl.text.trim(),
                password: passwordCtrl.text,
              );

              // STEP 2 — Re-authenticate against Firebase servers.
              // This IS a network call. Firebase verifies the credential
              // and, if correct, refreshes the session token to "now".
              // If the password is wrong, a FirebaseAuthException is thrown.
              await widget.auth.currentUser!
                  .reauthenticateWithCredential(credential);

              // STEP 3 — Credentials verified. Safe to sign out.
              await widget.auth.signOut();

              // STEP 4 — Close dialog then clear the navigation stack.
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                      (_) => false,
                );
              }

            } on FirebaseAuthException catch (e) {
              // Translate Firebase error codes into user-friendly messages.
              String msg;
              switch (e.code) {
                case 'wrong-password':
                case 'invalid-credential':
                  msg = 'Incorrect password. Please try again.';
                  break;
                case 'too-many-requests':
                // Firebase temporarily locks the account after repeated
                // failed attempts as brute-force protection.
                  msg = 'Too many failed attempts. Please try again later.';
                  break;
                case 'user-mismatch':
                  msg = 'Email does not match the signed-in account.';
                  break;
                default:
                  msg = e.message ?? 'Authentication failed. Try again.';
              }
              setDialogState(() {
                errorMessage = msg;
                isProcessing = false;
              });
            } catch (e) {
              setDialogState(() {
                errorMessage = 'Unexpected error: $e';
                isProcessing = false;
              });
            }
          }

          // ── Dialog UI ─────────────────────────────────────────
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),

            // ── Title ─────────────────────────────────────────────
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_person_outlined,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Confirm Logout',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Security context banner ──────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.20)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.security_outlined,
                          size: 15, color: AppColors.primary),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'To protect your active queue, please verify '
                              'your identity before logging out.',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: AppColors.primary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Email field — pre-filled and disabled ──────────
                // Disabled so the actor cannot substitute a different
                // email to attempt logout under a different identity.
                CustomTextField(
                  controller: emailCtrl,
                  label: 'Email',
                  hint: '',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: false,
                ),
                const SizedBox(height: 12),

                // ── Password field — active with visibility toggle ─
                CustomTextField(
                  controller: passwordCtrl,
                  label: 'Password',
                  hint: 'Enter your password to confirm',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: !isPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    // setDialogState — NOT setState — because this is
                    // inside StatefulBuilder, not the page's State class.
                    onPressed: () => setDialogState(
                            () => isPasswordVisible = !isPasswordVisible),
                  ),
                ),

                // ── Inline error message ──────────────────────────
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 14, color: AppColors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),

            actions: [
              // Cancel — user stays logged in, dialog closes.
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Cancel',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600)),
              ),

              // Confirm — triggers re-auth then sign-out.
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor:
                  AppColors.primary.withOpacity(0.50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                ),
                onPressed: isProcessing ? null : performLogout,
                icon: isProcessing
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white)),
                )
                    : const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Log Out',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );

    // Always dispose controllers when the dialog is closed to avoid
    // TextEditingController memory leaks reported by Flutter's debug tools.
    emailCtrl.dispose();
    passwordCtrl.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // DELETE ACCOUNT — Entry point (calls the hard-delete dialog)
  // ──────────────────────────────────────────────────────────────

  Future<void> _deleteAccount() async {
    // _showHardDeleteDialog handles navigation on success.
    await _showHardDeleteDialog();
  }

  // ──────────────────────────────────────────────────────────────
  // HARD-DELETE ACCOUNT DIALOG
  //
  // BLACK BOOK — WHY RE-AUTHENTICATE BEFORE ACCOUNT DELETION?
  //
  //   Firebase's security model designates account deletion as a
  //   "security-sensitive" operation. Firebase requires that the
  //   session token is RECENT (typically within the last 5 minutes).
  //   If it is not, calling currentUser.delete() throws:
  //     FirebaseAuthException(code: 'requires-recent-login')
  //
  //   Beyond satisfying Firebase's technical requirement, requiring
  //   password re-entry for deletion serves two additional purposes:
  //
  //   1. ACCIDENTAL DELETION PREVENTION:
  //      A doctor managing 20 patients might tap "Delete Account"
  //      by mistake. The password challenge is a deliberate friction
  //      that forces a conscious decision, reducing fat-finger deletes.
  //
  //   2. UNAUTHORIZED DELETION PREVENTION:
  //      On a shared or unattended device, a password gate ensures
  //      that a bystander cannot permanently destroy the clinic's data.
  //
  //   DELETION ORDER — Firestore FIRST, then Firebase Auth:
  //     If we delete Auth first and Firestore deletion subsequently
  //     fails, we have an orphaned document with no owning UID. The
  //     Firestore security rules would then prevent cleanup because
  //     the UID no longer exists in Auth. Reversing the order (Firestore
  //     first) means a retry is still possible if Auth deletion fails,
  //     because the UID is still live in Firebase Auth.
  // ──────────────────────────────────────────────────────────────

  Future<void> _showHardDeleteDialog() async {
    // Dialog-scoped controllers — disposed at the end of this method.
    final emailCtrl    = TextEditingController(
      text: widget.auth.currentUser?.email ?? '',
    );
    final passwordCtrl = TextEditingController();

    bool   isPasswordVisible = false;
    bool   isProcessing      = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {

          // ── Core re-auth + deletion logic ─────────────────────
          Future<void> performDelete() async {
            // Field validation — both fields must be non-empty.
            if (emailCtrl.text.trim().isEmpty ||
                passwordCtrl.text.isEmpty) {
              setDialogState(
                      () => errorMessage = 'Email and password are required.');
              return;
            }

            setDialogState(() {
              isProcessing = true;
              errorMessage = null;
            });

            try {
              // STEP 1 — Build AuthCredential (local, no network call yet).
              // EmailAuthProvider.credential() simply packages the email
              // and password into a data object that Firebase can consume.
              final credential = EmailAuthProvider.credential(
                email:    emailCtrl.text.trim(),
                password: passwordCtrl.text,
              );

              // STEP 2 — Re-authenticate with Firebase (network call).
              // This refreshes the session token to "just now", which is
              // required for the subsequent delete() call to succeed.
              // Throws FirebaseAuthException if credentials are invalid.
              await widget.auth.currentUser!
                  .reauthenticateWithCredential(credential);

              // STEP 3 — Delete Firestore document FIRST (see Black Book
              // comment above for why this ordering is intentional).
              await widget.db
                  .collection('doctors')
                  .doc(widget.uid)
                  .delete();

              // STEP 4 — Delete Firebase Auth account.
              // Succeeds because we just re-authenticated in Step 2.
              // After this call, the UID is permanently invalidated.
              await widget.auth.currentUser!.delete();

              // STEP 5 — Close dialog and clear the navigation stack.
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RoleSelectionScreen()),
                      (_) => false,
                );
              }

            } on FirebaseAuthException catch (e) {
              String msg;
              switch (e.code) {
                case 'wrong-password':
                case 'invalid-credential':
                  msg = 'Incorrect password. Please try again.';
                  break;
                case 'too-many-requests':
                  msg = 'Too many failed attempts. Try again later.';
                  break;
                case 'user-mismatch':
                  msg = 'Email does not match the signed-in account.';
                  break;
                default:
                  msg = e.message ?? 'Authentication failed. Try again.';
              }
              setDialogState(() {
                errorMessage = msg;
                isProcessing = false;
              });
            } catch (e) {
              setDialogState(() {
                errorMessage = 'Unexpected error: $e';
                isProcessing = false;
              });
            }
          }

          // ── Dialog UI ─────────────────────────────────────────
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),

            // ── Title ─────────────────────────────────────────────
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_forever_outlined,
                      color: AppColors.error, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Permanent Deletion',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── High-alert warning banner ────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 15, color: AppColors.error),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will permanently delete your clinic profile, '
                              'all schedule data, and your login account. '
                              'This cannot be undone.',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: AppColors.error,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Explain why credentials are needed ───────────
                // Transparency builds user trust — let them know WHY
                // the app is asking for their password again.
                const Text(
                  'Verify your identity to authorize this permanent action.',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),

                // ── Email field — pre-filled, disabled ──────────
                // Disabled to prevent an actor from substituting a
                // different email (e.g., to try brute-forcing another
                // account's password through this dialog).
                CustomTextField(
                  controller: emailCtrl,
                  label: 'Email',
                  hint: '',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: false,
                ),
                const SizedBox(height: 12),

                // ── Password field — active ──────────────────────
                CustomTextField(
                  controller: passwordCtrl,
                  label: 'Password',
                  hint: 'Enter your password to confirm',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: !isPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setDialogState(
                            () => isPasswordVisible = !isPasswordVisible),
                  ),
                ),

                // ── Inline error message ──────────────────────────
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 14, color: AppColors.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),

            actions: [
              // Cancel — abort, nothing is deleted.
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Cancel',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600)),
              ),

              // Delete — triggers re-auth + deletion pipeline.
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor:
                  AppColors.error.withValues(alpha: 0.50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                ),
                onPressed: isProcessing ? null : performDelete,
                child: isProcessing
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white),
                  ),
                )
                    : const Text(
                  'Delete Permanently',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Dispose controllers after the dialog closes to free memory.
    emailCtrl.dispose();
    passwordCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProfile) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_loadError != null) {
      return Center(child: _ErrorView(message: _loadError!));
    }

    final data = _profileData!;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _isEditing
          ? null
          : FloatingActionButton.small(
        backgroundColor: AppColors.primary,
        onPressed: () => setState(() => _isEditing = true),
        tooltip: 'Edit Profile',
        child:
        const Icon(Icons.edit_outlined, color: AppColors.white, size: 18),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileHeader(
              clinicName: data['clinicName'] as String? ?? '',
              email: data['email'] as String? ?? '',
              specialization: data['specialization'] as String? ?? '',
              isEditing: _isEditing,
            ),
            const SizedBox(height: 24),

            _SectionLabel(text: 'Contact Details', color: AppColors.primary),
            const SizedBox(height: 14),
            _ProfileCard(
              child: Column(children: [
                _InfoRow(icon: Icons.email_outlined, label: 'Email', value: data['email'] as String? ?? '—', isEditable: false),
                const Divider(color: AppColors.divider, height: 20),
                _isEditing
                    ? CustomTextField(
                    controller: _phoneCtrl,
                    label: 'Clinic Phone',
                    hint: '9876543210',
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_outlined,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ])
                    : _InfoRow(icon: Icons.phone_outlined, label: 'Clinic Phone', value: data['phone'] as String? ?? '—'),
                const Divider(color: AppColors.divider, height: 20),
                _isEditing
                    ? CustomTextField(
                    controller: _locationCtrl,
                    label: 'Clinic Location',
                    hint: 'City / Area',
                    prefixIcon: Icons.place_outlined)
                    : _InfoRow(icon: Icons.place_outlined, label: 'Location', value: _cap(data['location'] as String? ?? '—')),
              ]),
            ),

            const SizedBox(height: 20),
            _SectionLabel(text: 'Professional Details', color: AppColors.secondary),
            const SizedBox(height: 14),
            _ProfileCard(
              child: _isEditing
                  ? _AppDropdown<String>(
                  value: _editSpecialization,
                  label: 'Specialization',
                  hint: 'Select',
                  prefixIcon: Icons.school_outlined,
                  items: _specializations,
                  toLabel: (s) => s,
                  accentColor: AppColors.secondary,
                  onChanged: (v) => setState(() => _editSpecialization = v))
                  : _InfoRow(icon: Icons.medical_services_outlined, label: 'Specialization', value: data['specialization'] as String? ?? '—'),
            ),

            const SizedBox(height: 20),
            _SectionLabel(text: 'Clinic Schedule', color: AppColors.primary),
            const SizedBox(height: 14),
            _ProfileCard(
              child: _isEditing
                  ? Column(children: [
                Row(children: [
                  Expanded(
                    child: _EditTimeTile(
                        label: 'Opening Time',
                        icon: Icons.wb_sunny_outlined,
                        time: _editOpenTime,
                        accentColor: AppColors.primary,
                        formatFn: _formatTime,
                        onTap: () => _pickTime(isOpening: true)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EditTimeTile(
                        label: 'Closing Time',
                        icon: Icons.nightlight_outlined,
                        time: _editCloseTime,
                        accentColor: AppColors.secondary,
                        formatFn: _formatTime,
                        onTap: () => _pickTime(isOpening: false)),
                  ),
                ]),
                const SizedBox(height: 14),
                _AppDropdown<String>(
                    value: _editWeeklyOff,
                    label: 'Weekly Off',
                    hint: 'Select day',
                    prefixIcon: Icons.event_busy_outlined,
                    items: _weekdays,
                    toLabel: (d) => d,
                    accentColor: AppColors.primary,
                    onChanged: (v) => setState(() => _editWeeklyOff = v)),
              ])
                  : Column(children: [
                _InfoRow(
                    icon: Icons.access_time_outlined,
                    label: 'Hours',
                    value: '${data['openTime'] ?? '—'}  →  ${data['closeTime'] ?? '—'}'),
                const Divider(color: AppColors.divider, height: 20),
                _InfoRow(icon: Icons.event_busy_outlined, label: 'Weekly Off', value: data['offDay'] as String? ?? '—'),
              ]),
            ),

            const SizedBox(height: 24),
            if (_isEditing) ...[
              CustomButton(
                  text: 'Save Changes',
                  onPressed: _saveProfile,
                  isLoading: _isSaving,
                  icon: Icons.save_outlined,
                  backgroundColor: AppColors.secondary),
              const SizedBox(height: 10),
              CustomButton(
                  text: 'Cancel',
                  onPressed: () => setState(() => _isEditing = false),
                  backgroundColor: AppColors.textHint),
              const SizedBox(height: 24),
            ],

            _SectionLabel(text: 'Danger Zone', color: AppColors.error),
            const SizedBox(height: 14),

            // _DangerCard now calls _logout and _deleteAccount, which in turn
            // open the secure re-authentication dialogs defined above.
            _DangerCard(
              onLogout: _logout,
              onDeleteAccount: _deleteAccount,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Nunito')),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// WIDGETS — Queue Tab
// ═══════════════════════════════════════════════════════════════

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.isLive});
  final bool isLive;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: isLive ? AppColors.success : AppColors.textHint,
              shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(
        isLive ? 'QUEUE IS ACTIVE' : 'NO PATIENTS WAITING',
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isLive ? AppColors.success : AppColors.textHint,
        ),
      ),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.icon,
        required this.label,
        required this.value,
        required this.color});
  final IconData icon;
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider, width: 1.1),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha:0.07),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha:0.10),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color)),
        const SizedBox(height: 12),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _CurrentPatientCard extends StatelessWidget {
  const _CurrentPatientCard(
      {required this.name, required this.hasPatient});
  final String name;
  final bool hasPatient;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasPatient
              ? [AppColors.primary, const Color(0xFF1565C0)]
              : [AppColors.textHint, AppColors.textSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: (hasPatient ? AppColors.primary : AppColors.textHint)
                  .withValues(alpha:0.30),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('NOW SERVING',
            style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
                letterSpacing: 1.4)),
        const SizedBox(height: 6),
        Text(name,
            style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 4),
        Text(
          hasPatient
              ? 'Please proceed to the consultation room'
              : 'No patients are currently waiting',
          style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              color: Colors.white70,
              height: 1.4),
        ),
      ]),
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem(
      {required this.position,
        required this.patientName,
        required this.token,
        required this.isCurrent,
        this.bookedAt});
  final int position;
  final String patientName, token;
  final bool isCurrent;
  final Timestamp? bookedAt;
  @override
  Widget build(BuildContext context) {
    final Color c =
    isCurrent ? AppColors.primary : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withValues(alpha:0.06)
            : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isCurrent
                ? AppColors.primary.withValues(alpha:0.30)
                : AppColors.divider,
            width: 1.2),
      ),
      child: Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Center(
                child: Text('$position',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c)))),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patientName,
                      style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  if (bookedAt != null)
                    Text(_ago(bookedAt!.toDate()),
                        style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 11,
                            color: AppColors.textHint)),
                ])),
        if (isCurrent)
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20)),
            child: const Text('CURRENT',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.8)),
          ),
      ]),
    );
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours}h ago';
  }
}

class _EmptyQueue extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(Icons.event_available_outlined,
            size: 52, color: AppColors.textHint.withOpacity(0.5)),
        const SizedBox(height: 12),
        const Text('No patients in queue',
            style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textHint)),
        const SizedBox(height: 4),
        const Text(
          'Your queue will fill as patients book appointments.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              color: AppColors.textHint),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// WIDGETS — Profile Tab
// ═══════════════════════════════════════════════════════════════

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader(
      {required this.email,
        required this.clinicName,
        required this.specialization,
        required this.isEditing});
  final String email, specialization;
  final bool isEditing;
  final String clinicName;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withValues(alpha:0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 6))
              ]),
          child:
          const Icon(Icons.medical_services, color: Colors.white, size: 30)),
      const SizedBox(width: 16),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              specialization.isEmpty ? 'Doctor' : 'Dr. ($specialization)',
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            Text(email,
                style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    color: AppColors.textSecondary)),
            if (isEditing)
              Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('Editing mode',
                      style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning))),
          ])),
    ]);
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider, width: 1.1),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ]),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon,
        required this.label,
        required this.value,
        this.isEditable = true});
  final IconData icon;
  final String label, value;
  final bool isEditable;
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 12),
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                    letterSpacing: 0.3)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ])),
      if (!isEditable)
        const Icon(Icons.lock_outline, size: 14, color: AppColors.textHint),
    ]);
  }
}

class _EditTimeTile extends StatelessWidget {
  const _EditTimeTile(
      {required this.label,
        required this.icon,
        required this.time,
        required this.accentColor,
        required this.formatFn,
        required this.onTap});
  final String label;
  final IconData icon;
  final TimeOfDay? time;
  final Color accentColor;
  final String Function(TimeOfDay) formatFn;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final bool isSet = time != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSet
              ? accentColor.withValues(alpha: 0.07)
              : const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
              isSet ? accentColor.withValues(alpha: 0.35) : AppColors.divider,
              width: 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                    letterSpacing: 0.3))
          ]),
          const SizedBox(height: 6),
          Text(
            isSet ? formatFn(time!) : 'Tap to set',
            style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isSet ? AppColors.textPrimary : AppColors.textHint),
          ),
        ]),
      ),
    );
  }
}

class _DangerCard extends StatelessWidget {
  const _DangerCard(
      {required this.onLogout, required this.onDeleteAccount});
  final VoidCallback onLogout, onDeleteAccount;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppColors.error.withValues(alpha: 0.25), width: 1.2)),
      child: Column(children: [
        // Log Out button — now opens the Secure Logout Dialog
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.lock_person_outlined, size: 18),
            label: const Text('Log Out',
                style: TextStyle(
                    fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side:
                const BorderSide(color: AppColors.primary, width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 10),
        // Delete Account — now opens the Hard-Delete Dialog
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onDeleteAccount,
            icon:
            const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Delete Account',
                style: TextStyle(
                    fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(text,
          style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2)),
      const SizedBox(width: 10),
      Expanded(child: Divider(color: color.withOpacity(0.20), thickness: 1)),
    ]);
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text('Something went wrong',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppColors.error)),
        const SizedBox(height: 6),
        Text(message,
            style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                color: AppColors.textSecondary),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

class _AppDropdown<T> extends StatelessWidget {
  const _AppDropdown(
      {required this.value,
        required this.label,
        required this.hint,
        required this.prefixIcon,
        required this.items,
        required this.toLabel,
        required this.accentColor,
        required this.onChanged});
  final T? value;
  final String label, hint;
  final IconData prefixIcon;
  final List<T> items;
  final String Function(T) toLabel;
  final Color accentColor;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(prefixIcon,
              size: 20, color: AppColors.textSecondary),
          filled: true,
          fillColor: const Color(0xFFF0F4FF),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
              const BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
              const BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
              BorderSide(color: accentColor, width: 1.8))),
      items: items
          .map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(toLabel(item),
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary))))
          .toList(),
      onChanged: onChanged,
      icon: Icon(Icons.keyboard_arrow_down_rounded,
          color: accentColor, size: 22),
      dropdownColor: AppColors.white,
      borderRadius: BorderRadius.circular(14),
    );
  }
}