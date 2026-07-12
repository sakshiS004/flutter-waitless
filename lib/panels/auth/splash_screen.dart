/// ================================================================
/// FILE  : lib/screens/splash_screen.dart
/// AUTHOR: Waitless Project
///
/// OVERVIEW:
///   The SplashScreen is the first screen the user sees when the
///   app launches. It serves two purposes:
///
///     1. BRANDING — Displays the Waitless logo and app name for
///        a polished, professional first impression.
///
///     2. INITIALISATION BUFFER — Provides a 3-second window for
///        Firebase to finish initialising and for the AuthGate's
///        authStateChanges() stream to emit its first value,
///        preventing a flash of the RoleSelectionScreen on returning
///        users who are already logged in.
///
/// ────────────────────────────────────────────────────────────────
/// NAVIGATION LOGIC:
///
///   A Timer fires after 3 seconds and calls Navigator.pushReplacement.
///   pushReplacement REMOVES the SplashScreen from the navigation
///   stack entirely — the user cannot press Back to return to it.
///
///   The destination is AuthGate, which handles:
///     • Logged-in user  → routes to DocHomeScreen or PatientHomeScreen.
///     • No session      → routes to RoleSelectionScreen.
///
/// ────────────────────────────────────────────────────────────────
/// ANIMATION:
///
///   A three-phase entrance animation plays during the 3-second window:
///     Phase 1 (0–400ms)  — Logo fades in and slides up from below.
///     Phase 2 (200–600ms)— App name fades in with a slight delay.
///     Phase 3 (400–800ms)— Tagline and pulse ring fade in last.
///
///   The AnimationController is disposed in dispose() to prevent
///   memory leaks when the widget is removed from the tree.
///
/// ────────────────────────────────────────────────────────────────
/// THEME INTEGRATION:
///
///   All colours reference AppColors constants from constants.dart
///   (the same file used across the entire app). This ensures the
///   splash background, text, and accent colours automatically match
///   any future theme changes.
///
///   Typography uses the 'Nunito' font family declared in AppTheme,
///   and font weights mirror the heading styles used in other screens.
/// ================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:waitless/core/constants.dart';   // AppColors
import 'package:waitless/main.dart'; // Destination after splash

