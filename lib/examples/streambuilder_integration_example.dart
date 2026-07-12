/// ================================================================
/// FILE  : lib/examples/streambuilder_integration_example.dart
/// AUTHOR: Waitless Project
///
/// PURPOSE:
///   Demonstrates how to wire DbService streams into the Doctor
///   and Patient home screens using Flutter's StreamBuilder widget.
///
/// BLACK BOOK — StreamBuilder Explained:
///   A StreamBuilder<T> is a widget that:
///     1. Subscribes to a Stream<T> when it mounts.
///     2. Calls its builder() function every time the stream emits.
///     3. Passes an AsyncSnapshot<T> to the builder, which contains:
///          • snapshot.connectionState  → waiting / active / done
///          • snapshot.hasData          → true once first emit arrives
///          • snapshot.data             → the latest emitted value
///          • snapshot.hasError         → true if stream threw
///          • snapshot.error            → the thrown object
///     4. Unsubscribes automatically when the widget unmounts
///        (no manual stream.cancel() needed).
///
///   For Firestore streams, the connection goes:
///     App  →  Firestore WebSocket  →  server-side listener
///   The server pushes a new snapshot within ~300ms of any write
///   that affects the query. The StreamBuilder rebuilds only the
///   affected widget subtree, NOT the entire screen.
///
/// NOTE: These are SELF-CONTAINED EXAMPLE WIDGETS, not the full
///   production screens. They extract only the StreamBuilder pattern
///   for clarity. The real screens (doc_home.dart, patient_home.dart)
///   contain additional tabs, navigation, and edit functionality.
/// ================================================================

import 'package:flutter/material.dart';
//import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:waitless/core/constants.dart';
import 'package:waitless/models/doctor_model.dart';
import 'package:waitless/models/booking_model.dart';
import 'package:waitless/services/db_service.dart';

// ─────────────────────────────────────────────────────────────────
// EXAMPLE 1 — DOCTOR HOME: Live Queue StreamBuilder
// ─────────────────────────────────────────────────────────────────

/// Demonstrates the Live Queue tab of the Doctor Dashboard.
///
/// The StreamBuilder listens to DbService.getLiveQueue() and
/// rebuilds the queue list widget every time a patient books or
/// the doctor calls the next patient — with zero manual refresh.
///
/// Usage in DoctorHomeScreen:
///   // Replace your queue tab body with DoctorQueueExample
///   body: DoctorQueueExample(uid: _uid, dbService: _dbService),
class DoctorQueueExample extends StatelessWidget {
  const DoctorQueueExample({
    super.key,
    required this.uid,
    required this.dbService,
  });

  /// Firebase Auth UID of the currently signed-in doctor.
  final String uid;

