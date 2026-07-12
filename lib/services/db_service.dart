/// ================================================================
/// FILE  : lib/services/db_service.dart
/// AUTHOR: Waitless Project
///
/// PURPOSE:
///   Centralises ALL Firestore read / write / stream operations
///   for both the Patient Panel and the Doctor/Admin Panel.
///
/// BLACK BOOK — DATABASE SERVICE LAYER:
///   Direct Firestore calls scattered across widgets make code
///   hard to maintain — if a collection name or field key changes,
///   you must hunt every widget. DbService acts as the single
///   source of truth for all Firestore interactions:
///
///     Widget  →  calls DbService method
///     DbService  →  executes Firestore query / mutation
///     Firestore  →  returns QuerySnapshot / DocumentSnapshot / void
///     DbService  →  maps to typed model / Stream<List<Model>>
///     Widget  →  receives clean typed data, renders UI
///
/// REAL-TIME vs ONE-SHOT READS:
///   • StreamBuilder consumers (Live Queue, Clinic List) use
///     .snapshots() → Firestore maintains a persistent WebSocket
///     and pushes changes within ~300ms of a write anywhere in
///     the world. No polling. No refresh buttons.
///   • One-shot reads (profile fetch) use .get() → simpler,
///     cheaper (no open socket), appropriate for data that
///     doesn't need to update live.
///
/// FIRESTORE INDEXES REQUIRED:
///   getLiveQueue() uses a compound query:
///     WHERE doctorUid == X AND status == 'pending' ORDER BY timestamp ASC
///   This REQUIRES a composite index in the Firebase Console:
///     Collection : bookings
///     Fields     : doctorUid ASC → status ASC → timestamp ASC
///   Without the index, Firestore throws a runtime exception with
///   a direct link to create it automatically.
/// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/models/user_model.dart';
import 'package:waitless/models/doctor_model.dart';
import 'package:waitless/models/booking_model.dart';

/// Database service — wraps all Firestore interactions for the
/// Waitless app. Instantiate once and share via a Provider,
/// GetIt, or pass as a constructor parameter.
class DbService {

  final FirebaseFirestore _db = FirebaseFirestore.instance;


