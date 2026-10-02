import 'package:ecoscan_mobile/services/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('mensagens de autenticação continuam amigáveis', () {
    expect(const AuthFailure('INVALID_CREDENTIALS').toString(), 'E-mail ou senha incorretos.');
    expect(const AuthFailure('EMAIL_NOT_CONFIRMED').toString(), 'Confirme seu e-mail antes de entrar.');
    expect(const AuthFailure('GOOGLE_CONFIG').toString(), contains('Supabase'));
    expect(const AuthFailure('GOOGLE_EXCHANGE').toString(), contains('Client ID'));
  });

  test('modo visitante entra sem criar sessão Supabase', () {
    final auth = AuthSession(
      client: SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
      ),
    );
    addTearDown(auth.dispose);

    auth.continueAsGuest();
    expect(auth.isGuest, isTrue);
    expect(auth.account, isNull);
    expect(auth.guestMode, isTrue);

    auth.leaveGuest();
    expect(auth.isGuest, isFalse);
  });

}
