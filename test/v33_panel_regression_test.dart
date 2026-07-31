import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V33 panel trenera ma komplet modeli, API, UI i cennik', () {
    final models = File('lib/core/models.dart').readAsStringSync();
    final api = File('lib/core/api_client.dart').readAsStringSync();
    final shell = File('lib/screens/home_shell.dart').readAsStringSync();
    final plans = File('lib/screens/plans_screen.dart').readAsStringSync();
    final panel = File('lib/screens/trainer_panel_screen.dart').readAsStringSync();
    final subscriptions =
        File('lib/screens/subscription_screen.dart').readAsStringSync();

    expect(models, contains('class PlanTemplateSummary'));
    expect(models, contains('final String displayName;'));
    expect(models, contains('final bool archived;'));
    expect(api, contains('Future<PlanDetails> copyPlan'));
    expect(api, contains('Future<List<PlanTemplateSummary>> listPlanTemplates'));
    expect(shell, contains("'Panel trenera'"));
    expect(plans, contains("Text('Kopiuj ten dzień do podopiecznego')"));
    expect(panel, contains("title: 'Kopiuj cały plan między podopiecznymi'"));
    expect(subscriptions, contains('pricePln: 79.99'));
    expect(subscriptions, contains('pricePln: 39.99'));
    expect(subscriptions, contains('pricePln: 1499.99'));
  });
}
