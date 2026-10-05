import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';

class DownloadScreen extends StatelessWidget {
  const DownloadScreen({super.key});

  Uri? get _downloadUri {
    final uri = Uri.tryParse(AppConfig.apkDownloadUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  Future<void> _download(BuildContext context, Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o link de download.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = _downloadUri;
    final ready = uri != null;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            children: [
              Text(
                'ECO SCAN AI  ·  ANDROID',
                style: textTheme.labelLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text('Baixe o EcoScan', style: textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Leve a reciclagem inteligente com você. Encontre aqui a versão oficial mais recente para Android.',
                style: textTheme.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 24),
              Container(
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF173D25), Color(0xFF0D2014)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF376847)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -58,
                      right: -50,
                      child: Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.eco_rounded,
                            color: Color(0xFF8BE99D),
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          ready
                              ? 'Pronto para instalar?'
                              : 'Seu próximo passo mais verde',
                          style: textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ready
                              ? 'Baixe o arquivo oficial do EcoScan AI e instale no seu Android.'
                              : 'Assim que a nova versão estiver publicada, o link oficial vai aparecer aqui.',
                          style: textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFFD0E4D3),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: uri == null
                              ? null
                              : () => _download(context, uri),
                          icon: Icon(
                            ready
                                ? Icons.download_rounded
                                : Icons.hourglass_top_rounded,
                          ),
                          label: Text(ready ? 'Baixar APK' : 'APK em breve'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFC8F2D0),
                            foregroundColor: const Color(0xFF102A17),
                            disabledBackgroundColor: const Color(0xFF526B59),
                            disabledForegroundColor: const Color(0xFFE1E9E2),
                            minimumSize: const Size(0, 52),
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        ready
                            ? Icons.verified_outlined
                            : Icons.info_outline_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ready
                                  ? 'Link oficial disponível'
                                  : 'Nova versão em preparação',
                              style: textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ready
                                  ? 'Este botão abre o endereço de download da versão atual.'
                                  : 'Volte em breve para conferir o lançamento mais recente.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _FeaturePill(
                    icon: Icons.phone_android_rounded,
                    label: 'Android',
                  ),
                  _FeaturePill(
                    icon: Icons.eco_outlined,
                    label: 'Reciclagem inteligente',
                  ),
                  _FeaturePill(
                    icon: Icons.system_update_alt_rounded,
                    label: 'Versão oficial',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    ),
  );
}
