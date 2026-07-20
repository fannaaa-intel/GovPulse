import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../admin/providers/admin_reports_provider.dart' show ReportStatus;
import '../data/staff_repository.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Staff console providers
//
//  Identity is the root: every list provider watches it for the signed-in
//  staff member's department, so switching accounts / departments re-scopes the
//  whole console automatically.
// ════════════════════════════════════════════════════════════════════════════

final staffRepoProvider = Provider<StaffRepository>((_) => StaffRepository.I);

// ── Identity + presence ──────────────────────────────────────────────────────
class StaffIdentityNotifier extends AsyncNotifier<StaffIdentity> {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<StaffIdentity> build() => _repo.fetchIdentity();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.fetchIdentity);
  }

  /// Flips the on-duty flag. Optimistic — reverts on failure. When a staff
  /// member is online, the citizen chat's `findAvailableStaffId` can route a
  /// live-agent request to them.
  Future<void> setOnline(bool online) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(isOnline: online));
    try {
      await _repo.setOnline(online);
    } catch (_) {
      state = AsyncData(cur); // revert
      rethrow;
    }
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

// ── Conversations ────────────────────────────────────────────────────────────
class StaffConversationsNotifier extends AsyncNotifier<List<StaffConversation>> {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<List<StaffConversation>> build() async {
    final id = await ref.watch(staffIdentityProvider.future);
    return _repo.fetchConversations(id.department);
  }

  Future<void> refresh() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchConversations(dept));
  }

  Future<void> _reload() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next = await AsyncValue.guard(() => _repo.fetchConversations(dept));
    if (next.hasValue) state = next;
  }

  /// Background reload without a loading flash — used by the inbox's realtime
  /// subscription so a new waiting chat slides in without blanking the list.
  Future<void> silentRefresh() => _reload();

  Future<void> claim(String ticketId) async {
    await _repo.claimConversation(ticketId);
    await _reload();
  }

  Future<void> setStatus(String ticketId, String status) async {
    await _repo.setConversationStatus(ticketId, status);
    await _reload();
  }
}

final staffConversationsProvider =
    AsyncNotifierProvider<StaffConversationsNotifier, List<StaffConversation>>(
  StaffConversationsNotifier.new,
);

// ── Reports (department-scoped) ───────────────────────────────────────────────
class StaffReportsNotifier extends AsyncNotifier<List<StaffReport>> {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<List<StaffReport>> build() async {
    final id = await ref.watch(staffIdentityProvider.future);
    _watchRealtime();
    return _repo.fetchDepartmentReports(id.department);
  }

  /// Live inbox: any reports change the staff can see (RLS-scoped) — a fresh
  /// assignment, a status move — silently refreshes the list.
  void _watchRealtime() {
    final supabase = Supabase.instance.client;
    final channel = supabase
        .channel('staff_reports_inbox')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (_) => silentRefresh(),
        )
        .subscribe();
    ref.onDispose(() => supabase.removeChannel(channel));
  }

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

  Future<void> setStatus(String id, ReportStatus status) async {
    await _repo.setReportStatus(id, status);
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next =
        await AsyncValue.guard(() => _repo.fetchDepartmentReports(dept));
    if (next.hasValue) state = next;
  }

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

// ── Endorsements (external entities) ──────────────────────────────────────────
class StaffEndorsementsNotifier extends AsyncNotifier<List<StaffReport>> {
  StaffRepository get _repo => ref.read(staffRepoProvider);

  @override
  Future<List<StaffReport>> build() async {
    final id = await ref.watch(staffIdentityProvider.future);
    final supabase = Supabase.instance.client;
    final channel = supabase
        .channel('staff_endorsements_inbox')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (_) => silentRefresh(),
        )
        .subscribe();
    ref.onDispose(() => supabase.removeChannel(channel));
    return _repo.fetchEndorsedReports(id.department);
  }

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

  Future<void> setStatus(String id, ReportStatus status) async {
    await _repo.setReportStatus(id, status);
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next = await AsyncValue.guard(() => _repo.fetchEndorsedReports(dept));
    if (next.hasValue) state = next;
  }

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