// ─────────────────────────────────────────────────────────────────
// SplashScreen
// ─────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  // ── Animation controller ──────────────────────────────────────
  // SingleTickerProviderStateMixin provides a single vsync source
  // for the AnimationController. Using a single controller with
  // multiple Interval curves is more efficient than creating one
  // controller per animated element — it uses ONE Ticker object.
  late final AnimationController _controller;

  // ── Individual animations ─────────────────────────────────────
  // Each Animation<double> is driven by the SAME _controller but
  // fires at different time intervals within the 800ms window.

  /// Logo fade-in: 0ms → 400ms
  late final Animation<double> _logoFade;

  /// Logo vertical slide: starts 20px below, ends at resting position.
  late final Animation<Offset> _logoSlide;

  /// App name 'Waitless' fade-in: 200ms → 600ms (staggers after logo)
  late final Animation<double> _nameFade;

  /// Tagline fade-in: 400ms → 800ms (last element to appear)
  late final Animation<double> _taglineFade;

  /// Pulse ring scale: expands from 0.8 → 1.2 to create a breathing effect.
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseFade;

  // ── Navigation timer ──────────────────────────────────────────
  /// Holds a reference to the Timer so it can be cancelled in
  /// dispose() if the widget is removed before the 3 seconds elapse.
  /// Without this, the timer callback could call setState or
  /// Navigator on a disposed widget, causing an error.
  late final Timer _navigationTimer;

  // ──────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Force status bar to be transparent with dark icons so the
    // splash gradient is visible edge-to-edge under the status bar.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor:          Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // ── Entrance animation setup ───────────────────────────────
    // Total duration: 800ms (covers all three phases).
    // The _controller drives every animation — only one Ticker used.
    _controller = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    );

    // Phase 1: Logo fades in over the first 400ms (0.0 → 0.5 of 800ms).
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve:  const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Logo slides up from 20px below its resting position.
    // Offset(0, 1) in a SlideTransition = 100% of widget height.
    // We use a small value (0.08) for a subtle lift, not a full slide.
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end:   Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve:  const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Phase 2: 'Waitless' wordmark fades in, starting 200ms in.
    _nameFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve:  const Interval(0.25, 0.75, curve: Curves.easeOut),
      ),
    );

    // Phase 3: Tagline fades in last, starting 400ms in.
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve:  const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    // Pulse ring: scales from 0.85 → 1.15 and fades out for a
    // breathing/ripple effect around the logo.
    _pulseScale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve:  const Interval(0.1, 0.9, curve: Curves.easeInOut),
      ),
    );
    _pulseFade = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve:  const Interval(0.1, 0.9, curve: Curves.easeOut),
      ),
    );

    // Start the entrance animation immediately on mount.
    _controller.forward();

    // ── Navigation timer ───────────────────────────────────────
    // Timer.periodic would repeat; Timer fires ONCE after the duration.
    //
    // WHY 3 seconds?
    //   • Firebase.initializeApp() typically completes in < 500ms.
    //   • authStateChanges() emits its first value in < 200ms after init.
    //   • 3 seconds gives the user time to perceive the branding and
    //     for all async initialisations to complete on slow devices.
    _navigationTimer = Timer(const Duration(seconds: 3), _navigateToAuthGate);
  }

  @override
  void dispose() {
    // Cancel the timer if the widget is removed before it fires.
    // Example: OS kills the app during the splash. Without this,
    // the timer callback runs on a null BuildContext and crashes.
    _navigationTimer.cancel();

    // Always dispose AnimationControllers — they hold a reference
    // to a Ticker that keeps a vsync subscription alive until disposed.
    _controller.dispose();

    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // NAVIGATION
  //
  // Navigator.pushReplacement replaces the CURRENT route (SplashScreen)
  // with the new route (AuthGate) on the navigation stack.
  //
  // Effect: the SplashScreen is permanently removed from the stack.
  // If the user presses Back on AuthGate, the system exits the app
  // (or shows the previous screen below AuthGate if one exists) —
  // they CANNOT return to the splash screen.
  //
  // WHY pushReplacement and NOT pushAndRemoveUntil here?
  //   At splash time, there are no routes below it. pushReplacement
  //   is the correct, lighter call. pushAndRemoveUntil is used after
  //   login/register to clear auth screens.
  // ──────────────────────────────────────────────────────────────
  void _navigateToAuthGate() {
    // `mounted` check: guards against the rare case where the widget
    // was disposed (e.g., hot-reload during development) between the
    // Timer starting and firing. Calling Navigator on an unmounted
    // widget throws a 'setState called after dispose' error.
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      // PageRouteBuilder gives us a custom transition instead of the
      // default slide. A fade-out from the splash into the AuthGate
      // feels more polished than an abrupt slide.
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthPageNavigator(),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) {
          // Fade transition: splash fades out as AuthGate fades in.
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve:  Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Theme.of(context) pulls AppTheme.lightTheme set in main.dart.
    // Using Theme.of ensures splash typography exactly matches
    // headlineSmall / bodyMedium styles used in the rest of the app.
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      // AppColors.background matches the background used on all other
      // screens (login, register, home) — visual continuity.
      backgroundColor: AppColors.background,

      body: SafeArea(
        // extend: true lets the background fill behind the status bar
        // so the splash looks full-bleed on all devices.
        top:    false,
        bottom: false,
        child: Stack(
          children: [

            // ── Subtle radial gradient backdrop ─────────────────
            // Creates a soft glow behind the logo without introducing
            // a jarring colour that clashes with the rest of the app.
            // Uses AppColors.primary at very low opacity so it reads
            // as "branded" on the background colour.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.85,
                    colors: [
                      AppColors.primary.withOpacity(0.08),
                      AppColors.background,
                    ],
                  ),
                ),
              ),
            ),

            // ── Main centred content ─────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ── Pulse ring behind logo ─────────────────────
                  // A semi-transparent circle that scales and fades
                  // during the entrance animation. It sits BEHIND the
                  // logo using Stack ordering (painted before the logo).
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [

                          // Outer pulse ring
                          Opacity(
                            opacity: _pulseFade.value,
                            child: Transform.scale(
                              scale: _pulseScale.value,
                              child: Container(
                                width:  160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary.withOpacity(0.25),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── Logo ────────────────────────────────
                          // SlideTransition + FadeTransition applied
                          // from _logoSlide and _logoFade animations.
                          SlideTransition(
                            position: _logoSlide,
                            child: FadeTransition(
                              opacity: _logoFade,
                              child: Container(
                                width:  120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color:  AppColors.white,
                                  shape:  BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:      AppColors.primary.withOpacity(0.18),
                                      blurRadius: 32,
                                      offset:     const Offset(0, 10),
                                    ),
                                    BoxShadow(
                                      color:      AppColors.primary.withOpacity(0.08),
                                      blurRadius: 64,
                                      offset:     const Offset(0, 20),
                                    ),
                                  ],
                                ),
                                // Clip logo image to the circle bounds.
                                child: ClipOval(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    // Image.asset loads from assets/logo.png
                                    // declared in pubspec.yaml under flutter: assets:
                                    child: Image.asset(
                                      'assets/logo.png',
                                      fit: BoxFit.contain,
                                      // Fallback if the asset is missing during
                                      // development — shows a branded icon instead.
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.local_hospital_rounded,
                                        size:  56,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // ── App name: 'Waitless' ───────────────────────
                  // FadeTransition driven by _nameFade (staggers 200ms
                  // after the logo starts appearing for a cascading effect).
                  FadeTransition(
                    opacity: _nameFade,
                    child: Text(
                      'Waitless',
                      style: TextStyle(
                        // Matches the wordmark style used in all auth screens
                        // and the AppBar so there is visual consistency.
                        fontFamily:    'Nunito',
                        fontSize:      38,
                        fontWeight:    FontWeight.w800,  // bold as requested
                        color:         AppColors.primary,
                        letterSpacing: -1.2,
                        height:        1.0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Tagline ────────────────────────────────────
                  // Fades in last (400ms after logo) to complete the
                  // three-phase reveal sequence.
                  FadeTransition(
                    opacity: _taglineFade,
                    child: Text(
                      'Skip the wait. Not the care.',
                      style: TextStyle(
                        fontFamily:    'Nunito',
                        fontSize:      14,
                        fontWeight:    FontWeight.w500,
                        color:         AppColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom loading indicator ─────────────────────────
            // A thin progress bar at the bottom signals that something
            // is happening (Auth initialisation) without being intrusive.
            // Uses AppColors.primary to match the brand colour.
            Positioned(
              left:   0,
              right:  0,
              bottom: 40,
              child: FadeTransition(
                opacity: _taglineFade, // appears with the tagline
                child: Column(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      // LinearProgressIndicator replaced with a compact
                      // dot-pulse row for a more polished feel.
                      child: CircularProgressIndicator(
                        color:       AppColors.primary.withOpacity(0.35),
                        strokeWidth: 2.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontFamily:  'Nunito',
                        fontSize:    11,
                        fontWeight:  FontWeight.w500,
                        color:       AppColors.textHint,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}