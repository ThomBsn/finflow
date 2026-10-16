// Modèles des tables et vues Supabase utilisées par l'app
// (docs/modele-donnees.md). Montants en double : les calculs de solde
// sont faits côté base, le client ne fait qu'afficher et saisir.

typedef Json = Map<String, dynamic>;

double _money(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime _date(Object? v) => DateTime.parse(v! as String);

/// `installment_plans(installments)` embarqué par PostgREST (objet ou liste).
int? _embeddedInstallments(Object? v) => switch (v) {
  {'installments': final int n} => n,
  [{'installments': final int n}, ...] => n,
  _ => null,
};

String dbDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

enum TransactionType {
  depense('depense'),
  revenu('revenu'),
  transfertEpargne('transfert_epargne'),
  retraitEpargne('retrait_epargne'),
  transfert('transfert');

  const TransactionType(this.db);
  final String db;

  static TransactionType parse(String value) =>
      values.firstWhere((t) => t.db == value);
}

class Budget {
  const Budget({
    required this.id,
    required this.category,
    required this.monthlyAmount,
    required this.icon,
    required this.horsBudget,
  });

  factory Budget.fromJson(Json json) => Budget(
    id: json['id'] as String,
    category: json['category'] as String,
    monthlyAmount: _money(json['monthly_amount']),
    icon: json['icon'] as String,
    horsBudget: json['hors_budget'] as bool,
  );

  /// Budgets utilisés par les RPC : ni renommables ni supprimables.
  static const systemCategories = {'Abonnements', 'Frais externes'};

  final String id;
  final String category;
  final double monthlyAmount;
  final String icon;
  final bool horsBudget;

  bool get isSystem => systemCategories.contains(category);

  /// L'alloué d'« Abonnements » est calculé à partir des abonnements actifs.
  bool get hasComputedAmount => category == 'Abonnements';
}

/// Ligne de la vue `budget_status_current_month`.
class BudgetStatus {
  const BudgetStatus({
    required this.id,
    required this.category,
    required this.icon,
    required this.horsBudget,
    required this.allocated,
    required this.spent,
    required this.remaining,
    required this.reserved,
  });

  factory BudgetStatus.fromJson(Json json) => BudgetStatus(
    id: json['id'] as String,
    category: json['category'] as String,
    icon: json['icon'] as String,
    horsBudget: json['hors_budget'] as bool,
    allocated: _money(json['allocated']),
    spent: _money(json['spent']),
    remaining: _money(json['remaining']),
    reserved: _money(json['reserved']),
  );

  final String id;
  final String category;
  final String icon;
  final bool horsBudget;
  final double allocated;
  final double spent;
  final double remaining;

  /// Abonnements de la catégorie pas encore prélevés ce mois-ci.
  final double reserved;
}

class Transaction {
  const Transaction({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.label,
    required this.category,
    required this.horsBudget,
    required this.settled,
    required this.installments,
  });

  factory Transaction.fromJson(Json json) => Transaction(
    id: json['id'] as String,
    date: _date(json['date']),
    type: TransactionType.parse(json['type'] as String),
    amount: _money(json['amount']),
    label: json['label'] as String,
    category: json['category'] as String?,
    horsBudget: json['hors_budget'] as bool,
    settled: json['settled'] as bool,
    installments: _embeddedInstallments(json['installment_plans']),
  );

  final String id;
  final DateTime date;
  final TransactionType type;
  final double amount;
  final String label;
  final String? category;
  final bool horsBudget;
  final bool settled;

  /// Nombre de mois sur lesquels la dépense est étalée dans son budget.
  final int? installments;

  /// Ce que la RLS laisse modifier au client.
  bool get editable =>
      !settled &&
      (type == TransactionType.depense || type == TransactionType.revenu);

  /// Montant signé du point de vue du compte courant.
  double get signedAmount => switch (type) {
    TransactionType.revenu || TransactionType.retraitEpargne => amount,
    _ => -amount,
  };
}

/// Ligne de la vue `current_month_summary`.
class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.courant,
    required this.epargne,
    required this.unsettledExpenses,
    required this.safetyMargin,
    required this.suggestedSalary,
    required this.suggestedSharedTransfer,
    required this.budgetRemaining,
    required this.projectedSavings,
    required this.projectedSavingsBudgets,
  });

  factory MonthSummary.fromJson(Json json) => MonthSummary(
    month: _date(json['month']),
    courant: _money(json['courant']),
    epargne: _money(json['epargne']),
    unsettledExpenses: _money(json['unsettled_expenses']),
    safetyMargin: _money(json['safety_margin']),
    suggestedSalary: _money(json['suggested_salary']),
    suggestedSharedTransfer: _money(json['suggested_shared_transfer']),
    budgetRemaining: _money(json['budget_remaining']),
    projectedSavings: _money(json['projected_savings']),
    projectedSavingsBudgets: _money(json['projected_savings_budgets']),
  );

  final DateTime month;
  final double courant;
  final double epargne;

  /// Dépenses − revenus non réglés, déduits à la prochaine transition.
  final double unsettledExpenses;

  final double safetyMargin;

  /// Salaire et virement commun habituels (réglages, sinon mois en cours).
  final double suggestedSalary;
  final double suggestedSharedTransfer;

  /// Ce qui reste dans les enveloppes (abonnements à venir compris).
  final double budgetRemaining;

  /// Ce que la prochaine clôture épargnera au rythme actuel ; négatif : le
  /// courant passera d'autant sous la marge.
  final double projectedSavings;

  /// Même chose si les budgets sont dépensés jusqu'au bout.
  final double projectedSavingsBudgets;

  /// Salaire habituel pas encore renseigné : l'épargne prévue n'a pas de sens.
  bool get needsSalary => suggestedSalary <= 0;

  DateTime get nextMonth => DateTime(month.year, month.month + 1);
}

