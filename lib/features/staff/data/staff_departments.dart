// ════════════════════════════════════════════════════════════════════════════
//  Staff departments
//
//  The single source of truth for the departments a staff account can belong to.
//  Internal offices mirror ConcernCategory.department (chat_models.dart) so a
//  report/ticket routed to "Engineering Office" reaches the right staff.
//  External entities (DPWH, DENR, …) never own a report category — they only
//  receive reports the admin endorses to them when a concern is out of LGU
//  scope.
// ════════════════════════════════════════════════════════════════════════════

class StaffDept {
  final String name;
  final bool isExternal;

  /// The spelled-out agency name, for external agencies only.
  final String? fullName;
  const StaffDept(this.name, {this.isExternal = false, this.fullName});
}

class StaffDepartments {
  StaffDepartments._();

  /// LGU offices that own the citizen report categories.
  static const List<StaffDept> internal = [
    StaffDept('Engineering Office'),
    StaffDept('Sanitation Office'),
    StaffDept('Environment Office'),
    StaffDept("Mayor's Office"),
  ];

  /// External national agencies that receive endorsed, out-of-scope reports.
  static const List<StaffDept> external = [
    StaffDept(
      'DPWH',
      isExternal: true,
      fullName: 'Public Works and Highways',
    ),
    StaffDept(
      'DENR',
      isExternal: true,
      fullName: 'Environment and Natural Resources',
    ),
    StaffDept(
      'DOH',
      isExternal: true,
      fullName: 'Department of Health',
    ),
    StaffDept(
      'BFP',
      isExternal: true,
      fullName: 'Bureau of Fire Protection',
    ),
    StaffDept(
      'PNP',
      isExternal: true,
      fullName: 'Philippine National Police',
    ),
  ];

  static List<StaffDept> get all => [...internal, ...external];

  static bool isExternalName(String? name) =>
      external.any((d) => d.name == name);

  /// "Public Works and Highways" for "DPWH"; null for anything unknown.
  static String? externalFullName(String? name) {
    for (final d in external) {
      if (d.name == name) return d.fullName;
    }
    return null;
  }

  /// The internal office that owns a report [category] key. Mirrors the SQL
  /// `report_department()` function and ConcernCategory.department.
  static String forReportCategory(String? category) {
    switch (category) {
      case 'road':
      case 'drainage':
      case 'streetlight':
        return 'Engineering Office';
      case 'waste':
        return 'Sanitation Office';
      case 'environment':
        return 'Environment Office';
      default:
        return "Mayor's Office";
    }
  }
}
