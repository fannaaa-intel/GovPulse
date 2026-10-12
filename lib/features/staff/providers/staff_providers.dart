import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../admin/providers/admin_reports_provider.dart' show ReportStatus;
import '../../../core/services/session_cache.dart';
import '../data/staff_repository.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Staff console providers
//
//  Identity is the root: every list provider watches it for the signed-in
//  staff member's department, so switching accounts / departments re-scopes the
//  whole console automatically.
// ════════════════════════════════════════════════════════════════════════════

final staffRepoProvider = Provider<StaffRepository>((_) => StaffRepository.I);

// ── Identity ─────────────────────────────────────────────────────────────────
class StaffIdentityNotifier extends AsyncNotifier<StaffIdentity> {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<StaffIdentity> build() => _fetchWithCache();

  /// Fetches identity, falling back to the last known-good copy when the
  /// network does not cooperate.
  ///
  /// ── Why ──────────────────────────────────────────────────────────────────
  /// A failed fetch falls through to the console's own fallbacks — a generic
  /// 'S' avatar and the name 'Staff' — so a staff member on a weak connection
  /// saw someone else's idea of who they are. Same class of bug as the citizen
  /// profile falling back to 'unverified'.
  Future<StaffIdentity> _fetchWithCache() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      final identity = await _repo.fetchIdentity();
      if (uid != null) {
        // Only on a real answer — caching a failure is what would make a wrong
        // identity stick across restarts.
        unawaited(
          SessionCache.instance.saveStaffIdentity(
            uid: uid,
            identity: CachedStaffIdentity(
              email: identity.email,
              fullName: identity.fullName,
              title: identity.title,
              department: identity.department,
              photoUrl: identity.photoUrl,
              isExternal: identity.isExternal,
            ),
          ),
        );
      }
      return identity;
    } catch (_) {
      final cached = uid == null ? null : SessionCache.instance.staffFor(uid);
      if (cached == null) rethrow;
      return StaffIdentity(
        userId: uid!,
        email: cached.email,
        fullName: cached.fullName,
        title: cached.title,
        department: cached.department,
        isExternal: cached.isExternal,
        photoUrl: cached.photoUrl,
      );
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchWithCache);
  }

  /// Re-reads identity WITHOUT flashing a loading state, keeping the current
  /// value if the fetch fails.
  ///
  /// For the reconnect path: a console opened offline holds a failed identity
  /// — no name, no photo, no department — and nothing re-fetched it when the
  /// network returned. [refresh] is wrong there because it blanks the console
  /// to a spinner first and lands on an error if the connection is still
  /// flapping. Mirrors `UserProfileNotifier.silentRefresh`.
  Future<void> silentRefresh() async {
    final previous = state;
    final next = await AsyncValue.guard(_fetchWithCache);
    state = next.hasValue ? next : previous;
  }

  /// Uploads + persists a new avatar, then patches identity so the UI updates
  /// without a full refetch.
  Future<void> setPhoto(Uint8List bytes, String ext) async {
    final cur = state.valueOrNull;
    final url = await _repo.updatePhoto(bytes, ext);
    if (cur != null) state = AsyncData(cur.copyWith(photoUrl: url));
  }
}

final staffIdentityProvider =
    AsyncNotifierProvider<StaffIdentityNotifier, StaffIdentity>(
  StaffIdentityNotifier.new,
);

/// The signed-in staff member's department, once identity has loaded.
final staffDepartmentProvider = Provider<String?>((ref) {
  return ref.watch(staffIdentityProvider).valueOrNull?.department;
});

