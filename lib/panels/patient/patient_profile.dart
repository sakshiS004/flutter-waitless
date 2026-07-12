/// ================================================================
/// FILE  : lib/panels/patient/patient_profile.dart
/// AUTHOR: Waitless Project
///
/// OVERVIEW:
///   Displays and allows editing of the current patient's profile
///   data from the Firestore `patients` collection.
///
///   Features:
///     • FutureBuilder reads patients/{uid} on load.
///     • Edit icon (top-right) toggles in-place editing for
///       username and phone. Email is read-only (Firebase Auth).
///     • Save writes changed fields back to Firestore.
///     • Logout — Shows a professional AlertDialog with the user's
///       email for context before signing out.
///     • Delete Account — Shows a Re-Authentication dialog FIRST.
///       Firebase Security Model requires this (see _showDeleteReAuthDialog).
///       On success: deletes Firestore doc then Auth account.
///
/// ────────────────────────────────────────────────────────────────
/// WHY RE-AUTHENTICATION IS REQUIRED (Black Book Note):
///
///   Firebase Auth flags certain operations as "security-sensitive":
///     – Deleting an account
///     – Changing the account email address
///     – Changing the account password
///
///   For these operations, Firebase requires that the user signed in
///   RECENTLY (typically within the last 5 minutes). If the session
///   token is older than that, Firebase throws:
///     FirebaseAuthException with code == 'requires-recent-login'
///
///   The correct solution is to call:
///     credential = EmailAuthProvider.credential(email, password)
///     await user.reauthenticateWithCredential(credential)
///   ...BEFORE calling user.delete(). This forces the user to prove
///   they still know the password, preventing a malicious actor from
///   deleting an account on an unattended unlocked phone.
///
///   Reference: https://firebase.google.com/docs/auth/flutter/manage-users
///              #re-authenticate_a_user
/// ────────────────────────────────────────────────────────────────
/// NOTE: PatientProfilePage is designed to be embedded inside
///   PatientHomeScreen's IndexedStack (Tab 1), NOT pushed as a
///   separate route. It receives uid, db, and auth as constructor
///   parameters so PatientHomeScreen can pass the already-available
///   Firebase instances rather than creating new singletons.
/// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/widgets/custom_button.dart';
import 'package:waitless/widgets/custom_textfield.dart';
import 'package:waitless/panels/auth/role_selection_screen.dart';

// ─────────────────────────────────────────────────────────────────
// PatientProfilePage
// ─────────────────────────────────────────────────────────────────
class PatientProfilePage extends StatefulWidget {
  const PatientProfilePage({
    super.key,
    required this.uid,
    required this.db,
    required this.auth,
  });

  /// The current patient's Firebase Auth UID.
  final String            uid;
  final FirebaseFirestore db;
  final FirebaseAuth      auth;

  @override
  State<PatientProfilePage> createState() => _PatientProfilePageState();
}

class _PatientProfilePageState extends State<PatientProfilePage> {

  // ── Edit mode ─────────────────────────────────────────────────
  bool _editMode = false;
  bool _saving   = false;
  bool _deleting = false;

  // ── Controllers (populated from Firestore on first load) ──────
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl    = TextEditingController();

  /// Cached Firestore data — populated once by FutureBuilder.
  /// Used to re-populate controllers if the user cancels editing.
  Map<String, dynamic>? _cachedData;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// Fills all editable controllers with the current saved values.
  void _populateControllers(Map<String, dynamic> data) {
    _usernameCtrl.text = data['username'] as String? ?? '';
    _phoneCtrl.text    = data['phone']    as String? ?? '';
  }

