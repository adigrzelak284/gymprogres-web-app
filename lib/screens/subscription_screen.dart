import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_scope.dart';
import '../core/models.dart';

import '../core/web_page_body.dart';

const List<SubscriptionPlan> _approvedSubscriptionPlans = [
  SubscriptionPlan(
    code: 'personal',
    displayName: 'Personal Pro',
    accountType: 'personal',
    entitlementId: 'personal',
    fullAccess: true,
    products: [
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'monthly',
        productId: 'dt_personal:monthly',
        revenueCatPackageId: 'personal_monthly',
        pricePln: 9.99,
        trialDays: 14,
      ),
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'yearly',
        productId: 'dt_personal:yearly',
        revenueCatPackageId: 'personal_yearly',
        pricePln: 79.99,
        trialDays: 14,
      ),
    ],
  ),
  SubscriptionPlan(
    code: 'trainer_start',
    displayName: 'Trener Start',
    accountType: 'trainer',
    traineeLimit: 15,
    entitlementId: 'trainer_start',
    fullAccess: true,
    products: [
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'monthly',
        productId: 'dt_trainer_start:monthly',
        revenueCatPackageId: 'trainer_start_monthly',
        pricePln: 39.99,
        trialDays: 14,
      ),
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'yearly',
        productId: 'dt_trainer_start:yearly',
        revenueCatPackageId: 'trainer_start_yearly',
        pricePln: 399.99,
        trialDays: 14,
      ),
    ],
  ),
  SubscriptionPlan(
    code: 'trainer_pro',
    displayName: 'Trener Pro',
    accountType: 'trainer',
    traineeLimit: 30,
    entitlementId: 'trainer_pro',
    fullAccess: true,
    products: [
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'monthly',
        productId: 'dt_trainer_pro:monthly',
        revenueCatPackageId: 'trainer_pro_monthly',
        pricePln: 89.99,
        trialDays: 14,
      ),
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'yearly',
        productId: 'dt_trainer_pro:yearly',
        revenueCatPackageId: 'trainer_pro_yearly',
        pricePln: 899.99,
        trialDays: 14,
      ),
    ],
  ),
  SubscriptionPlan(
    code: 'trainer_studio',
    displayName: 'Trener Studio',
    accountType: 'trainer',
    traineeLimit: 60,
    entitlementId: 'trainer_studio',
    fullAccess: true,
    products: [
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'monthly',
        productId: 'dt_trainer_studio:monthly',
        revenueCatPackageId: 'trainer_studio_monthly',
        pricePln: 149.99,
        trialDays: 14,
      ),
      SubscriptionProduct(
        store: 'google_play',
        billingPeriod: 'yearly',
        productId: 'dt_trainer_studio:yearly',
        revenueCatPackageId: 'trainer_studio_yearly',
        pricePln: 1499.99,
        trialDays: 14,
      ),
    ],
  ),
];


int? _priceStringToCents(String value) {
  var normalized = value
      .replaceAll('\u00a0', '')
      .replaceAll(RegExp(r'[^0-9,.]'), '');
  if (normalized.isEmpty) return null;

  final comma = normalized.lastIndexOf(',');
  final dot = normalized.lastIndexOf('.');
  if (comma >= 0 && dot >= 0) {
    final decimalSeparator = comma > dot ? ',' : '.';
    final thousandsSeparator = decimalSeparator == ',' ? '.' : ',';
    normalized = normalized.replaceAll(thousandsSeparator, '');
    normalized = normalized.replaceAll(decimalSeparator, '.');
  } else if (comma >= 0) {
    final decimals = normalized.length - comma - 1;
    normalized = decimals == 2
        ? normalized.replaceAll(',', '.')
        : normalized.replaceAll(',', '');
  } else if (dot >= 0) {
    final decimals = normalized.length - dot - 1;
    if (decimals != 2) normalized = normalized.replaceAll('.', '');
  }

  final amount = double.tryParse(normalized);
  return amount == null ? null : (amount * 100).round();
}

