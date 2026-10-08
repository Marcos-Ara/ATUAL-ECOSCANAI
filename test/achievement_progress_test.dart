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
}
