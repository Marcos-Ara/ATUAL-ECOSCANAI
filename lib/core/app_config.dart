abstract final class AppConfig {
  static const appName = 'EcoScan AI';
  static const packageName = 'br.com.ecoscan.ecoscan_mobile';
  static const defaultLatitude = -23.5505;
  static const defaultLongitude = -46.6333;
  static const requestTimeout = Duration(seconds: 9);
  static const useSupabaseModel = bool.fromEnvironment(
    'ECOSCAN_USE_SUPABASE_MODEL',
    defaultValue: true,
  );
}
