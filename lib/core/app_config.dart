abstract final class AppConfig {
  static const appName = 'EcoScan AI';
  static const packageName = 'br.com.ecoscan.ecoscan_mobile';
  static const webUrl = 'https://ecoscanai-66682.web.app';
  static const apkDownloadUrl = String.fromEnvironment(
    'ECOSCAN_APK_DOWNLOAD_URL',
    defaultValue: '',
  );
  static const defaultLatitude = -23.5505;
  static const defaultLongitude = -46.6333;
  static const requestTimeout = Duration(seconds: 9);

  // Durante a validação do scanner, Supabase fica somente para autenticação.
  // Os recursos abaixo continuam prontos para serem reativados depois que o
  // banco definitivo for criado.
  static const useSupabaseModel = bool.fromEnvironment(
    'ECOSCAN_USE_SUPABASE_MODEL',
    defaultValue: false,
  );
  static const useSupabaseCatalog = bool.fromEnvironment(
    'ECOSCAN_USE_SUPABASE_CATALOG',
    defaultValue: false,
  );
  static const useSupabaseEcoPoints = bool.fromEnvironment(
    'ECOSCAN_USE_SUPABASE_ECOPOINTS',
    defaultValue: false,
  );
  static const syncSupabaseHistory = bool.fromEnvironment(
    'ECOSCAN_SYNC_SUPABASE_HISTORY',
    defaultValue: false,
  );
}
