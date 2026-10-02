import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

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
  final _email = TextEditingController();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    final user = context.read<AuthSession>().account;
    _name.text = user?.name ?? '';
    _email.text = user?.email ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _current, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work, String success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
      if (mounted) setState(() => _message = success);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is AuthFailure
              ? error.toString()
              : 'Não foi possível salvar. Tente novamente.',
        );
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
      if (selected == null) return;
      if (kIsWeb) {
        final bytes = await selected.readAsBytes();
        if (store.userId != uid) return;
        await store.setProfilePhoto(
          'data:image/jpeg;base64,${base64Encode(bytes)}',
        );
        return;
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
        return;
      }
      await store.setProfilePhoto(target);
    }, 'Foto de perfil atualizada neste aparelho.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Meu perfil')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Stack(
            children: [
              AccountAvatar(radius: 52, onTap: _busy ? null : _photo),
              const Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 15,
                  child: Icon(Icons.camera_alt, size: 17),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : _photo,
          child: const Text('Alterar foto'),
        ),
        const SizedBox(height: 14),
        Text('Dados pessoais', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (_name.text.trim().isEmpty || !_email.text.contains('@')) {
                    setState(
                      () => _message = 'Preencha seu nome e um e-mail válido.',
                    );
                    return;
                  }
                  final auth = context.read<AuthSession>();
                  final changed = _email.text.trim() != auth.account?.email;
                  _run(
                    () => auth.updateProfile(_name.text, _email.text),
                    changed
                        ? 'Nome salvo. Confirme o link enviado ao novo e-mail para concluir a alteração.'
                        : 'Perfil atualizado.',
                  );
                },
          child: const Text('Salvar alterações'),
        ),
        const SizedBox(height: 24),
        Text('Alterar senha', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _current,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Senha atual'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nova senha'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirmar nova senha'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () {
                  if (_current.text.isEmpty ||
                      _password.text.length < 6 ||
                      _password.text != _confirm.text) {
                    setState(
                      () => _message = 'Informe a senha atual e confirme uma nova senha com pelo menos 6 caracteres.',
                    );
                    return;
                  }
                  _run(() async {
                    await context.read<AuthSession>().changePassword(
                      _current.text,
                      _password.text,
                    );
                    _current.clear();
                    _password.clear();
                    _confirm.clear();
                  }, 'Senha atualizada.');
                },
          child: const Text('Atualizar senha'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => context.read<AuthSession>().resetPassword(
                    context.read<AuthSession>().account!.email,
                  ),
                  'Link de recuperação enviado.',
                ),
          child: const Text('Receber link de recuperação'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(_message!, textAlign: TextAlign.center),
          ),
      ],
    ),
  );
}
