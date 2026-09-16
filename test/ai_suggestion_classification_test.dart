// AI classification on suggestions — the chips an admin sees on the list.
//
// Three things are under test, and they fail in different ways:
//
//  1. THE NULL CONTRACT. All four ai_* columns are null whenever the classifier
//     hasn't reached a row, Groq quota is exhausted, or migration
//     20260917000000 hasn't been applied. Every one of those must render the
//     row EXACTLY as it looked before this feature — no chip, and no leftover
//     vertical gap where a chip would have been. This is the half that silently
//     rots: the AI path works in every manual test because the seed data has
//     been classified, and the null path only runs in the situations nobody
//     reproduces by hand.
//
//  2. 'other' IS NOT A THEME WORTH SHOWING. aiThemeLabel returns null for the
//     taxonomy's 'other' bucket as well as for an unclassified row, because
//     callers use its nullness to decide whether to reserve space at all. If
//     that check moved into the chip widget instead, a row themed 'other'
//     would render an invisible chip inside a real SizedBox and gain a gap.
//
//  3. THE CHIPS MUST NOT OVERFLOW. The mis-filed chip and the theme chip can
//     appear together on a phone card, and the desktop table row puts the
//     mis-filed chip in a `flex: 4` cell it shares with a 30px icon and the
//     short id. See [[admin-responsive-overflow-probe]] — a 1280px screenshot
//     shows this as fine while 320px clips it.
//
// What these tests CANNOT see, and why the preview target exists: the first
// version of the table row stacked the chip between the category and the short
// id. Nothing overflowed at any width, every assertion here passed — and the
// row grew a third line, so its text stopped lining up with the centered
// columns beside it. Only tool/preview_suggestion_ai_chips.dart caught that.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_suggestions_page.dart';
import 'package:govpulse/features/admin/providers/admin_suggestions_provider.dart';

import '_responsive_matrix.dart';

/// A suggestion carrying only the fields the chip logic reads. Everything else
/// is filler — the model has a wide constructor and none of it matters here.
AdminSuggestion _suggestion({
  required String categoryKey,
  String? aiCategory,
  String? aiTheme,
  String? aiCategoryReason,
  String details = 'Please add a streetlight near the covered court.',
}) {
  return AdminSuggestion(
    id: '00000000-0000-0000-0000-000000000001',
    shortId: 'SGS-00000000',
    categoryKey: categoryKey,
    category: suggestionCategoryLabel(categoryKey, null),
    categoryOther: null,
    barangay: 'Macanaya',
    address: null,
    latitude: null,
    longitude: null,
    details: details,
    isAnonymous: false,
    submitterName: 'Juan D. Cruz',
    submitterPhotoUrl: null,
    submitterRole: 'citizen',
    mediaCount: 0,
    status: SuggestionStatus.fresh,
    adminNote: null,
    adminResponse: null,
    reviewedAt: null,
    createdAt: DateTime(2026, 9, 17),
    aiCategoryKey: aiCategory,
    aiCategoryReason: aiCategoryReason,
    aiTheme: aiTheme,
  );
}

