// Preview target: the AI chips on the admin Suggestions list.
//
//   flutter build web --release -t tool/preview_suggestion_ai_chips.dart
//
// The chips are fed by classify-suggestion (migration 20260917000000). Two
// layouts render them, and they are NOT the same widget:
//   • the desktop table row — a fixed `flex: 4` column shared with a 30px icon,
//     which is why the mis-filed chip renders there in `compact: true` (bare
//     label, no "Looks like:" prefix). A sentence would ellipsize to nothing.
//   • the phone card — chips in a Wrap so a mis-filed chip plus a theme chip
//     reflow instead of overflowing.
//
// What to look for:
//   • the compact chip must not squeeze the category or the short-id out
//   • on the phone card, both chips on one line where they fit, wrapped where
//     they don't — never a yellow overflow stripe
//   • an unclassified row must look EXACTLY as it did before this feature: no
//     chip, and no leftover vertical gap where one would have been
//   • a row themed 'other' must also show no theme chip and no gap
//     (aiThemeLabel returns null for 'other' — that is the reason why)
//
// This renders the two card widgets directly rather than the whole page, so it
// needs no Supabase session and no provider override.
import 'package:flutter/material.dart';

import 'package:govpulse/features/admin/pages/admin_suggestions_page.dart';
import 'package:govpulse/features/admin/providers/admin_suggestions_provider.dart';

void main() {
  final w = double.tryParse(Uri.base.queryParameters['w'] ?? '');
  runApp(_App(single: w));
}

AdminSuggestion _row({
  required String id,
  required String categoryKey,
  String? aiCategory,
  String? aiTheme,
  String? aiReason,
  String details = 'Please install a streetlight along the Rizal Street corner '
      'near the covered court — it is very dark at night.',
}) {
  return AdminSuggestion(
    id: id,
    shortId: 'SGS-${id.toUpperCase()}',
    categoryKey: categoryKey,
    category: suggestionCategoryLabel(categoryKey, null),
    categoryOther: null,
    barangay: 'Macanaya',
    address: 'Rizal St.',
    latitude: null,
    longitude: null,
    details: details,
    isAnonymous: false,
    submitterName: 'Juan D. Cruz',
    submitterPhotoUrl: null,
    submitterRole: 'citizen',
    mediaCount: 2,
    status: SuggestionStatus.fresh,
    adminNote: null,
    adminResponse: null,
    reviewedAt: null,
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    aiCategoryKey: aiCategory,
    aiCategoryReason: aiReason,
    aiTheme: aiTheme,
    aiClassifiedAt: aiCategory == null && aiTheme == null
        ? null
        : DateTime.now().subtract(const Duration(hours: 4)),
  );
}

// The interesting states, not just the happy one.
final _rows = <({String label, AdminSuggestion row})>[
  (
    label: 'mis-filed + theme (the new UI)',
    row: _row(
      id: 'a1b2c3d4',
      categoryKey: 'others',
      aiCategory: 'infrastructure',
      aiTheme: 'new facility',
      aiReason: 'Asks for a streetlight to be installed, which is public '
          'infrastructure rather than an unclassified concern.',
    ),
  ),
  (
    label: 'correctly filed + theme',
    row: _row(
      id: 'b2c3d4e5',
      categoryKey: 'infrastructure',
      aiCategory: 'infrastructure',
      aiTheme: 'repair or upkeep',
    ),
  ),
  (
    label: "theme 'other' → no chip, no gap",
    row: _row(
      id: 'c3d4e5f6',
      categoryKey: 'community_program',
      aiCategory: 'community_program',
      aiTheme: 'other',
    ),
  ),
  (
    label: 'UNCLASSIFIED — must look untouched',
    row: _row(id: 'd4e5f6a7', categoryKey: 'environment'),
  ),
  (
    label: 'longest pair: mis-filed + longest theme',
    row: _row(
      id: 'e5f6a7b8',
      categoryKey: 'others',
      aiCategory: 'public_service',
      aiTheme: 'service improvement',
      details: 'Ang pila sa business permit ay sobrang haba, baka pwedeng '
          'dagdagan ang counter tuwing umaga.',
    ),
  ),
];

class _App extends StatelessWidget {
  final double? single;
  const _App({this.single});

  @override
  Widget build(BuildContext context) {
    // Desktop table rows need a wide frame; phone cards a narrow one. Both are
    // shown so the compact/full chip variants can be compared side by side.
    final widths = single != null
        ? <double>[single!]
        : <double>[1100, 390, 360];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in widths) ...[
                _Frame(width: w, table: w >= 900),
                const SizedBox(width: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final double width;

  /// At desktop width the page renders the table row; below it, the card.
  final bool table;
  const _Frame({required this.width, required this.table});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width,
          child: Text(
            '${width.toInt()} — ${table ? 'desktop table row' : 'phone card'}',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          padding: const EdgeInsets.all(12),
          color: const Color(0xFFF1F4F9),
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 1200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in _rows) ...[
                  Text(
                    r.label,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    color: Colors.white,
                    child: table
                        ? SuggestionTableRowPreview(r.row)
                        : SuggestionCardPreview(r.row),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
