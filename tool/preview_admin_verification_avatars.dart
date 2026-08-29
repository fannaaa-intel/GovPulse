// Dev-only harness for the ADMIN Verification queue's applicant avatars.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_admin_verification_avatars.dart
//   python -m http.server 57816 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The console is login- and role-gated, so the queue can't be reached in a
// fresh browser. adminVerificationProvider is overridden with canned rows
// instead — no Supabase at all.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * APPROVED rows with a synced avatar render the PHOTO (rows 1 and 2).
//  * Everything else — approved-but-unsynced, pending, rejected — renders the
//    neutral grey silhouette. No row anywhere shows initials any more.
//  * A broken photo URL (row 2) must fall back to that same silhouette rather
//    than a broken-image glyph.
//  * Both list layouts are covered: the table row at >= 1280 and the compact
//    card below the breakpoint. Tap a row for the details pane's 72px avatar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/features/admin/pages/admin_verification_page.dart';
import 'package:govpulse/features/admin/providers/admin_verification_provider.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [adminVerificationProvider.overrideWith(_FakeQueue.new)],
      child: const _PreviewApp(),
    ),
  );
}

// ── Canned queue ────────────────────────────────────────────────────────────

// A real, stable remote portrait so the "photo renders" case is unambiguous in
// a screenshot; the second approved row deliberately points at a dead URL to
// exercise AdminAvatar's errorChild.
const _kGoodPhoto =
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop';
const _kBrokenPhoto = 'https://example.invalid/not-a-real-avatar.jpg';

DateTime _ago(Duration d) => DateTime.now().subtract(d);

AdminVerification _v({
  required String id,
  required String first,
  required String last,
  required VerificationStatus status,
  String? photoUrl,
  String barangay = 'Barangay 2',
  String idType = 'PhilSys ID',
  required Duration age,
}) => AdminVerification(
  id: id,
  userId: 'user-$id',
  selectedIdType: idType,
  idNumber: '5249-0840-9564-1061',
  firstName: first,
  lastName: last,
  gender: 'female',
  birthdate: '11/03/2004',
  birthplace: 'APARRI, CAGAYAN',
  civilStatus: 'Single',
  contactNumber: '09510694647',
  barangay: barangay,
  street: 'ZONE 3',
  photoUrl: photoUrl,
  status: status,
  createdAt: _ago(age),
);

final _rows = <AdminVerification>[
  _v(
    id: '1C9B30F5',
    first: 'Chanzelyn',
    last: 'Sanchez',
    status: VerificationStatus.approved,
    photoUrl: _kGoodPhoto,
    barangay: 'Macanaya (Pescaria)',
    age: const Duration(days: 2),
  ),
  _v(
    id: '2D8A41E6',
    first: 'Mark',
    last: 'Reduca',
    status: VerificationStatus.approved,
    photoUrl: _kBrokenPhoto,
    barangay: 'Barangay 3',
    age: const Duration(days: 9),
  ),
  _v(
    id: '3E7B52D7',
    first: 'Giuseppe',
    last: 'Reduca Jr.',
    status: VerificationStatus.approved,
    idType: 'Philippine Passport ID',
    age: const Duration(days: 16),
  ),
  _v(
    id: '4F6C63C8',
    first: 'Ana',
    last: 'Perez',
    status: VerificationStatus.pending,
    age: const Duration(hours: 5),
  ),
  _v(
    id: '5A5D74B9',
    first: 'Juan',
    last: 'Dela Cruz',
    status: VerificationStatus.rejected,
    age: const Duration(days: 21),
  ),
];

class _FakeQueue extends AdminVerificationNotifier {
  @override
  Future<List<AdminVerification>> build() async => _rows;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> silentRefresh() async {}

  @override
  Future<String?> signedUrl(String? path) async => null;
}

// ── Harness ─────────────────────────────────────────────────────────────────

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  double _width = 1280;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final w in const [360.0, 420.0, 700.0, 900.0, 1280.0])
                      FilledButton(
                        onPressed: () => setState(() => _width = w),
                        style: FilledButton.styleFrom(
                          backgroundColor: _width == w
                              ? Colors.white
                              : Colors.white24,
                          foregroundColor: _width == w
                              ? Colors.black
                              : Colors.white,
                        ),
                        child: Text('${w.toInt()} px'),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _width,
                  child: ClipRect(
                    child: Builder(
                      builder: (outer) {
                        final mq = MediaQuery.of(outer);
                        return MediaQuery(
                          data: mq.copyWith(
                            size: Size(_width, mq.size.height - 70),
                          ),
                          child: Container(
                            color: AdminUi.pageBg,
                            // Nested Navigator so a pushed detail screen stays
                            // inside the simulated viewport.
                            child: Navigator(
                              onGenerateRoute: (_) => MaterialPageRoute(
                                builder: (_) => const AdminVerificationPage(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
