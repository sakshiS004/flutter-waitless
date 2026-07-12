/// ================================================================
/// FILE  : lib/panels/patient/clinic_details_page.dart
/// AUTHOR: Waitless Project
///
/// OVERVIEW:
///   ClinicDetailsPage is a DYNAMIC TEMPLATE. It is a single file
///   that renders the correct clinic for whichever doctor was tapped
///   on the home screen. The specific doctor is identified by the
///   `doctorUid` parameter passed in from PatientHomeScreen.
///
/// ────────────────────────────────────────────────────────────────
/// BLACK BOOK — How Dynamic UID Passing Works:
///
///   PROBLEM: A clinic app might have 50 doctors. Without dynamic
///   routing, you'd need 50 separate Dart files:
///     clinic_dr_smith.dart, clinic_dr_patel.dart, etc.
///   This is unmaintainable and breaks every time a doctor joins.
///
///   SOLUTION — Constructor Parameter Pattern:
///
///     // PatientHomeScreen.dart (caller)
///     Navigator.push(
///       context,
///       MaterialPageRoute(
///         builder: (_) => ClinicDetailsPage(doctorUid: "abc123"),
///       ),
///     );
///
///     // ClinicDetailsPage.dart (this file, receiver)
///     class ClinicDetailsPage extends StatefulWidget {
///       final String doctorUid;  ← receives the UID
///       const ClinicDetailsPage({required this.doctorUid});
///     }
///
///   The UID is then used in ALL queries in this file:
///     _db.collection('doctors').doc(widget.doctorUid)  ← profile
///     _db.collection('bookings')
///         .where('doctorId', isEqualTo: widget.doctorUid) ← queue
///
///   RESULT: One file handles ALL clinics. The UI is identical;
///   only the data changes based on which UID was passed.
///   Adding a new doctor to Firestore requires zero code changes.
///
/// ────────────────────────────────────────────────────────────────
/// TWO FIREBASE WIDGETS IN ONE SCREEN:
///
///   FutureBuilder — Doctor profile (doctors/{uid})
///     • One-time read. Profile data doesn't change while browsing.
///     • Cheaper: 1 Firestore read vs. a persistent listener.
///
///   StreamBuilder — Live queue count (bookings collection)
///     • Real-time listener. Queue changes as patients book/are served.
///     • Fires a UI rebuild every time the pending count changes.
///     • This is the cross-panel sync: when the Doctor Dashboard
///       calls "Call Next" and marks a booking as 'completed',
///       this screen's queue count drops immediately.
///
/// ────────────────────────────────────────────────────────────────
/// BOOKING DOCUMENT SCHEMA — bookings/{auto-id}:
///
///   {
///     patientUid:  String    — current patient's Auth UID
///     doctorId:    String    — the doctorUid passed to this page
///     status:      'pending' — initial state (doctor changes to 'completed')
///     timestamp:   Timestamp — when the booking was made
///     tokenNumber: int       — queue position number
///   }
///
/// ────────────────────────────────────────────────────────────────
/// BLACK BOOK — ESTIMATED WAIT TIME (NEW):
///
///   getEstimatedWaitTime(queuePosition, avgTimePerPatient) is a pure
///   helper (no Firestore/BuildContext dependency) so it's trivially
///   testable. It never influences queue ORDER — bookings are still
///   strictly FIFO by `timestamp`. It only turns "you are patient
///   #4" into a friendly string like "Approx. 30 mins remaining".
///
///   The patient's own queue POSITION is derived from the same
///   `_queueStream` that already powers the live count banner —
///   sorted client-side by `timestamp` and located by matching the
///   current user's `patientUid`. No new Firestore query or index
///   is needed.
///
///   NOTE — PRE-EXISTING FIELD NAME MISMATCH (not introduced here):
///   This file reads doctor fields as 'open_time' / 'close_time' /
///   'off_day' / 'clinic_phone' and queries bookings by 'doctorId',
///   while DoctorModel / DbService elsewhere in the app write
///   'openTime' / 'closeTime' / 'offDay' / 'phone' and query by
///   'doctorUid'. That mismatch already existed before this change
///   and has been left exactly as-is. The new 'avgTimePerPatient'
///   and 'clinicPhotoUrl' fields are read using their real camelCase
///   Firestore keys, since they are new and have no legacy mismatch.
/// ================================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/widgets/custom_button.dart';

// ─────────────────────────────────────────────────────────────────
// getEstimatedWaitTime — NEW pure helper function
// ─────────────────────────────────────────────────────────────────

