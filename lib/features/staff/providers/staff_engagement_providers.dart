// ════════════════════════════════════════════════════════════════════════════
//  Staff engagement providers — suggestions, feedback, performance
//
//  Same shape as the reports/conversations providers in staff_providers.dart:
//  identity is the root, every list watches it for the department, and each
//  notifier polls on an interval rather than subscribing.
//
//  WHY POLLING, NOT REALTIME: realtime.apply_rls runs each change through the
//  subscriber's own SELECT policies. Staff read suggestions and feedback
//  through security_invoker views whose predicate is a SECURITY DEFINER
//  function; the base-table policies exist, so a socket would in principle
//  deliver — but the reports console already settled on interval polling for
//  exactly this surface and mixing the two mechanisms in one console makes
//  "why didn't my list update" a two-answer question. Consistency wins.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/staff_engagement_repository.dart';
import 'staff_providers.dart';

final staffEngagementRepoProvider = Provider<StaffEngagementRepository>(
  (_) => StaffEngagementRepository(Supabase.instance.client),
);

/// Whether the signed-in office can receive feedback at all.
///
/// Environment Office never can — no office in the citizen feedback form maps
/// to it. The console uses this to omit the nav item entirely rather than
/// render a tab that is permanently empty.
final staffHasFeedbackProvider = Provider<bool>((ref) {
  final dept = ref.watch(staffDepartmentProvider);
  return departmentReceivesFeedback(dept);
});

// ── Suggestions ─────────────────────────────────────────────────────────────

final staffSuggestionsStaleProvider = StateProvider<bool>((_) => false);

class StaffSuggestionsNotifier extends AsyncNotifier<List<StaffSuggestion>>
    with StaffIntervalPoll {
  StaffEngagementRepository get _repo => ref.read(staffEngagementRepoProvider);

  @override
  Future<List<StaffSuggestion>> build() async {
    // Bound BEFORE the await, or a disposal during the suspension orphans the
    // timer — see StaffIntervalPoll.bindPollLifecycle.
    bindPollLifecycle(ref);
    final dept =
        await ref.watch(staffIdentityProvider.selectAsync((i) => i.department));
    startPolling();
    return _repo.fetchSuggestions(dept);
  }

  @override
  Future<void> poll() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next = await AsyncValue.guard(() => _repo.fetchSuggestions(dept));
    if (next.hasValue) {
      state = next;
      ref.read(staffSuggestionsStaleProvider.notifier).state = false;
    } else {
      ref.read(staffSuggestionsStaleProvider.notifier).state = true;
    }
  }

  Future<void> refresh() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchSuggestions(dept));
    ref.read(staffSuggestionsStaleProvider.notifier).state = false;
  }

  /// Submit a draft, then refresh so the composer closes against real state
  /// rather than an optimistic guess. A reply that appears locally but was
  /// refused by RLS is the exact failure the staff write gap produces.
  Future<void> submitReply(String suggestionId, String body) async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    await _repo.submitReply(
        suggestionId: suggestionId, department: dept, body: body);
    await refresh();
  }

  Future<void> reviseReply(String replyId, String body) async {
    await _repo.reviseReply(replyId: replyId, body: body);
    await refresh();
  }
}

final staffSuggestionsProvider =
    AsyncNotifierProvider<StaffSuggestionsNotifier, List<StaffSuggestion>>(
        StaffSuggestionsNotifier.new);

/// Suggestions still awaiting a reply — the number that drives the nav badge.
final staffPendingSuggestionsProvider = Provider<int>((ref) {
  final list = ref.watch(staffSuggestionsProvider).valueOrNull ?? const [];
  return list.where((s) => !s.isAnswered).length;
});

// ── Feedback ────────────────────────────────────────────────────────────────

final staffFeedbackStaleProvider = StateProvider<bool>((_) => false);

class StaffFeedbackNotifier extends AsyncNotifier<List<StaffFeedback>>
    with StaffIntervalPoll {
  StaffEngagementRepository get _repo => ref.read(staffEngagementRepoProvider);

  @override
  Future<List<StaffFeedback>> build() async {
    bindPollLifecycle(ref);
    final dept =
        await ref.watch(staffIdentityProvider.selectAsync((i) => i.department));
    // No polling for an office that can never receive feedback: an empty list
    // forever does not need a timer waking every 30 seconds to confirm it.
    if (!departmentReceivesFeedback(dept)) return const [];
    startPolling();
    return _repo.fetchFeedback(dept);
  }

  @override
  Future<void> poll() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    final next = await AsyncValue.guard(() => _repo.fetchFeedback(dept));
    if (next.hasValue) {
      state = next;
      ref.read(staffFeedbackStaleProvider.notifier).state = false;
    } else {
      ref.read(staffFeedbackStaleProvider.notifier).state = true;
    }
  }

  Future<void> refresh() async {
    final dept = ref.read(staffDepartmentProvider);
    if (dept == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchFeedback(dept));
    ref.read(staffFeedbackStaleProvider.notifier).state = false;
  }
}

final staffFeedbackProvider =
    AsyncNotifierProvider<StaffFeedbackNotifier, List<StaffFeedback>>(
        StaffFeedbackNotifier.new);

/// Low ratings (1-2★) in the last 7 days — the other nav badge.
final staffLowRatingsProvider = Provider<int>((ref) {
  final list = ref.watch(staffFeedbackProvider).valueOrNull ?? const [];
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  return list.where((f) => f.isLow && f.createdAt.isAfter(cutoff)).length;
});

/// Average rating across everything this office has received. Null when there
/// is nothing to average — a brand-new office must read as "no ratings yet",
/// never as 0.0, which looks like the worst possible score.
final staffAverageRatingProvider = Provider<double?>((ref) {
  final list = ref.watch(staffFeedbackProvider).valueOrNull ?? const [];
  final rated = list.where((f) => f.overallRating > 0).toList();
  if (rated.isEmpty) return null;
  final sum = rated.fold<int>(0, (a, f) => a + f.overallRating);
  return sum / rated.length;
});

/// Star histogram, index 0 = 1★ … index 4 = 5★. Computed client-side from the
/// already-fetched list so the mix panel costs no extra round trip.
final staffRatingMixProvider = Provider<List<int>>((ref) {
  final list = ref.watch(staffFeedbackProvider).valueOrNull ?? const [];
  final mix = List<int>.filled(5, 0);
  for (final f in list) {
    if (f.overallRating >= 1 && f.overallRating <= 5) {
      mix[f.overallRating - 1]++;
    }
  }
  return mix;
});

// ── Performance ─────────────────────────────────────────────────────────────

/// This staff member's own scorecard. Deliberately NOT a list of peers: staff
/// see their own standing, admins see the ranking.
final staffMyScorecardProvider = FutureProvider<StaffScorecard?>((ref) async {
  // Rebuild when identity changes so switching accounts re-scopes the card.
  ref.watch(staffIdentityProvider);
  return ref.read(staffEngagementRepoProvider).fetchMyScorecard();
});

/// Weekly rating trend for this office, oldest first.
final staffRatingTrendProvider =
    FutureProvider<List<RatingPoint>>((ref) async {
  final dept = ref.watch(staffDepartmentProvider);
  if (dept == null || !departmentReceivesFeedback(dept)) return const [];
  return ref.read(staffEngagementRepoProvider).fetchRatingTrend(dept);
});
