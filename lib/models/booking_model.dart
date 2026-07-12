/// ================================================================
/// FILE  : lib/core/models/booking_model.dart
/// AUTHOR: Waitless Project
///
/// PURPOSE:
///   Immutable data model for a single appointment booking stored
///   in the Firestore `bookings` collection.
///
/// FIRESTORE DOCUMENT SHAPE  ➜  bookings/{auto-id}
/// ┌──────────────────────────────────────────┐
/// │  patientUid  : "abc123"                  │
/// │  doctorUid   : "xyz789"   ← query key   │
/// │  patientName : "Arjun Mehta"             │
/// │  status      : "pending"  ← or "completed"│
/// │  timestamp   : Timestamp (server)        │
/// └──────────────────────────────────────────┘
///   bookingId = DocumentSnapshot.id (auto-generated).
///
/// STATUS LIFECYCLE:
///   "pending"  →  "completed"
///   Bookings are created as 'pending'. The doctor's "Call Next"
///   action updates the oldest pending booking to 'completed'.
///   Cancelled bookings are hard-deleted (not status-updated).
///
/// BLACK BOOK — Denormalisation: Why store patientName here?
///   Firestore has NO server-side JOINs. If we only stored
///   patientUid, the doctor's queue list would need an extra
///   Firestore read per booking to get the patient's name.
///   For N patients in queue → N extra reads per render.
///   Storing patientName directly in the booking document reduces
///   this to 0 extra reads. The trade-off: if a patient changes
///   their name, existing bookings show the old name. For a
///   queue-management app this is acceptable — bookings are
///   short-lived (hours, not days).
///
/// BLACK BOOK — Why 'doctorUid' as the query filter field?
///   DbService.getLiveQueue() uses:
///     .where('doctorUid', isEqualTo: uid)
///     .where('status',    isEqualTo: 'pending')
///     .orderBy('timestamp', descending: false)
///   Firestore requires a COMPOSITE INDEX for multi-field queries
///   with orderBy. Create this index in the Firebase Console:
///     Collection: bookings
///     Fields: doctorUid ASC, status ASC, timestamp ASC
/// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';


class BookingModel {

  /// Auto-generated Firestore document ID.
  /// NOT stored as a Firestore field — taken from DocumentSnapshot.id.
  final String bookingId;

  /// UID of the patient who booked. Firestore key: 'patientUid'.
  final String patientUid;

  /// UID of the doctor being visited. Firestore key: 'doctorUid'.
  /// This is the primary filter key in getLiveQueue() queries.
  final String doctorUid;

  /// Denormalised patient name for zero-read queue rendering.
  /// Firestore key: 'patientName'.
  final String patientName;

  /// 'pending' or 'completed'. Kept as a plain String (not an enum)
  /// so Firestore .where('status', isEqualTo: 'pending') works
  /// without a conversion function.
  /// Firestore key: 'status'.
  final String status;

  /// Server-side creation timestamp (FieldValue.serverTimestamp()).
  /// Used for FIFO ordering — ascending timestamp = oldest first.
  /// Nullable because the Firestore listener may receive the local
  /// write BEFORE the server has assigned the timestamp
  /// (optimistic local cache). Always non-null once committed.
  /// Firestore key: 'timestamp'.
  final Timestamp? timestamp;

  const BookingModel({
    required this.bookingId,
    required this.patientUid,
    required this.doctorUid,
    required this.patientName,
    required this.status,
    this.timestamp,
  });

  // ── Firestore → Dart ─────────────────────────────────────────
  /// Build a [BookingModel] from a Firestore document.
  ///
  /// [map] — DocumentSnapshot.data() as Map<String, dynamic>.
  /// [id]  — DocumentSnapshot.id  (auto-generated booking ID).
  factory BookingModel.fromMap(Map<String, dynamic> map, String id) {
    return BookingModel(
      bookingId:   id,
      patientUid:  map['patientUid']  as String?    ?? '',
      doctorUid:   map['doctorUid']   as String?    ?? '',
      patientName: map['patientName'] as String?    ?? 'Unknown Patient',
      status:      map['status']      as String?    ?? 'pending',
      timestamp:   map['timestamp']   as Timestamp?,
    );
  }

  // ── Dart → Firestore ─────────────────────────────────────────
  /// Serialises for Firestore add() / set() calls.
  ///
  /// bookingId is excluded (it's the document ID).
  /// timestamp is excluded — DbService writes it via
  /// FieldValue.serverTimestamp() for server-authoritative ordering.
  Map<String, dynamic> toMap() => {
    'patientUid':  patientUid,
    'doctorUid':   doctorUid,
    'patientName': patientName,
    'status':      status,
    // timestamp intentionally omitted — set server-side in DbService
  };

  // ── Convenience getters ───────────────────────────────────────

  /// true if still waiting in the queue.
  bool get isPending   => status == 'pending';

  /// true if the doctor has already called this patient.
  bool get isCompleted => status == 'completed';

  // ── Partial update helper ─────────────────────────────────────
  BookingModel copyWith({
    String?    bookingId,
    String?    patientUid,
    String?    doctorUid,
    String?    patientName,
    String?    status,
    Timestamp? timestamp,
  }) =>
      BookingModel(
        bookingId:   bookingId   ?? this.bookingId,
        patientUid:  patientUid  ?? this.patientUid,
        doctorUid:   doctorUid   ?? this.doctorUid,
        patientName: patientName ?? this.patientName,
        status:      status      ?? this.status,
        timestamp:   timestamp   ?? this.timestamp,
      );

  @override
  String toString() =>
      'BookingModel(id: $bookingId, patient: $patientName, status: $status)';
}