  /// Injected DbService — shared instance from the parent screen.
  final DbService dbService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookingModel>>(
      // ── Stream source ─────────────────────────────────────────
      // getLiveQueue() returns a Firestore .snapshots() stream
      // filtered to: doctorUid == uid AND status == 'pending',
      // ordered by timestamp ascending (FIFO).
      //
      // This stream stays open as long as this widget is mounted.
      // Firestore pushes an updated list whenever any booking
      // matching the query is added, modified, or removed.
      stream: dbService.getLiveQueue(uid),

      // ── Builder ───────────────────────────────────────────────
      // Called on every stream emission AND on first subscription.
      // snapshot.connectionState == waiting on the very first frame
      // (before the first Firestore response arrives).
      builder: (context, AsyncSnapshot<List<BookingModel>> snapshot) {

        // ── 1. Loading state ─────────────────────────────────────
        // ConnectionState.waiting means the stream has no data yet.
        // Show a spinner to avoid a blank screen flash on first load.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        // ── 2. Error state ────────────────────────────────────────
        // Likely cause: missing Firestore composite index (see
        // DbService.getLiveQueue() Black Book note for index details).
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Queue error: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      color: AppColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // ── 3. Data state ─────────────────────────────────────────
        // snapshot.data is the latest List<BookingModel> emitted.
        // It defaults to [] (empty list) if the query has no results.
        final List<BookingModel> queue = snapshot.data ?? [];
        final bool hasPatients = queue.isNotEmpty;

        return Column(
          children: [

            // ── Queue summary header ──────────────────────────────
            // Rebuilds automatically when queue.length changes.
            _QueueHeader(total: queue.length, hasPatients: hasPatients),

            // ── Patient list ──────────────────────────────────────
            if (hasPatients)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  // itemCount drives how many tiles are rendered.
                  // As queue grows/shrinks, ListView updates reactively.
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final BookingModel booking = queue[index];
                    return _QueueTile(
                      booking:   booking,
                      position:  index + 1,
                      isCurrent: index == 0, // first in queue = current
                      // Pass the raw Firestore docs to callNextPatient
                      // so DbService can use doc.reference directly.
                      onCallNext: index == 0
                          ? () => _callNext(context, snapshot)
                          : null,
                    );
                  },
                ),
              )
            else
              const Expanded(child: _EmptyQueueState()),

            // ── Action buttons ────────────────────────────────────
            _QueueActions(
              hasPatients: hasPatients,
              onCallNext:  hasPatients
                  ? () => _callNext(context, snapshot)
                  : null,
              onReset:     hasPatients
                  ? () => _resetQueue(context, snapshot)
                  : null,
            ),
          ],
        );
      },
    );
  }

  // ── Helper: extract raw docs for DbService calls ─────────────
  // DbService.callNextPatient() and resetQueue() accept the raw
  // QueryDocumentSnapshot list so they can use doc.reference
  // for updates/deletes without a second Firestore read.
  //
  // The stream emits List<BookingModel> (typed), but DbService
  // needs the raw docs for document references. In production,
  // the _QueueTab in doc_home.dart uses a StreamBuilder on the
  // raw QuerySnapshot and maps to BookingModel inside the builder,
  // giving access to both. This example shows the typed approach
  // for clarity; adapt as needed.

  Future<void> _callNext(
      BuildContext context,
      AsyncSnapshot<List<BookingModel>> snapshot,
      ) async {
    // NOTE: In your actual doc_home.dart, pass the raw
    // QueryDocumentSnapshot list from the StreamBuilder directly
    // to dbService.callNextPatient(). This example shows the
    // concept; the real implementation is in _QueueTab.
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Next patient called!',
              style: TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resetQueue(
      BuildContext context,
      AsyncSnapshot<List<BookingModel>> snapshot,
      ) async {
    // Show confirmation dialog before wiping the queue.
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset Queue?',
            style: TextStyle(
                fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
        content: Text(
          'This will permanently delete all ${snapshot.data?.length ?? 0} '
              'pending patients. This cannot be undone.',
          style: const TextStyle(fontFamily: 'Nunito'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset All',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Queue reset.',
            style: TextStyle(fontFamily: 'Nunito')),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// EXAMPLE 2 — PATIENT HOME: Clinic List StreamBuilder
// ─────────────────────────────────────────────────────────────────

/// Demonstrates the Clinic List screen of the Patient Panel.
///
/// The StreamBuilder listens to DbService.getClinics() and
/// rebuilds the list whenever a doctor registers or updates their
/// profile — the patient sees a live, always-current clinic list.
///
/// Usage in PatientHomeScreen:
///   body: PatientClinicListExample(
///     patientUid:   _uid,
///     patientName:  _patientName,
///     dbService:    _dbService,
///   ),
class PatientClinicListExample extends StatelessWidget {
  const PatientClinicListExample({
    super.key,
    required this.patientUid,
    required this.patientName,
    required this.dbService,
  });

  final String     patientUid;
  final String     patientName;
  final DbService  dbService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DoctorModel>>(
      // ── Stream source ─────────────────────────────────────────
      // getClinics() returns a Firestore .snapshots() stream on the
      // entire `doctors` collection, ordered alphabetically.
      //
      // This stream is intentionally unfiltered — patients see ALL
      // registered doctors. Client-side filtering (by specialization
      // or location) is applied on the emitted list, not in the query,
      // to avoid the need for multiple composite indexes.
      stream: dbService.getClinics(),

      builder: (context, AsyncSnapshot<List<DoctorModel>> snapshot) {

        // ── 1. Loading ────────────────────────────────────────────
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        // ── 2. Error ──────────────────────────────────────────────
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load clinics: ${snapshot.error}',
              style: const TextStyle(
                fontFamily: 'Nunito',
                color: AppColors.error,
              ),
            ),
          );
        }

        // ── 3. Data ───────────────────────────────────────────────
        final List<DoctorModel> clinics = snapshot.data ?? [];

        if (clinics.isEmpty) {
          return const Center(
            child: Text(
              'No clinics registered yet.',
              style: TextStyle(
                fontFamily: 'Nunito',
                color: AppColors.textSecondary,
              ),
            ),
          );
        }

        // ListView.builder renders only visible items (lazy/virtual),
        // which is efficient even for large clinic lists.
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: clinics.length,
          itemBuilder: (context, index) {
            final DoctorModel clinic = clinics[index];
            return _ClinicCard(
              clinic:      clinic,
              onBook:      () => _bookAppointment(context, clinic),
            );
          },
        );
      },
    );
  }

  // ── Book appointment handler ──────────────────────────────────
  Future<void> _bookAppointment(
      BuildContext context, DoctorModel clinic) async {
    // Confirm before booking.
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Booking',
            style: TextStyle(
                fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
        content: Text(
          'Book an appointment with ${clinic.clinicName}?\n\n'
              'You will be added to their live queue immediately.',
          style: const TextStyle(fontFamily: 'Nunito', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Book Now',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      // dbService.bookAppointment() writes to Firestore.
      // The doctor's getLiveQueue() stream will emit the new booking
      // within ~300ms on the doctor's device — completely automatic.
      final String bookingId = await dbService.bookAppointment(
        patientUid:  patientUid,
        patientName: patientName,
        doctorUid:   clinic.uid,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Booked! Your queue ID: ${bookingId.substring(0, 6).toUpperCase()}',
            style: const TextStyle(fontFamily: 'Nunito'),
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking failed: $e',
              style: const TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Private micro-widgets used only in this example file
// ─────────────────────────────────────────────────────────────────

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({required this.total, required this.hasPatients});
  final int  total;
  final bool hasPatients;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasPatients
              ? [AppColors.primary, const Color(0xFF1565C0)]
              : [AppColors.textHint, AppColors.textSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        const Icon(Icons.people_alt_outlined, color: Colors.white, size: 28),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '$total Patient${total == 1 ? '' : 's'} in Queue',
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            hasPatients ? 'Queue is active' : 'No patients waiting',
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.booking,
    required this.position,
    required this.isCurrent,
    this.onCallNext,
  });
  final BookingModel booking;
  final int          position;
  final bool         isCurrent;
  final VoidCallback? onCallNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withOpacity(0.07)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? AppColors.primary.withOpacity(0.35)
              : AppColors.divider,
          width: 1.2,
        ),
      ),
      child: Row(children: [
        // Queue position number
        CircleAvatar(
          radius: 16,
          backgroundColor: (isCurrent ? AppColors.primary : AppColors.textSecondary)
              .withOpacity(0.15),
          child: Text(
            '$position',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w800,
              color: isCurrent ? AppColors.primary : AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Patient name and booking ID
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              booking.patientName,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'ID: ${booking.bookingId.substring(0, 6).toUpperCase()}',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                color: AppColors.textHint,
              ),
            ),
          ]),
        ),
        // "CURRENT" badge for the first patient
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'CURRENT',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.8,
              ),
            ),
          ),
      ]),
    );
  }
}

