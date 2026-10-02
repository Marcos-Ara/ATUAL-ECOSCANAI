import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/backend_config.dart';

class Account {
  const Account({
    required this.uid,
    required this.email,
    required this.name,
    required this.verified,
  });

  final String uid;
  final String email;
  final String name;
  final bool verified;

  factory Account.fromSupabase(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final email = user.email ?? '';

    final name = (metadata['full_name'] ?? metadata['name'] ?? '')
        .toString()
        .trim();

    return Account(
      uid: user.id,
      email: email,
      name: name.isNotEmpty
          ? name
          : (email.contains('@') ? email.split('@').first : ''),
      verified: user.emailConfirmedAt != null,
    );
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.code, [this.details]);

  final String code;
  final String? details;

  @override
  String toString() => switch (code) {
        'INVALID_CREDENTIALS' => 'E-mail ou senha incorretos.',
        'EMAIL_EXISTS' => 'Este e-mail já possui uma conta.',
        'INVALID_EMAIL' => 'Digite um e-mail válido.',
        'WEAK_PASSWORD' => 'Use uma senha com pelo menos 6 caracteres.',
        'TOO_MANY_REQUESTS' =>
          'Muitas tentativas. Aguarde e tente novamente.',
        'EMAIL_NOT_CONFIRMED' =>
          'Confirme seu e-mail antes de entrar.',
        'SESSION_EXPIRED' =>
          'Sua sessão expirou. Entre novamente.',
        'NETWORK' =>
          'Sem conexão com o serviço. Confira a internet e tente novamente.',
        'GOOGLE_CONFIG' =>
          'O login com Google ainda precisa ser habilitado e configurado no Supabase.',
        'GOOGLE_EXCHANGE' =>
          'O Google respondeu, mas o Supabase não conseguiu concluir o login. Confira o Client ID e o Client Secret do Google no Supabase e tente novamente.',
        'CANCELED' => 'Acesso cancelado.',
        _ => details?.isNotEmpty == true
            ? 'Não foi possível concluir: $details'
            : 'Não foi possível concluir. Tente novamente.',
      };
}

class AuthSession extends ChangeNotifier {
  static const guestUserId = 'guest-local';

  // ============================================================
  // REDIRECT DO APP MOBILE
  // ============================================================
  //
  // Depois de:
  // - confirmar o e-mail
  // - entrar com Google
  // - redefinir a senha
  // - alterar o e-mail
  //
  // o Supabase deve voltar para o EcoScan.
  //
  static const String _mobileAuthRedirect =
      BackendConfig.mobileAuthRedirect;

  AuthSession({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    // Supabase Flutter already restores the locally persisted session during
    // initialization. Start from that value instead of running a second restore
    // pass from the UI, which caused duplicate auth-state rebuilds.
    _applyUser(_client.auth.currentUser);

    _authSubscription = _client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          passwordRecovery = true;
        } else if (data.event == AuthChangeEvent.signedOut) {
          passwordRecovery = false;
        }

        _applyUser(
          data.session?.user ?? _client.auth.currentUser,
        );

        if (data.event == AuthChangeEvent.signedIn) {
          authNotice = null;
        }

        // A completed auth event means any pending Google launch is over.
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.initialSession ||
            data.event == AuthChangeEvent.signedOut) {
          _clearGoogleGuard(notify: false);
        }