/// Shared interval-poll plumbing for the staff list notifiers.
///
/// Each notifier arms its timer in `build()` and cancels it via `ref.onDispose`.
/// The console pauses and resumes all three together on app lifecycle changes.
///
/// One timer per notifier, owned by the notifier — never by a page. A
/// page-owned timer only runs while that page is mounted, which once left a
/// dashboard panel frozen until someone opened the matching page.
///
/// UPGRADE PATH: when Broadcast lands (7c) it replaces all three timers in a
/// single change — inbox and dashboard both become live-push, because both read
/// these same providers. Delete the `startPolling()` calls and keep the stale
/// flags: a dropped socket must stay as visible as a failed poll.
mixin StaffIntervalPoll {
  Timer? _pollTimer;

  /// True once this notifier has been disposed for the current build.
  ///
  /// THE INVARIANT: a notifier disposed during its own `build()` must not leave
  /// a live timer behind.
  ///
  /// Each `build()` below suspends on `await ref.watch(...)` before arming its
  /// timer. If the notifier is disposed during that suspension — which is
  /// exactly what a sign-out teardown does — the build still resumes afterwards
  /// and arms a `Timer.periodic`. Registering `ref.onDispose` at that point is
  /// useless: disposal has already happened, so the hook never fires and the
  /// timer is ORPHANED. It then keeps calling [poll] every 30s against a
  /// disposed ref, reading and writing providers into a torn-down tree.
  ///
  /// Three per sign-out, accumulating across login/logout cycles.
  bool _pollDisposed = false;

  /// Registers disposal handling for this build. MUST be called synchronously
  /// at the top of `build()`, before any `await` — the whole point is that the
  /// hook exists before the window in which disposal can happen.
  ///
  /// Riverpod clears `onDispose` callbacks between builds, so re-registering on
  /// every build is correct, and resetting the flag here is what makes a
  /// rebuild (as opposed to a disposal) start clean.
  void bindPollLifecycle(Ref ref) {
    _pollDisposed = false;
    ref.onDispose(() {
      _pollDisposed = true;
      pausePolling();
    });
  }

  Duration get pollInterval => const Duration(seconds: 30);

  /// One tick. Each notifier implements this and must raise its own stale flag
  /// on failure rather than swallowing it.
  Future<void> poll();

  void startPolling() {
    // The guard that closes the orphan window. A build that resumes after its
    // own disposal must arm nothing — there is no longer an onDispose that
    // could cancel it, and the notifier it would poll into is gone.
    if (_pollDisposed) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      // Belt and braces: even a timer that somehow outlives its owner stops
      // touching providers rather than mutating a torn-down tree.
      if (_pollDisposed) {
        pausePolling();
        return;
      }
      poll();
    });
  }

  /// Backgrounded: stop consuming mobile data. Safe to call repeatedly.
  void pausePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Foregrounded: refetch IMMEDIATELY, then restart the interval. Waiting for
  /// the next tick would show the user up to 30s-old data on the screen they
  /// just returned to — the staleness we accept in the background is not
  /// acceptable in the first seconds of the foreground.
  void resumePolling() {
    poll();
    startPolling();
  }
}

// ── Reports (department-scoped) ───────────────────────────────────────────────

/// The two report queues an officer works — their department's reports, and the
/// reports endorsed to their agency — expose the SAME three write actions.
///
/// This names that overlap so a screen can be handed the PROVIDER and read the
/// notifier off its own `ref`, instead of being handed closures that captured
/// some other widget's `ref`. That mattered: the detail is pushed as a ROUTE,
/// the list underneath is free to be rebuilt or disposed while it is open, and
/// a captured `ref` from a disposed [ConsumerWidget] throws
/// "Bad state: Cannot use \"ref\" after the widget was disposed" on the first
/// button pressed in the detail. See [_ReportDetailState].
///
/// Extends [AsyncNotifier] rather than standing alone: Riverpod bounds
/// `AsyncNotifierProvider`'s notifier parameter to `AsyncNotifier<State>`, so a
/// bare interface cannot be used as that type argument. Both queues already
/// ARE async notifiers of the same state, so this costs nothing.
abstract class StaffReportQueue extends AsyncNotifier<List<StaffReport>> {
  Future<void> setStatus(String id, ReportStatus status);