  // ──────────────────────────────────────────────────────────────
  // SAVE — Write edits back to Firestore
  // ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_usernameCtrl.text.trim().isEmpty) {
      _showSnack('Name cannot be empty.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.db.collection('patients').doc(widget.uid).update({
        'username':  _usernameCtrl.text.trim(),
        'phone':     _phoneCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local cache so the view refreshes without re-fetching.
      if (_cachedData != null) {
        _cachedData!['username'] = _usernameCtrl.text.trim();
        _cachedData!['phone']    = _phoneCtrl.text.trim();
      }

      // Keep Firebase Auth displayName in sync with Firestore username.
      await widget.auth.currentUser?.updateDisplayName(
          _usernameCtrl.text.trim());

      setState(() => _editMode = false);
      _showSnack('Profile updated!', isError: false);
    } catch (e) {
      _showSnack('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // LOGOUT — Shows professional dialog with user's email context
  // ──────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final emailCtrl    = TextEditingController(text: widget.auth.currentUser?.email ?? '');
    final passwordCtrl = TextEditingController();
    bool isPasswordVisible = false;
    bool isProcessing      = false;
    String? errorMessage;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {

          Future<void> performLogout() async {
            if (passwordCtrl.text.isEmpty) {
              setDialogState(() => errorMessage = 'Password cannot be empty.');
              return;
            }
            setDialogState(() { isProcessing = true; errorMessage = null; });
            try {
              final credential = EmailAuthProvider.credential(
                email:    emailCtrl.text.trim(),
                password: passwordCtrl.text,
              );
              await widget.auth.currentUser!.reauthenticateWithCredential(credential);
              await widget.auth.signOut();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                      (_) => false,
                );
              }
            } on FirebaseAuthException catch (e) {
              final msg = switch (e.code) {
                'wrong-password' || 'invalid-credential' => 'Incorrect password.',
                'too-many-requests' => 'Too many attempts. Try later.',
                _ => e.message ?? 'Authentication failed.',
              };
              setDialogState(() { errorMessage = msg; isProcessing = false; });
            } catch (e) {
              setDialogState(() { errorMessage = 'Error: $e'; isProcessing = false; });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_person_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Confirm Logout', style: TextStyle(
                fontFamily: 'Nunito', fontWeight: FontWeight.w800,
                fontSize: 18, color: AppColors.textPrimary,
              )),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.20)),
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.security_outlined, size: 15, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Enter your password to confirm logout.',
                      style: TextStyle(fontFamily: 'Nunito', fontSize: 12, color: AppColors.primary, height: 1.4),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: emailCtrl,
                  label: 'Email', hint: '',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: false,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: passwordCtrl,
                  label: 'Password', hint: 'Enter your password',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: !isPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20, color: AppColors.textSecondary,
                    ),
                    onPressed: () => setDialogState(() => isPasswordVisible = !isPasswordVisible),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.error_outline, size: 14, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(child: Text(errorMessage!, style: const TextStyle(
                      fontFamily: 'Nunito', fontSize: 12,
                      color: AppColors.error, fontWeight: FontWeight.w600,
                    ))),
                  ]),
                ],
                const SizedBox(height: 20),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: isProcessing ? null : performLogout,
                icon: isProcessing
                    ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Log Out', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );

    emailCtrl.dispose();
    passwordCtrl.dispose();
  }

  Future<void> _deleteAccount() async {
    // Show the re-auth dialog. It returns true only when the user has
    // successfully re-authenticated AND confirmed deletion inside the dialog.
    final didDelete = await _showDeleteReAuthDialog();

    // If the dialog was cancelled or re-auth failed, do nothing.
    if (!didDelete) return;

    // Navigation is handled inside the dialog after successful deletion,
    // so nothing more is needed here. _deleting state is also managed
    // inside the dialog to keep the UI responsive.
  }

  // ──────────────────────────────────────────────────────────────
  // DELETE RE-AUTH DIALOG
  //
  // PURPOSE: Firebase's security model requires that "sensitive"
  // operations (account deletion, email/password change) are only
  // allowed if the user authenticated RECENTLY — typically within
  // the last 5 minutes. If too much time has passed, Firebase throws:
  //   FirebaseAuthException(code: 'requires-recent-login')
  //
  // SOLUTION (Re-Authentication):
  //   1. Show a dialog where the user re-enters their password.
  //   2. Build an AuthCredential from their email + password:
  //        EmailAuthProvider.credential(email, password)
  //   3. Call user.reauthenticateWithCredential(credential).
  //      This refreshes the session token to "just now", satisfying
  //      Firebase's recency requirement.
  //   4. Only after successful re-auth, call user.delete().
  //
  // This pattern is the ONLY recommended way to handle
  // 'requires-recent-login' for email/password accounts. For Google
  // Sign-In accounts, you would use GoogleAuthProvider instead.
  // ──────────────────────────────────────────────────────────────

  Future<bool> _showDeleteReAuthDialog() async {
    // ── Local state for the dialog ─────────────────────────────
    // These controllers live for the lifetime of the dialog only.
    // We use a StatefulBuilder inside the dialog to call setState
    // without rebuilding the entire page.
    final passwordCtrl = TextEditingController();
    bool  isPasswordVisible = false; // toggles the eye icon
    bool  isProcessing      = false; // shows loading state inside dialog
    String? errorMessage;            // inline error text (wrong password, etc.)

    // Pre-fill the email from the current authenticated user.
    // currentUser?.email is authoritative — it comes from Firebase Auth,
    // not from Firestore, so it is always the actual login email.
    final String email = widget.auth.currentUser?.email ?? '';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // force the user to explicitly cancel
      builder: (ctx) => StatefulBuilder(
        // StatefulBuilder lets us call setState((){}) inside the dialog
        // to update isPasswordVisible, isProcessing, and errorMessage
        // without rebuilding the whole PatientProfilePage widget tree.
        builder: (context, setDialogState) {

          // ── The actual deletion logic, scoped inside the dialog ──
          Future<void> performDelete() async {
            // Basic validation — password field must not be empty.
            if (passwordCtrl.text.isEmpty) {
              setDialogState(() => errorMessage = 'Please enter your password.');
              return;
            }

            setDialogState(() {
              isProcessing = true;
              errorMessage = null; // clear any previous error
            });

            try {
              // ── STEP 1: Re-authenticate ────────────────────────
              //
              // EmailAuthProvider.credential() bundles the email and
              // password into an AuthCredential object WITHOUT making
              // any network call. It is purely a local data structure.
              //
              // reauthenticateWithCredential() then sends that credential
              // to Firebase servers to verify it. On success, Firebase
              // refreshes the session token (making it "recent"), which
              // is required for the subsequent delete() call.
              final credential = EmailAuthProvider.credential(
                email:    email,
                password: passwordCtrl.text,
              );

              // This will throw FirebaseAuthException if the password
              // is wrong ('wrong-password') or user not found ('user-not-found').
              await widget.auth.currentUser!
                  .reauthenticateWithCredential(credential);

              // ── STEP 2: Delete Firestore document ─────────────
              //
              // We delete the Firestore record BEFORE the Auth account.
              // Reason: If Firestore deletion fails after Auth is deleted,
              // we would have an orphaned document with no owner. Doing
              // Firestore first means a retry is still possible (Auth UID
              // still exists, so security rules can still match).
              await widget.db
                  .collection('patients')
                  .doc(widget.uid)
                  .delete();

              // ── STEP 3: Delete Firebase Auth account ──────────
              //
              // This permanently deletes the Auth account. After this,
              // the UID is invalid and the user cannot log in again.
              // This call succeeds because we just re-authenticated (Step 1).
              await widget.auth.currentUser!.delete();

              // ── STEP 4: Close dialog and navigate ─────────────
              // Pop the dialog with true to signal success.
              if (ctx.mounted) Navigator.pop(ctx, true);

              // Navigate to RoleSelectionScreen, clearing the stack.
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RoleSelectionScreen()),
                      (_) => false,
                );
              }

            } on FirebaseAuthException catch (e) {
              // Handle known Firebase error codes with user-friendly messages.
              String msg;
              switch (e.code) {
                case 'wrong-password':
                case 'invalid-credential':
                // The most common case — user typed the wrong password.
                  msg = 'Incorrect password. Please try again.';
                  break;
                case 'too-many-requests':
                // Firebase temporarily locks the account after repeated
                // failed attempts as a brute-force protection measure.
                  msg = 'Too many attempts. Please wait and try again later.';
                  break;
                case 'user-mismatch':
                // The credential provided does not correspond to the
                // currently signed-in user. Should not normally happen.
                  msg = 'Account mismatch. Please log out and try again.';
                  break;
                default:
                  msg = e.message ?? 'Authentication failed. Please try again.';
              }
              setDialogState(() {
                errorMessage = msg;
                isProcessing = false;
              });

            } catch (e) {
              // Catch-all for unexpected errors (network issues, etc.)
              setDialogState(() {
                errorMessage = 'An unexpected error occurred: $e';
                isProcessing = false;
              });
            }
          }

          // ── Dialog UI ────────────────────────────────────────────
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),

            // ── Dialog title ───────────────────────────────────────
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
                    'Confirm Deletion',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),

            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Warning banner ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.20)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppColors.error),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All your data and booking history will be '
                              'permanently deleted. This cannot be undone.',
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
                const SizedBox(height: 16),

                // ── Re-auth explanation ─────────────────────────
                // Inform the user WHY they need to enter their
                // password again — reduces confusion and builds trust.
                const Text(
                  'For your security, please verify your identity by entering your account password.',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Email field — disabled/read-only ────────────
                // Pre-filled with the authenticated user's email.
                // Disabled so the user cannot change it and attempt
                // to re-auth with a different account.
                CustomTextField(
                  controller: TextEditingController(text: email),
                  label: 'Email',
                  hint: email,
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: false, // read-only — cannot be changed
                ),
                const SizedBox(height: 12),

                // ── Password field — active, with visibility toggle ──
                // Uses CustomTextField so the styling is consistent
                // with the rest of the app (AppColors, Nunito font, etc.)
                CustomTextField(
                  controller: passwordCtrl,
                  label: 'Password',
                  hint: 'Enter your password',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: !isPasswordVisible,
                  // The suffix eye icon toggles visibility.
                  // setDialogState is used (not setState) because we are
                  // inside a StatefulBuilder's builder, not the page state.
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () => setDialogState(
                            () => isPasswordVisible = !isPasswordVisible),
                  ),
                ),

                // ── Inline error message ────────────────────────
                // Shown below the password field when re-auth fails.
                // Keeping the error inside the dialog (rather than a
                // SnackBar) provides clearer context while the dialog
                // is still open.
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
              // Cancel — closes dialog without doing anything.
              TextButton(
                onPressed: isProcessing
                    ? null // disable cancel while processing
                    : () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600)),
              ),

              // Delete — triggers performDelete() defined above.
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor:
                  AppColors.error.withOpacity(0.50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                ),
                // Disable button while the async deletion is in progress.
                onPressed: isProcessing ? null : performDelete,
                child: isProcessing
                // Inline CircularProgressIndicator while awaiting Firebase.
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Text(
                  'Delete Account',
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

    // Dispose the password controller when the dialog closes to free
    // memory and avoid TextEditingController leak warnings.
    passwordCtrl.dispose();

    return result ?? false;
  }

  // ──────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(
                fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── App Bar ─────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.white,
            elevation: 0,
            title: const Text(
              'My Profile',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              // Edit / Cancel toggle
              IconButton(
                icon: Icon(
                  _editMode ? Icons.close_rounded : Icons.edit_outlined,
                  color: _editMode ? AppColors.error : AppColors.primary,
                ),
                tooltip: _editMode ? 'Cancel editing' : 'Edit profile',
                onPressed: () {
                  setState(() => _editMode = !_editMode);
                  // Restore saved values if the user taps Cancel.
                  if (!_editMode && _cachedData != null) {
                    _populateControllers(_cachedData!);
                  }
                },
              ),
            ],
          ),

          // ── FutureBuilder Body ───────────────────────────────────
          SliverToBoxAdapter(
            child: FutureBuilder<DocumentSnapshot>(
              future: widget.db
                  .collection('patients')
                  .doc(widget.uid)
                  .get(),
              builder: (context, snap) {

                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(60),
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2.5),
                    ),
                  );
                }

                if (snap.hasError ||
                    !snap.hasData ||
                    !snap.data!.exists) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        'Could not load profile.',
                        style: TextStyle(
                            fontFamily: 'Nunito',
                            color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }

                final data = snap.data!.data() as Map<String, dynamic>;

                // Cache data and populate controllers on first load only.
                if (_cachedData == null) {
                  _cachedData = data;
                  _populateControllers(data);
                }

                final username = data['username'] as String? ?? '—';
                final email    = data['email']    as String? ?? '—';
                final phone    = data['phone']    as String? ?? '—';

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Avatar banner ──────────────────────────
                      _ProfileBanner(username: username, email: email),
                      const SizedBox(height: 20),

                      // ── Profile Fields ─────────────────────────
                      _InfoCard(
                        children: [
                          _SectionLabel(
                            icon: Icons.person_outline_rounded,
                            text: 'Personal Information',
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 14),

                          // Email — always read-only (Firebase Auth manages it)
                          _ReadOnlyField(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: email,
                          ),
                          const SizedBox(height: 12),

                          // Username — editable in edit mode
                          _editMode
                              ? CustomTextField(
                            controller: _usernameCtrl,
                            label: 'Full Name',
                            hint: 'Your full name',
                            prefixIcon: Icons.badge_outlined,
                            keyboardType: TextInputType.name,
                          )
                              : _ReadOnlyField(
                            icon: Icons.badge_outlined,
                            label: 'Full Name',
                            value: username,
                          ),
                          const SizedBox(height: 12),

                          // Phone — editable in edit mode, digits only
                          _editMode
                              ? CustomTextField(
                            controller: _phoneCtrl,
                            label: 'Phone Number',
                            hint: '10-digit number',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                          )
                              : _ReadOnlyField(
                            icon: Icons.phone_outlined,
                            label: 'Phone Number',
                            value: phone,
                          ),
                        ],
                      ),

                      // ── Save button — only shown in edit mode ──
                      if (_editMode) ...[
                        const SizedBox(height: 16),
                        CustomButton(
                          text: 'Save Changes',
                          onPressed: _save,
                          isLoading: _saving,
                          icon: Icons.save_outlined,
                          backgroundColor: AppColors.secondary,
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ══════════════════════════════════════════
                      // DANGER ZONE
                      // ══════════════════════════════════════════
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.20),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 16, color: AppColors.error),
                              const SizedBox(width: 8),
                              const Text('Danger Zone',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  )),
                            ]),
                            const SizedBox(height: 6),
                            const Text(
                              'These actions are permanent and cannot be reversed.',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Logout — opens professional dialog
                            CustomButton(
                              text: 'Log Out',
                              onPressed: _logout,
                              icon: Icons.logout_rounded,
                              backgroundColor: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 12),

                            // Delete Account — triggers re-auth dialog
                            CustomButton(
                              text: 'Delete My Account',
                              onPressed: _deleteAccount,
                              isLoading: _deleting,
                              icon: Icons.delete_forever_outlined,
                              backgroundColor: AppColors.error,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Shared micro-widgets (private to this file)
// ─────────────────────────────────────────────────────────────────

class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.username, required this.email});
  final String username, email;

  /// Generates initials from the username for the avatar circle.
  String get _initials {
    final parts = username.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return username.isNotEmpty ? username[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Initials avatar circle
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.80),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Patient',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
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
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            )),
        const SizedBox(width: 10),
        Expanded(
            child: Divider(color: color.withValues(alpha: 0.20), thickness: 1)),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String   label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 1.0),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                    letterSpacing: 0.3,
                  )),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}