        notifyListeners();
      },
      onError: (Object error, StackTrace _) {
        // OAuth callback errors must never lock the whole application on an
        // error screen. Keep the user on the login page and show an actionable
        // message instead. A new Google attempt will replace the failed callback
        // URL in the browser.
        final failure = _failureFor(error);

        authNotice = failure.toString();

        _clearGoogleGuard(notify: false);

        notifyListeners();
      },
    );
  }

  final SupabaseClient _client;

  late final StreamSubscription<AuthState> _authSubscription;

  Timer? _googleGuardTimer;

  Account? account;

  String? authNotice;

  bool googleBusy = false;

  bool passwordRecovery = false;

  bool guestMode = false;

  bool get isGuest => guestMode && account == null;

  bool get googleReady =>
      BackendConfig.supabaseUrl.isNotEmpty &&
      BackendConfig.supabasePublicKey.isNotEmpty;

  // ============================================================
  // URL DE RETORNO
  // ============================================================

  String get _redirectUrl {
    if (kIsWeb) {
      return Uri.base.origin;
    }

    return _mobileAuthRedirect;
  }

  void _applyUser(User? user) {
    if (user == null) {
      account = null;
      return;
    }

    // A real Supabase session always wins over the local visitor session.
    guestMode = false;

    account = Account.fromSupabase(user);
  }

  void continueAsGuest() {
    _clearGoogleGuard(notify: false);

    authNotice = null;

    passwordRecovery = false;

    account = null;

    guestMode = true;

    notifyListeners();
  }

  void leaveGuest() {
    if (!guestMode) return;

    guestMode = false;

    authNotice = null;

    notifyListeners();
  }

  AuthFailure _failureFor(Object error) {
    if (error is AuthFailure) return error;

    if (error is AuthException) {
      final message = error.message.toLowerCase();

      if (message.contains('invalid login credentials') ||
          message.contains('invalid credentials')) {
        return const AuthFailure('INVALID_CREDENTIALS');
      }

      if (message.contains('email not confirmed')) {
        return const AuthFailure('EMAIL_NOT_CONFIRMED');
      }

      if (message.contains('already registered') ||
          message.contains('already been registered')) {
        return const AuthFailure('EMAIL_EXISTS');
      }

      if (message.contains('valid email') ||
          message.contains('invalid email')) {
        return const AuthFailure('INVALID_EMAIL');
      }

      if (message.contains('password') &&
          (message.contains('6') || message.contains('weak'))) {
        return const AuthFailure('WEAK_PASSWORD');
      }

      if (message.contains('rate limit') ||
          message.contains('too many')) {
        return const AuthFailure('TOO_MANY_REQUESTS');
      }

      if (message.contains('unable to exchange external code') ||
          message.contains('unexpected_failure') ||
          message.contains('oauth callback')) {
        return const AuthFailure('GOOGLE_EXCHANGE');
      }

      if (message.contains('session') ||
          message.contains('jwt')) {
        return const AuthFailure('SESSION_EXPIRED');
      }

      return AuthFailure(
        'AUTH',
        error.message,
      );
    }

    final text = error.toString().toLowerCase();

    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('failed host lookup')) {
      return const AuthFailure('NETWORK');
    }

    return AuthFailure(
      'UNKNOWN',
      error.toString(),
    );
  }

  Future<void> reload() async {
    try {
      final response = await _client.auth.getUser();

      _applyUser(response.user);

      notifyListeners();
    } catch (error) {
      throw _failureFor(error);
    }
  }

  // ============================================================
  // LOGIN E-MAIL / SENHA
  // ============================================================

  Future<void> signIn(
    String email,
    String password,
  ) async {
    guestMode = false;

    authNotice = null;

    try {
      final response =
          await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      _applyUser(response.user);

      notifyListeners();
    } catch (error) {
      throw _failureFor(error);
    }
  }

  // ============================================================
  // CADASTRO
  // ============================================================

  Future<void> register(
    String name,
    String email,
    String password,
  ) async {
    guestMode = false;

    authNotice = null;

    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,

        // IMPORTANTE:
        // Depois que o usuário clicar no e-mail de confirmação,
        // o Android abrirá novamente o EcoScan.
        emailRedirectTo: _redirectUrl,

        data: {
          'full_name': name.trim(),
        },
      );

      _applyUser(response.user);

      notifyListeners();
    } catch (error) {
      throw _failureFor(error);
    }
  }

  // ============================================================
  // REENVIAR E-MAIL DE CONFIRMAÇÃO
  // ============================================================

  Future<void> sendVerification() async {
    final email = account?.email;

    if (email == null || email.isEmpty) {
      throw const AuthFailure(
        'SESSION_EXPIRED',
      );
    }

    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,

        // O e-mail reenviado também volta para o EcoScan.
        emailRedirectTo: _redirectUrl,
      );
    } catch (error) {
      throw _failureFor(error);
    }
  }

  // ============================================================
  // RECUPERAÇÃO DE SENHA
  // ============================================================

  Future<void> resetPassword(
    String email,
  ) async {
    authNotice = null;

    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _redirectUrl,
      );
    } catch (error) {
      throw _failureFor(error);
    }
  }

  // ============================================================
  // ATUALIZAR PERFIL
  // ============================================================

  Future<void> updateProfile(
    String name,
    String email,
  ) async {
    try {
      final currentEmail = account?.email ?? '';

      final response =
          await _client.auth.updateUser(
        UserAttributes(
          email: email.trim() == currentEmail
              ? null
              : email.trim(),
          data: {
            'full_name': name.trim(),
          },
        ),

        emailRedirectTo: _redirectUrl,
      );

      _applyUser(response.user);

      notifyListeners();
    } catch (error) {
      throw _failureFor(error);
    }
  }

  // ============================================================
  // ALTERAR SENHA
  // ============================================================

  Future<void> changePassword(
    String current,
    String next,
  ) async {
    try {
      final response =
          await _client.auth.updateUser(
        UserAttributes(
          password: next,
          currentPassword: current,
        ),
      );

      _applyUser(response.user);

      notifyListeners();
    } catch (error) {
      throw _failureFor(error);
    }
  }

  // ============================================================
  // FINALIZAR RECUPERAÇÃO DE SENHA
  // ============================================================

  Future<void> completePasswordRecovery(
    String next,
  ) async {
    try {
      final response =
          await _client.auth.updateUser(
        UserAttributes(
          password: next,
        ),
      );

      _applyUser(response.user);

      passwordRecovery = false;

      notifyListeners();
    } catch (error) {
      throw _failureFor(error);
    }
  }

  void _clearGoogleGuard({
    bool notify = true,
  }) {
    _googleGuardTimer?.cancel();

    _googleGuardTimer = null;

    if (!googleBusy) return;

    googleBusy = false;

    if (notify) {
      notifyListeners();
    }
  }

  void clearAuthNotice() {
    if (authNotice == null) return;

    authNotice = null;

    notifyListeners();
  }

  // ============================================================
  // LOGIN GOOGLE
  // ============================================================

  Future<void> signInGoogle() async {
    guestMode = false;

    // Prevent two OAuth requests from being launched by a double click or a
    // rebuild while the browser is opening. There is only one Google auth path.
    if (googleBusy) return;

    if (!googleReady) {
      throw const AuthFailure(
        'GOOGLE_CONFIG',
      );
    }

    if (_client.auth.currentSession != null) {
      return;
    }

    authNotice = null;

    googleBusy = true;

    notifyListeners();

    try {
      final started =
          await _client.auth.signInWithOAuth(
        OAuthProvider.google,

        // WEB:
        // retorna para o domínio do site.
        //
        // ANDROID:
        // retorna para ecoscan://login-callback/
        redirectTo: _redirectUrl,

        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,

        queryParams: const {
          'prompt': 'select_account',
        },
      );

      if (!started) {
        throw const AuthFailure(
          'CANCELED',
        );
      }

      // On web the page normally redirects immediately. On mobile, if the
      // external auth screen is cancelled, allow a new attempt after a while.
      _googleGuardTimer?.cancel();

      _googleGuardTimer =
          Timer(
        const Duration(seconds: 30),
        () {
          if (account == null) {
            _clearGoogleGuard();
          }
        },
      );
    } catch (error) {
      _clearGoogleGuard();

      throw _failureFor(error);
    }
  }

  // ============================================================
  // SAIR
  // ============================================================

  Future<void> signOut() async {
    _clearGoogleGuard(
      notify: false,
    );

    authNotice = null;

    if (guestMode) {
      guestMode = false;

      account = null;

      notifyListeners();

      return;
    }

    try {
      await _client.auth.signOut();
    } catch (error) {
      throw _failureFor(error);
    } finally {
      account = null;

      notifyListeners();
    }
  }

  @override
  void dispose() {
    _googleGuardTimer?.cancel();

    _authSubscription.cancel();

    super.dispose();
  }
}