import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/models.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'more_screen.dart';
import 'plans_screen.dart';
import 'settings_screen.dart';
import 'trainer_panel_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _seenDataRevision = -1;
  final List<Key> _pageKeys = List<Key>.generate(6, (_) => UniqueKey());

  bool _canManagePlans(AppUser user) {
    if (user.isAdmin || user.isTrainer) return true;
    return user.isTrainee && user.trainerLogin == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = AppScope.of(context).dataRevision;

    if (_seenDataRevision == -1) {
      _seenDataRevision = revision;
      return;
    }
    if (revision == _seenDataRevision) return;

    _seenDataRevision = revision;
    for (var i = 0; i < _pageKeys.length; i++) {
      if (i != _index) _pageKeys[i] = UniqueKey();
    }
  }

  Future<void> _openPlanManagement() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const PlansScreen(
          title: 'Zarządzaj planami',
          manageMode: true,
        ),
      ),
    );
    if (mounted) setState(() => _pageKeys[1] = UniqueKey());
  }

  void _selectDestination(int value) {
    if (value == _index) return;
    setState(() {
      _index = value;
      _pageKeys[value] = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.user!;

    final pages = user.isTrainer
        ? <Widget>[
            DashboardScreen(key: _pageKeys[0]),
            PlansScreen(key: _pageKeys[1]),
            HistoryScreen(key: _pageKeys[2]),
            TrainerPanelScreen(key: _pageKeys[3]),
            MoreScreen(key: _pageKeys[4]),
            SettingsScreen(key: _pageKeys[5]),
          ]
        : <Widget>[
            DashboardScreen(key: _pageKeys[0]),
            PlansScreen(key: _pageKeys[1]),
            HistoryScreen(key: _pageKeys[2]),
            MoreScreen(key: _pageKeys[3]),
            SettingsScreen(key: _pageKeys[4]),
          ];

    final labels = user.isTrainer
        ? const ['Start', 'Plany', 'Historia', 'Panel trenera', 'Więcej', 'Konto']
        : const ['Start', 'Plany', 'Historia', 'Więcej', 'Konto'];

    if (_index >= pages.length) _index = pages.length - 1;
    final accountIndex = pages.length - 1;

    final destinations = user.isTrainer
        ? const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Start',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Plany',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Historia',
            ),
            NavigationDestination(
              icon: Icon(Icons.dashboard_customize_outlined),
              selectedIcon: Icon(Icons.dashboard_customize),
              label: 'Panel',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: 'Więcej',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Konto',
            ),
          ]
        : const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Start',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Plany',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Historia',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: 'Więcej',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Konto',
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(labels[_index]),
        actions: [
          if (_index == 1 && _canManagePlans(user))
            IconButton(
              onPressed: _openPlanManagement,
              tooltip: 'Zarządzaj planami',
              icon: const Icon(Icons.edit_outlined),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                user.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (controller.subscription?.canWrite == false)
            MaterialBanner(
              content: const Text(
                'Subskrypcja wygasła. Dane pozostają dostępne do podglądu, ale nowe zapisy i edycja są zablokowane.',
              ),
              leading: const Icon(Icons.lock_outline),
              actions: [
                TextButton(
                  onPressed: () => _selectDestination(accountIndex),
                  child: const Text('Przejdź do konta'),
                ),
              ],
            ),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectDestination,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: destinations,
      ),
    );
  }
}
