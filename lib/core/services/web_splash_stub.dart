/// Non-web implementation — see `web_splash.dart`.
///
/// A no-op rather than a throw: unlike the phone dialer, whose call sites are
/// each `kIsWeb`-guarded because a mis-dispatch is a real bug, this is
/// "dismiss the HTML splash if there is one". On Android and iOS there never
/// is one, so the correct behaviour is simply to do nothing, and the caller in
/// main.dart stays free of a platform branch.
void removeWebSplash() {}
