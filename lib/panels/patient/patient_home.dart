/// ================================================================
/// FILE  : lib/panels/patient/patient_home.dart
/// AUTHOR: Waitless Project
///
/// OVERVIEW:
///   The Patient Home screen is the main discovery hub for patients.
///   It displays a real-time list of all registered doctors fetched
///   from the Firestore `doctors` collection using a StreamBuilder.
///
///   ARCHITECTURE — Dynamic Page Routing with Doctor UID:
///   ─────────────────────────────────────────────────────
///   Instead of creating a separate page file for each clinic, we
///   use a SINGLE template page — ClinicDetailsPage — and pass the
///   specific doctor's UID as a constructor parameter.
///
///   Flow:
///     PatientHomeScreen                 ClinicDetailsPage
///     ─────────────────                 ────────────────────────
///     StreamBuilder reads all docs
///     from `doctors` collection
///                ↓
///     Renders a DoctorCard per doc
///     (each card knows its doctorUid)
///                ↓
///     Patient taps a card
///                ↓
///     Navigator.push( ─────────────→   ClinicDetailsPage(
///       ClinicDetailsPage(               doctorUid: "xyz123"
///         doctorUid: doc.id            )
///       )                              Uses doctorUid to query:
///     )                                  doctors/xyz123  (profile)
///                                        bookings where
///                                          doctorId == "xyz123"
///
///   WHY THIS IS BETTER THAN MULTIPLE FILES:
///   • 1 file instead of N files (one per doctor).
///   • All clinic pages look consistent — same layout, same logic.
///   • Adding a new doctor to Firestore automatically creates a
///     new tappable card with a working detail page. Zero code change.
///   • This pattern is called a "Dynamic Route" or "Detail Page"
///     and is standard in Flutter, Android (Intents + extras),
///     and web development (route parameters like /clinic/:id).
/// ================================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/panels/patient/clinic_details_page.dart';
import 'package:waitless/panels/patient/patient_profile.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  /// Current tab index for bottom navigation.
  /// 0 = Find Doctors, 1 = My Profile
  int _currentIndex = 0;

  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  /// Convenience getter — the signed-in patient.
  /// Non-null because this screen is only reachable after login.
  User get _user => _auth.currentUser!;

  /// Search query string — filters the doctor list in real time.
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // STREAM — All doctors from Firestore
  // ──────────────────────────────────────────────────────────────

  /// Returns a real-time stream of all documents in the `doctors`
  /// collection. Firestore pushes a new snapshot whenever any
  /// doctor registers, updates their profile, or is deleted.
  ///
  /// We order by `createdAt` so newer doctors don't jump to the
  /// top and disrupt the patient's visual scanning.
  Stream<QuerySnapshot> get _doctorsStream =>
      _db.collection('doctors').snapshots();

  // ──────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildDiscoveryTab(),
          PatientProfilePage(uid: _user.uid, db: _db, auth: _auth),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.primary.withValues(alpha:0.12),
        destinations: const [
          NavigationDestination(
            icon:         Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: AppColors.primary),
            label: 'Find Doctors',
          ),
          NavigationDestination(
            icon:         Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: AppColors.primary),
            label: 'My Profile',
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Discovery Tab Widget
  // ──────────────────────────────────────────────────────────────

  Widget _buildDiscoveryTab() {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Greeting row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Find a Doctor',
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Real-time availability near you',
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      // Live indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha:0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.success.withValues(alpha:0.30)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 7, height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text('Live',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.success,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Search bar ───────────────────────────────
                  /// Filters the StreamBuilder results client-side.
                  /// For large datasets, move filtering to a Firestore
                  /// query (.where / full-text search with Algolia).
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.toLowerCase()),
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by name, specialization, or city…',
                        hintStyle: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 14,
                          color: AppColors.textHint,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.textSecondary, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.textHint, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Doctor List via StreamBuilder ─────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: _doctorsStream,
            builder: (context, snapshot) {

              // Loading skeleton
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (_, i) => const _DoctorCardSkeleton(),
                    childCount: 4,
                  ),
                );
              }

              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: _ErrorCard(msg: snapshot.error.toString()),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];

              // Client-side search filter
              final docs = _searchQuery.isEmpty
                  ? allDocs
                  : allDocs.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final name = (d['clinicName'] ?? '').toString().toLowerCase();
                final spec  = (d['specialization'] ?? '').toString().toLowerCase();
                final loc   = (d['location']       ?? '').toString().toLowerCase();
                return name.contains(_searchQuery)
                    || spec.contains(_searchQuery)
                    || loc.contains(_searchQuery);
              }).toList();

              if (docs.isEmpty) {
                return SliverToBoxAdapter(
                  child: _EmptyState(
                    message: _searchQuery.isNotEmpty
                        ? 'No doctors match "$_searchQuery"'
                        : 'No doctors registered yet.',
                  ),
                );
              }

              return SliverPadding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, i) {
                      final data =
                      docs[i].data() as Map<String, dynamic>;

                      /// KEY PATTERN — Passing doctorUid dynamically:
                      /// docs[i].id is the Firestore document ID, which
                      /// equals the doctor's Firebase Auth UID (set during
                      /// registration). We pass it to DoctorCard, which
                      /// forwards it to ClinicDetailsPage via Navigator.push.
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _DoctorCard(
                          doctorUid:      docs[i].id,
                          doctorName:     data['doctorName']    as String? ?? '',
                          email:          data['email']          as String? ?? '—',
                          specialization: data['specialization'] as String? ?? '—',
                          location:       data['location']       as String? ?? '—',
                          openTime:       data['openTime']       as String? ?? '—',
                          closeTime:      data['closeTime']      as String? ?? '—',
                          offDay:         data['offDay']         as String? ?? '—',
                          isVerified:     data['is_verified']    as bool?   ?? false,
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                ),
              );
            },
          ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.doctorUid,
    required this.doctorName,
    required this.email,
    required this.specialization,
    required this.location,
    required this.openTime,
    required this.closeTime,
    required this.offDay,
    required this.isVerified,
  });

  final String doctorUid;
  final String email, specialization, location;
  final String openTime, closeTime, offDay;
  final String doctorName;
  final bool   isVerified;

  // Maps specialization string to an appropriate medical icon
  IconData get _specIcon {
    return switch (specialization.toLowerCase()) {
      'orthopedic'    => Icons.accessibility_new_rounded,
      'dermatologist' => Icons.face_retouching_natural,
      _               => Icons.local_hospital_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          /// This is where the dynamic routing happens.
          /// We construct ClinicDetailsPage with the specific
          /// doctorUid of the card that was tapped.
          builder: (_) => ClinicDetailsPage(doctorUid: doctorUid),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha:0.05),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Coloured header ────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.06),
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha:0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(_specIcon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                specialization,
                                style: const TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            if (isVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha:0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.verified_rounded,
                                        size: 11, color: AppColors.success),
                                    SizedBox(width: 3),
                                    Text('Verified',
                                        style: TextStyle(
                                          fontFamily: 'Nunito',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.success,
                                        )),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          doctorName.isNotEmpty ? doctorName : email,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Info row ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _InfoPill(
                    icon: Icons.place_outlined,
                    text: location,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  _InfoPill(
                    icon: Icons.access_time_rounded,
                    text: '$openTime – $closeTime',
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),

            // ── Footer row ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InfoPill(
                    icon: Icons.event_busy_outlined,
                    text: 'Off: $offDay',
                    color: AppColors.error,
                  ),
                  Row(
                    children: const [
                      Text('View Clinic',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          )),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 15, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Supporting small widgets
// ─────────────────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String   text;
  final Color    color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorCardSkeleton extends StatelessWidget {
  const _DoctorCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.divider.withValues(alpha:0.5),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 56, color: AppColors.textHint.withValues(alpha:0.5)),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                color: AppColors.textSecondary,
              )),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.msg});
  final String msg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha:0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha:0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    color: AppColors.error,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}