/// Converts a patient's raw queue position into a friendly,
/// human-readable estimated wait time string.
///
/// [queuePosition]      — 1-based position in the FIFO queue
///                        (1 = next patient to be called).
/// [avgTimePerPatient]  — doctor-configured minutes per patient
///                        (DoctorModel.avgTimePerPatient).
///
/// Business rule:
///   waitMinutes = (queuePosition - 1) * avgTimePerPatient
///
/// queuePosition <= 1 is treated as "you're up next" rather than
/// running the multiplication, since (1-1)*x is always 0 anyway
/// and deserves a clearer message than "Approx. 0 mins remaining".
String getEstimatedWaitTime(int queuePosition, int avgTimePerPatient) {
  if (queuePosition <= 1) {
    return 'You are next! Please arrive at the clinic desk.';
  }

  final int waitMinutes = (queuePosition - 1) * avgTimePerPatient;

  if (waitMinutes < 60) {
    return 'Approx. $waitMinutes mins remaining';
  }

  final int hours   = waitMinutes ~/ 60;
  final int minutes = waitMinutes % 60;

  if (minutes == 0) {
    return 'Approx. ${hours}h remaining';
  }
  return 'Approx. ${hours}h ${minutes}m remaining';
}

// ─────────────────────────────────────────────────────────────────
// ClinicDetailsPage — Dynamic Template
// ─────────────────────────────────────────────────────────────────
class ClinicDetailsPage extends StatefulWidget {
  /// The Firestore document ID of the doctor whose clinic to display.
  /// This is the ONLY field needed to fully populate this entire page.
  /// It is passed from PatientHomeScreen via Navigator.push().
  final String doctorUid;

  const ClinicDetailsPage({super.key, required this.doctorUid});

  @override
  State<ClinicDetailsPage> createState() => _ClinicDetailsPageState();
}

class _ClinicDetailsPageState extends State<ClinicDetailsPage> {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Whether a booking write is in progress (controls button spinner).
  bool _booking = false;

  // ──────────────────────────────────────────────────────────────
  // FUTURE — Doctor profile (one-time read)
  // ──────────────────────────────────────────────────────────────

  /// Fetches the doctor document once. The result is cached by
  /// FutureBuilder for the lifetime of this widget.
  ///
  /// widget.doctorUid — the UID passed from the home screen.
  Future<DocumentSnapshot> get _doctorFuture =>
      _db.collection('doctors').doc(widget.doctorUid).get();

  // ──────────────────────────────────────────────────────────────
  // STREAM — Live queue count (real-time)
  // ──────────────────────────────────────────────────────────────

  /// Returns a live stream of pending bookings for THIS doctor.
  ///
  /// WHY StreamBuilder here but FutureBuilder for the profile?
  ///   The queue count changes frequently (patients book, doctor
  ///   calls next). A StreamBuilder keeps the count live without
  ///   the patient needing to refresh the page.
  ///
  ///   The profile (specialization, hours) rarely changes, so a
  ///   one-time FutureBuilder read is cheaper and sufficient.
  Stream<QuerySnapshot> get _queueStream => _db
      .collection('bookings')
      .where('doctorId', isEqualTo: widget.doctorUid)
      .where('status',   isEqualTo: 'pending')
      .snapshots();

  // ──────────────────────────────────────────────────────────────
  // BOOK APPOINTMENT
  // ──────────────────────────────────────────────────────────────