/// Résultat (ou aperçu) de `close_month`.
class CloseResult {
  const CloseResult({
    required this.totalExpenses,
    required this.totalSavings,
    required this.courant,
  });

  factory CloseResult.fromJson(Json json) => CloseResult(
    totalExpenses: _money(json['total_expenses']),
    totalSavings: _money(json['total_savings']),
    courant: _money(json['courant']),
  );

  final double totalExpenses;
  final double totalSavings;
  final double courant;
}

/// Résultat de `rebalance_from_safety_fund`.
class RebalanceResult {
  const RebalanceResult({required this.withdrawn, required this.remaining});

  factory RebalanceResult.fromJson(Json json) => RebalanceResult(
    withdrawn: _money(json['withdrawn']),
    remaining: _money(json['remaining']),
  );

  final double withdrawn;
  final double remaining;
}

/// Saisie d'une dépense ou d'un revenu (création si [id] est null).
class TransactionDraft {
  const TransactionDraft({
    this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.label,
    required this.category,
    required this.horsBudget,
  });

  final String? id;
  final DateTime date;
  final TransactionType type;
  final double amount;
  final String label;
  final String? category;
  final bool horsBudget;

  Json toJson() => {
    'date': dbDate(date),
    'type': type.db,
    'amount': amount,
    'label': label,
    'category': category,
    'hors_budget': horsBudget,
  };
}

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.amount,
    required this.billingDay,
    required this.active,
    this.category = Subscription.defaultCategory,
    this.lastChargeDate,
  });

  factory Subscription.fromJson(Json json) => Subscription(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    amount: _money(json['amount']),
    billingDay: json['billing_day'] as int,
    active: json['active'] as bool,
    lastChargeDate: json['last_charge_date'] == null
        ? null
        : _date(json['last_charge_date']),
  );

  final String id;
  final String name;
  final double amount;
  final int billingDay;
  final bool active;

  /// Budget du prélèvement (ex. assurance moto → Véhicule).
  final String category;
  final DateTime? lastChargeDate;

  static const defaultCategory = 'Abonnements';

  /// Prochain prélèvement à partir de [today] : jour ramené en fin de mois,
  /// mois suivant si celui de [today] est déjà prélevé ou passé.
  DateTime nextCharge(DateTime today) {
    DateTime chargeIn(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, billingDay > lastDay ? lastDay : billingDay);
    }

    final thisMonth = chargeIn(today.year, today.month);
    final charged =
        lastChargeDate != null &&
        lastChargeDate!.year == today.year &&
        lastChargeDate!.month == today.month;
    final todayDate = DateTime(today.year, today.month, today.day);
    return charged || thisMonth.isBefore(todayDate)
        ? chargeIn(today.year, today.month + 1)
        : thisMonth;
  }
}

/// Ligne de la vue `installment_plans_status` : dépense étalée sur son budget.
class InstallmentPlan {
  const InstallmentPlan({
    required this.id,
    required this.label,
    required this.category,
    required this.date,
    required this.totalAmount,
    required this.installments,
    required this.monthlyAmount,
    required this.currentNumber,
    required this.remainingCount,
    required this.remainingAmount,
  });

  factory InstallmentPlan.fromJson(Json json) => InstallmentPlan(
    id: json['id'] as String,
    label: json['label'] as String,
    category: json['category'] as String,
    date: _date(json['date']),
    totalAmount: _money(json['total_amount']),
    installments: json['installments'] as int,
    monthlyAmount: _money(json['monthly_amount']),
    currentNumber: json['current_number'] as int,
    remainingCount: json['remaining_count'] as int,
    remainingAmount: _money(json['remaining_amount']),
  );

  final String id;
  final String label;
  final String category;
  final DateTime date;
  final double totalAmount;
  final int installments;
  final double monthlyAmount;

