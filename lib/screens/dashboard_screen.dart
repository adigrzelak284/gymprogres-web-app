import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/ui_helpers.dart';
import '../widgets/common_widgets.dart';
import 'admin_screen.dart';
import 'history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  WorkoutSummary? _latest;
  List<Map<String, dynamic>> _recommendations = const [];
  List<VolumePoint> _volume = const [];
  List<TrainerInvitation> _invitations = const [];
  String? _invitationBusyId;
  bool _loading = true;
  Object? _error;

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
    final controller = AppScope.of(context);
    final api = controller.api;
    final user = controller.user!;
    try {
      final results = await Future.wait([
        api.listWorkouts(limit: 1),
        api.currentDietRecommendations(),
        api.volume(limit: 12),
        if (user.isTrainee && user.trainerLogin == null)
          api.incomingTrainerInvitations()
        else
          Future<List<TrainerInvitation>>.value(const []),
      ]);
      if (!mounted) return;
      final workouts = results[0] as List<WorkoutSummary>;
      setState(() {
        _latest = workouts.isEmpty ? null : workouts.first;
        _recommendations = results[1] as List<Map<String, dynamic>>;
        _volume = results[2] as List<VolumePoint>;
        _invitations = results[3] as List<TrainerInvitation>;
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

  Future<void> _acceptInvitation(TrainerInvitation invitation) async {
    if (_invitationBusyId != null) return;

    setState(() => _invitationBusyId = invitation.id);
    final controller = AppScope.read(context);

    TrainerInvitationActionResult result;
    try {
      // Najpierw wykonujemy samą operację akceptacji. Dopiero jej błąd może być
      // pokazany jako błąd akceptowania zaproszenia.
      result = await controller.api.acceptTrainerInvitation(invitation.id);
    } catch (error) {
      if (mounted) showError(context, error);
      if (mounted) setState(() => _invitationBusyId = null);
      return;
    }

    if (!mounted) return;

    // API zaakceptowało zaproszenie, więc od razu aktualizujemy ekran i
    // pokazujemy sukces. Ewentualny problem z późniejszym odświeżaniem sesji
    // nie może już zamienić poprawnej akceptacji w komunikat o błędzie.
    setState(() {
      _invitations = _invitations
          .where((item) => item.id != invitation.id)
          .toList(growable: false);
    });
    showSuccess(
      context,
      result.message.trim().isEmpty
          ? 'Zaproszenie zostało zaakceptowane.'
          : result.message,
    );

    try {
      // Odświeżamy tylko użytkownika. Stan subskrypcji zostanie pobrany
      // niezależnie i nie blokuje zakończenia akceptacji zaproszenia.
      await controller.refreshCurrentUser(refreshSubscription: false);
    } catch (_) {
      // Przypisanie jest już zapisane w API. Dane sesji odświeżą się przy
      // kolejnym wejściu na ekran lub ponownym uruchomieniu aplikacji.
    }

    if (!mounted) return;
    controller.notifyDataChanged();

    if (result.personalSubscriptionActive &&
        result.personalSubscriptionAutoRenew == true) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Masz aktywną subskrypcję Personal'),
          content: const Text(
            'Od teraz korzystasz również z pakietu trenera. Twoja własna '
            'subskrypcja Personal nie została automatycznie anulowana. '
            'Wyłącz jej odnawianie w Google Play albo App Store, aby uniknąć '
            'kolejnej opłaty.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Rozumiem'),
            ),
          ],
        ),
      );
    }

    if (mounted) setState(() => _invitationBusyId = null);
  }

  Future<void> _rejectInvitation(TrainerInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Odrzucić zaproszenie?'),
        content: Text(
          'Zaproszenie od trenera ${invitation.trainerLogin} zostanie odrzucone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Odrzuć'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _invitationBusyId = invitation.id);
    try {
      final result = await AppScope.read(
        context,
      ).api.rejectTrainerInvitation(invitation.id);
      if (!mounted) return;
      showSuccess(context, result.message);
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, error);
    } finally {
      if (mounted) setState(() => _invitationBusyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.user!;
    if (_loading) {
      return const LoadingView();
    }
    if (_error != null) {
      return ErrorView(message: errorText(_error!), onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _refreshAllViews,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (user.isAdmin)
            Card(
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A1430), Color(0xFF121827)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x55A78BFA)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0x28A78BFA),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: const Color(0x66A78BFA)),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings,
                        color: Color(0xFFA78BFA),
                        size: 31,
                      ),
                    ),
                    const SizedBox(width: 17),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Centrum administracyjne',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x2EA78BFA),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0x66A78BFA),
                                  ),
                                ),
                                child: const Text(
                                  'ADMIN',
                                  style: TextStyle(
                                    color: Color(0xFFD8C9FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Zalogowano jako ${user.displayName}. Zarządzaj kontami, '
                            'hasłami i dostępem użytkowników GymProgres.',
                            style: const TextStyle(
                              color: Color(0xFFC3BAD7),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminUsersScreen(),
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                      ),
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: const Text('Otwórz panel admina'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cześć, ${user.displayName}!',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Typ konta: ${user.accountTypeLabel}'),
                    if (user.trainerLogin != null)
                      Text('Twój trener: ${user.trainerLogin}'),
                  ],
                ),
              ),
            ),
          if (_invitations.isNotEmpty)
            SectionCard(
              title: 'Zaproszenia od trenerów',
              icon: Icons.mark_email_unread_outlined,
              child: Column(
                children: [
                  for (final invitation in _invitations)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trener ${invitation.trainerLogin}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Zaproszenie ważne do '
                              '${appDateTimeFormat.format(invitation.expiresAt)}.',
                              style: const TextStyle(color: Colors.white60),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed:
                                        _invitationBusyId == invitation.id
                                        ? null
                                        : () => _rejectInvitation(invitation),
                                    child: const Text('Odrzuć'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    onPressed:
                                        _invitationBusyId == invitation.id
                                        ? null
                                        : () => _acceptInvitation(invitation),
                                    child: _invitationBusyId == invitation.id
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Akceptuj'),
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
          if (_latest != null)
            MetricTile(
              label: 'Ostatni trening',
              value:
                  '${_latest!.planName} • ${appDateFormat.format(_latest!.startedAt)}',
              icon: Icons.fitness_center,
            )
          else
            const MetricTile(
              label: 'Ostatni trening',
              value: 'Brak zapisanych treningów',
              icon: Icons.fitness_center,
            ),
          WorkoutVolumeChart(
            points: _volume,
            height: 170,
            emptyMessage: 'Wykres pojawi się po zapisaniu pierwszego treningu.',
          ),
          SectionCard(
            title: 'Aktualne zalecenia diety',
            icon: Icons.restaurant_menu,
            child: _recommendations.isEmpty
                ? const Text('Brak aktualnych zaleceń.')
                : Column(
                    children: _recommendations.map((item) {
                      final type = item['day_type'] == 'treningowy'
                          ? 'Dzień treningowy'
                          : 'Dzień nietreningowy';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(type),
                        subtitle: Text(
                          '${item['calories']} kcal • B ${item['protein']} g • T ${item['fat']} g • W ${item['carbohydrates']} g',
                        ),
                      );
                    }).toList(),
                  ),
          ),
          if (user.isAdmin)
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Panel administratora'),
                subtitle: const Text(
                  'Twórz konta, resetuj hasła i zarządzaj użytkownikami.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
