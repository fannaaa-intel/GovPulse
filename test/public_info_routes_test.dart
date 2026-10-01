import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:govpulse/features/home/shell/citizen_shell_router.dart';

// The landing footer links to Privacy Policy, Terms of Service and About
// GovPulse. On web those paths used to exist only in the MOBILE route table, so
// every one of them opened the 404 page. These pin both halves of the fix: the
// web router really has the routes, and no visitor is swept away from them.
void main() {
  const paths = <String>['/privacy_policy', '/terms_of_service', '/about'];

  test('the web router declares every footer page as a top-level route', () {
    final declared = citizenRouter.configuration.routes
        .whereType<GoRoute>()
        .map((r) => r.path)
        .toSet();
    for (final p in paths) {
      expect(declared, contains(p), reason: '$p would 404 on web');
    }
  });

  test('the footer pages are public for every identity', () {
    for (final p in paths) {
      for (final who in RouterIdentity.values) {
        expect(
          debugRedirectFor(p, identity: who),
          isNull,
          reason: '$p must be readable by $who, including before sign-up',
        );
      }
    }
  });
}
