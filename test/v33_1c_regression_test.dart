import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V33.1C upraszcza panel trenera w webie', () {
    final panel =
        File('lib/screens/trainer_panel_screen.dart').readAsStringSync();

    expect(
      panel,
      isNot(contains(
        "icon: Icons.manage_accounts_outlined,\n                  title: 'Zarządzaj planami podopiecznych'",
      )),
    );
    expect(
      panel,
      isNot(contains(
        "icon: Icons.edit_note,\n                  title: 'Moje plany trenera'",
      )),
    );
  });
}
