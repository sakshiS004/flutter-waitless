/// ================================================================
/// FILE  : lib/core/models/doctor_model.dart
/// AUTHOR: Waitless Project
///
/// PURPOSE:
///   Immutable data model for a Doctor / Clinic document stored in
///   the Firestore `doctors` collection.
///
/// FIRESTORE DOCUMENT SHAPE  ➜  doctors/{uid}
/// ┌──────────────────────────────────────────────────┐
/// │  clinicName        : "City Care Clinic"          │
/// │  specialization    : "Orthopedic"                │
/// │  location          : "Bandra, Mumbai"            │
/// │  phone             : "9123456789"                │
/// │  openTime          : "9:00 AM"                    │
/// │  closeTime         : "6:00 PM"                    │
/// │  offDay            : "Sunday"                     │
/// │  description       : "15 years experience"        │
/// │  role              : "doctor"                      │
/// │  avgTimePerPatient : 10        (NEW)               │
/// │  clinicPhotoUrl    : "https://..." (NEW)           │
/// └──────────────────────────────────────────────────┘
///   uid is the document ID, NOT a stored field.
///
/// FIELD NAME CONTRACT:
///   These camelCase Firestore keys (clinicName, openTime, etc.)
///   are dictated by the frontend team and must NOT be renamed here
///   without updating every Firestore query, index, and widget
///   binding simultaneously. fromMap() / toMap() use these exact
///   strings as the source of truth.
///
/// BLACK BOOK — Denormalisation note:
///   'clinicName' and 'specialization' are also stored inside each
///   BookingModel so the patient queue card can render without a
///   JOIN back to the doctors collection. This is deliberate
///   read-optimisation (Firestore has no server-side joins).
///
/// BLACK BOOK — NEW FIELDS (Wait Time + Profile Photo):
///   • avgTimePerPatient (int, minutes):
///       Doctor-configurable pacing value used purely on the
///       PATIENT side to estimate "Approx. N mins remaining" in
///       the live queue. It never affects queue ORDER — ordering
///       is still strictly FIFO by `timestamp`. It only affects the
///       wait-time ESTIMATE text shown to patients.
///       Defaults to 10 so older doctor documents that predate this
///       field still produce a sane estimate instead of 0 or null.
///   • clinicPhotoUrl (String):
///       A plain HTTPS image URL the doctor pastes in during
///       registration/settings. Deliberately a URL string rather
///       than a Firebase Storage upload — this keeps the app on
///       the Spark (free) plan, since Storage triggers/usage are
///       billed and not included in Spark. Defaults to a neutral
///       medical placeholder so the UI never has to null-check it.
/// ================================================================

class DoctorModel {

  /// Firebase Auth UID — mirrors DocumentSnapshot.id.
  final String uid;

  /// Name of the clinic. Firestore key: 'clinicName'.
  final String clinicName;

  /// Medical specialization (e.g., 'MBBS', 'Dermatologist').
  /// Firestore key: 'specialization'.
  final String specialization;

  /// City or area string. Firestore key: 'location'.
  final String location;

  /// Clinic contact number, digits only. Firestore key: 'phone'.
  final String phone;

  /// Opening time as a display string (e.g., '9:00 AM').
  /// Stored as a human-readable string rather than a Timestamp
  /// because the doctor edits it via a time picker and it is
  /// used directly in UI text widgets without parsing.
  /// Firestore key: 'openTime'.
  final String openTime;

  /// Closing time as display string. Firestore key: 'closeTime'.
  final String closeTime;

  /// The day the clinic is closed (e.g., 'Sunday').
  /// Firestore key: 'offDay'.
  final String offDay;

  /// Optional free-text bio / about section for the clinic card.
  final String description;

  /// Role discriminator — always 'doctor'. Stored in Firestore so
  /// the login router and security rules can check role without
  /// querying a second collection.
  final String role;
  final String doctorName;

  /// NEW — Average minutes the doctor spends per patient.
  /// Used exclusively for the patient-facing wait-time estimate.
  /// Firestore key: 'avgTimePerPatient'. Defaults to 10.
  final int avgTimePerPatient;

