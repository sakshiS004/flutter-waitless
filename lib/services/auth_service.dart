/// ================================================================
/// FILE  : lib/services/auth_service.dart
/// AUTHOR: Waitless Project
///
/// PURPOSE:
///   Centralises ALL Firebase Authentication and account-lifecycle
///   operations for both Patient and Doctor roles.
///
/// BLACK BOOK — SERVICE LAYER PATTERN:
///   In a clean architecture, widgets should never call Firebase
///   SDKs directly. Instead, every Firebase interaction is
///   encapsulated in a Service class:
///
///     Widget  →  calls AuthService method
///     AuthService  →  calls Firebase SDK
///     Firebase SDK  →  returns result / throws exception
///     AuthService  →  re-throws typed exceptions upward
///     Widget  →  catches exception, shows SnackBar
///
///   Benefits:
///     • Firebase import is isolated to the Services layer.
///     • Widgets stay focused on rendering, not business logic.
///     • Easy to mock AuthService in unit tests.
///     • One place to change if Firebase SDK APIs evolve.
///
/// COLLECTIONS WRITTEN BY THIS SERVICE:
///   patients/{uid}  — created during patient registration
///   doctors/{uid}   — created during doctor registration
///
/// ERROR HANDLING:
///   All public methods are async and propagate exceptions to the
///   caller (widget layer). This keeps error-display logic (SnackBar
///   messages, AppColors) in the UI where it belongs, not buried
///   inside a service that shouldn't know about widgets.
/// ================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/models/user_model.dart';
import 'package:waitless/models/doctor_model.dart';

/// Service class that wraps Firebase Authentication and the
/// account-creation Firestore writes for both user roles.
class AuthService {

  // ── Firebase SDK instances ────────────────────────────────────
  // Using the SDK's own global singletons rather than constructor
  // injection because FirebaseAuth.instance and
  // FirebaseFirestore.instance are already process-level singletons
  // guaranteed to be initialised before any service is used
  // (Firebase.initializeApp() is called in main.dart before runApp).
  final FirebaseAuth      _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db   = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────────────
  // AUTH STATE STREAM
  //
  // BLACK BOOK — Reactive Auth Routing:
  //   authStateChanges() returns a Stream<User?> maintained by
  //   the Firebase SDK. It emits:
  //     • A User object  →  someone is signed in.
  //     • null           →  nobody is signed in (cold start or
  //                         after signOut() / account deletion).
  //
  //   The root widget wraps its router in a StreamBuilder on this
  //   stream. When the stream emits null, the app automatically
  //   navigates to RoleSelectionScreen WITHOUT any manual
  //   Navigator.push call. This means signOut() and deleteAccount()
  //   trigger navigation purely through the reactive stream,
  //   keeping navigation logic out of the service layer.
  // ──────────────────────────────────────────────────────────────

  /// Reactive stream of Firebase Auth state changes.
  ///
  /// Listen to this in your root StreamBuilder to auto-route
  /// between the login screen and the home screen.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// The currently signed-in Firebase [User], or null if nobody is
  /// logged in. Use this for quick synchronous UID access inside
  /// service methods rather than listening to the stream.
  User? get currentUser => _auth.currentUser;

  // ──────────────────────────────────────────────────────────────
  // PATIENT REGISTRATION
  //
  // BLACK BOOK — Two-phase account creation:
  //
  //   Firebase Authentication stores ONLY credentials:
  //     email, hashed password, UID, display name.
  //   All app-specific profile data (username, phone, role) MUST
  //   be stored separately in Firestore.
  //
  //   Registration therefore has two distinct phases:
  //     Phase 1: createUserWithEmailAndPassword → Auth account
  //     Phase 2: db.collection('patients').doc(uid).set() → profile
  //
  //   Both MUST succeed for the account to be usable. If Phase 2
  //   fails, the user can log in (Auth exists) but the app crashes
  //   trying to render the profile (Firestore document missing).
  //
  //   Production solution: use a Cloud Function triggered by
  //   Auth onCreate event to create the Firestore document atomically.
  //   For this project: inline two-phase creation with re-throw on
  //   failure so the registration screen shows an error.
  // ──────────────────────────────────────────────────────────────

