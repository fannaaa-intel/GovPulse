import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../staff/data/staff_departments.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Admin → Agency performance (panel revision item 3)
//
//  How the external agencies (DPWH, DENR, DOH, BFP, PNP) handle the reports the
//  LGU endorses to them, plus what the reporting citizens said about it.
//    admin_agency_performance()  → one row per agency: counts, timings, stars
//    agency_feedback (admin RLS) → the most recent ratings with comments
//  Both from 20261013000000_agency_feedback.sql. Citizens are never named here,
//  so an anonymous report's rating is as anonymous as the report.
//
//  Errors are NOT swallowed into an empty list: an empty panel must mean "no
//  endorsements yet", never "the read failed".
// ════════════════════════════════════════════════════════════════════════════

double? _num(dynamic v) =>
    v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
int _int(dynamic v) => v is int ? v : (_num(v)?.toInt() ?? 0);

class AgencyPerformance {
  final String agency;

  /// Live (non-withdrawn) endorsements, at any stage.
  final int endorsements;
  final int awaiting;

  /// Received, including the ones since completed.
  final int received;
  final int completed;
  final int withdrawn;
  final double? avgDaysToReceive;

  /// Endorsement → completion: the whole wait the citizen saw.
  final double? avgDaysToComplete;
  final int ratings;
  final double? avgStars;

  const AgencyPerformance({
    required this.agency,
    this.endorsements = 0,
    this.awaiting = 0,
    this.received = 0,
    this.completed = 0,
    this.withdrawn = 0,
    this.avgDaysToReceive,
    this.avgDaysToComplete,
    this.ratings = 0,
    this.avgStars,
  });

  factory AgencyPerformance.fromRow(Map<String, dynamic> r) => AgencyPerformance(
    agency: '${r['agency'] ?? ''}',
    endorsements: _int(r['endorsements']),
    awaiting: _int(r['awaiting']),
    received: _int(r['received']),
    completed: _int(r['completed']),
    withdrawn: _int(r['withdrawn']),
    avgDaysToReceive: _num(r['avg_days_to_receive']),
    avgDaysToComplete: _num(r['avg_days_to_complete']),
    ratings: _int(r['ratings']),
    avgStars: _num(r['avg_stars']),
  );

  /// Share of live endorsements the agency has acknowledged; null with none.
  double? get receivedShare =>
      endorsements == 0 ? null : received / endorsements;
  double? get completedShare =>
      endorsements == 0 ? null : completed / endorsements;
}

class AgencyComment {
  final String agency;
  final int stars;
  final String? comment;

  /// The agency's progress when the citizen rated: endorsed (not yet
  /// acknowledged) / received / completed.
  final String state;
  final DateTime? at;

  const AgencyComment({
    required this.agency,
    required this.stars,
    required this.comment,
    required this.state,
    required this.at,
  });

  factory AgencyComment.fromRow(Map<String, dynamic> r) => AgencyComment(
    agency: '${r['agency'] ?? ''}',
    stars: _int(r['stars']),
    comment: (r['comment'] as String?)?.trim(),
    state: '${r['endorsement_state'] ?? 'endorsed'}',
    at: DateTime.tryParse('${r['updated_at']}')?.toLocal(),
  );
}

class AgencyPerformanceData {
  final List<AgencyPerformance> agencies;
  final List<AgencyComment> recent;
  const AgencyPerformanceData({required this.agencies, required this.recent});
}

/// Every canonical external agency appears, even with no endorsements yet, so
/// "PNP: 0" reads as a fact rather than a missing row. Agencies outside the
/// canonical list (a renamed one, historical data) are kept, after them.
List<AgencyPerformance> mergeWithCanonicalAgencies(
  List<AgencyPerformance> rows,
) {
  final byName = {for (final r in rows) r.agency: r};
  return [
    for (final d in StaffDepartments.external)
      byName.remove(d.name) ?? AgencyPerformance(agency: d.name),
    ...byName.values,
  ];
}

const int kAgencyRecentComments = 20;

final adminAgencyPerformanceProvider =
    FutureProvider.autoDispose<AgencyPerformanceData>((ref) async {
      final db = Supabase.instance.client;
      final perfF = db.rpc<dynamic>('admin_agency_performance');
      final recentF = db
          .from('agency_feedback')
          .select('agency, stars, comment, endorsement_state, updated_at')
          .order('updated_at', ascending: false)
          .limit(kAgencyRecentComments);
      final perf = ((await perfF) as List)
          .cast<Map<String, dynamic>>()
          .map(AgencyPerformance.fromRow)
          .toList();
      final recent = (await recentF).map(AgencyComment.fromRow).toList();
      return AgencyPerformanceData(
        agencies: mergeWithCanonicalAgencies(perf),
        recent: recent,
      );
    });
