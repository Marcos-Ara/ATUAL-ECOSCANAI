import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/firebase_backend_config.dart';

/// Reuses the existing Supabase account ID as the Firebase UID. A trusted
/// Supabase Edge Function validates the Supabase session and mints the token.
abstract final class FirebaseSessionBridge {
  static Future<bool>? _pendingSync;

  static Future<bool> syncCurrentSession() {
    final pending = _pendingSync;
    if (pending != null) return pending;
    final operation = _syncCurrentSession();
    _pendingSync = operation;
    return operation.whenComplete(() {
      if (identical(_pendingSync, operation)) _pendingSync = null;
    });
  }

  static Future<bool> _syncCurrentSession() async {
    if (!FirebaseBackendConfig.isConfigured || Firebase.apps.isEmpty) {
      return false;
    }

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final expectedUid = session?.user.id;
    final auth = FirebaseAuth.instance;
    if (expectedUid == null) {
      if (auth.currentUser != null) await auth.signOut();
      return false;
    }
    if (auth.currentUser?.uid == expectedUid) return true;

    final response = await client.functions.invoke('firebase-custom-token');
    final data = response.data;
    final customToken = data is Map ? data['customToken']?.toString() : null;
    if (response.status < 200 ||
        response.status >= 300 ||
        customToken == null ||
        customToken.isEmpty) {
      throw StateError('Não foi possível abrir a sessão segura do Firebase.');
    }
    if (client.auth.currentUser?.id != expectedUid) return false;

    final credential = await auth.signInWithCustomToken(customToken);
    if (credential.user?.uid != expectedUid ||
        client.auth.currentUser?.id != expectedUid) {
      await auth.signOut();
      if (client.auth.currentUser?.id != expectedUid) return false;
      throw StateError('A conta do Firebase não corresponde à conta EcoScan.');
    }
    return true;
  }
}