  /// Resolve AND account for the work in one transaction. Returns the new
  /// completion update's id, so photos can be attached to it.
  /// See StaffRepository.resolveReportWithCompletion.
  Future<String> resolveWithCompletion(String id, String body);
  Future<void> returnToTriage(String id, String reason);
  Future<void> refresh();
}

class StaffReportsNotifier extends AsyncNotifier<List<StaffReport>>
    with StaffIntervalPoll
    implements StaffReportQueue {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<List<StaffReport>> build() async {
    // selectAsync, NOT watch(...future): this notifier must rebuild only when
    // the DEPARTMENT changes, never on an unrelated identity emission (avatar
    // change, a plain refetch). Rebuilding re-arms the interval timer from
    // zero, so identity churn could otherwise starve the poll indefinitely.
    // See StaffIdentity's == for the diagnosis.
    //
    // Bound BEFORE the await — see [StaffIntervalPoll.bindPollLifecycle].
    bindPollLifecycle(ref);
    final dept =
        await ref.watch(staffIdentityProvider.selectAsync((i) => i.department));
    startPolling();
    return _repo.fetchDepartmentReports(dept);
  }

  /// Interval poll, replacing the realtime subscription removed in migration
  /// 20260722000000. That subscription used postgres_changes on `reports`, and
  /// realtime authorises delivery by the subscriber's SELECT policy — staff no
  /// longer have one on that table, so it would receive nothing. The table is
  /// deliberately still IN the publication (three citizen screens subscribe to
  /// their own reports), so this is a staff-side change only.
  ///
  /// Disposal is bound up front in `build()` — see
  /// [StaffIntervalPoll.bindPollLifecycle].

  /// Unlike [silentRefresh], a FAILED poll is not swallowed: the last good list
  /// is kept so the screen does not blank, AND the stale flag is raised so the
  /// UI can say the list may be out of date. Staleness is the failure mode we
  /// accept in exchange for closing the leak; a silently-failing refresh
  /// showing old data as fresh is the silent-success bug in a new costume.
  @override
  Future<void> poll() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next =
        await AsyncValue.guard(() => _repo.fetchDepartmentReports(dept));
    if (next.hasValue) {
      state = next;
      ref.read(staffReportsStaleProvider.notifier).state = false;
    } else {
      ref.read(staffReportsStaleProvider.notifier).state = true;
    }
  }

  @override
  Future<void> refresh() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchDepartmentReports(dept));
  }

  /// Background reload without a loading flash — used when the staff switches
  /// into the Reports/Dashboard tab so freshly-landed reports appear.
  Future<void> silentRefresh() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next =
        await AsyncValue.guard(() => _repo.fetchDepartmentReports(dept));
    if (next.hasValue) state = next;
  }

  @override
  Future<void> setStatus(String id, ReportStatus status) async {
    await _repo.setReportStatus(id, status);
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next =
        await AsyncValue.guard(() => _repo.fetchDepartmentReports(dept));
    if (next.hasValue) state = next;
  }

  @override
  Future<String> resolveWithCompletion(String id, String body) async {
    final updateId = await _repo.resolveReportWithCompletion(id, body);
    final dept = ref.read(staffDepartmentProvider);
    if (dept != null) {
      final next =
          await AsyncValue.guard(() => _repo.fetchDepartmentReports(dept));
      if (next.hasValue) state = next;
    }
    return updateId;
  }

  @override
  Future<void> returnToTriage(String id, String reason) async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    await _repo.returnToTriage(id, reason, dept);
    final next =
        await AsyncValue.guard(() => _repo.fetchDepartmentReports(dept));
    if (next.hasValue) state = next;
  }
}

final staffReportsProvider =
    AsyncNotifierProvider<StaffReportsNotifier, List<StaffReport>>(
  StaffReportsNotifier.new,
);

/// True when the most recent background poll of the staff REPORTS list failed,
/// so the list on screen may be out of date. After migration 20260722000000 the
/// reports list polls instead of streaming, and a poll that fails silently is
/// indistinguishable from success. Cleared on the next successful poll.
final staffReportsStaleProvider = StateProvider<bool>((_) => false);