  /// Registers a new patient.
  ///
  /// Phase 1: Creates a Firebase Auth account with [email]/[password].
  /// Phase 2: Writes a patient profile document to `patients/{uid}`.
  ///
  /// Returns the populated [UserModel] on success.
  /// Throws [FirebaseAuthException] on Auth errors (e.g. weak
  /// password, email-already-in-use).
  Future<UserModel> registerPatient({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) async {
    // Phase 1 — Firebase Auth credential creation.
    final UserCredential cred = await _auth.createUserWithEmailAndPassword(
      email:    email.trim(),
      password: password,
    );

    final String uid = cred.user!.uid;

    // Sync display name to Auth so currentUser.displayName works
    // without a Firestore fetch in places that only need the name.
    await cred.user!.updateDisplayName(name.trim());

    // Phase 2 — Firestore profile document.
    // set() is used (not add()) because the document ID must equal
    // the Auth UID for security rules to work: allow read, write:
    //   if request.auth.uid == resource.id;
    final UserModel user = UserModel(
      uid:      uid,
      username: name.trim(),
      email:    email.trim(),
      phone:    phone.trim(),
      address: address,
      role:     'patient',
    );
    await _db.collection('patients').doc(uid).set(user.toMap());

    return user;
  }

  // ──────────────────────────────────────────────────────────────
  // DOCTOR REGISTRATION
  // ──────────────────────────────────────────────────────────────

  /// Registers a new doctor / clinic.
  ///
  /// Phase 1: Firebase Auth account.
  /// Phase 2: Firestore document in `doctors/{uid}` with all clinic
  ///          metadata (the Firestore field names match the frontend
  ///          bindings exactly: clinicName, openTime, closeTime, offDay).
  ///
  /// Returns the populated [DoctorModel] on success.
  /// Throws [FirebaseAuthException] on credential errors.
  Future<DoctorModel> registerDoctor({
    required String clinicName,
    required String email,
    required String phone,
    required String password,
    required String specialization,
    required String location,
    required String openTime,
    required String closeTime,
    required String offDay,
    String description = '',
  }) async {
    // Phase 1 — Auth account.
    final UserCredential cred = await _auth.createUserWithEmailAndPassword(
      email:    email.trim(),
      password: password,
    );

    final String uid = cred.user!.uid;
    await cred.user!.updateDisplayName(clinicName.trim());

    // Phase 2 — Firestore document in the `doctors` collection.
    final DoctorModel doctor = DoctorModel(
      uid:            uid,
      clinicName:     clinicName.trim(),
      specialization: specialization,
      location:       location.trim(),
      phone:          phone.trim(),
      openTime:       openTime,
      closeTime:      closeTime,
      offDay:         offDay,
      description:    description.trim(),
      role:           'doctor', doctorName: '',
    );
    await _db.collection('doctors').doc(uid).set(doctor.toMap());

    return doctor;
  }

  // ──────────────────────────────────────────────────────────────
  // SIGN IN — shared for both roles
  //
  // Returns the raw Firebase User. The calling screen then calls
  // getUserRole() to decide whether to route to PatientHome or
  // DoctorHome.
  // ──────────────────────────────────────────────────────────────

  /// Signs in with email and password.
  ///
  /// Returns the Firebase [User] on success.
  /// Throws [FirebaseAuthException] with codes such as:
  ///   'user-not-found', 'wrong-password', 'invalid-credential',
  ///   'user-disabled', 'too-many-requests'.
  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    final UserCredential cred = await _auth.signInWithEmailAndPassword(
      email:    email.trim(),
      password: password,
    );
    return cred.user!;
  }

  // ──────────────────────────────────────────────────────────────
  // SIGN OUT
  // ──────────────────────────────────────────────────────────────

  /// Signs the current user out.
  ///
  /// After this call, authStateChanges() emits null, which triggers
  /// the root StreamBuilder to navigate back to RoleSelectionScreen
  /// automatically — no Navigator.push needed in widget code.
  Future<void> signOut() => _auth.signOut();

  // ──────────────────────────────────────────────────────────────
  // RE-AUTHENTICATION
  //
  // BLACK BOOK — Why re-authentication is mandatory for deletion:
  //
  //   Firebase designates certain operations as "security-sensitive":
  //     • Deleting an account  (user.delete())
  //     • Changing email       (user.updateEmail())
  //     • Changing password    (user.updatePassword())
  //
  //   For these, Firebase requires the session token to be RECENT
  //   (typically within the last 5 minutes). If it is not, Firebase
  //   throws:  FirebaseAuthException(code: 'requires-recent-login')
  //
  //   The fix: call reauthenticate() BEFORE the sensitive operation.
  //   This refreshes the session token to "just now".
  //
  //   SECURITY BENEFIT:
  //     Even if a malicious actor gains access to a logged-in device,
  //     they cannot delete the account without knowing the password.
  //     This prevents irreversible data loss from unattended sessions.
  //
  //   IMPLEMENTATION:
  //     EmailAuthProvider.credential(email, password)
  //       → local-only constructor, NO network call.
  //     user.reauthenticateWithCredential(credential)
  //       → network call to Firebase; refreshes token on success.
  // ──────────────────────────────────────────────────────────────

