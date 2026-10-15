class AchievementProgress {
  const AchievementProgress({
    required this.id,
    required this.icon,
    required this.title,
    required this.current,
    required this.target,
  });

  final String id;
  final String icon;
  final String title;
  final int current;
  final int target;

  int get displayedCurrent => current.clamp(0, target).toInt();
  bool get isUnlocked => current >= target;
  double get fraction => (current / target).clamp(0.0, 1.0).toDouble();

  static List<AchievementProgress> build({
    required int scans,
    required int categories,
    required bool exploredMap,
  }) => [
    AchievementProgress(
      id: 'primeiro_scan',
      icon: '🌱',
      title: 'Primeiro Scan',
      current: scans,
      target: 1,
    ),
    AchievementProgress(
      id: 'reciclador',
      icon: '♻️',
      title: 'Reciclador',
      current: scans,
      target: 10,
    ),
    AchievementProgress(
      id: 'guardiao_ambiental',
      icon: '🌎',
      title: 'Guardião Ambiental',
      current: scans,
      target: 25,
    ),
    AchievementProgress(
      id: 'mestre_sustentavel',
      icon: '🏆',
      title: 'Mestre Sustentável',
      current: scans,
      target: 50,
    ),
    AchievementProgress(
      id: 'explorador_verde',
      icon: '📍',
      title: 'Explorador Verde',
      current: exploredMap ? 1 : 0,
      target: 1,
    ),
    AchievementProgress(
      id: 'educador_verde',
      icon: '📚',
      title: 'Educador Verde',
      current: scans,
      target: 100,
    ),
    AchievementProgress(
      id: 'detetive_materiais',
      icon: '🧠',
      title: 'Detetive dos Materiais',
      current: categories,
      target: 5,
    ),
    AchievementProgress(
      id: 'destino_certo',
      icon: '🗑️',
      title: 'Destino Certo',
      current: scans,
      target: 10,
    ),
  ];
}