// ── Endorsements (external entities) ──────────────────────────────────────────
class StaffEndorsementsNotifier extends AsyncNotifier<List<StaffReport>>
    with StaffIntervalPoll
    implements StaffReportQueue {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<List<StaffReport>> build() async {
    // selectAsync — see StaffReportsNotifier.build for why watching the whole
    // identity starves the timer.
    // Bound BEFORE the await — see [StaffIntervalPoll.bindPollLifecycle].
    bindPollLifecycle(ref);
    final dept =
        await ref.watch(staffIdentityProvider.selectAsync((i) => i.department));
    // Interval poll, replacing the postgres_changes subscription on `reports`
    // removed in migration 20260722000000 — staff no longer hold a SELECT
    // policy on that table, so realtime would deliver nothing to them.
    startPolling();
    return _repo.fetchEndorsedReports(dept);
  }

  /// Failed polls raise the stale flag rather than silently keeping old data.
  ///
  /// Raises [staffEndorsementsStaleProvider], NOT the reports flag. It used to
  /// raise the reports one, which was harmless only because nothing displayed
  /// either — the moment a banner exists, a borrowed flag reports an
  /// endorsements failure as a reports failure.
  @override
  Future<void> poll() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next = await AsyncValue.guard(() => _repo.fetchEndorsedReports(dept));
    if (next.hasValue) {
      state = next;
      ref.read(staffEndorsementsStaleProvider.notifier).state = false;
    } else {
      ref.read(staffEndorsementsStaleProvider.notifier).state = true;
    }
  }

  @override
  Future<void> refresh() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchEndorsedReports(dept));
  }

  /// Background reload without a loading flash — used on tab switch.
  Future<void> silentRefresh() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next = await AsyncValue.guard(() => _repo.fetchEndorsedReports(dept));
    if (next.hasValue) state = next;
  }

  @override
  Future<void> setStatus(String id, ReportStatus status) async {
    await _repo.setReportStatus(id, status);
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next = await AsyncValue.guard(() => _repo.fetchEndorsedReports(dept));
    if (next.hasValue) state = next;
  }

  @override
  Future<String> resolveWithCompletion(String id, String body) async {
    final updateId = await _repo.resolveReportWithCompletion(id, body);
    final dept = ref.read(staffDepartmentProvider);
    if (dept != null) {
      final next =
          await AsyncValue.guard(() => _repo.fetchEndorsedReports(dept));
      if (next.hasValue) state = next;
    }
    return updateId;
  }

  @override
  Future<void> returnToTriage(String id, String reason) async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    await _repo.returnToTriage(id, reason, dept);
    final next = await AsyncValue.guard(() => _repo.fetchEndorsedReports(dept));
    if (next.hasValue) state = next;
  }
}

final staffEndorsementsProvider =
    AsyncNotifierProvider<StaffEndorsementsNotifier, List<StaffReport>>(
  StaffEndorsementsNotifier.new,
);

/// True when the most recent background poll of the ENDORSEMENTS list failed.
/// Split out from [staffReportsStaleProvider], which the endorsements poll used
/// to raise. Sharing a flag was invisible while nothing rendered it; with a
/// banner on screen it would attribute an endorsements failure to reports and
/// send staff to the wrong list looking for the problem.
final staffEndorsementsStaleProvider = StateProvider<bool>((_) => false);

// ── Community submissions ─────────────────────────────────────────────────────
class StaffCommunityNotifier extends AsyncNotifier<List<StaffCommunityPost>> {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<List<StaffCommunityPost>> build() {
    _watchRealtime();
    return _repo.fetchMyCommunityPosts();
  }