  /// Re-authenticates the current user with their password.
  ///
  /// Call this before [deleteAccount] or any sensitive operation.
  /// Throws [FirebaseAuthException] with code 'wrong-password' /
  /// 'invalid-credential' if the password is incorrect.
  Future<void> reauthenticate({
    required String email,
    required String password,
  }) async {
    // Build the credential object locally (no network yet).
    final AuthCredential credential = EmailAuthProvider.credential(
      email:    email.trim(),
      password: password,
    );
    // Send to Firebase for verification and token refresh.
    await _auth.currentUser!.reauthenticateWithCredential(credential);
  }

  // ──────────────────────────────────────────────────────────────
  // DELETE ACCOUNT
  //
  // BLACK BOOK — Deletion order: Firestore FIRST, Auth SECOND.
  //
  //   If we delete the Auth account first and then the Firestore
  //   deletion fails:
  //     • The UID no longer exists in Firebase Auth.
  //     • Firestore security rules (which check request.auth.uid)
  //       would BLOCK any further attempts to delete the document.
  //     • The orphaned document becomes permanently undeletable
  //       from the client SDK.
  //
  //   Reversing the order (Firestore first, Auth second):
  //     • If Firestore deletion fails → Auth account still exists
  //       → the user can retry deletion after re-logging in.
  //     • If Auth deletion fails → Firestore is already clean;
  //       the UID is still live, so a retry is possible.
  //
  //   PRECONDITION: The caller MUST call reauthenticate() before
  //   either delete method. Otherwise Firebase throws
  //   FirebaseAuthException(code: 'requires-recent-login').
  // ──────────────────────────────────────────────────────────────

  /// Permanently deletes a PATIENT account.
  ///
  /// Step 1 — Deletes `patients/{uid}` from Firestore.
  /// Step 2 — Deletes the Firebase Auth account.
  ///
  /// Caller must have called [reauthenticate] first.
  Future<void> deletePatientAccount() async {
    final String uid = _auth.currentUser!.uid;
    // Step 1: Firestore first (see ordering rationale above).
    await _db.collection('patients').doc(uid).delete();
    // Step 2: Auth account — succeeds because we just re-authed.
    await _auth.currentUser!.delete();
  }

  /// Permanently deletes a DOCTOR account.
  ///
  /// Step 1 — Deletes `doctors/{uid}` from Firestore.
  /// Step 2 — Deletes the Firebase Auth account.
  ///
  /// NOTE: Existing `bookings` documents that reference this
  /// doctorUid are NOT deleted here. In production, a Cloud
  /// Function scheduled job handles orphaned booking cleanup.
  ///
  /// Caller must have called [reauthenticate] first.
  Future<void> deleteDoctorAccount() async {
    final String uid = _auth.currentUser!.uid;
    // Step 1: Firestore first.
    await _db.collection('doctors').doc(uid).delete();
    // Step 2: Auth account.
    await _auth.currentUser!.delete();
  }

  // ──────────────────────────────────────────────────────────────
  // GET USER ROLE
  //
  // Called immediately after signIn() to determine which home
  // screen to route the user to.
  //
  // Checks `patients/{uid}` first, then `doctors/{uid}`.
  // Returns 'patient', 'doctor', or null (corrupted account).
  //
  // Performance note: 2 Firestore reads per login. Production
  // optimisation: store role in Firebase Auth Custom Claims via a
  // Cloud Function, then read claims from the ID token — 0 reads.
  // ──────────────────────────────────────────────────────────────

  /// Returns the role string ('patient' | 'doctor') for [uid],
  /// or null if no matching document exists in either collection.
  Future<String?> getUserRole(String uid) async {
    final patientDoc = await _db.collection('patients').doc(uid).get();
    if (patientDoc.exists) {
      return patientDoc.data()?['role'] as String? ?? 'patient';
    }
    final doctorDoc = await _db.collection('doctors').doc(uid).get();
    if (doctorDoc.exists) {
      return doctorDoc.data()?['role'] as String? ?? 'doctor';
    }
    return null; // no document found — partially registered account
  }
}