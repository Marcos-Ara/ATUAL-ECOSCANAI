import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../services/auth_session.dart';
import '../state/ecoscan_store.dart';
import '../widgets/account_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _newEmail = TextEditingController();
  final _currentPassword = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late final AuthSession _auth;
  bool _busy = false;
  bool _nameEdited = false;
  bool _showNewPassword = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthSession>();
    _name.text = _auth.account?.name ?? '';
    _auth.addListener(_syncProfileName);
  }

  @override
  void dispose() {
    _auth.removeListener(_syncProfileName);
    for (final controller in [
      _name,
      _newEmail,
      _currentPassword,
      _password,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncProfileName() {
    final accountName = _auth.account?.name ?? '';
    if (!_nameEdited && accountName.isNotEmpty && _name.text != accountName) {
      _name.value = TextEditingValue(
        text: accountName,
        selection: TextSelection.collapsed(offset: accountName.length),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<String?> Function() work) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await work();
      if (mounted && message != null) {
        setState(() {
          _message = message;
          _messageIsError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error is AuthFailure
              ? error.toString()
              : 'Não foi possível concluir agora. Tente novamente.';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    final store = context.read<EcoScanStore>();
    final uid = store.userId;
    if (uid == null) return;

    await _run(() async {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 88,
      );
      if (selected == null) return null;
      if (kIsWeb) {
        final bytes = await selected.readAsBytes();
        if (store.userId != uid) return null;
        await store.setProfilePhoto(
          'data:image/jpeg;base64,${base64Encode(bytes)}',
        );
        return 'Foto de perfil atualizada.';
      }

      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        p.join(documents.path, 'ecoscan', uid, 'profile'),
      );
      await directory.create(recursive: true);
      final target = p.join(
        directory.path,
        'avatar_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await File(selected.path).copy(target);
      if (store.userId != uid) {
        await File(target).delete();
        return null;
      }
      await store.setProfilePhoto(target);
      return 'Foto de perfil atualizada.';
    });
  }

  Future<void> _saveName() async {
    if (_name.text.trim().isEmpty) {
      setState(() {
        _message = 'Digite o nome que deseja usar no perfil.';
        _messageIsError = true;
      });
      return;
    }
    await _run(() async {
      await _auth.updateProfileName(_name.text);
      _nameEdited = false;
      return 'Nome do perfil salvo na sua conta.';
    });
  }

  Future<void> _requestEmailChange() async {
    await _run(() async {
      final sent = await _auth.requestEmailChange(_newEmail.text);
      if (!sent) return 'Esse já é o e-mail atual da sua conta.';
      _newEmail.clear();
      return 'Solicitação processada. Se o Supabase enviar um link, confirme o novo endereço para concluir a troca.';
    });
  }

  Future<void> _changePassword() async {
    if (_currentPassword.text.isEmpty ||
        _password.text.length < 6 ||
        _password.text != _confirmPassword.text) {
      setState(() {
        _message =
            'Informe a senha atual e confirme uma nova senha com pelo menos 6 caracteres.';
        _messageIsError = true;
      });
      return;
    }
    await _run(() async {
      await _auth.changePassword(_currentPassword.text, _password.text);
      _currentPassword.clear();
      _password.clear();
      _confirmPassword.clear();
      return 'Senha atualizada.';
    });
  }

  Widget _sectionTitle(IconData icon, String title, String subtitle) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text, {required bool error}) {
    final color = error ? AppColors.danger : AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error ? Icons.info_outline : Icons.check_circle_outline,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSession>();
    final account = auth.account;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primaryDark.withValues(alpha: 0.32),
                            Theme.of(context).cardColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              AccountAvatar(
                                radius: 48,
                                onTap: _busy ? null : _photo,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).cardColor,
                                      width: 3,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.edit,
                                    size: 15,
                                    color: colors.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            account?.name.isNotEmpty == true
                                ? account!.name
                                : 'Seu perfil EcoScan',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            account?.email ?? '',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_user_outlined,
                                    size: 15, color: colors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  account?.verified == true
                                      ? 'Conta conectada e verificada'
                                      : 'Conta EcoScan',
                                  style: TextStyle(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _busy ? null : _photo,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Alterar foto'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionTitle(
                      Icons.person_outline,
                      'Informações do perfil',
                      'Escolha como seu nome aparece no EcoScan.',
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _name,
                              enabled: !_busy,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              onChanged: (_) => _nameEdited = true,
                              decoration: const InputDecoration(
                                labelText: 'Nome de perfil',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _busy ? null : _saveName,
                              icon: const Icon(Icons.check),
                              label: const Text('Salvar nome'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle(
                      Icons.alternate_email,
                      'E-mail da conta',
                      'A troca só acontece depois de confirmar o novo endereço.',
                    ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('E-mail atual',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 5),
                            SelectableText(
                              account?.email ?? 'Não disponível',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (auth.pendingEmailChange != null) ...[
                              const SizedBox(height: 12),
                              _notice(
                                'Aguardando confirmação de ${auth.pendingEmailChange}. O e-mail atual continua ativo até você abrir o link enviado.',
                                error: false,
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextField(
                              controller: _newEmail,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Novo e-mail',
                                hintText: 'voce@exemplo.com',
                                prefixIcon: Icon(Icons.mark_email_unread_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _requestEmailChange,
                              icon: const Icon(Icons.send_outlined),
                              label: const Text('Enviar confirmação'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Confira também a caixa de spam. A entrega depende das configurações de e-mail do Supabase.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle(
                      Icons.lock_outline,
                      'Segurança',
                      'Mantenha sua conta protegida.',
                    ),
                    Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.password_outlined),
                        title: const Text('Alterar senha'),
                        subtitle: const Text('Atualize sua senha de acesso'),
                        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        children: [
                          TextField(
                            controller: _currentPassword,
                            enabled: !_busy,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Senha atual',
                              prefixIcon: Icon(Icons.lock_open_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: !_showNewPassword,
                            decoration: InputDecoration(
                              labelText: 'Nova senha',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _showNewPassword = !_showNewPassword,
                                ),
                                icon: Icon(_showNewPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirmPassword,
                            enabled: !_busy,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Confirmar nova senha',
                              prefixIcon: Icon(Icons.verified_user_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.tonal(
                            onPressed: _busy ? null : _changePassword,
                            child: const Text('Atualizar senha'),
                          ),
                          TextButton(
                            onPressed: _busy || account?.email.isNotEmpty != true
                                ? null
                                : () => _run(() async {
                                    await _auth.resetPassword(account!.email);
                                    return 'Link de recuperação enviado para ${account.email}.';
                                  }),
                            child: const Text('Enviar link de recuperação'),
                          ),
                        ],
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_message != null)
                      _notice(_message!, error: _messageIsError),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