  /// Live "My submissions": any change to THIS staff member's own posts — an
  /// admin approving/rejecting, or a post being taken down — silently refreshes
  /// the list, so a pending card flips to Approved/Rejected without waiting for
  /// the notification tap. Mirrors the admin console's realtime feed.
  void _watchRealtime() {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final channel = supabase
        .channel('staff_my_posts_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'author_id',
            value: uid,
          ),
          callback: (_) => _silentRefresh(),
        )
        .subscribe();
    ref.onDispose(() => supabase.removeChannel(channel));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.fetchMyCommunityPosts);
  }

  /// Background reload without a loading flash — for the realtime subscription.
  Future<void> _silentRefresh() async {
    final next = await AsyncValue.guard(_repo.fetchMyCommunityPosts);
    if (next.hasValue) state = next;
  }

  /// Retract one of the staff member's own pending submissions. Optimistically
  /// drops it from the list, then hard-deletes it; restores + rethrows on
  /// failure so the caller can surface the error.
  Future<void> retract(String id) async {
    final prev = state.valueOrNull ?? const <StaffCommunityPost>[];
    state = AsyncData(prev.where((p) => p.id != id).toList());
    try {
      await _repo.deleteMyCommunityPost(id);
    } catch (e) {
      state = AsyncData(prev);
      rethrow;
    }
  }

  /// Returns the number of photos that failed to upload (0 = all uploaded).
  /// The post itself is committed either way — see StaffRepository.
  ///
  /// Inserts an optimistic stand-in synchronously (before the first await) so
  /// "My submissions" and the Pending KPI update the instant the composer
  /// closes; the real row + photo thumbnails swap in on the refetch. If the
  /// whole submission fails, the stand-in is pulled back out and the error
  /// rethrown for the caller to surface.
  Future<int> submit({
    required String title,
    required String body,
    required String barangay,
    required String tag,
    required String tagColorHex,
    List<XFile> images = const [],
  }) async {
    final prev = state.valueOrNull ?? const <StaffCommunityPost>[];
    final optimistic = StaffCommunityPost(
      id: 'temp_${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim(),
      body: body.trim(),
      tag: tag,
      tagColor: tagColorHex,
      status: 'pending_approval',
      rejectedReason: null,
      barangay: barangay,
      createdAt: DateTime.now(),
      localImages: List.of(images),
    );
    state = AsyncData([optimistic, ...prev]);
    try {
      final failedPhotos = await _repo.submitCommunityPost(
        title: title,
        body: body,
        barangay: barangay,
        tag: tag,
        tagColorHex: tagColorHex,
        images: images,
      );
      final next = await AsyncValue.guard(_repo.fetchMyCommunityPosts);
      state = next.hasValue ? next : AsyncData(prev);
      return failedPhotos;
    } catch (e) {
      state = AsyncData(prev); // pull the stand-in back out
      rethrow;
    }
  }
}

final staffCommunityProvider =
    AsyncNotifierProvider<StaffCommunityNotifier, List<StaffCommunityPost>>(
  StaffCommunityNotifier.new,
);

// ── Sign-out teardown ────────────────────────────────────────────────────────

/// Every staff provider scoped to the signed-in account, for the sign-out
/// teardown in `core/services/session_teardown.dart`.
///
/// Why this list has to exist: none of the providers above is `.autoDispose`,
/// so each one's state lives for the lifetime of the root ProviderScope. On web
/// that scope outlives sign-out, and a staff member's identity, department and
/// cached lists were still in the container when the next account signed in.
///
/// KEEP IN SYNC with the declarations above — a provider missing here survives
/// sign-out into the next account, which is precisely the bug this closes. It
/// lives in this file, immediately after them, so that adding a sibling puts
/// this list in view.
///
/// [staffRepoProvider] is absent on purpose: it wraps a stateless singleton and
/// holds nothing to clear.
final List<ProviderOrFamily> staffSessionProviders = <ProviderOrFamily>[
  staffIdentityProvider,
  staffDepartmentProvider,
  staffReportsProvider,
  staffReportsStaleProvider,
  staffEndorsementsProvider,
  staffEndorsementsStaleProvider,
  staffCommunityProvider,
];
