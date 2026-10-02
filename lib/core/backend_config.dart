/// Public client configuration used by EcoScan.
///
/// Only the Supabase project URL and publishable key are required in the app.
/// Never place a Supabase service-role key here.
abstract final class BackendConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kekcfxoiyufskltnzlie.supabase.co',
  );

  static const supabasePublicKey = String.fromEnvironment(
    'SUPABASE_PUBLIC_KEY',
    defaultValue: 'sb_publishable_dj-ppXJKqhWAU7YkeV3BbQ_Fz1ORIKV',
  );

  /// Deep link used by Supabase Auth to return to Android/iOS after OAuth,
  /// e-mail confirmation and password recovery.
  static const mobileAuthRedirect = String.fromEnvironment(
    'SUPABASE_MOBILE_REDIRECT',
    defaultValue: 'ecoscan://login-callback/',
  );
}
