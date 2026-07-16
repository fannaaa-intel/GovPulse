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
  const StaffDept(this.name, {this.isExternal = false});
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
    StaffDept('DPWH', isExternal: true), // Public Works & Highways
    StaffDept('DENR', isExternal: true), // Environment & Natural Resources
    StaffDept('DOH', isExternal: true), //  Health
    StaffDept('BFP', isExternal: true), //  Bureau of Fire Protection
    StaffDept('PNP', isExternal: true), //  Philippine National Police
  ];

  static List<StaffDept> get all => [...internal, ...external];

  static bool isExternalName(String? name) =>
      external.any((d) => d.name == name);

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
