/// How an LGU account is NAMED to anyone reading it.
///
/// An official does not act as themselves. An admin speaks for the LGU; a staff
/// member speaks for their OFFICE. So the public-facing name is institutional —
/// "LGU Aparri" or "Sanitation Office" — never the person's own name. This
/// holds on the community feed, in comment threads, in notification text and on
/// submissions alike: the same account must not read as "LGU Aparri" in one
/// place and "Rheinz" in another.
///
/// The mirror of this rule lives in SQL as `public.actor_display_name(uuid)`,
/// for the notification triggers that build their text server-side. Change one,
/// change the other.
library;

/// The LGU's own brand. Used for admins, and as the fallback for a staff
/// account with no department on file — vaguer, but never WRONG, which is the
/// same trade the SQL helper makes.
const String kLguBrandName = 'LGU Aparri';

/// Public-facing name for an official author/actor.
///
/// [role] is the app's role string ('admin' / 'staff'); [department] is
/// `admin_profiles.department`, which only staff carry.
String officialDisplayName({String? role, String? department}) {
  final dept = department?.trim() ?? '';
  if (role == 'staff' && dept.isNotEmpty) return dept;
  return kLguBrandName;
}
