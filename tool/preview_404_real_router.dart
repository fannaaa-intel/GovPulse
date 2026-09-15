// Dev-only harness that loads a bad URL through the REAL [citizenRouter].
//
//   flutter build web --release -t tool/preview_404_real_router.dart
//   then open /#/my-reprots
//
// ── Why this exists, and why the other preview was not enough ───────────────
// tool/preview_not_found.dart mounts [NotFoundPage] behind a STUB router, so it
// proves the page renders and nothing more. That is exactly the gap that hid a
// real bug: the page was perfect in every screenshot while being UNREACHABLE in
// the shipped router, because GoRouter runs `redirect` before it decides a
// location is an error and the guard swept unknown paths to /login.
//
// This one boots the real thing — the real routes, the real `_authRedirect`,
// the real `errorBuilder` — so what appears on screen is what a visitor who
// mistypes a URL actually gets.
//
// Supabase and Firebase must be initialised because the guard reads both.
// Nobody signs in, which is the case under test: a signed-out stranger
// following a link that rotted.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/services/auth_ready.dart';
import 'package:govpulse/features/home/shell/citizen_shell_router.dart';
import 'package:govpulse/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );

  // The guard holds every location until restoration settles, so without this
  // the page under test never builds and the screen sits on the spinner.
  // `begin()` is what main.dart calls; with no session it settles as
  // "signed out", which is the visitor this harness is for.
  AuthRestoration.instance.begin();

  runApp(const ProviderScope(child: GovPulseWebApp()));
}
