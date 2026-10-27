import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Firebase application options. Privileged service-account credentials
/// must never be placed in this app.
abstract final class FirebaseBackendConfig {
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'ecoscanai-66682',
  );
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'ecoscanai-66682.firebaseapp.com',
  );
  static const androidAppId = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const iosAppId = String.fromEnvironment('FIREBASE_APP_ID_IOS');
  static const webAppId = String.fromEnvironment('FIREBASE_APP_ID_WEB');

  static bool get isConfigured {
    final appId = kIsWeb
        ? webAppId
        : defaultTargetPlatform == TargetPlatform.iOS
        ? iosAppId
        : androidAppId;
    return apiKey.isNotEmpty &&
        messagingSenderId.isNotEmpty &&
        projectId.isNotEmpty &&
        storageBucket.isNotEmpty &&
        appId.isNotEmpty;
  }

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('As opções públicas do Firebase ainda não foram preenchidas.');
    }
    final appId = kIsWeb
        ? webAppId
        : defaultTargetPlatform == TargetPlatform.iOS
        ? iosAppId
        : androidAppId;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket,
      authDomain: kIsWeb ? authDomain : null,
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
          ? 'br.com.ecoscan.ecoscanMobile'
          : null,
    );
  }
}
