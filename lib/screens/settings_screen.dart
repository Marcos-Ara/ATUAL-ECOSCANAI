import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_session.dart';
import '../services/learning_sync_service.dart';
import '../state/ecoscan_store.dart';
import 'profile_screen.dart';
import 'community_screens.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.onOpenMap, super.key});
  final VoidCallback onOpenMap;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<EcoScanStore>();
    final auth = context.watch<AuthSession>();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Configurações',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Tema escuro'),
            value: store.darkMode,
            onChanged: store.setDarkMode,
          ),
          SwitchListTile(
            title: const Text('Avisos do aplicativo'),
            subtitle: const Text('Confirmações dentro do EcoScan'),
            value: store.notifications,
            onChanged: store.setNotifications,
          ),
          SwitchListTile(
            title: const Text('Sons do EcoScan'),
            value: store.sounds,
            onChanged: store.setSounds,
          ),
          if (auth.isGuest)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Modo visitante'),
              subtitle: const Text(
                'Sem conta: histórico e preferências ficam neste dispositivo.',
              ),
              trailing: const Icon(Icons.login_rounded),
              onTap: () {
                store.switchUser(null);
                auth.leaveGuest();
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Meu perfil'),
              subtitle: const Text('Nome, foto, e-mail e senha'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
            ),
          const ListTile(
            leading: Icon(Icons.language),
            title: Text('Idioma: Português (BR)'),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Criadores do projeto'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const CreatorsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Abrir EcoPontos'),
            onTap: onOpenMap,
          ),
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('Amostras locais para melhoria'),
            subtitle: Text(
              '${store.learningSampleCount}/30 leituras inconclusivas · sem envio automático',
            ),
            trailing: const Icon(Icons.lock_outline),
          ),
          if (store.learningSampleCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: auth.isGuest
                        ? null
                        : () => _uploadLearning(context, store),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      auth.isGuest
                          ? 'Entre para enviar'
                          : 'Enviar com consentimento',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _clearLearning(context, store),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Apagar do aparelho'),
                  ),
                ],
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              auth.isGuest ? 'Sair do modo visitante' : 'Sair da conta',
              style: const TextStyle(color: Colors.redAccent),
            ),
            onTap: () async {
              store.switchUser(null);
              await auth.signOut();
            },
          ),
        ],
      ),
    );
  }

  static Future<void> _clearLearning(
    BuildContext context,
    EcoScanStore store,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar amostras locais?'),
        content: const Text(
          'Essas imagens reduzidas ficam somente neste aparelho e ajudam a '
          'preparar um futuro conjunto de treinamento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (approved == true) await store.clearLearningSamples();
  }

  static Future<void> _uploadLearning(
    BuildContext context,
    EcoScanStore store,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar para revisão?'),
        content: const Text(
          'As miniaturas e caixas sugeridas serão enviadas ao Supabase para '
          'revisão humana. Nada é usado para treinar automaticamente e as '
          'amostras locais só serão removidas após o envio confirmado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Concordo e enviar'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    try {
      final uploaded = await LearningSyncService().uploadWithConsent(
        List.of(store.learningSamples),
      );
      await store.removeLearningSamples(uploaded);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${uploaded.length} amostras enviadas para revisão.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível enviar. As amostras continuam no aparelho.',
            ),
          ),
        );
      }
    }
  }
}
