import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V33.1 zawiera poprawki UX, kalendarza i całych planów', () {
    final comments =
        File('lib/widgets/exercise_comment_dialog.dart').readAsStringSync();
    final workout = File('lib/screens/workout_screen.dart').readAsStringSync();
    final history = File('lib/screens/history_screen.dart').readAsStringSync();
    final shell = File('lib/screens/home_shell.dart').readAsStringSync();
    final dashboard =
        File('lib/screens/dashboard_screen.dart').readAsStringSync();
    final panel =
        File('lib/screens/trainer_panel_screen.dart').readAsStringSync();

    expect(comments, contains('Możesz już zacząć pisać'));
    expect(comments, contains('LinearProgressIndicator(minHeight: 2)'));
    expect(workout, contains('Trening jest zapisywany'));
    expect(history, contains("label: 'Cardio'"));
    expect(history, contains("label: 'Interwał'"));
    expect(history, isNot(contains("label: 'Cardio/interwały'")));

    expect(shell, contains('TrainerPanelScreen(key: _pageKeys[3])'));
    expect(shell, contains('MoreScreen(key: _pageKeys[4])'));
    expect(shell, contains("'Panel trenera', 'Więcej', 'Konto'"));
    expect(dashboard, isNot(contains("title: const Text('Moi podopieczni')")));
    expect(panel, isNot(contains('Pozostałe funkcje GymProgres')));

    expect(panel, contains('Skopiuj cały plan'));
    expect(panel, contains('for (final plan in plansToCopy)'));
    expect(panel, contains('class FullPlanTemplatesScreen'));
    expect(panel, contains('GYMPROGRES_FULL_PLAN_V1:'));
    expect(panel, contains('Zapisz cały plan jako szablon'));
    expect(panel, contains('Przypisz cały plan'));
  });
}
