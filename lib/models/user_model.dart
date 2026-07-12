/// ================================================================
/// FILE  : lib/core/models/user_model.dart
/// AUTHOR: Waitless Project
///
/// PURPOSE:
///   Immutable data model for a Patient user document stored in
///   the Firestore `patients` collection.
///
/// FIRESTORE DOCUMENT SHAPE  ➜  patients/{uid}
/// ┌──────────────────────────────────────────┐
/// │  username  : "Arjun Mehta"               │
/// │  email     : "arjun@email.com"           │
/// │  phone     : "9876543210"                │
/// │  role      : "patient"                   │
/// └──────────────────────────────────────────┘
///   uid is the document ID, NOT a stored field.
///
/// BLACK BOOK — Why typed models instead of raw Maps?
///   Firestore snapshots return Map<String, dynamic>. Every access
///   requires a runtime cast and null guard. A typed model class:
///     1. Gives compile-time field checking (typos caught at build).
///     2. Centralises null-fallback defaults in ONE place (fromMap).
///     3. Simplifies widget code — pass UserModel, not a raw Map.
///     4. copyWith() enables immutable partial updates cleanly.
/// ================================================================

class UserModel {

  /// Firebase Auth UID — mirrors DocumentSnapshot.id.
  /// Not stored as a Firestore field; passed separately.
  final String uid;

  /// Patient display name. Firestore key: 'username'.
  final String username;

  /// Login email, mirrors Firebase Auth email.
  final String email;

  /// 10-digit phone number, digits only.
  final String phone;

  /// Role discriminator — always 'patient' for this model.
  /// Stored in Firestore so login router can avoid a second
  /// collection lookup when deciding which home screen to show.
  final String role;
  final String address;

  const UserModel({
    required this.uid,
    required this.username,
    required this.email,
    required this.phone,
    required this.address,
    this.role = 'patient',
  });

  // ── Firestore → Dart ─────────────────────────────────────────
  /// Build a [UserModel] from a Firestore document snapshot.
  ///
  /// [map] — DocumentSnapshot.data() as Map<String, dynamic>.
  /// [id]  — DocumentSnapshot.id  (equals the Firebase Auth UID).
  ///
  /// ?? '' fallbacks ensure a partially-written document never
  /// causes a null-deref crash in the UI layer.
  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      uid:      id,
      username: map['username'] as String? ?? '',
      email:    map['email']    as String? ?? '',
      phone:    map['phone']    as String? ?? '',
      address:  map['address']  as String? ?? '',
      role:     map['role']     as String? ?? 'patient',
    );
  }

  // ── Dart → Firestore ─────────────────────────────────────────
  /// Serialises this model to a Map for Firestore set() / update().
  /// uid is excluded — it is the document ID, not a field.
  Map<String, dynamic> toMap() => {
    'username': username,
    'email':    email,
    'phone':    phone,
    'address':  address,
    'role':     role,
  };

  // ── Partial update helper ─────────────────────────────────────
  /// Returns a NEW UserModel with only the supplied fields changed.
  /// All other fields are carried forward unchanged.
  UserModel copyWith({
    String? uid,
    String? username,
    String? email,
    String? phone,
    String? address,
    String? role,
  }) =>
      UserModel(
        uid:      uid      ?? this.uid,
        username: username ?? this.username,
        email:    email    ?? this.email,
        phone:    phone    ?? this.phone,
        address:  address  ?? this.address,
        role:     role     ?? this.role,
      );

  @override
  String toString() =>
      'UserModel(uid: $uid, username: $username, role: $role)';
}