bool _storePriceMatchesApproved(String storePrice, double approvedPrice) {
  final storeCents = _priceStringToCents(storePrice);
  final approvedCents = (approvedPrice * 100).round();
  return storeCents != null && storeCents == approvedCents;
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String _period = 'monthly';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).refreshSubscriptions();
    });
  }

  bool _canPurchasePlan(AppUser user, SubscriptionPlan plan) {
    if (user.isAdmin) return false;
    if (user.trainerLogin != null && user.trainerLogin!.isNotEmpty) {
      return false;
    }
    if (user.isTrainer) return plan.accountType == 'trainer';
    return plan.accountType == 'personal';
  }

  String _disabledLabel(AppUser user, SubscriptionPlan plan) {
    if (user.isAdmin) return 'Cennik informacyjny';
    if (user.trainerLogin != null && user.trainerLogin!.isNotEmpty) {
      return 'Dostęp zapewnia trener';
    }
    if (user.isTrainer && plan.accountType != 'trainer') {
      return 'Plan dla użytkownika';
    }
    if (!user.isTrainer && plan.accountType == 'trainer') {
      return 'Plan dla trenerów';
    }
    return 'Płatności dostępne w wersji sklepowej';
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final user = controller.user!;
    final status = controller.subscription;
    final eligibleSubscriptionOwner =
        !user.isAdmin &&
        (user.trainerLogin == null || user.trainerLogin!.isEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('Subskrypcja')),
      body: GymProgresPageBody(
        child: RefreshIndicator(
          onRefresh: () => controller.refreshSubscriptions(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              SubscriptionSummaryCard(
                status: status,
                loading: controller.subscriptionLoading,
                onTap: null,
              ),
              if (controller.subscriptionError != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(child: Text(controller.subscriptionError!)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (user.isAdmin)
                const _InfoCard(
                  icon: Icons.admin_panel_settings,
                  title: 'Administrator',
                  text:
                      'Konto administratora nie wymaga subskrypcji. Poniżej znajduje się zatwierdzony cennik informacyjny.',
                )
              else if (status?.isProvidedByTrainer == true)
                _InfoCard(
                  icon: Icons.verified_user_outlined,
                  title: 'Dostęp zapewnia trener',
                  text:
                      'Korzystasz z aplikacji w ramach planu trenera ${status!.ownerLogin}. Nie musisz kupować osobnej subskrypcji.',
                ),
              const SizedBox(height: 16),
              Text(
                'Zatwierdzony cennik',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Wszystkie pakiety trenerskie mają pełny zakres funkcji i różnią się wyłącznie limitem podopiecznych oraz ceną.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 12),
              if (!user.isTrainer)
                const _FreePlanCard(
                  title: 'Personal Free',
                  limitText: '1 aktywny plan i podstawowa historia treningów',
                )
              else
                const _FreePlanCard(
                  title: 'Trener Free',
                  limitText: 'Do 3 aktywnych podopiecznych',
                ),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'monthly', label: Text('Miesięcznie')),
                  ButtonSegment(
                    value: 'yearly',
                    label: Text('Rocznie • korzystniej'),
                  ),
                ],
                selected: {_period},
                onSelectionChanged: (value) {
                  setState(() => _period = value.first);
                },
              ),
              const SizedBox(height: 16),
              for (final plan in _approvedSubscriptionPlans)
                _PlanCard(
                  plan: plan,
                  period: _period,
                  recommended: plan.code == 'trainer_pro',
                  purchaseEligible: _canPurchasePlan(user, plan),
                  disabledLabel: _disabledLabel(user, plan),
                ),
              if (user.isTrainer)
                const _FreePlanCard(
                  title: 'Trener Business',
                  limitText: 'Powyżej 60 podopiecznych — wycena indywidualna',
                  business: true,
                ),
              const SizedBox(height: 12),
              if (eligibleSubscriptionOwner)
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.restore),
                        title: const Text('Przywróć wcześniejszy zakup'),
                        subtitle: const Text(
                          'Użyj tego po zmianie telefonu lub ponownej instalacji.',
                        ),
                        onTap: controller.purchaseBusy
                            ? null
                            : () => _restore(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.manage_accounts_outlined),
                        title: const Text('Zarządzaj subskrypcją w sklepie'),
                        onTap: _openStoreSubscriptions,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Bezpłatny okres próbny jest dostępny dla kwalifikujących się nowych subskrybentów. Po 14 dniach subskrypcja odnawia się automatycznie zgodnie z ceną pokazaną przez Google Play lub App Store, chyba że zostanie wcześniej anulowana.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final controller = AppScope.read(context);
    final ok = await controller.restorePurchases();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Zakupy zostały przywrócone. Status może zaktualizować się po kilku sekundach.'
              : controller.subscriptionError ??
                    'Nie udało się przywrócić zakupu.',
        ),
      ),
    );
  }

  Future<void> _openStoreSubscriptions() async {
    if (kIsWeb) return;
    final url = Platform.isAndroid
        ? Uri.parse('https://play.google.com/store/account/subscriptions')
        : Uri.parse('https://apps.apple.com/account/subscriptions');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

class SubscriptionSummaryCard extends StatelessWidget {
  const SubscriptionSummaryCard({
    required this.status,
    required this.loading,
    required this.onTap,
    super.key,
  });

  final SubscriptionStatusInfo? status;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = status;
    final title = value?.planName ?? 'Subskrypcja';
    String subtitle;
    if (loading && value == null) {
      subtitle = 'Sprawdzanie statusu…';
    } else if (value == null) {
      subtitle = 'Otwórz, aby sprawdzić dostęp';
    } else if (value.isProvidedByTrainer) {
      subtitle = 'Dostęp przez trenera ${value.ownerLogin}';
    } else if (value.trial && value.daysRemaining != null) {
      subtitle = '${value.statusLabel} • pozostało ${value.daysRemaining} dni';
    } else {
      subtitle = value.statusLabel;
    }
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  value?.canWrite == false ? Icons.lock_outline : Icons.star,
                ),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _FreePlanCard extends StatelessWidget {
  const _FreePlanCard({
    required this.title,
    required this.limitText,
    this.business = false,
  });

  final String title;
  final String limitText;
  final bool business;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              business ? 'Wycena indywidualna' : '0,00 zł',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text('✓ $limitText'),
            if (!business) const Text('✓ Bez podawania karty'),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.period,
    required this.recommended,
    required this.purchaseEligible,
    required this.disabledLabel,
  });

  final SubscriptionPlan plan;
  final String period;
  final bool recommended;
  final bool purchaseEligible;
  final String disabledLabel;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final status = controller.subscription;
    SubscriptionProduct? product;
    for (final item in plan.products) {
      if (item.billingPeriod == period) {
        product = item;
        break;
      }
    }
    if (product == null) return const SizedBox.shrink();
    final selectedProduct = product;

    final storePackage = controller.storePackage(
      selectedProduct.revenueCatPackageId,
    );
    final formatter = NumberFormat.currency(
      locale: 'pl_PL',
      symbol: 'zł',
      decimalDigits: 2,
    );
    final approvedPrice = formatter.format(selectedProduct.pricePln);
    final suffix = period == 'yearly' ? ' / rok' : ' / miesiąc';
    final storePriceMatches = storePackage != null &&
        _storePriceMatchesApproved(
          storePackage.price,
          selectedProduct.pricePln,
        );
    final storeReady =
        purchaseEligible &&
        status?.revenueCatReady == true &&
        controller.purchases.readyForStore &&
        storePackage != null &&
        storePriceMatches;

    String buttonLabel;
    if (!purchaseEligible) {
      buttonLabel = disabledLabel;
    } else if (storePackage != null && !storePriceMatches) {
      buttonLabel = 'Aktualizujemy cenę w Google Play';
    } else if (storeReady) {
      buttonLabel = 'Rozpocznij 14 dni bezpłatnie';
    } else {
      buttonLabel = 'Płatności dostępne w wersji sklepowej';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: recommended
          ? RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (recommended)
                  const Chip(label: Text('Najczęściej wybierany')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              approvedPrice + suffix,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (period == 'yearly')
              Text(
                'Około ${formatter.format(selectedProduct.pricePln / 12)} miesięcznie',
              ),
            if (storePackage != null) ...[
              const SizedBox(height: 8),
              if (storePriceMatches)
                Text(
                  'Cena w Google Play: ${storePackage.price}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    'Google Play ma jeszcze cenę ${storePackage.price}. '
                    'Zakup tego wariantu jest tymczasowo wyłączony do czasu '
                    'zaktualizowania ceny w sklepie.',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Text('✓ ${selectedProduct.trialDays} dni bezpłatnie'),
            const Text('✓ Pełny dostęp do funkcji aplikacji'),
            if (plan.traineeLimit != null)
              Text('✓ Do ${plan.traineeLimit} podopiecznych'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !storeReady || controller.purchaseBusy
                    ? null
                    : () => _purchase(
                        context,
                        selectedProduct.revenueCatPackageId,
                      ),
                child: controller.purchaseBusy && purchaseEligible
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _purchase(BuildContext context, String packageId) async {
    final controller = AppScope.read(context);
    final ok = await controller.purchaseSubscription(packageId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Zakup został przyjęty. Status może zaktualizować się po kilku sekundach.'
              : controller.subscriptionError ??
                    'Nie udało się rozpocząć zakupu.',
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
