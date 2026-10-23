class AchievementProgress {
  const AchievementProgress({
    required this.id,
    required this.icon,
    required this.title,
    required this.current,
    required this.target,
    this.previouslyUnlocked = false,
  });

  final String id;
  final String icon;
  final String title;
  final int current;
  final int target;
  final bool previouslyUnlocked;

  int get displayedCurrent =>
      previouslyUnlocked ? target : current.clamp(0, target).toInt();
  bool get isUnlocked => previouslyUnlocked || current >= target;
  double get fraction =>
      previouslyUnlocked ? 1 : (current / target).clamp(0.0, 1.0).toDouble();

  static List<AchievementProgress> build({
    required int scans,
    required int categories,
    required bool exploredMap,
    Set<String> previouslyUnlocked = const <String>{},
  }) => [
    AchievementProgress(
      id: 'primeiro_scan',
      icon: '🌱',
      title: 'Primeiro Scan',
      current: scans,
      target: 1,
      previouslyUnlocked: previouslyUnlocked.contains('primeiro_scan'),
    ),
    AchievementProgress(
      id: 'reciclador',
      icon: '♻️',
      title: 'Reciclador',
      current: scans,
      target: 10,
      previouslyUnlocked: previouslyUnlocked.contains('reciclador'),
    ),
    AchievementProgress(
      id: 'guardiao_ambiental',
      icon: '🌎',
      title: 'Guardião Ambiental',
      current: scans,
      target: 25,
      previouslyUnlocked: previouslyUnlocked.contains('guardiao_ambiental'),
    ),
    AchievementProgress(
      id: 'mestre_sustentavel',
      icon: '🏆',
      title: 'Mestre Sustentável',
      current: scans,
      target: 50,
      previouslyUnlocked: previouslyUnlocked.contains('mestre_sustentavel'),
    ),
    AchievementProgress(
      id: 'explorador_verde',
      icon: '📍',
      title: 'Explorador Verde',
      current: exploredMap ? 1 : 0,
      target: 1,
      previouslyUnlocked: previouslyUnlocked.contains('explorador_verde'),
    ),
    AchievementProgress(
      id: 'educador_verde',
      icon: '📚',
      title: 'Educador Verde',
      current: scans,
      target: 100,
      previouslyUnlocked: previouslyUnlocked.contains('educador_verde'),
    ),
    AchievementProgress(
      id: 'detetive_materiais',
      icon: '🧠',
      title: 'Detetive dos Materiais',
      current: categories,
      target: 5,
      previouslyUnlocked: previouslyUnlocked.contains('detetive_materiais'),
    ),
    AchievementProgress(
      id: 'destino_correto',
      icon: '🗑️',
      title: 'Destino Certo',
      current: scans,
      target: 10,
      previouslyUnlocked: previouslyUnlocked.contains('destino_correto'),
    ),
  ];
}