  /// NEW — Direct HTTPS URL to the clinic's profile photo.
  /// Plain string field (no Storage upload) to stay on the Spark
  /// free tier. Firestore key: 'clinicPhotoUrl'.
  final String clinicPhotoUrl;

  /// Default placeholder shown until a doctor sets a real photo URL.
  static const String defaultClinicPhotoUrl =
      'https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?w=800&q=80';

  const DoctorModel({
    required this.uid,
    required this.doctorName,
    required this.clinicName,
    required this.specialization,
    required this.location,
    required this.phone,
    required this.openTime,
    required this.closeTime,
    required this.offDay,
    this.description = '',
    this.role = 'doctor',
    this.avgTimePerPatient = 10,
    this.clinicPhotoUrl = defaultClinicPhotoUrl,
  });

  // ── Firestore → Dart ─────────────────────────────────────────
  /// Build a [DoctorModel] from a Firestore document snapshot.
  ///
  /// [map] — DocumentSnapshot.data() as Map<String, dynamic>.
  /// [id]  — DocumentSnapshot.id  (equals the Firebase Auth UID).
  factory DoctorModel.fromMap(Map<String, dynamic> map, String id) {
    return DoctorModel(
      uid:            id,
      doctorName:     map['doctorName']     as String? ?? '',
      clinicName:     map['clinicName']     as String? ?? '',
      specialization: map['specialization'] as String? ?? '',
      location:       map['location']       as String? ?? '',
      phone:          map['phone']          as String? ?? '',
      openTime:       map['openTime']       as String? ?? '',
      closeTime:      map['closeTime']      as String? ?? '',
      offDay:         map['offDay']         as String? ?? '',
      description:    map['description']    as String? ?? '',
      role:           map['role']           as String? ?? 'doctor',
      avgTimePerPatient: (map['avgTimePerPatient'] as num?)?.toInt() ?? 10,
      clinicPhotoUrl: (map['clinicPhotoUrl'] as String?)?.trim().isNotEmpty == true
          ? map['clinicPhotoUrl'] as String
          : defaultClinicPhotoUrl,
    );
  }

  // ── Dart → Firestore ─────────────────────────────────────────
  /// Serialises to a Firestore-writable Map.
  /// uid excluded — it is the document ID.
  Map<String, dynamic> toMap() => {
    'doctorName':     doctorName,
    'clinicName':     clinicName,
    'specialization': specialization,
    'location':       location,
    'phone':          phone,
    'openTime':       openTime,
    'closeTime':      closeTime,
    'offDay':         offDay,
    'description':    description,
    'role':           role,
    'avgTimePerPatient': avgTimePerPatient,
    'clinicPhotoUrl':    clinicPhotoUrl,
  };

  // ── Partial update helper ─────────────────────────────────────
  DoctorModel copyWith({
    String? uid,
    String? doctorName,
    String? clinicName,
    String? specialization,
    String? location,
    String? phone,
    String? openTime,
    String? closeTime,
    String? offDay,
    String? description,
    String? role,
    int? avgTimePerPatient,
    String? clinicPhotoUrl,
  }) =>
      DoctorModel(
        uid:            uid            ?? this.uid,
        doctorName:     doctorName     ?? this.doctorName,
        clinicName:     clinicName     ?? this.clinicName,
        specialization: specialization ?? this.specialization,
        location:       location       ?? this.location,
        phone:          phone          ?? this.phone,
        openTime:       openTime       ?? this.openTime,
        closeTime:      closeTime      ?? this.closeTime,
        offDay:         offDay         ?? this.offDay,
        description:    description    ?? this.description,
        role:           role           ?? this.role,
        avgTimePerPatient: avgTimePerPatient ?? this.avgTimePerPatient,
        clinicPhotoUrl:    clinicPhotoUrl    ?? this.clinicPhotoUrl,
      );

  @override
  String toString() =>
      'DoctorModel(uid: $uid, clinicName: $clinicName, spec: $specialization, '
          'avgTimePerPatient: $avgTimePerPatient, clinicPhotoUrl: $clinicPhotoUrl)';
}

