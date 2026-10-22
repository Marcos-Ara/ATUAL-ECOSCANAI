import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../services/auth_session.dart';
import '../state/ecoscan_store.dart';
import 'learning_samples_review_screen.dart';
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
            title: const Text('Avisos dentro do app'),
            subtitle: const Text(
              'Mensagens na tela; não são notificações do celular.',
            ),
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
            leading: const Icon(Icons.language_outlined),
            title: const Text('Acessar página web'),
            subtitle: const Text('Abrir o EcoScan AI no navegador'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openWebPage(context),
          ),
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('Correções e amostras para melhoria'),
              subtitle: Text(
                '${auth.isGuest || !AppConfig.syncSupabaseHistory ? 'Salvas neste aparelho' : 'Sincronização da conta ativa'} · ${store.learningSampleCount} ${store.learningSampleCount == 1 ? 'correção' : 'correções'} · envio para treinamento só com seu consentimento',
              ),
            trailing: const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF8FE69A),
            ),
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
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const LearningSamplesReviewScreen(),
                            ),
                          ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      auth.isGuest
                          ? 'Entre para enviar'
                          : 'Revisar e escolher amostras',
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
          'Esta ação apaga a cópia deste aparelho. Correções já sincronizadas '
          'continuam na sua conta. O envio para revisão e treinamento exige '
          'seu consentimento.',
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

  static Future<void> _openWebPage(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(AppConfig.webUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a página web.')),
      );
    }
  }

}
