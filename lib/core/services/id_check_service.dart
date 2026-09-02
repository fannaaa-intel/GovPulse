import 'dart:convert';


import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the server decided about one captured side of one ID.
enum IdVerdict {
  /// Score cleared the bar: the wizard proceeds without comment.
  autoAccept,

  /// Usable, but a human should look. The user still proceeds — the flag
  /// travels with the submission for the reviewer.
  review,

  /// Not a usable capture of the declared ID. The user is asked to retake.
  reject,
}

/// One reason the score moved, in words a person can act on.
class IdCheckReason {
  final String code;
  final String detail;
  final int delta;

  const IdCheckReason({
    required this.code,
    required this.detail,
    required this.delta,
  });

  factory IdCheckReason.fromJson(Map<String, dynamic> j) => IdCheckReason(
    code: (j['code'] ?? '').toString(),
    detail: (j['detail'] ?? '').toString(),
    delta: (j['delta'] as num?)?.toInt() ?? 0,
  );
}

class IdCheckResult {
  final bool ok;
  final int score;
  final IdVerdict verdict;
  final List<IdCheckReason> reasons;
  final Map<String, String> fields;

  /// A different ID type whose wording fit better than the declared one.
  final String? suspectedType;

  /// Upload-only signals (`no_camera_metadata`, `png_likely_screenshot`).
  final List<String> sourceFlags;

  const IdCheckResult({
    required this.ok,
    required this.score,
    required this.verdict,
    this.reasons = const [],
    this.fields = const {},
    this.suspectedType,
    this.sourceFlags = const [],
  });

  /// The state every path used to be in: nothing was checked.
  ///
  /// Deliberately `review`, never `autoAccept`. If the checker cannot be
  /// reached the submission must still reach a human — which is exactly where
  /// every submission went before this existed.
  static const unchecked = IdCheckResult(
    ok: false,
    score: 0,
    verdict: IdVerdict.review,
  );

  /// The single sentence to show the user when a capture is refused.
  String get userMessage {
    for (final r in reasons) {
      switch (r.code) {
        case 'no_text':
          return 'We could not read any text on that photo. Move somewhere '
              'brighter, hold the card still, and make sure it fills the frame.';
        case 'type_mismatch':
          return suspectedType == null
              ? 'That does not look like the ID you chose.'
              : 'That looks like a $suspectedType, not the ID you chose. Pick '
                    'the matching ID type or photograph the right card.';
        case 'uncorroborated':
          return 'We could see the card\'s heading but none of its details. '
              'Make sure the whole card is in frame and in focus.';
      }
    }
    return 'We could not confirm that card. Try again with the whole ID in '
        'frame, in focus, and free of glare.';
  }
}

/// What the automated check concluded about a whole submission, ready to
/// persist alongside it.
///
/// ── Why the WORST side wins ─────────────────────────────────────────────────
/// A submission is two captures, and they are not independent evidence: a
/// pristine front paired with a back that scored 20 is more suspicious than
/// either number alone suggests, because a real card has two real sides. Taking
/// the minimum means a reviewer is never reassured by an average that hides the
/// half that failed.
class IdSubmissionCheck {
  final int score;
  final IdVerdict verdict;
  final List<IdCheckReason> reasons;
  final List<String> sourceFlags;

  const IdSubmissionCheck({
    required this.score,
    required this.verdict,
    this.reasons = const [],
    this.sourceFlags = const [],
  });

  /// Combines the front and back results into one row-shaped verdict.
  ///
  /// Either side may be null — the mobile camera path checks with ML Kit
  /// rather than this service, and a checker outage produces nothing at all.
  static IdSubmissionCheck? combine(IdCheckResult? front, IdCheckResult? back) {
    final sides = [front, back].whereType<IdCheckResult>().toList();
    if (sides.isEmpty) return null;

    // Rank by severity, not by score: `reject` outranks `review` even if the
    // rejected side happens to have scored higher on its bands.
    int rank(IdVerdict v) => switch (v) {
      IdVerdict.reject => 0,
      IdVerdict.review => 1,
      IdVerdict.autoAccept => 2,
    };
    sides.sort((a, b) {
      final byVerdict = rank(a.verdict).compareTo(rank(b.verdict));
      return byVerdict != 0 ? byVerdict : a.score.compareTo(b.score);
    });
    final worst = sides.first;

    return IdSubmissionCheck(
      score: worst.score,
      verdict: worst.verdict,
      // Every reason from both sides: a reviewer wants the full picture, and
      // the codes already say which side each came from by their content.
      reasons: [for (final s in sides) ...s.reasons],
      sourceFlags: {for (final s in sides) ...s.sourceFlags}.toList(),
    );
  }

