import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/backend_config.dart';
import 'state/ecoscan_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storeFuture = EcoScanStore.load();

  await Supabase.initialize(
    url: BackendConfig.supabaseUrl,
    publishableKey: BackendConfig.supabasePublicKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
    debug: false,
  );

  final store = await storeFuture;
  runApp(EcoScanApp(store: store));
}