  /// Rang de la mensualité du mois en cours (> [installments] : terminé).
  final int currentNumber;
  final int remainingCount;

  /// Part de la dépense qui pèsera encore sur les budgets des mois suivants.
  final double remainingAmount;

  bool get finished => currentNumber >= installments;
}

/// Ligne de la vue `budget_lines_current_month` : contribution d'une
/// transaction au consommé d'un budget du mois en cours.
class BudgetLine {
  const BudgetLine({
    required this.transactionId,
    required this.date,
    required this.label,
    required this.type,
    required this.amount,
    required this.transactionAmount,
    required this.installmentNumber,
    required this.installments,
  });

  factory BudgetLine.fromJson(Json json) => BudgetLine(
    transactionId: json['transaction_id'] as String,
    date: _date(json['date']),
    label: json['label'] as String,
    type: TransactionType.parse(json['type'] as String),
    amount: _money(json['amount']),
    transactionAmount: _money(json['transaction_amount']),
    installmentNumber: json['installment_number'] as int?,
    installments: json['installments'] as int?,
  );

  final String transactionId;
  final DateTime date;
  final String label;
  final TransactionType type;

  /// Contribution au consommé : mensualité si étalée, négative pour un revenu.
  final double amount;
  final double transactionAmount;
  final int? installmentNumber;
  final int? installments;

  bool get isInstallment => installments != null;
}

enum DistributionMode {
  automatique,
  precis;

  String get db => name;
}

class SavingsProject {
  const SavingsProject({
    required this.id,
    required this.name,
    required this.percentage,
    required this.targetAmount,
    required this.currentAmount,
    required this.isDefault,
    required this.isSafetyFund,
  });

  factory SavingsProject.fromJson(Json json) => SavingsProject(
    id: json['id'] as String,
    name: json['name'] as String,
    percentage: _money(json['percentage']),
    targetAmount: json['target_amount'] == null
        ? null
        : _money(json['target_amount']),
    currentAmount: _money(json['current_amount']),
    isDefault: json['is_default'] as bool,
    isSafetyFund: json['is_safety_fund'] as bool,
  );

  final String id;
  final String name;
  final double percentage;
  final double? targetAmount;
  final double currentAmount;

  /// Épargne générale : reçoit le complément à 100 %, sans objectif.
  final bool isDefault;

  /// Fond de sécurité : reçoit les excédents, sert au rééquilibrage.
  final bool isSafetyFund;

  bool get isSystem => isDefault || isSafetyFund;
  bool get isFull => targetAmount != null && currentAmount >= targetAmount!;
}

/// Mois clôturé (`monthly_settlements` réglé).
class ClosedMonth {
  const ClosedMonth({
    required this.id,
    required this.month,
    required this.totalExpenses,
    required this.totalSavings,
    required this.specialMonth,
    required this.closingBalance,
  });

  factory ClosedMonth.fromJson(Json json) => ClosedMonth(
    id: json['id'] as String,
    month: _date(json['month']),
    totalExpenses: _money(json['total_expenses']),
    totalSavings: _money(json['total_savings']),
    specialMonth: json['special_month'] as bool,
    closingBalance: json['closing_balance'] == null
        ? null
        : _money(json['closing_balance']),
  );

  final String id;
  final DateTime month;
  final double totalExpenses;
  final double totalSavings;
  final bool specialMonth;

  /// Null pour une clôture antérieure au suivi des flux.
  final double? closingBalance;
}

enum FlowKind {
  opening,
  salary,
  income,
  overdraft,
  expense,
  shared,
  savings,
  remaining,
  openingOverdraft;

  static FlowKind parse(String value) => switch (value) {
    'opening_overdraft' => openingOverdraft,
    _ => values.byName(value),
  };
}

/// Ligne de la vue `settlement_flows` : un flux d'une clôture.
class SettlementFlow {
  const SettlementFlow({
    required this.incoming,
    required this.kind,
    required this.label,
    required this.amount,
  });

  factory SettlementFlow.fromJson(Json json) => SettlementFlow(
    incoming: json['side'] == 'in',
    kind: FlowKind.parse(json['kind'] as String),
    label: json['label'] as String,
    amount: _money(json['amount']),
  );

  /// Entrée (d'où vient l'argent) ou sortie (où il est allé).
  final bool incoming;
  final FlowKind kind;
  final String label;
  final double amount;
}

/// Réglages de l'utilisateur (`settings`).
class Settings {
  const Settings({
    required this.defaultSalary,
    required this.defaultSharedTransfer,
    required this.safetyMargin,
  });

  factory Settings.fromJson(Json json) => Settings(
    defaultSalary: _money(json['default_salary']),
    defaultSharedTransfer: _money(json['default_shared_transfer']),
    safetyMargin: _money(json['safety_margin']),
  );

  final double defaultSalary;
  final double defaultSharedTransfer;
  final double safetyMargin;
}