  String get verdictColumn => switch (verdict) {
    IdVerdict.autoAccept => 'auto_accept',
    IdVerdict.review => 'review',
    IdVerdict.reject => 'reject',
  };

  /// The columns added by migration 20260902000000.
  Map<String, dynamic> toSubmissionColumns() => {
    'check_score': score,
    'check_verdict': verdictColumn,
    'check_reasons': [
      for (final r in reasons)
        {'code': r.code, 'detail': r.detail, 'delta': r.delta},
    ],
    'check_source_flags': sourceFlags,
    'check_at': DateTime.now().toUtc().toIso8601String(),
  };

  /// Round-trips through a route's `arguments` map, which is how this survives
  /// the three hops between the scan screen and the submit.
  Map<String, dynamic> toRouteArg() => {
    'score': score,
    'verdict': verdictColumn,
    'reasons': [
      for (final r in reasons)
        {'code': r.code, 'detail': r.detail, 'delta': r.delta},
    ],
    'sourceFlags': sourceFlags,
  };

  static IdSubmissionCheck? fromRouteArg(Object? raw) {
    if (raw is! Map) return null;
    final verdict = switch ((raw['verdict'] ?? '').toString()) {
      'auto_accept' => IdVerdict.autoAccept,
      'reject' => IdVerdict.reject,
      _ => IdVerdict.review,
    };
    final rawReasons = raw['reasons'];
    return IdSubmissionCheck(
      score: (raw['score'] as num?)?.toInt() ?? 0,
      verdict: verdict,
      reasons: rawReasons is List
          ? [
              for (final r in rawReasons)
                if (r is Map) IdCheckReason.fromJson(Map<String, dynamic>.from(r)),
            ]
          : const [],
      sourceFlags: raw['sourceFlags'] is List
          ? (raw['sourceFlags'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// Server-side ID verification, for EVERY capture path.
///
/// ── Why this is not [IdVerificationService] ─────────────────────────────────
/// That service is ML Kit based and needs `dart:io`, so it only ever ran on the
/// mobile camera path. Three of the app's four capture paths — mobile web,
/// the larger-screen file upload, and the mobile gallery picker — had no
/// checking and no auto-fill at all. This calls the `verify-id` Edge Function,
/// which runs the same rules for all of them.
///
/// Scoring on the server is also the only version that can be trusted: a
/// client-side check is advice, and the client can be patched.
class IdCheckService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Verifies one side of one ID.
  ///
  /// [source] is `'camera'` for a live capture and `'upload'` for a file the
  /// user chose; the server applies screenshot/EXIF heuristics only to the
  /// latter, because only an uploaded file can be a saved image.
  ///
  /// NEVER throws. A verification outage must not block a citizen from
  /// signing up, so every failure returns [IdCheckResult.unchecked], which
  /// routes the submission to a human exactly as before.
  static Future<IdCheckResult> check({
    required Uint8List imageBytes,
    required String idType,
    required bool isFront,
    String source = 'camera',
  }) async {
    try {
      final res = await _client.functions.invoke(
        'verify-id',
        body: {
          'idType': idType,
          'side': isFront ? 'front' : 'back',
          'source': source,
          'imageBase64': base64Encode(imageBytes),
        },
      );

      final data = res.data;
      if (data is! Map) return IdCheckResult.unchecked;

      // `ok:false` is the function's own fail-open path — it already returns a
      // `review` verdict and a reason, so the body is still worth reading.
      final verdict = switch ((data['verdict'] ?? '').toString()) {
        'auto_accept' => IdVerdict.autoAccept,
        'reject' => IdVerdict.reject,
        _ => IdVerdict.review,
      };

      final rawFields = data['fields'];
      final fields = <String, String>{};
      if (rawFields is Map) {
        rawFields.forEach((k, v) {
          final s = (v ?? '').toString().trim();
          if (s.isNotEmpty) fields[k.toString()] = s;
        });
      }

      final rawReasons = data['reasons'];
      final reasons = <IdCheckReason>[];
      if (rawReasons is List) {
        for (final r in rawReasons) {
          if (r is Map) {
            reasons.add(IdCheckReason.fromJson(Map<String, dynamic>.from(r)));
          }
        }
      }

      final rawFlags = data['sourceFlags'];
      final flags = rawFlags is List
          ? rawFlags.map((e) => e.toString()).toList()
          : const <String>[];

      return IdCheckResult(
        ok: data['ok'] == true,
        score: (data['score'] as num?)?.toInt() ?? 0,
        verdict: verdict,
        reasons: reasons,
        fields: fields,
        suspectedType: (data['suspectedType'] as Object?)?.toString(),
        sourceFlags: flags,
      );
    } catch (e) {
      debugPrint('[ID-CHECK] verify-id unavailable: $e');
      return IdCheckResult.unchecked;
    }
  }
}
