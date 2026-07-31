import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/ui_helpers.dart';
import '../core/web_page_body.dart';
import '../widgets/common_widgets.dart';
import 'exercise_library_screen.dart';
import 'plans_screen.dart';
import 'trainer_screen.dart';

class TrainerPanelScreen extends StatefulWidget {
  const TrainerPanelScreen({super.key});

  @override
  State<TrainerPanelScreen> createState() => _TrainerPanelScreenState();
}

class _TrainerPanelScreenState extends State<TrainerPanelScreen> {
  bool _loading = true;
  Object? _error;
  TrainerSummary? _summary;
  List<TrainerClient> _clients = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.read(context).api;
      final results = await Future.wait<Object>([
        api.trainerSummary(),
        api.trainerClients(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as TrainerSummary;
        _clients = results[1] as List<TrainerClient>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _load();
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView(label: 'Ładowanie panelu trenera…');
    if (_error != null) {
      return ErrorView(message: errorText(_error!), onRetry: _load);
    }

    final summary = _summary!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          SectionCard(
            title: 'Podsumowanie',
            icon: Icons.dashboard_customize_outlined,
            child: Row(
              children: [
                Expanded(
                  child: _TrainerStat(
                    label: 'Podopieczni',
                    value: '${summary.currentClients}',
                    icon: Icons.groups_2_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TrainerStat(
                    label: 'Wolne miejsca',
                    value: '${(summary.traineeLimit - summary.reservedSlots).clamp(0, summary.traineeLimit)}',
                    icon: Icons.person_add_alt_1_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TrainerStat(
                    label: 'Zaproszenia',
                    value: '${summary.pendingInvitations}',
                    icon: Icons.outgoing_mail,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Podopieczni',
            icon: Icons.groups_outlined,
            child: Column(
              children: [
                _actionTile(
                  icon: Icons.groups_2_outlined,
                  title: 'Moi podopieczni',
                  subtitle:
                      '${_clients.length} aktywnych osób — profile, historia, dieta, pomiary i suplementy.',
                  onTap: () => _open(const TrainerClientsScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Plany i szablony',
            icon: Icons.fitness_center,
            child: Column(
              children: [
                _actionTile(
                  icon: Icons.compare_arrows,
                  title: 'Kopiuj cały plan między podopiecznymi',
                  subtitle:
                      'Skopiuj wszystkie dni planu albo tylko jeden wybrany dzień do jednej lub kilku osób.',
                  onTap: () => _open(const CopyPlanBetweenClientsScreen()),
                ),
                _actionTile(
                  icon: Icons.content_copy_outlined,
                  title: 'Biblioteka szablonów planów',
                  subtitle:
                      'Zapisuj jako szablon cały plan z wieloma dniami albo pojedynczy dzień i przypisuj go wielu osobom.',
                  onTap: () => _open(const FullPlanTemplatesScreen()),
                ),
                _actionTile(
                  icon: Icons.library_books_outlined,
                  title: 'Moja baza ćwiczeń',
                  subtitle:
                      'Dodawaj i edytuj ćwiczenia wykorzystywane w planach podopiecznych.',
                  onTap: () => _open(const ExerciseLibraryScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainerStat extends StatelessWidget {
  const _TrainerStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 7),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class TrainerPlanManagementScreen extends StatefulWidget {
  const TrainerPlanManagementScreen({super.key});

  @override
  State<TrainerPlanManagementScreen> createState() =>
      _TrainerPlanManagementScreenState();
}

class _TrainerPlanManagementScreenState
    extends State<TrainerPlanManagementScreen> {
  bool _loading = true;
  Object? _error;
  List<TrainerClient> _clients = const [];
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await AppScope.read(context).api.trainerClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _openPlans({String? login, String? displayName}) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlansScreen(
          userLogin: login,
          title: login == null
              ? 'Moje plany — zarządzanie'
              : 'Plany: ${displayName ?? login}',
          manageMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final clients = _clients
        .where(
          (client) =>
              client.displayName.toLowerCase().contains(query) ||
              client.login.toLowerCase().contains(query),
        )
        .toList();
    final body = _loading
        ? const LoadingView(label: 'Pobieranie podopiecznych…')
        : _error != null
            ? ErrorView(message: errorText(_error!), onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: const Text(
                          'Moje plany trenera',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Edytowanie, kopiowanie, daty, archiwum i szablony.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openPlans(),
                      ),
                    ),
                    if (_clients.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                        child: TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            labelText: 'Szukaj podopiecznego',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _search.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                    if (_clients.isEmpty)
                      const EmptyView(
                        message:
                            'Nie masz jeszcze podopiecznych. Dodaj osobę w sekcji „Moi podopieczni”.',
                        icon: Icons.groups_outlined,
                      )
                    else if (clients.isEmpty)
                      const EmptyView(
                        message: 'Nie znaleziono podopiecznego.',
                        icon: Icons.search_off,
                      )
                    else
                      for (final client in clients)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(
                              client.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${client.login} • ${client.workoutDays} dni treningowych',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openPlans(
                              login: client.login,
                              displayName: client.displayName,
                            ),
                          ),
                        ),
                  ],
                ),
              );

    return Scaffold(
      appBar: AppBar(title: const Text('Zarządzaj planami podopiecznych')),
      body: GymProgresPageBody(child: body),
    );
  }
}

class CopyPlanBetweenClientsScreen extends StatefulWidget {
  const CopyPlanBetweenClientsScreen({super.key});

  @override
  State<CopyPlanBetweenClientsScreen> createState() =>
      _CopyPlanBetweenClientsScreenState();
}

class _CopyPlanBetweenClientsScreenState
    extends State<CopyPlanBetweenClientsScreen> {
  static const String _trainerSource = '__trainer__';

  bool _loading = true;
  bool _loadingPlans = false;
  bool _saving = false;
  bool _copyWholePlan = true;
  Object? _error;
  List<TrainerClient> _clients = const [];
  List<PlanSummary> _plans = const [];
  String? _sourceOwner;
  String? _sourcePlan;
  final Set<String> _targets = <String>{};
  final TextEditingController _newName = TextEditingController();
  bool _overwrite = false;
  DateTime? _startDate;
  DateTime? _endDate;

  String? get _sourceLogin =>
      _sourceOwner == _trainerSource ? null : _sourceOwner;

  List<PlanSummary> get _activeSourcePlans =>
      _plans.where((plan) => !plan.archived).toList(growable: false);

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _error == null) _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await AppScope.read(context).api.trainerClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _selectSource(String? value) async {
    if (value == null) return;
    setState(() {
      _sourceOwner = value;
      _sourcePlan = null;
      _plans = const [];
      _targets.remove(value);
      _loadingPlans = true;
    });
    try {
      final plans = await AppScope.read(context).api.listPlans(
            userLogin: value == _trainerSource ? null : value,
          );
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loadingPlans = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingPlans = false);
      showError(context, error);
    }
  }

  void _selectPlan(String? value) {
    if (value == null) return;
    final plan = _plans.firstWhere((item) => item.name == value);
    setState(() {
      _sourcePlan = value;
      _newName.text = value;
      _startDate = plan.startDate;
      _endDate = plan.endDate;
    });
  }

  Future<void> _pickStartDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) setState(() => _startDate = value);
  }

  Future<void> _pickEndDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) setState(() => _endDate = value);
  }

  String _dateLabel(DateTime? value) =>
      value == null ? 'Nie ustawiono' : appDateFormat.format(value);

  Future<void> _copy() async {
    if (_sourceOwner == null) {
      showError(context, const ApiException('Wybierz właściciela planu.'));
      return;
    }
    if (_targets.isEmpty) {
      showError(
        context,
        const ApiException('Wybierz co najmniej jednego podopiecznego.'),
      );
      return;
    }

    final plansToCopy = _copyWholePlan
        ? _activeSourcePlans
        : _plans.where((plan) => plan.name == _sourcePlan).toList();
    if (plansToCopy.isEmpty) {
      showError(
        context,
        ApiException(
          _copyWholePlan
              ? 'Wybrana osoba nie ma aktywnych dni planu.'
              : 'Wybierz dzień planu źródłowego.',
        ),
      );
      return;
    }

    if (!_copyWholePlan) {
      final newName = _newName.text.trim();
      if (newName.isEmpty) {
        showError(context, const ApiException('Wpisz nazwę kopiowanego dnia.'));
        return;
      }
      if (_startDate != null &&
          _endDate != null &&
          _endDate!.isBefore(_startDate!)) {
        showError(
          context,
          const ApiException(
            'Data zakończenia nie może być wcześniejsza niż data rozpoczęcia.',
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);
    final failures = <String>[];
    var copiedDays = 0;

    for (final login in _targets) {
      for (final plan in plansToCopy) {
        try {
          await AppScope.read(context).api.copyPlan(
                planName: plan.name,
                newName: _copyWholePlan ? plan.name : _newName.text.trim(),
                sourceUserLogin: _sourceLogin,
                targetUserLogin: login,
                startDate: _copyWholePlan ? plan.startDate : _startDate,
                endDate: _copyWholePlan ? plan.endDate : _endDate,
                overwrite: _overwrite,
              );
          copiedDays++;
        } catch (_) {
          failures.add('$login — ${plan.name}');
        }
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    AppScope.read(context).notifyDataChanged();

    if (failures.isEmpty) {
      showSuccess(
        context,
        _copyWholePlan
            ? 'Skopiowano cały plan: ${plansToCopy.length} dni do ${_targets.length} osób.'
            : 'Skopiowano dzień „${plansToCopy.first.name}” do ${_targets.length} osób.',
      );
      setState(() => _targets.clear());
    } else {
      final preview = failures.take(6).join(', ');
      final extra = failures.length > 6
          ? ' oraz ${failures.length - 6} kolejnych'
          : '';
      showError(
        context,
        ApiException(
          'Skopiowano $copiedDays dni. Nie udało się: $preview$extra. '
          'Sprawdź, czy odbiorca nie ma już dni o tych samych nazwach albo włącz zastępowanie.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableTargets = _clients
        .where((client) => client.login != _sourceLogin)
        .toList();
    final body = _loading
        ? const LoadingView(label: 'Pobieranie podopiecznych…')
        : _error != null
            ? ErrorView(message: errorText(_error!), onRetry: _loadClients)
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  SectionCard(
                    title: '1. Wybierz źródło',
                    icon: Icons.source_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey('source-owner-${_sourceOwner ?? 'none'}'),
                          initialValue: _sourceOwner,
                          decoration: fieldDecoration('Właściciel planu'),
                          items: [
                            const DropdownMenuItem(
                              value: _trainerSource,
                              child: Text('Moje plany trenera'),
                            ),
                            for (final client in _clients)
                              DropdownMenuItem(
                                value: client.login,
                                child: Text(
                                  '${client.displayName} (${client.login})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _saving ? null : _selectSource,
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.copy_all_outlined),
                              label: Text('Cały plan'),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.copy_outlined),
                              label: Text('Jeden dzień'),
                            ),
                          ],
                          selected: {_copyWholePlan},
                          onSelectionChanged: _saving
                              ? null
                              : (selection) => setState(() {
                                    _copyWholePlan = selection.first;
                                  }),
                        ),
                        const SizedBox(height: 12),
                        if (_loadingPlans)
                          const LinearProgressIndicator()
                        else if (_copyWholePlan && _sourceOwner != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _activeSourcePlans.isEmpty
                                ? const Text(
                                    'Brak aktywnych dni planu.',
                                    style: TextStyle(color: Colors.white60),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Do skopiowania: ${_activeSourcePlans.length} dni',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      for (final plan in _activeSourcePlans)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 3),
                                          child: Text('• ${plan.name}'),
                                        ),
                                    ],
                                  ),
                          )
                        else if (!_copyWholePlan)
                          DropdownButtonFormField<String>(
                            key: ValueKey('source-plan-${_sourcePlan ?? 'none'}'),
                            initialValue: _sourcePlan,
                            decoration: fieldDecoration('Dzień źródłowy'),
                            items: [
                              for (final plan in _activeSourcePlans)
                                DropdownMenuItem(
                                  value: plan.name,
                                  child: Text(plan.name),
                                ),
                            ],
                            onChanged: _saving || _activeSourcePlans.isEmpty
                                ? null
                                : _selectPlan,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: '2. Wybierz odbiorców',
                    icon: Icons.groups_2_outlined,
                    trailing: availableTargets.isEmpty
                        ? null
                        : TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      if (_targets.length ==
                                          availableTargets.length) {
                                        _targets.clear();
                                      } else {
                                        _targets
                                          ..clear()
                                          ..addAll(
                                            availableTargets.map(
                                              (client) => client.login,
                                            ),
                                          );
                                      }
                                    }),
                            child: Text(
                              _targets.length == availableTargets.length
                                  ? 'Odznacz wszystkich'
                                  : 'Zaznacz wszystkich',
                            ),
                          ),
                    child: availableTargets.isEmpty
                        ? const Text(
                            'Brak innych podopiecznych, do których można skopiować plan.',
                            style: TextStyle(color: Colors.white60),
                          )
                        : Column(
                            children: [
                              for (final client in availableTargets)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _targets.contains(client.login),
                                  title: Text(client.displayName),
                                  subtitle: Text(client.login),
                                  onChanged: _saving
                                      ? null
                                      : (selected) => setState(() {
                                            if (selected == true) {
                                              _targets.add(client.login);
                                            } else {
                                              _targets.remove(client.login);
                                            }
                                          }),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: '3. Ustawienia kopii',
                    icon: Icons.tune,
                    child: Column(
                      children: [
                        if (_copyWholePlan)
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.layers_outlined),
                            title: Text('Zachowaj nazwy i daty wszystkich dni'),
                            subtitle: Text(
                              'Każdy aktywny dzień planu zostanie skopiowany jako osobna pozycja.',
                            ),
                          )
                        else ...[
                          TextField(
                            controller: _newName,
                            enabled: !_saving,
                            decoration:
                                fieldDecoration('Nazwa nowego dnia planu'),
                          ),
                          const SizedBox(height: 10),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.play_circle_outline),
                            title: const Text('Data rozpoczęcia'),
                            subtitle: Text(_dateLabel(_startDate)),
                            trailing: _startDate == null
                                ? null
                                : IconButton(
                                    onPressed: _saving
                                        ? null
                                        : () => setState(
                                              () => _startDate = null,
                                            ),
                                    icon: const Icon(Icons.clear),
                                  ),
                            onTap: _saving ? null : _pickStartDate,
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.event_available_outlined),
                            title: const Text('Data zakończenia'),
                            subtitle: Text(_dateLabel(_endDate)),
                            trailing: _endDate == null
                                ? null
                                : IconButton(
                                    onPressed: _saving
                                        ? null
                                        : () => setState(() => _endDate = null),
                                    icon: const Icon(Icons.clear),
                                  ),
                            onTap: _saving ? null : _pickEndDate,
                          ),
                        ],
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _overwrite,
                          title: const Text(
                            'Zastąp dni o tych samych nazwach',
                          ),
                          subtitle: const Text(
                            'Pozostaw wyłączone, aby istniejące dni odbiorcy nie zostały nadpisane.',
                          ),
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _overwrite = value),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _copy,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.copy_all_outlined),
                            label: Text(
                              _saving
                                  ? 'Kopiowanie…'
                                  : _copyWholePlan
                                      ? 'Skopiuj cały plan'
                                      : 'Skopiuj wybrany dzień',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

    return Scaffold(
      appBar: AppBar(title: const Text('Kopiuj plan między podopiecznymi')),
      body: body,
    );
  }
}


class FullPlanTemplatesScreen extends StatefulWidget {
  const FullPlanTemplatesScreen({super.key});

  @override
  State<FullPlanTemplatesScreen> createState() =>
      _FullPlanTemplatesScreenState();
}

class _FullPlanTemplatesScreenState extends State<FullPlanTemplatesScreen> {
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  List<PlanTemplateSummary> _templates = const [];
  List<TrainerClient> _clients = const [];

  List<_FullPlanTemplateSet> get _sets {
    final grouped = <String, List<_FullPlanTemplateDay>>{};
    for (final template in _templates) {
      final metadata = _FullPlanTemplateMetadata.tryParse(template.description);
      if (metadata == null) continue;
      grouped
          .putIfAbsent(metadata.setId, () => <_FullPlanTemplateDay>[])
          .add(_FullPlanTemplateDay(template: template, metadata: metadata));
    }
    final result = <_FullPlanTemplateSet>[];
    for (final days in grouped.values) {
      days.sort((a, b) => a.metadata.order.compareTo(b.metadata.order));
      result.add(_FullPlanTemplateSet(days: days));
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.read(context).api;
      final results = await Future.wait<Object>([
        api.listPlanTemplates(),
        api.trainerClients(),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<PlanTemplateSummary>;
        _clients = results[1] as List<TrainerClient>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _createSet() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFullPlanTemplateScreen(clients: _clients),
      ),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _assignSet(_FullPlanTemplateSet set) async {
    final selected = <String>{};
    var overwrite = false;
    final currentUser = AppScope.of(context).user!;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Przypisz cały plan: ${set.name}'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${set.days.length} dni planu zostanie przypisanych z zachowaniem nazw i dat.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(currentUser.login),
                    title: const Text('Moje konto trenera'),
                    subtitle: Text(currentUser.displayName),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected.add(currentUser.login);
                      } else {
                        selected.remove(currentUser.login);
                      }
                    }),
                  ),
                  for (final client in _clients)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(client.login),
                      title: Text(client.displayName),
                      subtitle: Text(client.login),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(client.login);
                        } else {
                          selected.remove(client.login);
                        }
                      }),
                    ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: overwrite,
                    title: const Text('Zastąp dni o tych samych nazwach'),
                    subtitle: const Text(
                      'Pozostaw wyłączone, aby istniejące dni nie zostały nadpisane.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => overwrite = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Przypisz cały plan'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || selected.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final failures = <String>[];
    var assignedDays = 0;
    try {
      for (final day in set.days) {
        try {
          await AppScope.read(context).api.assignPlanTemplate(
                templateId: day.template.id,
                userLogins: selected.toList(),
                planName: day.metadata.dayName,
                startDate: day.metadata.startDate,
                endDate: day.metadata.endDate,
                overwrite: overwrite,
              );
          assignedDays++;
        } catch (_) {
          failures.add(day.metadata.dayName);
        }
      }
      if (!mounted) return;
      AppScope.read(context).notifyDataChanged();
      if (failures.isEmpty) {
        showSuccess(
          context,
          'Przypisano cały plan „${set.name}” do ${selected.length} kont.',
        );
      } else {
        showError(
          context,
          ApiException(
            'Przypisano $assignedDays dni. Nie udało się przypisać: ${failures.join(', ')}.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSet(_FullPlanTemplateSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć szablon całego planu?'),
        content: Text(
          'Zestaw „${set.name}” i wszystkie jego ${set.days.length} dni zostaną usunięte. Już przypisane plany pozostaną bez zmian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń zestaw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      for (final day in set.days) {
        await AppScope.read(context).api.deletePlanTemplate(day.template.id);
      }
      if (!mounted) return;
      await _load();
      if (mounted) showSuccess(context, 'Szablon całego planu został usunięty.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sets = _sets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Szablony całych planów'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _createSet,
            tooltip: 'Utwórz szablon całego planu',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(label: 'Pobieranie szablonów…')
          : _error != null
              ? ErrorView(message: errorText(_error!), onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      SectionCard(
                        title: 'Szablony całych planów',
                        icon: Icons.layers_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _createSet,
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text(
                                'Utwórz szablon z całego planu',
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.push<void>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const PlanTemplatesScreen(),
                                        ),
                                      ),
                              icon: const Icon(Icons.bookmark_outline),
                              label: const Text(
                                'Pojedyncze dni i starsze szablony',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (sets.isEmpty)
                        const SizedBox(
                          height: 240,
                          child: EmptyView(
                            message:
                                'Nie masz jeszcze szablonu całego planu. Utwórz go z aktywnych dni planu swojego lub podopiecznego.',
                            icon: Icons.layers_clear_outlined,
                          ),
                        )
                      else
                        for (final set in sets)
                          Card(
                            child: ExpansionTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.layers_outlined),
                              ),
                              title: Text(
                                set.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${set.days.length} dni • ${set.exerciseCount} ćwiczeń'
                                '${set.note == null || set.note!.isEmpty ? '' : ' • ${set.note}'}',
                              ),
                              children: [
                                for (final day in set.days)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.fitness_center,
                                      size: 19,
                                    ),
                                    title: Text(day.metadata.dayName),
                                    subtitle: Text(
                                      '${day.template.exerciseCount} ćwiczeń',
                                    ),
                                  ),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 4, 12, 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _deleteSet(set),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Usuń'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _assignSet(set),
                                          icon: const Icon(
                                            Icons.person_add_alt_1_outlined,
                                          ),
                                          label: const Text('Przypisz'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}

class CreateFullPlanTemplateScreen extends StatefulWidget {
  const CreateFullPlanTemplateScreen({
    required this.clients,
    super.key,
  });

  final List<TrainerClient> clients;

  @override
  State<CreateFullPlanTemplateScreen> createState() =>
      _CreateFullPlanTemplateScreenState();
}

class _CreateFullPlanTemplateScreenState
    extends State<CreateFullPlanTemplateScreen> {
  static const String _trainerSource = '__trainer__';

  final TextEditingController _name = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final Set<String> _selectedDays = <String>{};
  String? _sourceOwner;
  List<PlanSummary> _plans = const [];
  bool _loadingPlans = false;
  bool _saving = false;

  String? get _sourceLogin =>
      _sourceOwner == _trainerSource ? null : _sourceOwner;

  List<PlanSummary> get _activePlans =>
      _plans.where((plan) => !plan.archived).toList(growable: false);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _selectSource(String? value) async {
    if (value == null) return;
    setState(() {
      _sourceOwner = value;
      _plans = const [];
      _selectedDays.clear();
      _loadingPlans = true;
    });
    try {
      final plans = await AppScope.read(context).api.listPlans(
            userLogin: value == _trainerSource ? null : value,
          );
      if (!mounted) return;
      final active = plans.where((plan) => !plan.archived).toList();
      setState(() {
        _plans = plans;
        _selectedDays.addAll(active.map((plan) => plan.name));
        _loadingPlans = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingPlans = false);
      showError(context, error);
    }
  }

  String _templateName(String setName, String dayName) {
    final value = '$setName • $dayName';
    return value.length <= 200 ? value : value.substring(0, 200);
  }

  Future<void> _save() async {
    final setName = _name.text.trim();
    final note = _note.text.trim();
    if (_sourceOwner == null) {
      showError(context, const ApiException('Wybierz właściciela planu.'));
      return;
    }
    if (setName.isEmpty) {
      showError(context, const ApiException('Wpisz nazwę szablonu.'));
      return;
    }
    final selectedPlans = _activePlans
        .where((plan) => _selectedDays.contains(plan.name))
        .toList();
    if (selectedPlans.isEmpty) {
      showError(
        context,
        const ApiException('Wybierz co najmniej jeden dzień planu.'),
      );
      return;
    }

    setState(() => _saving = true);
    final createdIds = <String>[];
    final setId = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      for (var index = 0; index < selectedPlans.length; index++) {
        final plan = selectedPlans[index];
        final metadata = _FullPlanTemplateMetadata(
          setId: setId,
          setName: setName,
          dayName: plan.name,
          order: index + 1,
          count: selectedPlans.length,
          note: note.isEmpty ? null : note,
          startDate: plan.startDate,
          endDate: plan.endDate,
        );
        final created = await AppScope.read(context).api.createTemplateFromPlan(
              templateName: _templateName(setName, plan.name),
              sourcePlanName: plan.name,
              sourceUserLogin: _sourceLogin,
              description: metadata.encode(),
            );
        createdIds.add(created.id);
      }
      if (!mounted) return;
      showSuccess(
        context,
        'Utworzono szablon „$setName” z ${selectedPlans.length} dni.',
      );
      Navigator.pop(context, true);
    } catch (error) {
      for (final id in createdIds) {
        try {
          await AppScope.read(context).api.deletePlanTemplate(id);
        } catch (_) {
          // Sprzątanie po częściowym utworzeniu nie może ukryć głównego błędu.
        }
      }
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nowy szablon całego planu')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionCard(
            title: 'Źródło planu',
            icon: Icons.source_outlined,
            child: DropdownButtonFormField<String>(
              initialValue: _sourceOwner,
              decoration: fieldDecoration('Właściciel planu'),
              items: [
                const DropdownMenuItem(
                  value: _trainerSource,
                  child: Text('Moje plany trenera'),
                ),
                for (final client in widget.clients)
                  DropdownMenuItem(
                    value: client.login,
                    child: Text(
                      '${client.displayName} (${client.login})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving ? null : _selectSource,
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Nazwa i dni planu',
            icon: Icons.layers_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: fieldDecoration('Nazwa całego szablonu'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  enabled: !_saving,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: fieldDecoration('Opis (opcjonalnie)'),
                ),
                if (_loadingPlans) const LinearProgressIndicator(),
                if (!_loadingPlans && _sourceOwner != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Wybierz dni (${_selectedDays.length}/${_activePlans.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving || _activePlans.isEmpty
                            ? null
                            : () => setState(() {
                                  if (_selectedDays.length ==
                                      _activePlans.length) {
                                    _selectedDays.clear();
                                  } else {
                                    _selectedDays
                                      ..clear()
                                      ..addAll(
                                        _activePlans.map((plan) => plan.name),
                                      );
                                  }
                                }),
                        child: Text(
                          _selectedDays.length == _activePlans.length
                              ? 'Odznacz wszystkie'
                              : 'Zaznacz wszystkie',
                        ),
                      ),
                    ],
                  ),
                  if (_activePlans.isEmpty)
                    const Text(
                      'Wybrana osoba nie ma aktywnych dni planu.',
                      style: TextStyle(color: Colors.white60),
                    )
                  else
                    for (final plan in _activePlans)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _selectedDays.contains(plan.name),
                        title: Text(plan.name),
                        subtitle: Text('${plan.exerciseCount} ćwiczeń'),
                        onChanged: _saving
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _selectedDays.add(plan.name);
                                  } else {
                                    _selectedDays.remove(plan.name);
                                  }
                                }),
                      ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? 'Tworzenie szablonu…'
                        : 'Zapisz cały plan jako szablon',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullPlanTemplateMetadata {
  const _FullPlanTemplateMetadata({
    required this.setId,
    required this.setName,
    required this.dayName,
    required this.order,
    required this.count,
    this.note,
    this.startDate,
    this.endDate,
  });

  static const prefix = 'GYMPROGRES_FULL_PLAN_V1:';

  final String setId;
  final String setName;
  final String dayName;
  final int order;
  final int count;
  final String? note;
  final DateTime? startDate;
  final DateTime? endDate;

  String encode() {
    return '$prefix${jsonEncode({
      'set_id': setId,
      'set_name': setName,
      'day_name': dayName,
      'order': order,
      'count': count,
      'note': note,
      'start_date': startDate?.toIso8601String().split('T').first,
      'end_date': endDate?.toIso8601String().split('T').first,
    })}';
  }

  static _FullPlanTemplateMetadata? tryParse(String? value) {
    if (value == null || !value.startsWith(prefix)) return null;
    try {
      final json = jsonDecode(value.substring(prefix.length));
      if (json is! Map<String, dynamic>) return null;
      return _FullPlanTemplateMetadata(
        setId: json['set_id']?.toString() ?? '',
        setName: json['set_name']?.toString() ?? '',
        dayName: json['day_name']?.toString() ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
        note: json['note']?.toString(),
        startDate: DateTime.tryParse(json['start_date']?.toString() ?? ''),
        endDate: DateTime.tryParse(json['end_date']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

class _FullPlanTemplateDay {
  const _FullPlanTemplateDay({
    required this.template,
    required this.metadata,
  });

  final PlanTemplateSummary template;
  final _FullPlanTemplateMetadata metadata;
}

class _FullPlanTemplateSet {
  const _FullPlanTemplateSet({required this.days});

  final List<_FullPlanTemplateDay> days;

  String get name => days.first.metadata.setName;
  String? get note => days.first.metadata.note;
  int get exerciseCount => days.fold<int>(
        0,
        (sum, day) => sum + day.template.exerciseCount,
      );
  DateTime get updatedAt => days
      .map((day) => day.template.updatedAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);
}