void main() {
  group('isMiscategorized — the mis-filed signal', () {
    test('null ai_category is never a disagreement', () {
      // The unclassified case. A null must not read as "the AI disagrees",
      // which is what a naive `aiCategory != categoryKey` would do.
      expect(
        _suggestion(categoryKey: 'others').isMiscategorized,
        isFalse,
      );
    });

    test('agreement is not a disagreement', () {
      expect(
        _suggestion(categoryKey: 'infrastructure', aiCategory: 'infrastructure')
            .isMiscategorized,
        isFalse,
      );
    });

    test('a real disagreement is flagged', () {
      final s = _suggestion(categoryKey: 'others', aiCategory: 'infrastructure');
      expect(s.isMiscategorized, isTrue);
      // The label must describe the MODEL's category, not the citizen's.
      expect(s.aiCategoryLabel, 'Infrastructure');
    });

    test('aiCategoryLabel ignores the citizen\'s "others" free text', () {
      // categoryOther belongs to the citizen's own pick. Passing it into the
      // model's label would print the citizen's typed words as the AI's
      // opinion — two different claims wearing the same chip.
      final s = AdminSuggestion(
        id: 'x',
        shortId: 'SGS-X',
        categoryKey: 'others',
        category: 'Streetlights',
        categoryOther: 'Streetlights',
        barangay: null,
        address: null,
        latitude: null,
        longitude: null,
        details: 'd',
        isAnonymous: false,
        submitterName: null,
        submitterPhotoUrl: null,
        submitterRole: null,
        mediaCount: 0,
        status: SuggestionStatus.fresh,
        adminNote: null,
        adminResponse: null,
        reviewedAt: null,
        createdAt: DateTime(2026, 9, 17),
        aiCategoryKey: 'infrastructure',
      );
      expect(s.aiCategoryLabel, 'Infrastructure');
      expect(s.aiCategoryLabel, isNot(contains('Streetlights')));
    });
  });

  group('aiThemeLabel — null means "reserve no space"', () {
    test('unclassified → null', () {
      expect(_suggestion(categoryKey: 'others').aiThemeLabel, isNull);
    });

    test("the 'other' bucket → null, so no chip and no gap", () {
      // Point 2 in the header. If this ever returns 'Other', a row themed
      // 'other' renders an empty chip inside a real SizedBox.
      expect(
        _suggestion(categoryKey: 'others', aiTheme: 'other').aiThemeLabel,
        isNull,
      );
      expect(
        _suggestion(categoryKey: 'others', aiTheme: 'OTHER').aiThemeLabel,
        isNull,
      );
    });

    test('blank and whitespace-only themes → null', () {
      expect(_suggestion(categoryKey: 'others', aiTheme: '').aiThemeLabel,
          isNull);
      expect(_suggestion(categoryKey: 'others', aiTheme: '   ').aiThemeLabel,
          isNull);
    });

    test('a real theme is title-cased for display', () {
      expect(
        _suggestion(categoryKey: 'others', aiTheme: 'repair or upkeep')
            .aiThemeLabel,
        'Repair Or Upkeep',
      );
      expect(
        _suggestion(categoryKey: 'others', aiTheme: 'new facility').aiThemeLabel,
        'New Facility',
      );
    });
  });

  group('an unclassified row renders as it always did', () {
    testWidgets('no chip text appears on the card', (tester) async {
      await pumpAt(tester, kModernPhone, () {
        return MaterialApp(
          home: Scaffold(
            body: SuggestionCardPreview(_suggestion(categoryKey: 'environment')),
          ),
        );
      });
      expect(find.textContaining('Looks like'), findsNothing);
      // No theme chip either — and nothing title-cased from a null.
      expect(find.text('Other'), findsNothing);
    });

    testWidgets('an unclassified card is no taller than before', (tester) async {
      // The guard in the card reads `isMiscategorized || aiThemeLabel != null`.
      // If either half were wrong, the classified-but-themeless row would gain
      // a SizedBox with nothing in it. Compare the two heights directly rather
      // than asserting a magic number.
      Future<double> heightOf(AdminSuggestion s) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 390, child: SuggestionCardPreview(s)),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        return tester.getSize(find.byType(SuggestionCardPreview)).height;
      }

      final unclassified = await heightOf(_suggestion(categoryKey: 'others'));
      final themedOther = await heightOf(
        _suggestion(
          categoryKey: 'others',
          aiCategory: 'others', // agrees → no mis-filed chip
          aiTheme: 'other', // → no theme chip
        ),
      );
      expect(themedOther, unclassified,
          reason: 'a row whose AI output shows nothing must not reserve space');
    });
  });

  group('the chips survive every phone width', () {
    // Point 3. The densest case: mis-filed AND a long theme, in both layouts.
    final dense = _suggestion(
      categoryKey: 'others',
      aiCategory: 'public_service',
      aiTheme: 'service improvement',
      aiCategoryReason: 'Asks for more counters at the business permit window.',
      details: 'Ang pila sa business permit ay sobrang haba, baka pwedeng '
          'dagdagan ang counter tuwing umaga.',
    );

    // 320 is the real floor: [[admin-responsive-overflow-probe]] found three
    // overflows that a 1280px screenshot showed as fine.
    const devices = [kSmallPhone, kPhone, kModernPhone, kBigPhone, kTablet];
    for (final device in devices) {
      testWidgets('card: no overflow on ${device.name}', (tester) async {
        final errors = await pumpAt(tester, device, () {
          return MaterialApp(
            home: Scaffold(body: SuggestionCardPreview(dense)),
          );
        });
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('table row: no overflow in its narrowest real cell',
        (tester) async {
      // The table only renders at desktop width, but the cell is a flex: 4 of
      // whatever the window gives it. 900 is the narrowest width at which the
      // page still chooses the table over cards.
      final errors = await pumpAt(tester, const Device('narrow desktop', Size(900, 800)),
          () {
        return MaterialApp(
          home: Scaffold(body: SuggestionTableRowPreview(dense)),
        );
      });
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    testWidgets('table row survives a large text scale', (tester) async {
      // An admin on a 1.3x display scale is the case that actually clips this
      // cell, since the chip label and the short id share one line.
      final errors = await pumpAt(
        tester,
        const Device('narrow desktop', Size(900, 800)),
        () => MaterialApp(
          home: Scaffold(body: SuggestionTableRowPreview(dense)),
        ),
        textScale: 1.3,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });
}
