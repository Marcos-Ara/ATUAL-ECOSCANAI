import 'package:ecoscan_mobile/models/achievement_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mostra o progresso da conquista limitado à meta', () {
    final achievements = AchievementProgress.build(
      scans: 3,
      categories: 1,
      exploredMap: true,
    );
    final firstScan = achievements.first;

    expect(firstScan.current, 3);
    expect(firstScan.displayedCurrent, 1);
    expect(firstScan.target, 1);
    expect(firstScan.fraction, 1);
    expect(firstScan.isUnlocked, isTrue);
  });

  test('mantém uma conquista obtida mesmo se o histórico diminuir', () {
    final achievements = AchievementProgress.build(
      scans: 0,
      categories: 0,
      exploredMap: false,
      previouslyUnlocked: const {'reciclador'},
    );
    final recycler = achievements.firstWhere(
      (achievement) => achievement.id == 'reciclador',
    );

    expect(recycler.isUnlocked, isTrue);
    expect(recycler.displayedCurrent, recycler.target);
    expect(recycler.fraction, 1);
  });
}