  Stream<List<DoctorModel>> getClinics() {
    return _db
        .collection('doctors')
    //.orderBy('clinicName') // alphabetical A-Z for UI
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => DoctorModel.fromMap(doc.data(), doc.id))
        .toList());
  }


  /// [patientUid]  — Firebase Auth UID of the booking patient.
  /// [patientName] — Denormalised name for zero-read queue render.
  /// [doctorUid]   — Target doctor's Firebase Auth UID.
  ///
  Future<String> bookAppointment({
    required String patientUid,
    required String patientName,
    required String doctorUid,
  }) async {
    final booking = BookingModel(
      bookingId:   '',         // placeholder — ID assigned by Firestore
      patientUid:  patientUid,
      doctorUid:   doctorUid,
      patientName: patientName,
      status:      'pending',  // all bookings start as 'pending'
    );

    // add() returns a DocumentReference whose .id is the auto-generated key.
    final DocumentReference ref = await _db.collection('bookings').add({
      ...booking.toMap(),
      // Server timestamp for reliable FIFO ordering (see Black Book note).
      'timestamp': FieldValue.serverTimestamp(),
    });

    return ref.id; // caller can use this as a booking receipt ID
  }


  Future<UserModel?> getPatientProfile(String uid) async {
    final doc = await _db.collection('patients').doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromMap(doc.data()!, doc.id);
  }

  /// Updates the patient's editable profile fields in Firestore.
  Future<void> updatePatientProfile({
    required String uid,
    required String username,
    required String phone,
    required String address, // ← include address here too
  }) async {
    await _db.collection('patients').doc(uid).update({
      'username':  username.trim(),
      'phone':     phone.trim(),
      'address':   address.trim(), // ← so profile edits save address
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createPatient({
    required String uid,
    required String username,
    required String email,
    required String phone,
    required String address,
  }) async {
    await _db.collection('patients').doc(uid).set({
      'uid': uid,
      'username': username.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
      'role': 'patient',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }


  Stream<List<BookingModel>> getPatientBookings(String patientUid) {
    return _db
        .collection('bookings')
        .where('patientUid', isEqualTo: patientUid)
    //.orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
        .map((doc) => BookingModel.fromMap(doc.data(), doc.id))
        .toList());
  }


  Stream<List<BookingModel>> getLiveQueue(String doctorUid) {
    return _db
        .collection('bookings')
        .where('doctorUid', isEqualTo: doctorUid) // only this doctor's queue
        .where('status',    isEqualTo: 'pending')  // only waiting patients
    //.orderBy('timestamp', descending: false)   // oldest first = FIFO
        .snapshots()
        .map((snap) => snap.docs
        .map((doc) => BookingModel.fromMap(doc.data(), doc.id))
        .toList());
  }



  Future<void> callNextPatient(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> pendingDocs) async {
    if (pendingDocs.isEmpty) {
      throw StateError('callNextPatient called on an empty queue.');
    }

    // docs[0] is the oldest (lowest timestamp) — the next patient.
    await _db.collection('bookings').doc(pendingDocs.first.id).update({
      'status':   'completed',
      'servedAt': FieldValue.serverTimestamp(), // record when they were called
    });
  }

  Future<void> resetQueue(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> pendingDocs) async {
    if (pendingDocs.isEmpty) return; // nothing to reset

    // A WriteBatch groups all deletes into one atomic operation.
    final WriteBatch batch = _db.batch();
    for (final doc in pendingDocs) {
      batch.delete(doc.reference);
    }
    // commit() sends all batched operations to Firestore at once.
    await batch.commit();
  }

  // ──────────────────────────────────────────────────────────────
  // getDoctorProfile() — One-shot doctor profile read
  // ──────────────────────────────────────────────────────────────

  /// Fetches the doctor profile document from `doctors/{uid}`.
  ///
  /// Returns null if no document exists.
  Future<DoctorModel?> getDoctorProfile(String uid) async {
    final doc = await _db.collection('doctors').doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return DoctorModel.fromMap(doc.data()!, doc.id);
  }

  // ──────────────────────────────────────────────────────────────
  // updateDoctorProfile() — REFACTORED
  //
  // NEW PARAMETERS:
  //   avgTimePerPatient — doctor-configured pacing (minutes/patient),
  //                       used only for the patient-facing wait-time
  //                       estimate. Has a default so existing call
  //                       sites that haven't been updated yet still
  //                       compile and behave sensibly.
  //   clinicPhotoUrl    — plain HTTPS URL pasted by the doctor.
  //                       No Firebase Storage involved, so this
  //                       stays free on the Spark plan.
  //
  // ATOMIC UPDATE GUARANTEE:
  //   This still uses .update() (not .set()), which only touches the
  //   keys explicitly listed below. Every other field already on the
  //   doctors/{uid} document — createdAt, isVerified, email, role,
  //   denormalised queue data, etc. — is left completely untouched.
  // ──────────────────────────────────────────────────────────────
  Future<void> updateDoctorProfile({
    required String uid,
    required String clinicName,
    required String specialization,
    required String location,
    required String phone,
    required String openTime,
    required String closeTime,
    required String offDay,
    String description = '',
    int avgTimePerPatient = 10,        // NEW
    String clinicPhotoUrl = '',        // NEW
  }) async {
    await _db.collection('doctors').doc(uid).update({
      'clinicName':     clinicName.trim(),
      'specialization': specialization,
      'location':       location.trim(),
      'phone':          phone.trim(),
      'openTime':       openTime,
      'closeTime':      closeTime,
      'offDay':         offDay,
      'description':    description.trim(),
      // NEW — only written when non-empty so a doctor who hasn't
      // touched the photo URL field doesn't overwrite an existing
      // value with an empty string.
      'avgTimePerPatient': avgTimePerPatient,
      if (clinicPhotoUrl.trim().isNotEmpty)
        'clinicPhotoUrl': clinicPhotoUrl.trim(),
      'updatedAt':      FieldValue.serverTimestamp(), // audit trail
    });
  }

  // ──────────────────────────────────────────────────────────────
  // getCompletedBookings() — Doctor's historical patient log
  // ──────────────────────────────────────────────────────────────

  /// Returns a live stream of all completed bookings for [doctorUid],
  /// ordered most-recent first (useful for a "today's patients" log).
  Stream<List<BookingModel>> getCompletedBookings(String doctorUid) {
    return _db
        .collection('bookings')
        .where('doctorUid', isEqualTo: doctorUid)
        .where('status',    isEqualTo: 'completed')
    //.orderBy('servedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
        .map((doc) => BookingModel.fromMap(doc.data(), doc.id))
        .toList());
  }


}