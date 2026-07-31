import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V33.1B poprawia nawigacje, panel i podzial szablonow', () {
    final shell = File('lib/screens/home_shell.dart').readAsStringSync();
    final panel =
        File('lib/screens/trainer_panel_screen.dart').readAsStringSync();
    final plans = File('lib/screens/plans_screen.dart').readAsStringSync();

    expect(
      shell,
      contains('labelBehavior: NavigationDestinationLabelBehavior.alwaysShow'),
    );
    expect(shell, isNot(contains('onlyShowSelected')));

    expect(
      panel.indexOf("title: 'Podopieczni'"),
      lessThan(panel.indexOf("title: 'Plany i szablony'")),
    );

    expect(plans, contains('Wgraj nowy plan z Excela'));
    expect(
      plans,
      isNot(contains('Wgraj poprawiony Excel i zastąp plan')),
    );
    expect(plans, contains('bool _isFullPlanTemplate'));
    expect(
      plans,
      contains('.where((template) => !_isFullPlanTemplate(template))'),
    );
    expect(plans, contains('GYMPROGRES_FULL_PLAN_V1:'));
  });
}
