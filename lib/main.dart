import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/backend_config.dart';
import 'core/firebase_backend_config.dart';
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

  if (FirebaseBackendConfig.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: FirebaseBackendConfig.currentPlatform,
      );
      // The app keeps its own small outbox; don't add a second full history cache.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
    } catch (_) {
      // A Firebase setup issue must not prevent the existing Supabase app from
      // opening. Pending account writes can be retried after configuration.
    }
  }

  final store = await storeFuture;
  runApp(EcoScanApp(store: store));
}
