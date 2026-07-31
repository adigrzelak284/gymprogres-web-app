import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/notification_service.dart';
import '../core/ui_helpers.dart';
import '../widgets/exercise_comment_dialog.dart';

import '../core/web_page_body.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({required this.plan, this.userLogin, super.key});

  final PlanDetails plan;
  final String? userLogin;

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _SetControllers {
  _SetControllers()
    : reps = TextEditingController(),
      weight = TextEditingController();
  final TextEditingController reps;
  final TextEditingController weight;

  void dispose() {
    reps.dispose();
    weight.dispose();
  }
}

class _ExerciseControllers {
  _ExerciseControllers(PlanExercise exercise)
    : exercise = exercise,
      sets = List.generate(exercise.sets, (_) => _SetControllers());

  PlanExercise exercise;
  final List<_SetControllers> sets;
  final Object identity = Object();

  void dispose() {
    for (final set in sets) {
      set.dispose();
    }
  }
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen>
    with WidgetsBindingObserver {
  late final DateTime _startedAt;
  late final List<_ExerciseControllers> _inputs;
  Timer? _clockTimer;
  Timer? _restTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _restEndsAt;
  int _restRemaining = 0;
  int? _restExerciseIndex;
  String? _restExercise;
  bool _saving = false;
  bool _allowPop = false;
  bool _lastResultsRequested = false;
  final Map<String, ExerciseLastPerformance> _lastResults = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    _inputs = widget.plan.exercises.map(_ExerciseControllers.new).toList();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_lastResultsRequested) {
      _lastResultsRequested = true;
      _loadLastResults();
    }
  }

  Future<void> _loadLastResults() async {
    final api = AppScope.of(context).api;
    final results = await Future.wait(
      _inputs.map(
        (input) => api.lastExercisePerformance(
          input.exercise.name,
          userLogin: widget.userLogin,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      for (final result in results) {
        _lastResults[result.exerciseName.toLowerCase().trim()] = result;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _restTimer?.cancel();
    if (_restEndsAt != null) {
      unawaited(RestNotificationService.instance.cancelRestEnd());
    }
    for (final input in _inputs) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncRestCountdown(showFinishedMessage: false);
    }
  }

  Future<void> _startRest(PlanExercise exercise, int exerciseIndex) async {
    final duration = Duration(seconds: exercise.restSeconds);
    final endsAt = DateTime.now().add(duration);

    _restTimer?.cancel();
    try {
      await RestNotificationService.instance.cancelRestEnd();
    } catch (_) {
      // Brak zgody na powiadomienia nie może blokować samego stopera.
    }
    if (!mounted) return;

    setState(() {
      _restEndsAt = endsAt;
      _restRemaining = exercise.restSeconds;
      _restExerciseIndex = exerciseIndex;
      _restExercise = exercise.name;
    });
    _startRestTicker();

    try {
      await RestNotificationService.instance.scheduleRestEnd(
        endsAt: endsAt,
        exerciseName: exercise.name,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Stoper działa, ale powiadomienie nie zostało zaplanowane. Sprawdź uprawnienia powiadomień i alarmów.',
          ),
        ),
      );
    }
  }

  void _startRestTicker() {
    _restTimer?.cancel();
    _syncRestCountdown();
    _restTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncRestCountdown(),
    );
  }

  void _syncRestCountdown({bool showFinishedMessage = true}) {
    final endsAt = _restEndsAt;
    if (endsAt == null || !mounted) return;

    final milliseconds = endsAt.difference(DateTime.now()).inMilliseconds;
    final remaining = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
    if (remaining <= 0) {
      _restTimer?.cancel();
      final exerciseName = _restExercise;
      setState(() {
        _restEndsAt = null;
        _restRemaining = 0;
        _restExerciseIndex = null;
        _restExercise = null;
      });
      if (showFinishedMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exerciseName == null
                  ? 'Czas na następną serię.'
                  : 'Czas na następną serię: $exerciseName',
            ),
          ),
        );
      }
      return;
    }

    if (_restRemaining != remaining) {
      setState(() => _restRemaining = remaining);
    }
  }

  void _stopRest() {
    _restTimer?.cancel();
    unawaited(RestNotificationService.instance.cancelRestEnd());
    if (!mounted) return;
    setState(() {
      _restEndsAt = null;
      _restRemaining = 0;
      _restExerciseIndex = null;
      _restExercise = null;
    });
  }

  void _disposeExerciseAfterFrame(_ExerciseControllers input) {
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
  }

  void _disposeSetAfterFrame(_SetControllers input) {
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
  }

  Future<void> _showExerciseInfo(String title, String? value) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(
          (value ?? '').trim().isEmpty ? 'Brak danych w planie.' : value!,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openInstruction(PlanExercise exercise) async {
    final value = exercise.instructionUrl?.trim() ?? '';
    if (value.isEmpty) {
      await _showExerciseInfo(
        'Instrukcja',
        'Brak linku do instrukcji dla tego ćwiczenia.',
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

  Future<ExerciseLibraryItem?> _pickLibraryExercise() async {
    try {
      final exercises = await AppScope.of(
        context,
      ).api.exerciseLibraryItems(userLogin: widget.userLogin);
      if (!mounted) return null;
      if (exercises.isEmpty) {
        showError(
          context,
          const ApiException('Biblioteka ćwiczeń jest pusta.'),
        );
        return null;
      }

      return showDialog<ExerciseLibraryItem>(
        context: context,
        builder: (dialogContext) =>
            _LibraryExercisePickerDialog(exercises: exercises),
      );
    } catch (error) {
      if (mounted) showError(context, error);
      return null;
    }
  }

  Future<PlanExercise?> _editExercise({
    PlanExercise? initial,
    String? fixedName,
  }) {
    return showDialog<PlanExercise>(
      context: context,
      builder: (dialogContext) => _ExerciseEditorDialog(
        initial: initial,
        fixedName: fixedName,
        defaultOrder: initial?.order ?? _inputs.length + 1,
      ),
    );
  }

  PlanExercise _withSetCount(PlanExercise exercise, int setCount) {
    return PlanExercise(
      id: exercise.id,
      name: exercise.name,
      sets: setCount,
      recommendedReps: exercise.recommendedReps,
      restDescription: exercise.restDescription,
      restSeconds: exercise.restSeconds,
      rir: exercise.rir,
      tempo: exercise.tempo,
      instructionUrl: exercise.instructionUrl,
      order: exercise.order,
    );
  }

  void _addSet(int exerciseIndex) {
    final input = _inputs[exerciseIndex];
    setState(() {
      input.sets.add(_SetControllers());
      input.exercise = _withSetCount(input.exercise, input.sets.length);
    });
  }

  Future<void> _removeSet(int exerciseIndex) async {
    final input = _inputs[exerciseIndex];
    if (input.sets.length <= 1) return;

    final lastSet = input.sets.last;
    final hasData =
        lastSet.reps.text.trim().isNotEmpty ||
        lastSet.weight.text.trim().isNotEmpty;
    if (hasData) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Usunąć ostatnią serię?'),
          content: const Text(
            'W ostatniej serii są wpisane dane. Po usunięciu nie będzie można ich odzyskać.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Usuń serię'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    late final _SetControllers removed;
    setState(() {
      removed = input.sets.removeLast();
      input.exercise = _withSetCount(input.exercise, input.sets.length);
    });
    _disposeSetAfterFrame(removed);
  }

  void _replaceInput(int index, PlanExercise exercise) {
    if (_restExerciseIndex == index) _stopRest();
    final old = _inputs[index];
    final replacement = _ExerciseControllers(exercise);
    final copiedSets = old.sets.length < replacement.sets.length
        ? old.sets.length
        : replacement.sets.length;
    for (var i = 0; i < copiedSets; i++) {
      replacement.sets[i].reps.text = old.sets[i].reps.text;
      replacement.sets[i].weight.text = old.sets[i].weight.text;
    }
    setState(() => _inputs[index] = replacement);
    _disposeExerciseAfterFrame(old);
    _loadLastResultFor(exercise.name);
  }

  Future<void> _loadLastResultFor(String exerciseName) async {
    try {
      final result = await AppScope.of(
        context,
      ).api.lastExercisePerformance(exerciseName, userLogin: widget.userLogin);
      if (!mounted) return;
      setState(() {
        _lastResults[result.exerciseName.toLowerCase().trim()] = result;
      });
    } catch (_) {
      // Brak historii nie blokuje edycji bieżącego treningu.
    }
  }

  Future<void> _removeExercise(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć ćwiczenie?'),
        content: Text(
          'Ćwiczenie „${_inputs[index].exercise.name}” zostanie usunięte tylko z bieżącego treningu.',
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
    final activeRestIndex = _restExerciseIndex;
    if (activeRestIndex == index) {
      _stopRest();
    } else if (activeRestIndex != null && activeRestIndex > index) {
      setState(() => _restExerciseIndex = activeRestIndex - 1);
    }
    late final _ExerciseControllers removed;
    setState(() => removed = _inputs.removeAt(index));
    _disposeExerciseAfterFrame(removed);
  }

  Future<void> _replaceFromLibrary(int index) async {
    final selected = await _pickLibraryExercise();
    if (selected == null || !mounted) return;
    final old = _inputs[index].exercise;
    final defaults = selected.toPlanExercise(order: old.order, id: old.id);
    final replacement = await _editExercise(
      initial: defaults,
      fixedName: selected.name,
    );
    if (replacement != null && mounted) _replaceInput(index, replacement);
  }

  Future<void> _replaceWithNew(int index) async {
    final replacement = await _editExercise(initial: _inputs[index].exercise);
    if (replacement != null && mounted) _replaceInput(index, replacement);
  }

  Future<void> _addExercise() async {
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

    PlanExercise? exercise;
    if (source == 'library') {
      final selected = await _pickLibraryExercise();
      if (selected == null || !mounted) return;
      exercise = await _editExercise(
        initial: selected.toPlanExercise(order: _inputs.length + 1),
        fixedName: selected.name,
      );
    } else {
      exercise = await _editExercise();
    }
    if (exercise == null || !mounted) return;
    final addedExercise = exercise;
    setState(() => _inputs.add(_ExerciseControllers(addedExercise)));
    _loadLastResultFor(addedExercise.name);
  }

  Future<void> _handleExerciseMenu(int index, String value) async {
    final exercise = _inputs[index].exercise;
    switch (value) {
      case 'rir':
        await _showExerciseInfo('RIR', exercise.rir);
        return;
      case 'tempo':
        await _showExerciseInfo('Tempo', exercise.tempo);
        return;
      case 'instruction':
        await _openInstruction(exercise);
        return;
      case 'comment':
        await showExerciseCommentDialog(
          context,
          exerciseName: exercise.name,
          userLogin: widget.userLogin,
        );
        return;
      case 'delete':
        await _removeExercise(index);
        return;
      case 'library':
        await _replaceFromLibrary(index);
        return;
      case 'new':
        await _replaceWithNew(index);
        return;
    }
  }

  Future<void> _save() async {
    final exercises = <Map<String, dynamic>>[];
    var nonEmptySets = 0;
    var completedExercises = 0;

    for (final item in _inputs) {
      final sets = <Map<String, dynamic>>[];
      var exerciseCompleted = false;
      for (var i = 0; i < item.sets.length; i++) {
        final repetitions = int.tryParse(item.sets[i].reps.text.trim()) ?? 0;
        final normalizedWeight = item.sets[i].weight.text.trim().replaceAll(
          ',',
          '.',
        );
        final weight = double.tryParse(normalizedWeight) ?? 0;
        if (repetitions > 0 || weight > 0) {
          nonEmptySets++;
          exerciseCompleted = true;
        }
        sets.add({
          'set_number': i + 1,
          'repetitions': repetitions,
          'weight': weight,
        });
      }
      if (exerciseCompleted) completedExercises++;
      exercises.add({'name': item.exercise.name, 'sets': sets});
    }

    if (nonEmptySets == 0) {
      showError(
        context,
        const ApiException('Uzupełnij przynajmniej jedną serię.'),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zapisać trening?'),
        content: const Text(
          'Czy na pewno chcesz zakończyć i zapisać ten trening?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Jeszcze nie'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Tak, zapisz'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final savingNotice = ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(days: 1),
        content: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Trening jest zapisywany. Nie zamykaj aplikacji…',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
    var savingNoticeClosed = false;
    void closeSavingNotice() {
      if (savingNoticeClosed) return;
      savingNoticeClosed = true;
      savingNotice.close();
    }

    try {
      final details = await AppScope.of(context).api.saveWorkout({
        'plan_name': widget.plan.name,
        'started_at': _startedAt.toIso8601String(),
        'duration_minutes': (_elapsed.inSeconds / 60).ceil(),
        'exercises': exercises,
      }, userLogin: widget.userLogin);
      if (!mounted) return;
      closeSavingNotice();
      AppScope.read(context).notifyDataChanged();
      _stopRest();
      setState(() => _allowPop = true);
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutSummaryScreen(
            details: details,
            completedExerciseCount: completedExercises,
            plannedExerciseCount: _inputs.length,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      closeSavingNotice();
      if (mounted) setState(() => _saving = false);
    }
  }

  String _durationText(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _restDurationText(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Przerwać trening?'),
        content: const Text(
          'Niezapisane dane z tego treningu zostaną utracone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zostań'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Przerwij'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String? _lastSetText(_ExerciseControllers input, int setIndex) {
    final result = _lastResults[input.exercise.name.toLowerCase().trim()];
    if (result == null || setIndex >= result.sets.length) return null;
    final set = result.sets[setIndex];
    final plan = result.planName == null ? '' : ' • ${result.planName}';
    return 'Ostatnio$plan: ${set.repetitions} powt. / ${formatNumber(set.weight, decimals: 1)} kg';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _allowPop) return;
        if (await _confirmExit() && context.mounted) {
          _stopRest();
          setState(() => _allowPop = true);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.plan.name),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(
                  _durationText(_elapsed),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        body: GymProgresPageBody(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 180),
            itemCount: _inputs.length,
            itemBuilder: (context, actualIndex) {
              final input = _inputs[actualIndex];
              return Card(
                key: ObjectKey(input.identity),
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
                            child: Text('${actualIndex + 1}'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              input.exercise.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) =>
                                _handleExerciseMenu(actualIndex, value),
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
                              PopupMenuItem(value: 'rir', child: Text('RIR')),
                              PopupMenuItem(
                                value: 'tempo',
                                child: Text('Tempo'),
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
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Usuń z tego treningu'),
                              ),
                              PopupMenuItem(
                                value: 'library',
                                child: Text('Zamień na ćwiczenie z biblioteki'),
                              ),
                              PopupMenuItem(
                                value: 'new',
                                child: Text('Zamień na nowe ćwiczenie'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Plan: ${input.exercise.recommendedReps} powt. • przerwa ${input.exercise.restDescription}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child:
                            _restExerciseIndex == actualIndex &&
                                _restRemaining > 0
                            ? FilledButton.tonalIcon(
                                onPressed: _stopRest,
                                icon: const Icon(Icons.stop_circle_outlined),
                                label: Text(
                                  'Przerwa ${_restDurationText(_restRemaining)}',
                                ),
                              )
                            : OutlinedButton.icon(
                                onPressed: () =>
                                    _startRest(input.exercise, actualIndex),
                                icon: const Icon(Icons.timer_outlined),
                                label: Text(
                                  'Start przerwy (${input.exercise.restSeconds}s)',
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      for (
                        var setIndex = 0;
                        setIndex < input.sets.length;
                        setIndex++
                      ) ...[
                        Text(
                          'Seria ${setIndex + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (_lastSetText(input, setIndex) != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            _lastSetText(input, setIndex)!,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: input.sets[setIndex].reps,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Powtórzenia',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: input.sets[setIndex].weight,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Ciężar',
                                  suffixText: 'kg',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: input.sets.length <= 1
                                  ? null
                                  : () => _removeSet(actualIndex),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('Usuń serię'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _addSet(actualIndex),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Dodaj serię'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          'Liczba serii: ${input.sets.length}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _addExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj ćwiczenie'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _saving ? 'Zapisywanie…' : 'Zakończ i zapisz trening',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _normalizeExerciseSearch(String value) {
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

int _parseRestSecondsValue(String value) {
  final lower = value.toLowerCase();
  final matches = RegExp(r'\d+').allMatches(lower).toList();
  if (matches.isEmpty) return 60;
  final number = int.tryParse(matches.last.group(0)!) ?? 60;
  return lower.contains('min') ? number * 60 : number;
}

class _LibraryExercisePickerDialog extends StatefulWidget {
  const _LibraryExercisePickerDialog({required this.exercises});

  final List<ExerciseLibraryItem> exercises;

  @override
  State<_LibraryExercisePickerDialog> createState() =>
      _LibraryExercisePickerDialogState();
}

class _LibraryExercisePickerDialogState
    extends State<_LibraryExercisePickerDialog> {
  late final TextEditingController _searchController;
  late final List<ExerciseLibraryItem> _sortedExercises;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _sortedExercises = List<ExerciseLibraryItem>.from(widget.exercises)
      ..sort(
        (a, b) => _normalizeExerciseSearch(
          a.name,
        ).compareTo(_normalizeExerciseSearch(b.name)),
      );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ExerciseLibraryItem> get _filteredExercises {
    final normalizedQuery = _normalizeExerciseSearch(_query);
    if (normalizedQuery.isEmpty) return _sortedExercises;
    return _sortedExercises
        .where(
          (exercise) =>
              _normalizeExerciseSearch(exercise.name).contains(normalizedQuery),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredExercises = _filteredExercises;
    final dialogHeight = MediaQuery.sizeOf(context).height * 0.55;

    return AlertDialog(
      title: const Text('Wybierz ćwiczenie z biblioteki'),
      content: SizedBox(
        width: double.maxFinite,
        height: dialogHeight,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Szukaj ćwiczenia',
                hintText: 'Wpisz nazwę lub jej fragment',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Wyczyść wyszukiwanie',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredExercises.isEmpty
                  ? const Center(
                      child: Text('Nie znaleziono pasującego ćwiczenia.'),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filteredExercises.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final exercise = filteredExercises[index];
                        return ListTile(
                          title: Text(exercise.name),
                          subtitle: Text(
                            '${exercise.sets} serie • ${exercise.recommendedReps} powt. • ${exercise.restDescription}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, exercise),
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

class _ExerciseEditorDialog extends StatefulWidget {
  const _ExerciseEditorDialog({
    required this.defaultOrder,
    this.initial,
    this.fixedName,
  });

  final PlanExercise? initial;
  final String? fixedName;
  final int defaultOrder;

  @override
  State<_ExerciseEditorDialog> createState() => _ExerciseEditorDialogState();
}

class _ExerciseEditorDialogState extends State<_ExerciseEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _restController;
  late final TextEditingController _rirController;
  late final TextEditingController _tempoController;
  late final TextEditingController _instructionUrlController;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(
      text: widget.fixedName ?? initial?.name ?? '',
    );
    _setsController = TextEditingController(text: '${initial?.sets ?? 3}');
    _repsController = TextEditingController(
      text: initial?.recommendedReps ?? '10',
    );
    _restController = TextEditingController(
      text: initial?.restDescription ?? '60s',
    );
    _rirController = TextEditingController(text: initial?.rir ?? '');
    _tempoController = TextEditingController(text: initial?.tempo ?? '');
    _instructionUrlController = TextEditingController(
      text: initial?.instructionUrl ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    _restController.dispose();
    _rirController.dispose();
    _tempoController.dispose();
    _instructionUrlController.dispose();
    super.dispose();
  }

  void _submit() {
    final exerciseName = _nameController.text.trim();
    final numberOfSets = int.tryParse(_setsController.text.trim());

    if (exerciseName.isEmpty || numberOfSets == null || numberOfSets < 1) {
      setState(() {
        _validationMessage = 'Podaj nazwę ćwiczenia i poprawną liczbę serii.';
      });
      return;
    }

    final restDescription = _restController.text.trim().isEmpty
        ? '60s'
        : _restController.text.trim();

    Navigator.pop(
      context,
      PlanExercise(
        name: exerciseName,
        sets: numberOfSets,
        recommendedReps: _repsController.text.trim(),
        restDescription: restDescription,
        restSeconds: _parseRestSecondsValue(restDescription),
        rir: _rirController.text.trim().isEmpty
            ? null
            : _rirController.text.trim(),
        tempo: _tempoController.text.trim().isEmpty
            ? null
            : _tempoController.text.trim(),
        instructionUrl: _instructionUrlController.text.trim().isEmpty
            ? null
            : _instructionUrlController.text.trim(),
        order: widget.initial?.order ?? widget.defaultOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdding = widget.initial == null || widget.initial?.id == null;

    return AlertDialog(
      title: Text(isAdding ? 'Dodaj ćwiczenie' : 'Zamień ćwiczenie'),
      content: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_validationMessage != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _validationMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _nameController,
              enabled: widget.fixedName == null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nazwa ćwiczenia'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _setsController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Serie'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _repsController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Powtórzenia'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _restController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Przerwa, np. 60s lub 2 min',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rirController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'RIR (opcjonalnie)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tempoController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Tempo (opcjonalnie)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _instructionUrlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Link do instrukcji (opcjonalnie)',
                hintText: 'https://youtu.be/...',
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
        FilledButton(onPressed: _submit, child: const Text('Zapisz')),
      ],
    );
  }
}

class WorkoutSummaryScreen extends StatelessWidget {
  const WorkoutSummaryScreen({
    required this.details,
    required this.completedExerciseCount,
    required this.plannedExerciseCount,
    super.key,
  });

  final WorkoutDetails details;
  final int completedExerciseCount;
  final int plannedExerciseCount;

  int get completionPercent {
    if (plannedExerciseCount <= 0) return 0;
    return ((completedExerciseCount / plannedExerciseCount) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final percent = completionPercent.clamp(0, 100);
    return Scaffold(
      appBar: AppBar(title: const Text('Podsumowanie treningu')),
      body: GymProgresPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
          children: [
            Card(
              color: const Color(0xFF183A24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.emoji_events,
                      color: Colors.amber,
                      size: 68,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Gratulacje!',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Trening „${details.planName}” został zapisany.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '$completedExerciseCount z $plannedExerciseCount ćwiczeń',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$percent% wykonania planu',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryMetric(
                            icon: Icons.fitness_center,
                            label: 'Objętość',
                            value: '${formatNumber(details.totalVolume)} kg',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryMetric(
                            icon: Icons.schedule,
                            label: 'Czas treningu',
                            value: '${details.durationMinutes ?? 0} min',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _VolumeComparison(details: details),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Wróć do planów'),
        ),
      ),
    );
  }
}

class _VolumeComparison extends StatelessWidget {
  const _VolumeComparison({required this.details});

  final WorkoutDetails details;

  @override
  Widget build(BuildContext context) {
    final previous = details.previousSamePlanVolume;
    final change = details.volumeChange;
    final percent = details.volumeChangePercent;

    if (previous == null || change == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.auto_graph_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'To pierwszy zapis treningu o tej nazwie — porównanie objętości pojawi się następnym razem.',
              ),
            ),
          ],
        ),
      );
    }

    final increased = change > 0.005;
    final decreased = change < -0.005;
    final icon = increased
        ? Icons.trending_up
        : decreased
        ? Icons.trending_down
        : Icons.trending_flat;
    final changeLabel = increased
        ? 'Objętość wzrosła'
        : decreased
        ? 'Objętość spadła'
        : 'Objętość bez zmian';
    final absolute = '${formatNumber(change.abs())} kg';
    final percentLabel = percent == null
        ? ''
        : ' (${increased
              ? '+'
              : decreased
              ? '−'
              : ''}${formatNumber(percent.abs(), decimals: 1)}%)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  increased || decreased
                      ? '$changeLabel o $absolute$percentLabel'
                      : changeLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Poprzedni „${details.planName}”: ${formatNumber(previous)} kg',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
