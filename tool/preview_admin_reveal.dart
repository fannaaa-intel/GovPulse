// Preview target: the two-step anonymous reveal form, with a fake server.
//
//   flutter build web --release -t tool/preview_admin_reveal.dart
//
// No Supabase: revealApiProvider and currentAdminIsFullAdminProvider are
// overridden. Password "wrong" → wrong-password error; code "000000" → wrong
// code; any other 6-digit code reveals. Resize the browser (or use CDP
// Emulation.setDeviceMetricsOverride) to see the phone bottom sheet (<640px)
// and the desktop dialog.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:govpulse/features/admin/providers/admin_identity_reveal_provider.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/revealable_submitter.dart';

final _api = RevealApi(
  sendCode: ({required String password, String? actorName}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (password == 'wrong') {
      throw const RevealException(
        'bad_password',
        'Incorrect password. Please try again.',
      );
    }
    return 'r•••@gmail.com';
  },
  reveal:
      ({
        required RevealSource source,
        required String submissionId,
        required String password,
        required String reason,
        required String code,
        String? actorName,
      }) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (code == '000000') {
          throw const RevealException(
            'bad_code',
            'Incorrect or expired code. Request a new one.',
          );
        }
        return const RevealedIdentity(
          userId: 'u-1',
          name: 'Juan Dela Cruz',
          phone: '09171234567',
        );
      },
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Semantics on, so a headless-Chrome driver can find buttons by label.
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    ProviderScope(
      overrides: [
        revealApiProvider.overrideWithValue(_api),
        currentAdminIsFullAdminProvider.overrideWith((ref) async => true),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AdminUi.pageBg,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                margin: const EdgeInsets.all(16),
                color: AdminUi.surface,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: RevealableSubmitter(
                    source: RevealSource.report,
                    submissionId: '11111111-2222-3333-4444-555555555555',
                    isAnonymous: true,
                    subject: 'reporter',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
