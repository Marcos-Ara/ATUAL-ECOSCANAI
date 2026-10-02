import 'dart:io';
import 'dart:ui' as ui;

import 'package:ecoscan_mobile/core/app_theme.dart';
import 'package:ecoscan_mobile/screens/auth_screen.dart';
import 'package:ecoscan_mobile/screens/main_shell.dart';
import 'package:ecoscan_mobile/screens/session_gate.dart';
import 'package:ecoscan_mobile/screens/scanner_screen.dart';
import 'package:ecoscan_mobile/screens/profile_screen.dart';
import 'package:ecoscan_mobile/screens/history_screen.dart';
import 'package:ecoscan_mobile/screens/community_screens.dart';
import 'package:ecoscan_mobile/screens/settings_screen.dart';
import 'package:ecoscan_mobile/services/auth_session.dart';
import 'package:ecoscan_mobile/state/ecoscan_store.dart';
import 'package:ecoscan_mobile/widgets/eco_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Outfit')
      ..addFont(rootBundle.load('assets/fonts/Outfit.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  Future<Widget> host(
    Widget screen, {
    bool signedIn = false,
    bool verified = true,
    bool light = false,
  }) async {
    final store = await EcoScanStore.load();
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() {
      client.auth.dispose();
    });
    final auth = AuthSession(client: client);
    if (signedIn) {
      auth.account = Account(
        uid: 'preview-user',
        email: 'marcos@example.com',
        name: 'Marcos Vinicius',
        verified: verified,
      );
      store.switchUser('preview-user');
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EcoScanStore>(create: (_) => store),
        ChangeNotifierProvider<AuthSession>(create: (_) => auth),
      ],
      child: RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.light : AppTheme.dark,
          home: screen,
        ),
      ),
    );
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('EXPORT_PREVIEWS')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('verification/previews').create(recursive: true);
      await File(
        'verification/previews/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('intro aparece antes do login e oferece modo visitante', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await host(const SessionGate()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Escaneie. Descubra. Descarte melhor.'), findsOneWidget);
    await screenshot(tester, '01-intro');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Entre na sua conta'), findsOneWidget);
    expect(find.text('Continuar sem conta'), findsOneWidget);
    expect(find.text('Iniciar Escaneamento'), findsNothing);
    await screenshot(tester, '02-login');

    await tester.ensureVisible(find.text('Continuar sem conta'));
    await tester.tap(find.text('Continuar sem conta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Visitante'), findsWidgets);
    expect(find.text('Iniciar Escaneamento'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cadastro oferece confirmação de senha', (tester) async {
    await tester.pumpWidget(await host(const AuthScreen()));
    await tester.tap(find.text('Criar Conta'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar senha'), findsOneWidget);
    expect(find.text('Nome'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home da web e menu cabem em tela pequena e tema claro', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await host(const MainShell(), signedIn: true));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Marcos!'), findsOneWidget);
    expect(find.text('Estatísticas'), findsOneWidget);
    expect(find.text('Conquistas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, '03-inicio');
    await tester.pumpWidget(
      await host(const MainShell(), signedIn: true, light: true),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await screenshot(tester, '04-inicio-claro');
  });

  testWidgets('sem câmera a galeria continua disponível', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/camera'),
          (_) async => throw PlatformException(code: 'CameraAccessDenied'),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('google_mlkit_image_labeler'),
          (_) async => null,
        );
    await tester.pumpWidget(
      await host(const Scaffold(body: ScannerScreen()), signedIn: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Galeria'), findsOneWidget);
    expect(find.textContaining('Permita a câmera'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('exportar marca para ícones nativos', (tester) async {
    if (!const bool.fromEnvironment('EXPORT_PREVIEWS')) return;
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const RepaintBoundary(
        key: ValueKey('capture'),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: Color(0xFF071008),
            child: Center(child: EcoBrand(size: 960)),
          ),
        ),
      ),
    );
    await tester.pump();
    await screenshot(tester, 'brand');
  });

  testWidgets('telas de conta e conteúdo abrem sem erro em 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final screens = <Widget>[
      const VerificationScreen(),
      const ProfileScreen(),
      const HistoryScreen(),
      const StatsScreen(),
      const LearnScreen(),
      const AchievementsScreen(),
      const CreatorsScreen(),
      Scaffold(body: SettingsScreen(onOpenMap: () {})),
    ];
    for (final screen in screens) {
      await tester.pumpWidget(await host(screen, signedIn: true));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: screen.runtimeType.toString(),
      );
      if (screen is ProfileScreen) await screenshot(tester, '05-perfil');
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final size in [
    const Size(320, 568),
    const Size(430, 932),
    const Size(844, 390),
    const Size(768, 1024),
    const Size(1366, 768),
  ]) {
    testWidgets(
      'login, cadastro, início e perfil em ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in [
          const AuthScreen(),
          const MainShell(),
          const ProfileScreen(),
        ]) {
          await tester.pumpWidget(await host(screen, signedIn: true));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType} em $size',
          );
          if (screen is AuthScreen) {
            await tester.ensureVisible(find.text('Criar Conta'));
            await tester.tap(find.text('Criar Conta'));
            await tester.pumpAndSettle();
            expect(find.text('Confirmar senha'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
