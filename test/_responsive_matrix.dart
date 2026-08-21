// Shared device matrix + overflow probe for the MOBILE app's responsiveness
// audit.
//
// The Flutter test binding runs with `kIsWeb == false`, so every widget pumped
// through here takes the same branch the shipped Android/iOS app takes — which
// is the whole reason the audit lives in a widget test rather than in the web
// preview harnesses under tool/.
//
// [pumpAt] restores the view afterwards and returns the RenderFlex/RenderBox
// overflow errors Flutter raised while laying the tree out, so a caller can
// assert on "nothing overflowed at 320x568" directly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Device {
  final String name;
  final Size size;
  const Device(this.name, this.size);

  Device get rotated => Device('$name landscape', Size(size.height, size.width));
  @override
  String toString() => '$name (${size.width.toInt()}x${size.height.toInt()})';
}

/// Portrait sizes, smallest first. Shortest side stays < 600 for the phones so
/// `resolveNavBand` keeps them on NavBand.phone in BOTH orientations.
const kSmallPhone = Device('small phone', Size(320, 568));
const kPhone = Device('phone', Size(360, 640));
const kModernPhone = Device('modern phone', Size(390, 844));
const kBigPhone = Device('big phone', Size(430, 932));
const kTablet = Device('tablet', Size(768, 1024));

List<Device> get kPortrait => const [kSmallPhone, kPhone, kModernPhone, kBigPhone];
List<Device> get kLandscape => kPortrait.map((d) => d.rotated).toList();
List<Device> get kAllPhones => [...kPortrait, ...kLandscape];

/// The `lib/…dart:LINE:COL` Flutter names as the error-causing widget.
///
/// Without it a failure says only "overflowed by 117 pixels" for a screen with
/// a hundred Rows in it, and every finding costs a bisect to locate. Flutter
/// already knows the answer and prints it in the diagnostics; this just lifts
/// it into the one line the test report actually shows.
String _blame(FlutterErrorDetails details) {
  final m = RegExp(
    r'file:///.*?/(lib/[^\s:]+\.dart:\d+:\d+)',
  ).firstMatch(details.toString());
  return m == null ? '(location unknown)' : m.group(1)!;
}

/// Pumps [build] at [device] and returns every overflow message Flutter logged.
///
/// ── Why the size and scale are set on the VIEW ───────────────────────────
/// `MaterialApp` inserts its own `MediaQuery.fromView` beneath itself, so a
/// MediaQuery wrapped around the app is replaced before any screen reads it —
/// an injected `textScaler` is silently dropped and every scale quietly
/// re-tests 1.0. `physicalSize` and `textScaleFactorTestValue` are what that
/// MediaQuery is built FROM, so they survive.
///
/// ── Why the tree is torn down first ──────────────────────────────────────
/// `pumpWidget` UPDATES a tree whose widget types match instead of rebuilding
/// it, so a sweep that pumps the same screen at eight sizes reuses one
/// `RenderFlex` throughout — and a `RenderFlex` reports its overflow only the
/// first time it paints one. Without the teardown a screen that overflows at
/// every size reports at the first size and looks clean at the other seven.
/// Pumping an empty tree in between forces fresh render objects each time.
///
/// ── What the numbers mean ────────────────────────────────────────────────
/// Tests run on Flutter's fallback font, whose every glyph is one em wide, so
/// a string measures roughly twice what Roboto would give it. That makes this
/// probe PESSIMISTIC, and deliberately so: it is standing in for the two cases
/// a 1.0x English measurement would miss — the Tagalog half of this bilingual
/// app, where the same label runs half again as long, and a user on Android's
/// Largest font size. A Row that survives here has real headroom for both.
Future<List<String>> pumpAt(
  WidgetTester tester,
  Device device,
  Widget Function() build, {
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());

  final errors = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    final s = details.exceptionAsString();
    if (s.contains('overflowed') ||
        s.contains('RenderFlex') ||
        s.contains('Infinity')) {
      errors.add('${s.split('\n').first}  ${_blame(details)}');
    } else {
      prev?.call(details);
    }
  };
  tester.view.physicalSize = device.size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  try {
    await tester.pumpWidget(build());
    await tester.pump();
    // Let the staggered entrance timers fire and the entrance animations
    // finish. Two reasons, and the second is the important one: it drains the
    // one-shot timers these screens schedule in initState, which the binding
    // otherwise reports as "A Timer is still pending" at the end of the test;
    // and the layout it leaves behind is the RESTING one, which is the layout
    // a citizen actually looks at. `pumpAndSettle` is not an option — several
    // of these screens shimmer on a repeating controller and never settle.
    await tester.pump(const Duration(milliseconds: 600));
  } finally {
    FlutterError.onError = prev;
  }
  return errors;
}