  /// Writes a new booking document to Firestore.
  ///
  /// Steps:
  ///   1. Check if patient already has a pending booking for this doctor.
  ///   2. Get current queue length to assign tokenNumber.
  ///   3. Write the booking document.
  ///   4. Show success SnackBar.
  ///
  /// Cross-panel effect:
  ///   This .add() call triggers a Firestore snapshot update in the
  ///   Doctor Dashboard's StreamBuilder (doc_home.dart). The doctor
  ///   sees the queue count increase within ~1 second automatically.
  Future<void> _bookAppointment() async {
    final String patientUid = _auth.currentUser!.uid;

    setState(() => _booking = true);
    try {
      // ── Check for duplicate pending booking ─────────────────
      final existing = await _db
          .collection('bookings')
          .where('patientUid', isEqualTo: patientUid)
          .where('doctorId',   isEqualTo: widget.doctorUid)
          .where('status',     isEqualTo: 'pending')
          .get();

      if (existing.docs.isNotEmpty) {
        _showSnack(
          'You already have a pending booking with this doctor.',
          isError: true,
        );
        return;
      }

      // ── Get current queue length for token number ────────────
      final queueSnap = await _db
          .collection('bookings')
          .where('doctorId', isEqualTo: widget.doctorUid)
          .where('status',   isEqualTo: 'pending')
          .get();

      final int tokenNumber = queueSnap.docs.length + 1;

      // ── Write booking document ──────────────────────────────
      // .add() auto-generates a document ID. We don't need to
      // control the ID here because bookings are queried by
      // doctorId + status, not by their document ID.
      await _db.collection('bookings').add({
        'patientUid':  patientUid,
        'doctorId':    widget.doctorUid,
        'status':      'pending',
        'tokenNumber': tokenNumber,
        'timestamp':   FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnack(
          '✓ Booked! Your token number is #$tokenNumber.',
          isError: false,
        );
      }
    } catch (e) {
      _showSnack('Booking failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // HELPER — SnackBar
  // ──────────────────────────────────────────────────────────────

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(
                fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<DocumentSnapshot>(
        future: _doctorFuture,
        builder: (context, snapshot) {

          // ── Loading ─────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2.5),
            );
          }

          // ── Error / not found ────────────────────────────────
          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Clinic Details'),
                backgroundColor: AppColors.white,
              ),
              body: Center(
                child: Text(
                  'Clinic not found.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            );
          }

          // ── Extract doctor profile data ──────────────────────
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final spec      = data['specialization'] as String? ?? '—';
          final email     = data['email']          as String? ?? '—';
          final location  = data['location']       as String? ?? '—';
          final openTime  = data['open_time']       as String? ?? '—';
          final closeTime = data['close_time']      as String? ?? '—';
          final offDay    = data['off_day']          as String? ?? '—';
          final phone     = data['clinic_phone']    as String? ?? '—';
          // NEW — tolerant parse, default 10, mirrors DoctorModel.fromMap.
          final int avgTimePerPatient =
              (data['avgTimePerPatient'] as num?)?.toInt() ?? 10;

          return CustomScrollView(
            slivers: [
              // ── Hero App Bar ───────────────────────────────────
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.primary,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, Color(0xFF1976D2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 32),
                          Container(
                            width: 70, height: 70,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.20),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.4),
                                  width: 2),
                            ),
                            child: const Icon(Icons.local_hospital_rounded,
                                color: Colors.white, size: 36),
                          ),
                          const SizedBox(height: 10),
                          Text(spec,
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              )),
                          const SizedBox(height: 4),
                          Text(location,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.80),
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Live Queue Card (StreamBuilder) ──────────
                      /// StreamBuilder subscribes to the bookings query
                      /// for this specific doctorUid. When the doctor's
                      /// dashboard marks the next patient, this count
                      /// decreases in real time.
                      ///
                      /// NEW — also derives THIS patient's own queue
                      /// position from the same snapshot (sorted by
                      /// timestamp) and renders a live wait-time
                      /// estimate card right below the count banner.
                      StreamBuilder<QuerySnapshot>(
                        stream: _queueStream,
                        builder: (context, qSnap) {
                          final queueCount =
                              qSnap.data?.docs.length ?? 0;
                          final isLoading = qSnap.connectionState ==
                              ConnectionState.waiting;

                          // NEW — figure out THIS patient's 1-based
                          // position in the pending queue, ordered by
                          // timestamp (oldest first = FIFO).
                          int? myPosition;
                          final currentUid = _auth.currentUser?.uid;
                          if (qSnap.hasData && currentUid != null) {
                            final docs = [...qSnap.data!.docs]
                              ..sort((a, b) {
                                final ta = (a.data()
                                as Map<String, dynamic>)['timestamp'];
                                final tb = (b.data()
                                as Map<String, dynamic>)['timestamp'];
                                // Bookings missing a server timestamp
                                // (extremely recent writes still
                                // resolving serverTimestamp()) sort last.
                                if (ta == null || tb == null) return 0;
                                return (ta as Timestamp)
                                    .compareTo(tb as Timestamp);
                              });

                            final idx = docs.indexWhere((d) =>
                            (d.data() as Map<String, dynamic>)
                            ['patientUid'] ==
                                currentUid);
                            if (idx != -1) myPosition = idx + 1; // 1-based
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LiveQueueBanner(
                                count: queueCount,
                                isLoading: isLoading,
                              ),

                              // NEW — only shown once we know the
                              // patient actually has a pending
                              // booking for this doctor.
                              if (myPosition != null) ...[
                                const SizedBox(height: 12),
                                _EstimatedWaitCard(
                                  queuePosition: myPosition,
                                  avgTimePerPatient: avgTimePerPatient,
                                ),
                              ],
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // ── About Section ──────────────────────────
                      _InfoCard(children: [
                        _SectionLabel(
                          icon: Icons.info_outline_rounded,
                          text: 'About the Clinic',
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 14),
                        _DetailRow(
                          icon: Icons.school_outlined,
                          label: 'Specialization',
                          value: spec,
                        ),
                        _DetailRow(
                          icon: Icons.email_outlined,
                          label: 'Contact Email',
                          value: email,
                        ),
                        _DetailRow(
                          icon: Icons.phone_outlined,
                          label: 'Clinic Phone',
                          value: phone,
                        ),
                        _DetailRow(
                          icon: Icons.place_outlined,
                          label: 'Location',
                          value: location,
                        ),
                      ]),

                      const SizedBox(height: 16),

                      // ── Timings Section ────────────────────────
                      _InfoCard(children: [
                        _SectionLabel(
                          icon: Icons.schedule_outlined,
                          text: 'Clinic Timings',
                          color: AppColors.secondary,
                        ),
                        const SizedBox(height: 14),
                        _DetailRow(
                          icon: Icons.wb_sunny_outlined,
                          label: 'Opening',
                          value: openTime,
                        ),
                        _DetailRow(
                          icon: Icons.nightlight_outlined,
                          label: 'Closing',
                          value: closeTime,
                        ),
                        _DetailRow(
                          icon: Icons.event_busy_outlined,
                          label: 'Weekly Off',
                          value: offDay,
                        ),
                      ]),

                      const SizedBox(height: 28),

                      // ── Book Appointment Button ────────────────
                      /// Tapping this button writes to Firestore `bookings`.
                      /// The Doctor Dashboard's StreamBuilder (doc_home.dart)
                      /// detects the new document and updates the queue count
                      /// there — this is the cross-panel real-time sync.
                      CustomButton(
                        text: 'Book Appointment',
                        onPressed: _bookAppointment,
                        isLoading: _booking,
                        icon: Icons.calendar_today_rounded,
                        backgroundColor: AppColors.primary,
                      ),

                      const SizedBox(height: 12),

                      // Disclaimer
                      Center(
                        child: Text(
                          'You will receive a queue token number after booking.',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// _LiveQueueBanner
// Shows the real-time queue count from the StreamBuilder.
// ─────────────────────────────────────────────────────────────────
class _LiveQueueBanner extends StatelessWidget {
  const _LiveQueueBanner({required this.count, required this.isLoading});
  final int  count;
  final bool isLoading;

  Color get _statusColor {
    if (count == 0) return AppColors.success;
    if (count <= 5) return AppColors.warning;
    return AppColors.error;
  }

  String get _statusText {
    if (count == 0) return 'No wait — walk in now!';
    if (count <= 5) return 'Short wait expected';
    return 'Busy — consider booking later';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _statusColor.withOpacity(0.12),
            _statusColor.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _statusColor.withOpacity(0.30), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: isLoading
                ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
                : Center(
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _statusColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                          color: _statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    const Text('Live Queue',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  count == 0
                      ? 'No patients waiting'
                      : '$count patient${count > 1 ? "s" : ""} in queue',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(_statusText,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// _EstimatedWaitCard — NEW
// Shows the live wait-time estimate for the current patient, using
// getEstimatedWaitTime(). Only rendered when the patient has an
// active pending booking with this doctor.
// ─────────────────────────────────────────────────────────────────
class _EstimatedWaitCard extends StatelessWidget {
  const _EstimatedWaitCard({
    required this.queuePosition,
    required this.avgTimePerPatient,
  });

  final int queuePosition;
  final int avgTimePerPatient;

  @override
  Widget build(BuildContext context) {
    final String waitText =
    getEstimatedWaitTime(queuePosition, avgTimePerPatient);
    final bool isNext = queuePosition <= 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: (isNext ? AppColors.success : AppColors.primary)
            .withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isNext ? AppColors.success : AppColors.primary)
              .withOpacity(0.30),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isNext
                ? Icons.notifications_active_rounded
                : Icons.hourglass_top_rounded,
            size: 20,
            color: isNext ? AppColors.success : AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Estimated Wait',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHint,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  waitText,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isNext ? AppColors.success : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '#$queuePosition',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isNext ? AppColors.success : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Shared micro-widgets
// ─────────────────────────────────────────────────────────────────

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
            color: AppColors.primary.withOpacity(0.04),
            blurRadius: 18,
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
            color: color.withOpacity(0.10),
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
            child: Divider(color: color.withOpacity(0.20), thickness: 1)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String   label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
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
              const SizedBox(height: 1),
              Text(value,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
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