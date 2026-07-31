import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/ui_helpers.dart';
import '../widgets/common_widgets.dart';
import '../widgets/exercise_comment_dialog.dart';
import 'exercise_library_screen.dart';
import 'workout_screen.dart';

import '../core/web_page_body.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({
    this.userLogin,
    this.title,
    this.manageMode = false,
    super.key,
  });

  final String? userLogin;
  final String? title;
  final bool manageMode;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _loading = true;
  bool _actionBusy = false;
  Object? _error;
  List<PlanSummary> _plans = const [];
  bool _showArchived = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _error == null) _load();
  }

  bool get _canManage {
    final user = AppScope.of(context).user!;
    if (user.isAdmin || user.isTrainer) return true;
    return widget.userLogin == null &&
        user.isTrainee &&
        user.trainerLogin == null;
  }

  bool get _canManageLibrary {
    final user = AppScope.of(context).user!;
    if (user.isTrainer) return true;
    return widget.userLogin == null &&
        user.isTrainee &&
        user.trainerLogin == null;
  }

  Future<void> _openExerciseLibrary() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
    );
  }

  Future<void> _openManagement() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlansScreen(
          userLogin: widget.userLogin,
          title: 'Zarządzaj planami',
          manageMode: true,
        ),
      ),
    );
    if (mounted) {
      await _load();
      if (mounted) AppScope.read(context).notifyDataChanged();
    }
  }

  Future<void> _addTrainingDay() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateTrainingDayScreen(
          userLogin: widget.userLogin,
          existingPlanNames: _plans.map((plan) => plan.name).toList(),
        ),
      ),
    );
    if (created == true && mounted) {
      await _load();
      if (mounted) AppScope.read(context).notifyDataChanged();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppScope.of(
        context,
      ).api.listPlans(
        userLogin: widget.userLogin,
        includeArchived: _showArchived,
      );
      if (!mounted) return;
      setState(() {
        _plans = result;
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

  Future<void> _refreshAllViews() async {
    await _load();
    if (!mounted || _error != null) return;
    AppScope.read(context).notifyDataChanged();
  }

  Future<void> _importExcel() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Wybierz plan treningowy Excel',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zastąpić obecny plan?'),
        content: const Text(
          'Nowy plik Excel zastąpi wszystkie obecne plany tego użytkownika. '
          'Historia wykonanych treningów pozostanie bez zmian. Jeśli plik jest '
          'nieprawidłowy, dotychczasowy plan nie zostanie usunięty.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Zastąp plan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final file = picked.files.single;
    final bytes = file.bytes ?? await file.xFile.readAsBytes();

    if (!mounted) return;
    setState(() => _actionBusy = true);
    try {
      final imported = await AppScope.of(context).api.importPlansFromExcel(
        bytes: bytes,
        fileName: file.name,
        userLogin: widget.userLogin,
      );
      await _load();
      if (mounted) {
        AppScope.read(context).notifyDataChanged();
        showSuccess(
          context,
          'Zastąpiono plan. Wgrano: ${imported.map((plan) => plan.name).join(', ')}.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _saveExcelBytes({
    required Future<Uint8List> Function() loader,
    required String fileName,
    required String dialogTitle,
    required String successMessage,
  }) async {
    setState(() => _actionBusy = true);
    try {
      final data = await loader();
      final savedPath = await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: data,
      );
      if (savedPath != null && mounted) showSuccess(context, successMessage);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _downloadTemplate() async {
    await _saveExcelBytes(
      loader: () => AppScope.of(context).api.downloadPlanTemplate(),
      fileName: 'Wzor planu w Excel.xlsx',
      dialogTitle: 'Zapisz wzór planu treningowego',
      successMessage: 'Wzór planu został zapisany.',
    );
  }

  Future<void> _openEditor(PlanSummary summary) async {
    setState(() => _actionBusy = true);
    try {
      final plan = await AppScope.of(
        context,
      ).api.getPlan(summary.name, userLogin: widget.userLogin);
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PlanEditorScreen(plan: plan, userLogin: widget.userLogin),
        ),
      );
      if (changed == true) {
        await _load();
        if (mounted) AppScope.read(context).notifyDataChanged();
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _copyPlan(PlanSummary plan) async {
    final controller = TextEditingController(text: '${plan.name} — kopia');
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skopiuj plan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: fieldDecoration('Nazwa nowego planu'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Utwórz kopię'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await AppScope.of(context).api.copyPlan(
        planName: plan.name,
        newName: newName.trim(),
        sourceUserLogin: widget.userLogin,
        targetUserLogin: widget.userLogin,
      );
      await _load();
      if (mounted) {
        AppScope.read(context).notifyDataChanged();
        showSuccess(context, 'Utworzono kopię planu „${newName.trim()}”.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }


  Future<void> _copyPlanToClients(PlanSummary plan) async {
    setState(() => _actionBusy = true);
    List<TrainerClient> clients;
    try {
      clients = await AppScope.of(context).api.trainerClients();
    } catch (error) {
      if (mounted) showError(context, error);
      if (mounted) setState(() => _actionBusy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _actionBusy = false);

    final availableClients = clients
        .where((client) => client.login != widget.userLogin)
        .toList();
    if (availableClients.isEmpty) {
      showError(
        context,
        const ApiException(
          'Nie masz innego podopiecznego, do którego można skopiować plan.',
        ),
      );
      return;
    }

    final nameController = TextEditingController(text: plan.name);
    final selected = <String>{};
    var overwrite = false;
    final data = await showDialog<_CopyToClientsData>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Kopiuj „${plan.name}” do podopiecznego'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: fieldDecoration('Nazwa kopiowanego planu'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 310),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final client in availableClients)
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
                    ],
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: overwrite,
                  title: const Text('Zastąp plan o tej samej nazwie'),
                  subtitle: const Text(
                    'Pozostaw wyłączone, aby nie nadpisać istniejącego planu.',
                  ),
                  onChanged: (value) =>
                      setDialogState(() => overwrite = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Anuluj'),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty || nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        _CopyToClientsData(
                          planName: nameController.text.trim(),
                          userLogins: selected.toList(),
                          overwrite: overwrite,
                        ),
                      ),
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Kopiuj'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (data == null || !mounted) return;

    setState(() => _actionBusy = true);
    final failed = <String>[];
    var copied = 0;
    for (final login in data.userLogins) {
      try {
        await AppScope.of(context).api.copyPlan(
          planName: plan.name,
          newName: data.planName,
          sourceUserLogin: widget.userLogin,
          targetUserLogin: login,
          startDate: plan.startDate,
          endDate: plan.endDate,
          overwrite: data.overwrite,
        );
        copied++;
      } catch (_) {
        failed.add(login);
      }
    }
    if (!mounted) return;
    setState(() => _actionBusy = false);
    AppScope.read(context).notifyDataChanged();
    if (failed.isEmpty) {
      showSuccess(
        context,
        'Skopiowano plan „${plan.name}” do $copied podopiecznych.',
      );
    } else {
      showError(
        context,
        ApiException(
          'Skopiowano plan do $copied osób. Nie udało się dla: ${failed.join(', ')}.',
        ),
      );
    }
  }

  Future<void> _saveAsTemplate(PlanSummary plan) async {
    final name = TextEditingController(text: plan.name);
    final description = TextEditingController();
    final data = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zapisz ten dzień jako szablon'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: fieldDecoration('Nazwa szablonu'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: fieldDecoration('Opis (opcjonalnie)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, [
              name.text.trim(),
              description.text.trim(),
            ]),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (data == null || data.first.isEmpty || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await AppScope.of(context).api.createTemplateFromPlan(
        templateName: data.first,
        description: data[1].isEmpty ? null : data[1],
        sourcePlanName: plan.name,
        sourceUserLogin: widget.userLogin,
      );
      if (mounted) showSuccess(context, 'Szablon „${data.first}” został zapisany.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _setArchived(PlanSummary plan, bool archived) async {
    setState(() => _actionBusy = true);
    try {
      await AppScope.of(context).api.updatePlanMetadata(
        planName: plan.name,
        userLogin: widget.userLogin,
        startDate: plan.startDate,
        endDate: plan.endDate,
        archived: archived,
      );
      await _load();
      if (mounted) {
        AppScope.read(context).notifyDataChanged();
        showSuccess(
          context,
          archived ? 'Plan przeniesiono do archiwum.' : 'Plan przywrócono z archiwum.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _setPlanDates(PlanSummary plan) async {
    DateTime? startDate = plan.startDate;
    DateTime? endDate = plan.endDate;
    String dateLabel(DateTime? value) => value == null
        ? 'Nie ustawiono'
        : '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Daty planu „${plan.name}”'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Data rozpoczęcia'),
                subtitle: Text(dateLabel(startDate)),
                trailing: startDate == null
                    ? null
                    : IconButton(
                        onPressed: () => setDialogState(() => startDate = null),
                        icon: const Icon(Icons.clear),
                      ),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: startDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null) {
                    setDialogState(() => startDate = selected);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Data zakończenia'),
                subtitle: Text(dateLabel(endDate)),
                trailing: endDate == null
                    ? null
                    : IconButton(
                        onPressed: () => setDialogState(() => endDate = null),
                        icon: const Icon(Icons.clear),
                      ),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: endDate ?? startDate ?? DateTime.now(),
                    firstDate: startDate ?? DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null) {
                    setDialogState(() => endDate = selected);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () {
                if (startDate != null &&
                    endDate != null &&
                    endDate!.isBefore(startDate!)) {
                  showError(
                    context,
                    const ApiException(
                      'Data zakończenia nie może być wcześniejsza niż data rozpoczęcia.',
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _actionBusy = true);
    try {
      await AppScope.of(context).api.updatePlanMetadata(
        planName: plan.name,
        userLogin: widget.userLogin,
        startDate: startDate,
        endDate: endDate,
        archived: plan.archived,
      );
      await _load();
      if (mounted) showSuccess(context, 'Zapisano daty obowiązywania planu.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _openTemplates() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const PlanTemplatesScreen()),
    );
  }

  String _planSubtitle(PlanSummary plan) {
    final parts = <String>['${plan.exerciseCount} ćwiczeń'];
    String date(DateTime value) =>
        '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
    if (plan.startDate != null || plan.endDate != null) {
      parts.add(
        '${plan.startDate == null ? '—' : date(plan.startDate!)} – '
        '${plan.endDate == null ? 'bez terminu' : date(plan.endDate!)}',
      );
    }
    if (plan.archived) parts.add('Archiwum');
    return parts.join(' • ');
  }

  Future<void> _deletePlan(PlanSummary plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć plan?'),
        content: Text(
          'Plan „${plan.name}” zostanie usunięty. Historia wykonanych treningów pozostanie w bazie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await AppScope.of(
        context,
      ).api.deletePlan(plan.name, userLogin: widget.userLogin);
      await _load();
      if (mounted) {
        AppScope.read(context).notifyDataChanged();
        showSuccess(context, 'Usunięto plan „${plan.name}”.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Widget _managementCard() {
    return SectionCard(
      title: 'Zarządzaj planami',
      icon: Icons.edit_note,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _actionBusy ? null : _importExcel,
            icon: const Icon(Icons.upload_file),
            label: const Text('Wgraj nowy plan z Excela'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _actionBusy ? null : _downloadTemplate,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Pobierz pusty wzór Excel'),
          ),
          if (_canManageLibrary) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _actionBusy ? null : _openExerciseLibrary,
              icon: const Icon(Icons.library_books_outlined),
              label: Text(
                AppScope.of(context).user!.isTrainer
                    ? 'Moja baza ćwiczeń dla podopiecznych'
                    : 'Moja baza ćwiczeń',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _actionBusy ? null : _openTemplates,
              icon: const Icon(Icons.content_copy_outlined),
              label: const Text('Biblioteka szablonów planów'),
            ),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _showArchived,
            title: const Text('Pokaż zarchiwizowane plany'),
            onChanged: _actionBusy
                ? null
                : (value) {
                    setState(() => _showArchived = value);
                    _load();
                  },
          ),
          const SizedBox(height: 8),
          const Text(
            'Możesz wgrać nowy lub poprawiony plan z Excela. '
            'Wgrany plik zastępuje plan bazowy, ale nie usuwa historii treningów.',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) return const LoadingView(label: 'Pobieranie planów…');
    if (_error != null) {
      return ErrorView(message: errorText(_error!), onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _refreshAllViews,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_plans.isEmpty)
            const EmptyView(
              message: 'Brak planów treningowych.',
              icon: Icons.fitness_center,
            )
          else
            for (var index = 0; index < _plans.length; index++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(
                    _plans[index].name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(_planSubtitle(_plans[index])),
                  trailing: _canManage
                      ? PopupMenuButton<String>(
                          enabled: !_actionBusy,
                          onSelected: (value) {
                            final plan = _plans[index];
                            if (value == 'edit') _openEditor(plan);
                            if (value == 'copy') _copyPlan(plan);
                            if (value == 'copy_to_client') {
                              _copyPlanToClients(plan);
                            }
                            if (value == 'template') _saveAsTemplate(plan);
                            if (value == 'dates') _setPlanDates(plan);
                            if (value == 'archive') _setArchived(plan, !plan.archived);
                            if (value == 'delete') _deletePlan(plan);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined),
                                  SizedBox(width: 10),
                                  Text('Edytuj plan'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'copy',
                              child: Row(
                                children: [
                                  Icon(Icons.copy_outlined),
                                  SizedBox(width: 10),
                                  Text('Utwórz kopię'),
                                ],
                              ),
                            ),
                            if (AppScope.of(context).user!.isTrainer)
                              const PopupMenuItem(
                                value: 'copy_to_client',
                                child: Row(
                                  children: [
                                    Icon(Icons.person_add_alt_1_outlined),
                                    SizedBox(width: 10),
                                    Text('Kopiuj ten dzień do podopiecznego'),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'template',
                              child: Row(
                                children: [
                                  Icon(Icons.bookmark_add_outlined),
                                  SizedBox(width: 10),
                                  Text('Zapisz ten dzień jako szablon'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'dates',
                              child: Row(
                                children: [
                                  Icon(Icons.date_range_outlined),
                                  SizedBox(width: 10),
                                  Text('Ustaw daty planu'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'archive',
                              child: Row(
                                children: [
                                  Icon(
                                    _plans[index].archived
                                        ? Icons.unarchive_outlined
                                        : Icons.archive_outlined,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _plans[index].archived
                                        ? 'Przywróć z archiwum'
                                        : 'Archiwizuj plan',
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline),
                                  SizedBox(width: 10),
                                  Text('Usuń plan'),
                                ],
                              ),
                            ),
                          ],
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlanDetailsScreen(
                        planName: _plans[index].name,
                        userLogin: widget.userLogin,
                      ),
                    ),
                  ),
                ),
              ),
          if (!widget.manageMode && _canManage) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilledButton.icon(
                onPressed: _actionBusy ? null : _addTrainingDay,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Dodaj dzień treningowy'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                'Utwórz nowy dzień, nadaj mu nazwę i wybierz ćwiczenia ze swojej bazy.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
          if (widget.manageMode && _canManage) ...[
            const SizedBox(height: 12),
            _managementCard(),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _content();
    if (widget.title == null) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title!),
        actions: [
          if (_canManage && !widget.manageMode)
            IconButton(
              onPressed: _actionBusy ? null : _openManagement,
              tooltip: 'Zarządzaj planami',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: GymProgresPageBody(child: body),
    );
  }
}


String? _templateDescriptionForDisplay(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  if (value.startsWith('GYMPROGRES_FULL_PLAN_V1:')) {
    return 'Element szablonu całego planu';
  }
  return value;
}

bool _isFullPlanTemplate(PlanTemplateSummary template) {
  return template.description?.startsWith('GYMPROGRES_FULL_PLAN_V1:') ==
      true;
}


class _CopyToClientsData {
  const _CopyToClientsData({
    required this.planName,
    required this.userLogins,
    required this.overwrite,
  });

  final String planName;
  final List<String> userLogins;
  final bool overwrite;
}


class PlanTemplatesScreen extends StatefulWidget {
  const PlanTemplatesScreen({super.key});

  @override
  State<PlanTemplatesScreen> createState() => _PlanTemplatesScreenState();
}

class _PlanTemplatesScreenState extends State<PlanTemplatesScreen> {
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  List<PlanTemplateSummary> _templates = const [];
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
      final api = AppScope.of(context).api;
      final user = AppScope.of(context).user!;
      final templatesFuture = api.listPlanTemplates();
      final clientsFuture = user.isTrainer
          ? api.trainerClients()
          : Future<List<TrainerClient>>.value(const []);
      final results = await Future.wait<Object>([templatesFuture, clientsFuture]);
      if (!mounted) return;
      final allTemplates = results[0] as List<PlanTemplateSummary>;
      setState(() {
        _templates = allTemplates
            .where((template) => !_isFullPlanTemplate(template))
            .toList(growable: false);
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

  Future<void> _assign(PlanTemplateSummary template) async {
    final user = AppScope.of(context).user!;
    final planName = TextEditingController(text: template.name);
    final selected = <String>{};
    if (!user.isTrainer) selected.add(user.login);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Przypisz: ${template.name}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: planName,
                    decoration: fieldDecoration('Nazwa planu po przypisaniu'),
                  ),
                  if (user.isTrainer) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Wybierz podopiecznych',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    if (_clients.isEmpty)
                      const Text(
                        'Nie masz aktywnych podopiecznych.',
                        style: TextStyle(color: Colors.white60),
                      )
                    else
                      for (final client in _clients)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selected.contains(client.login),
                          title: Text(client.displayName),
                          subtitle: Text(client.email ?? client.login),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selected.add(client.login);
                            } else {
                              selected.remove(client.login);
                            }
                          }),
                        ),
                  ],
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
              onPressed: () {
                if (planName.text.trim().isEmpty || selected.isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Przypisz'),
            ),
          ],
        ),
      ),
    );
    final name = planName.text.trim();
    planName.dispose();
    if (accepted != true || name.isEmpty || selected.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.assignPlanTemplate(
        templateId: template.id,
        userLogins: selected.toList(),
        planName: name,
      );
      if (mounted) {
        AppScope.read(context).notifyDataChanged();
        showSuccess(
          context,
          selected.length == 1
              ? 'Plan został przypisany.'
              : 'Plan przypisano ${selected.length} podopiecznym.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PlanTemplateSummary template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć szablon?'),
        content: Text(
          'Szablon „${template.name}” zostanie usunięty. Już przypisane plany pozostaną bez zmian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.deletePlanTemplate(template.id);
      await _load();
      if (mounted) showSuccess(context, 'Szablon został usunięty.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Szablony planów')),
      body: _loading
          ? const LoadingView(label: 'Pobieranie szablonów…')
          : _error != null
          ? ErrorView(message: errorText(_error!), onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: _templates.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        EmptyView(
                          message:
                              'Nie masz jeszcze szablonów. Otwórz zarządzanie planem i wybierz „Zapisz jako szablon”.',
                          icon: Icons.bookmarks_outlined,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _templates.length,
                      itemBuilder: (context, index) {
                        final template = _templates[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.bookmark_outline),
                            ),
                            title: Text(
                              template.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              <String?>[
                                '${template.exerciseCount} ćwiczeń',
                                _templateDescriptionForDisplay(
                                  template.description,
                                ),
                              ].whereType<String>().join(' • '),
                            ),
                            onTap: _busy ? null : () => _assign(template),
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (value) {
                                if (value == 'assign') _assign(template);
                                if (value == 'delete') _delete(template);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'assign',
                                  child: Text('Przypisz plan'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Usuń szablon'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class CreateTrainingDayScreen extends StatefulWidget {
  const CreateTrainingDayScreen({
    required this.existingPlanNames,
    this.userLogin,
    super.key,
  });

  final List<String> existingPlanNames;
  final String? userLogin;

  @override
  State<CreateTrainingDayScreen> createState() =>
      _CreateTrainingDayScreenState();
}

class _CreateTrainingDayScreenState extends State<CreateTrainingDayScreen> {
  final TextEditingController _name = TextEditingController();
  List<PlanExercise> _exercises = [];
  bool _saving = false;
  String? _validation;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    try {
      final library = await AppScope.of(
        context,
      ).api.exerciseLibraryItems(userLogin: widget.userLogin);
      if (!mounted) return;
      if (library.isEmpty) {
        showError(
          context,
          const ApiException(
            'Twoja baza ćwiczeń jest pusta. Najpierw dodaj ćwiczenia w „Zarządzaj planami” → „Moja baza ćwiczeń”.',
          ),
        );
        return;
      }
      final selected = await showDialog<ExerciseLibraryItem>(
        context: context,
        builder: (_) => _PlanLibraryDialog(exercises: library),
      );
      if (selected == null || !mounted) return;

      final added = await showDialog<PlanExercise>(
        context: context,
        builder: (_) => _PlanExerciseDialog(
          initial: selected.toPlanExercise(order: _exercises.length + 1),
          fixedName: selected.name,
          order: _exercises.length + 1,
        ),
      );
      if (added == null || !mounted) return;
      setState(() {
        _exercises.add(added);
        _validation = null;
      });
      showSuccess(
        context,
        'Ćwiczenie „${added.name}” zostało dodane do dnia treningowego.',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _editExercise(int index) async {
    final updated = await showDialog<PlanExercise>(
      context: context,
      builder: (_) =>
          _PlanExerciseDialog(initial: _exercises[index], order: index + 1),
    );
    if (updated != null && mounted) {
      setState(() => _exercises[index] = updated.copyWith(order: index + 1));
    }
  }

  Future<void> _removeExercise(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć ćwiczenie?'),
        content: Text(
          '„${_exercises[index].name}” zostanie usunięte z tworzonego dnia treningowego.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _exercises.removeAt(index);
      _renumber();
    });
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _exercises.length) return;
    setState(() {
      final item = _exercises.removeAt(from);
      _exercises.insert(to, item);
      _renumber();
    });
  }

  void _renumber() {
    _exercises = [
      for (var index = 0; index < _exercises.length; index++)
        _exercises[index].copyWith(order: index + 1),
    ];
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _validation = 'Wpisz nazwę dnia treningowego.');
      return;
    }
    final duplicate = widget.existingPlanNames.any(
      (item) => _normalizeSearch(item) == _normalizeSearch(name),
    );
    if (duplicate) {
      setState(
        () => _validation =
            'Dzień o tej nazwie już istnieje. Wybierz inną nazwę.',
      );
      return;
    }
    if (_exercises.isEmpty) {
      setState(
        () => _validation = 'Dodaj co najmniej jedno ćwiczenie ze swojej bazy.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dodać dzień treningowy?'),
        content: Text(
          'Dzień „$name” z ${_exercises.length} ćwiczeniami zostanie zapisany na liście planów.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Dodaj dzień'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await AppScope.of(context).api.replacePlan(
        PlanDetails(name: name, exercises: _exercises),
        userLogin: widget.userLogin,
      );
      if (!mounted) return;
      showSuccess(context, 'Dzień treningowy „$name” został dodany.');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj dzień treningowy')),
      body: GymProgresPageBody(
        child: Column(
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _name,
                      enabled: !_saving,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      decoration: fieldDecoration(
                        'Nazwa dnia, np. FBW, Push lub Nogi',
                      ),
                      onChanged: (_) {
                        if (_validation != null) {
                          setState(() => _validation = null);
                        }
                      },
                    ),
                    if (_validation != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _validation!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'Ćwiczenia wybierasz ze swojej bazy. Przed dodaniem możesz zmienić serie, powtórzenia, przerwę, RIR i tempo.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _exercises.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nie dodano jeszcze ćwiczeń.\nNaciśnij „Dodaj ćwiczenie z bazy”.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
                      itemCount: _exercises.length,
                      onReorderItem: _move,
                      itemBuilder: (context, index) {
                        final exercise = _exercises[index];
                        return Card(
                          key: ValueKey(
                            'new-day-${exercise.name}-${exercise.order}-$index',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                    CircleAvatar(
                                      radius: 15,
                                      child: Text('${index + 1}'),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        exercise.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _editExercise(index),
                                      tooltip: 'Edytuj parametry',
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _removeExercise(index),
                                      tooltip: 'Usuń z dnia',
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    Chip(label: Text('${exercise.sets} serie')),
                                    Chip(
                                      label: Text(
                                        '${exercise.recommendedReps} powt.',
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        'Przerwa ${exercise.restDescription}',
                                      ),
                                    ),
                                    if ((exercise.rir ?? '').isNotEmpty)
                                      Chip(label: Text('RIR ${exercise.rir}')),
                                    if ((exercise.tempo ?? '').isNotEmpty)
                                      Chip(
                                        label: Text('Tempo ${exercise.tempo}'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addExercise,
        icon: const Icon(Icons.library_add_outlined),
        label: const Text('Dodaj ćwiczenie z bazy'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Zapisywanie…' : 'Zapisz dzień treningowy'),
        ),
      ),
    );
  }
}

class PlanDetailsScreen extends StatefulWidget {
  const PlanDetailsScreen({required this.planName, this.userLogin, super.key});

  final String planName;
  final String? userLogin;

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen> {
  PlanDetails? _plan;
  Object? _error;

  bool get _canManage {
    final user = AppScope.of(context).user!;
    if (user.isAdmin || user.isTrainer) return true;
    return widget.userLogin == null &&
        user.isTrainee &&
        user.trainerLogin == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_plan == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final plan = await AppScope.of(
        context,
      ).api.getPlan(widget.planName, userLogin: widget.userLogin);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _editPlan() async {
    final plan = _plan;
    if (plan == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PlanEditorScreen(plan: plan, userLogin: widget.userLogin),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _plan = null);
      await _load();
    }
  }

  Future<void> _openInstruction(PlanExercise exercise) async {
    final value = exercise.instructionUrl?.trim() ?? '';
    if (value.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Instrukcja'),
          content: const Text('Brak linku do instrukcji dla tego ćwiczenia.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      showError(
        context,
        const ApiException('Link do instrukcji jest nieprawidłowy.'),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showError(
        context,
        const ApiException('Nie udało się otworzyć instrukcji.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.planName),
        actions: [
          if (_canManage && _plan != null)
            IconButton(
              onPressed: _editPlan,
              tooltip: 'Edytuj plan na stałe',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: GymProgresPageBody(
        child: _plan == null
            ? _error == null
                  ? const LoadingView()
                  : ErrorView(
                      message: errorText(_error!),
                      onRetry: () {
                        setState(() => _error = null);
                        _load();
                      },
                    )
            : ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  for (var i = 0; i < _plan!.exercises.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  child: Text('${i + 1}'),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _plan!.exercises[i].name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'instruction') {
                                      _openInstruction(_plan!.exercises[i]);
                                    }
                                    if (value == 'comment') {
                                      showExerciseCommentDialog(
                                        context,
                                        exerciseName: _plan!.exercises[i].name,
                                        userLogin: widget.userLogin,
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'instruction',
                                      child: Row(
                                        children: [
                                          Icon(Icons.play_circle_outline),
                                          SizedBox(width: 10),
                                          Text('Instrukcja'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'comment',
                                      child: Row(
                                        children: [
                                          Icon(Icons.comment_outlined),
                                          SizedBox(width: 10),
                                          Text('Komentarz'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  label: Text(
                                    '${_plan!.exercises[i].sets} serie',
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    '${_plan!.exercises[i].recommendedReps} powt.',
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    'Przerwa: ${_plan!.exercises[i].restDescription}',
                                  ),
                                ),
                                if ((_plan!.exercises[i].rir ?? '').isNotEmpty)
                                  Chip(
                                    label: Text(
                                      'RIR: ${_plan!.exercises[i].rir}',
                                    ),
                                  ),
                                if ((_plan!.exercises[i].tempo ?? '')
                                    .isNotEmpty)
                                  Chip(
                                    label: Text(
                                      'Tempo: ${_plan!.exercises[i].tempo}',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: _plan == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  widget.userLogin == null
                      ? 'Rozpocznij trening'
                      : 'Rozpocznij trening podopiecznego',
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActiveWorkoutScreen(
                      plan: _plan!,
                      userLogin: widget.userLogin,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class PlanEditorScreen extends StatefulWidget {
  const PlanEditorScreen({required this.plan, this.userLogin, super.key});

  final PlanDetails plan;
  final String? userLogin;

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  late List<PlanExercise> _exercises;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _exercises = [
      for (var i = 0; i < widget.plan.exercises.length; i++)
        widget.plan.exercises[i].copyWith(order: i + 1),
    ];
  }

  Future<void> _edit(int index) async {
    final updated = await showDialog<PlanExercise>(
      context: context,
      builder: (_) =>
          _PlanExerciseDialog(initial: _exercises[index], order: index + 1),
    );
    if (updated != null && mounted) {
      setState(() => _exercises[index] = updated.copyWith(order: index + 1));
    }
  }

  Future<void> _add() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: const Text('Z biblioteki ćwiczeń'),
              onTap: () => Navigator.pop(sheetContext, 'library'),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Nowe ćwiczenie'),
              onTap: () => Navigator.pop(sheetContext, 'new'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    String? fixedName;
    PlanExercise? libraryDefaults;
    if (source == 'library') {
      try {
        final library = await AppScope.of(
          context,
        ).api.exerciseLibraryItems(userLogin: widget.userLogin);
        if (!mounted) return;
        final selected = await showDialog<ExerciseLibraryItem>(
          context: context,
          builder: (_) => _PlanLibraryDialog(exercises: library),
        );
        if (selected == null || !mounted) return;
        fixedName = selected.name;
        libraryDefaults = selected.toPlanExercise(order: _exercises.length + 1);
      } catch (error) {
        if (mounted) showError(context, error);
        return;
      }
    }

    final added = await showDialog<PlanExercise>(
      context: context,
      builder: (_) => _PlanExerciseDialog(
        initial: libraryDefaults,
        fixedName: fixedName,
        order: _exercises.length + 1,
      ),
    );
    if (added != null && mounted) {
      setState(() => _exercises.add(added));
      showSuccess(
        context,
        'Ćwiczenie „${added.name}” zostało dodane do planu. Zapisz plan, aby utrwalić zmiany.',
      );
    }
  }

  Future<void> _remove(int index) async {
    if (_exercises.length <= 1) {
      showError(
        context,
        const ApiException('Plan musi zawierać co najmniej jedno ćwiczenie.'),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć ćwiczenie z planu?'),
        content: Text(
          '„${_exercises[index].name}” zostanie trwale usunięte z planu bazowego. Historia pozostanie bez zmian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _exercises.removeAt(index);
      _renumber();
    });
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _exercises.length) return;
    setState(() {
      final item = _exercises.removeAt(from);
      _exercises.insert(to, item);
      _renumber();
    });
  }

  void _renumber() {
    _exercises = [
      for (var i = 0; i < _exercises.length; i++)
        _exercises[i].copyWith(order: i + 1),
    ];
  }

  Future<void> _save() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zapisać zmiany w planie?'),
        content: const Text(
          'Zmiany zostaną zapisane na stałe w planie bazowym. Nie wpłyną na wcześniejszą historię treningów.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Zapisz plan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await AppScope.of(context).api.replacePlan(
        PlanDetails(
          name: widget.plan.name,
          exercises: _exercises,
          startDate: widget.plan.startDate,
          endDate: widget.plan.endDate,
          archived: widget.plan.archived,
          sourceTemplateId: widget.plan.sourceTemplateId,
        ),
        userLogin: widget.userLogin,
      );
      if (!mounted) return;
      showSuccess(context, 'Plan został zaktualizowany.');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edytuj: ${widget.plan.name}')),
      body: GymProgresPageBody(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 110),
          itemCount: _exercises.length,
          onReorderItem: (oldIndex, newIndex) {
            _move(oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final exercise = _exercises[index];
            return Card(
              key: ValueKey('${exercise.id}-${exercise.name}-$index'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                        CircleAvatar(radius: 15, child: Text('${index + 1}')),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            exercise.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _edit(index),
                          tooltip: 'Edytuj ćwiczenie',
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: () => _remove(index),
                          tooltip: 'Usuń z planu',
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        Chip(label: Text('${exercise.sets} serie')),
                        Chip(label: Text('${exercise.recommendedReps} powt.')),
                        Chip(
                          label: Text('Przerwa ${exercise.restDescription}'),
                        ),
                        if ((exercise.rir ?? '').isNotEmpty)
                          Chip(label: Text('RIR ${exercise.rir}')),
                        if ((exercise.tempo ?? '').isNotEmpty)
                          Chip(label: Text('Tempo ${exercise.tempo}')),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('Dodaj ćwiczenie'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Zapisywanie…' : 'Zapisz zmiany w planie'),
        ),
      ),
    );
  }
}

class _PlanExerciseDialog extends StatefulWidget {
  const _PlanExerciseDialog({
    required this.order,
    this.initial,
    this.fixedName,
  });

  final int order;
  final PlanExercise? initial;
  final String? fixedName;

  @override
  State<_PlanExerciseDialog> createState() => _PlanExerciseDialogState();
}

class _PlanExerciseDialogState extends State<_PlanExerciseDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sets;
  late final TextEditingController _reps;
  late final TextEditingController _rest;
  late final TextEditingController _rir;
  late final TextEditingController _tempo;
  late final TextEditingController _instruction;
  String? _validation;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(
      text: widget.fixedName ?? initial?.name ?? '',
    );
    _sets = TextEditingController(text: '${initial?.sets ?? 3}');
    _reps = TextEditingController(text: initial?.recommendedReps ?? '10');
    _rest = TextEditingController(text: initial?.restDescription ?? '60s');
    _rir = TextEditingController(text: initial?.rir ?? '');
    _tempo = TextEditingController(text: initial?.tempo ?? '');
    _instruction = TextEditingController(text: initial?.instructionUrl ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _sets.dispose();
    _reps.dispose();
    _rest.dispose();
    _rir.dispose();
    _tempo.dispose();
    _instruction.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final sets = int.tryParse(_sets.text.trim());
    if (name.isEmpty || sets == null || sets < 1 || sets > 100) {
      setState(() => _validation = 'Podaj nazwę i liczbę serii od 1 do 100.');
      return;
    }
    final rest = _rest.text.trim().isEmpty ? '60s' : _rest.text.trim();
    Navigator.pop(
      context,
      PlanExercise(
        id: widget.initial?.id,
        name: name,
        sets: sets,
        recommendedReps: _reps.text.trim(),
        restDescription: rest,
        restSeconds: _parseRestSeconds(rest),
        rir: _rir.text.trim().isEmpty ? null : _rir.text.trim(),
        tempo: _tempo.text.trim().isEmpty ? null : _tempo.text.trim(),
        instructionUrl: _instruction.text.trim().isEmpty
            ? null
            : _instruction.text.trim(),
        order: widget.order,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial?.id == null ? 'Dodaj ćwiczenie' : 'Edytuj ćwiczenie',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_validation != null) ...[
              Text(
                _validation!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _name,
              enabled: widget.fixedName == null,
              decoration: fieldDecoration('Nazwa ćwiczenia'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sets,
              keyboardType: TextInputType.number,
              decoration: fieldDecoration('Serie'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reps,
              decoration: fieldDecoration('Powtórzenia'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rest,
              decoration: fieldDecoration('Przerwa, np. 60s lub 2 min'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _rir, decoration: fieldDecoration('RIR')),
            const SizedBox(height: 10),
            TextField(controller: _tempo, decoration: fieldDecoration('Tempo')),
            const SizedBox(height: 10),
            TextField(
              controller: _instruction,
              keyboardType: TextInputType.url,
              decoration: fieldDecoration('Link do instrukcji'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Zapisz')),
      ],
    );
  }
}

class _PlanLibraryDialog extends StatefulWidget {
  const _PlanLibraryDialog({required this.exercises});
  final List<ExerciseLibraryItem> exercises;

  @override
  State<_PlanLibraryDialog> createState() => _PlanLibraryDialogState();
}

class _PlanLibraryDialogState extends State<_PlanLibraryDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalizeSearch(_query);
    final items =
        widget.exercises
            .where((item) => _normalizeSearch(item.name).contains(query))
            .toList()
          ..sort(
            (a, b) =>
                _normalizeSearch(a.name).compareTo(_normalizeSearch(b.name)),
          );
    return AlertDialog(
      title: const Text('Wybierz ćwiczenie z biblioteki'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Szukaj ćwiczenia',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Nie znaleziono ćwiczenia.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.sets} serie • ${item.recommendedReps} powt. • ${item.restDescription}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
      ],
    );
  }
}

int _parseRestSeconds(String value) {
  final lower = value.toLowerCase();
  final matches = RegExp(r'\d+').allMatches(lower).toList();
  if (matches.isEmpty) return 60;
  final number = int.tryParse(matches.last.group(0)!) ?? 60;
  return lower.contains('min') ? number * 60 : number;
}

String _normalizeSearch(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll('ą', 'a')
      .replaceAll('ć', 'c')
      .replaceAll('ę', 'e')
      .replaceAll('ł', 'l')
      .replaceAll('ń', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ś', 's')
      .replaceAll('ź', 'z')
      .replaceAll('ż', 'z');
}