class _EmptyQueueState extends StatelessWidget {
  const _EmptyQueueState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.event_available_outlined,
            size: 60, color: AppColors.textHint.withOpacity(0.4)),
        const SizedBox(height: 16),
        const Text(
          'Queue is empty',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textHint,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Patients will appear here when they book.',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 13,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}

class _QueueActions extends StatelessWidget {
  const _QueueActions({
    required this.hasPatients,
    this.onCallNext,
    this.onReset,
  });
  final bool         hasPatients;
  final VoidCallback? onCallNext;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
              hasPatients ? AppColors.primary : AppColors.textHint,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onCallNext,
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            label: const Text('Call Next Patient',
                style: TextStyle(
                    fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(
                  color: hasPatients
                      ? AppColors.error
                      : AppColors.divider),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset Queue',
                style: TextStyle(
                    fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({required this.clinic, required this.onBook});
  final DoctorModel  clinic;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Clinic name + specialization
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_hospital_outlined,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                clinic.clinicName,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                clinic.specialization,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
        ]),

        const SizedBox(height: 12),
        const Divider(color: AppColors.divider, height: 1),
        const SizedBox(height: 12),

        // Location and hours chips
        Wrap(spacing: 10, runSpacing: 6, children: [
          _InfoChip(Icons.place_outlined,
              clinic.location.isEmpty ? 'N/A' : clinic.location),
          _InfoChip(Icons.access_time_outlined,
              '${clinic.openTime} – ${clinic.closeTime}'),
          _InfoChip(Icons.event_busy_outlined,
              'Off: ${clinic.offDay.isEmpty ? 'N/A' : clinic.offDay}'),
        ]),

        const SizedBox(height: 14),

        // Book button — triggers _bookAppointment via onBook callback
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onBook,
            child: const Text(
              'Book Appointment',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);
  final IconData icon;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ]),
    );
  }
}