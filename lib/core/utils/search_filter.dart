/// Helpers for safely folding free-text search into PostgREST filters.
///
/// PostgREST's `.or(...)` takes a *filter string* where `,` separates OR
/// branches and `.` separates column/operator/value, and `()` groups nested
/// conditions. Interpolating raw user text into that string lets a caller inject
/// extra branches — e.g. a search of `x,status.eq.deleted` becomes a second OR
/// condition. RLS still bounds which rows come back, but the filter shape should
/// never be caller-controlled. [sanitizeOrTerm] strips every character that has
/// structural meaning so the term can only ever land inside the `%...%` we wrap
/// it in.
library;

/// Strips PostgREST-significant characters from a free-text search [term] so it
/// is safe to interpolate into an `ilike`/`or` filter value. Removes the
/// structural characters (`,` `.` `(` `)` `:` `\`), the `ilike` wildcards
/// (`%` `*`), and collapses whitespace. The result only ever matches as a
/// literal substring.
String sanitizeOrTerm(String term) {
  return term
      .replaceAll(RegExp(r'[,.():\\%*]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
