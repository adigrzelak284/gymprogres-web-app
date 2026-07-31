import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V33.1A upraszcza plany i domyslnie pokazuje miesieczne subskrypcje', () {
    final plans = File('lib/screens/plans_screen.dart').readAsStringSync();
    final subscriptions =
        File('lib/screens/subscription_screen.dart').readAsStringSync();

    expect(plans, isNot(contains("title: 'Zarządzanie planami'")));
    expect(plans, isNot(contains('Pobierz aktualny plan Excel')));
    expect(plans, isNot(contains('_downloadCurrentPlan')));
    expect(plans, contains("tooltip: 'Zarządzaj planami'"));
    expect(plans, contains('Wgraj nowy plan z Excela'));
    expect(plans, isNot(contains('Wgraj poprawiony Excel i zastąp plan')));
    expect(subscriptions, contains("String _period = 'monthly';"));
    expect(subscriptions, isNot(contains("String _period = 'yearly';")));
  });
}
