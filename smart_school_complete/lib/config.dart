/// Values are passed at build time, never hard-coded:
/// flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=SCHOOL_NAME="..."
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const schoolName = String.fromEnvironment('SCHOOL_NAME', defaultValue: 'S.K. PU College');
  static bool get isConfigured => supabaseUrl.isNotEmpty && anonKey.isNotEmpty;
}
