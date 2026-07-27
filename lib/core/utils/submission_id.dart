import 'dart:math';

final Random _rng = Random.secure();

/// Generates an RFC 4122 version 4 UUID using a cryptographically secure RNG.
///
/// Written by hand rather than pulling in `package:uuid` — this is the only
/// place the app needs one, and a 15-line function beats a dependency.
///
/// ## Why the client generates submission ids
///
/// Report and suggestion media used to be stored under
/// `reports/<auth.uid()>/<file>`, which put the citizen's identity in the
/// object key — including for submissions flagged `is_anonymous`. Staff could
/// read those keys and de-anonymise a reporter without touching the `reports`
/// table at all.
///
/// Objects are now keyed by the SUBMISSION id instead. But media is uploaded
/// before the parent row is inserted (deliberately — `trg_classify_report`
/// fires on insert, and reordering would change what the classifier sees), so
/// the id has to exist client-side first. The flow is:
///
///   1. `uuidV4()` here
///   2. upload to `reports/<that id>/<file>`
///   3. insert the report with `'id': <that id>`
///   4. insert `report_media` rows
///
/// The insert uses `.insert(...)`, never `.upsert(...)`: a client-supplied
/// primary key must fail cleanly on collision rather than overwrite an existing
/// row. Do not change that.
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx

  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
