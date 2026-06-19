import 'package:supabase/supabase.dart';

Future<void> main() async {
  final supabase = SupabaseClient(
    'https://vxvflhjbafqwehuxnmeq.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ4dmZsaGpiYWZxd2VodXhubWVxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MzA1MTE5NywiZXhwIjoyMDg4NjI3MTk3fQ.Ngh1gnz5G9SmMJwig2FwFR75Kh6pjsX01JvGcaoPUes',
  );

  // [ source in verification-assets , destination in profile-photos ]
  final jobs = <List<String>>[
    [
      '76159d2c-4eda-4919-abdd-4569cfbde326/profile_1780383405926.jpg',
      '76159d2c-4eda-4919-abdd-4569cfbde326/profile_1780383405926.jpg',
    ],
    [
      '4a41b350-1d3f-41a9-9d82-cef9a422a056/profile_1780796825600.jpg',
      '4a41b350-1d3f-41a9-9d82-cef9a422a056/profile_1780796825600.jpg',
    ],
    [
      '384dfd84-efad-488a-8632-5b46e3fbf3d7/profile_1780383037973.jpg',
      '384dfd84-efad-488a-8632-5b46e3fbf3d7/profile_1781571931047.jpg',
    ],
  ];

  for (final j in jobs) {
    try {
      final bytes = await supabase.storage
          .from('verification-assets')
          .download(j[0]);
      await supabase.storage
          .from('profile-photos')
          .uploadBinary(
            j[1],
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      // ignore: empty_catches
    } catch (e) {}
  }
}
