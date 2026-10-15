// Modèles des tables et vues Supabase utilisées par l'app
// (docs/modele-donnees.md). Montants en double : les calculs de solde
// sont faits côté base, le client ne fait qu'afficher et saisir.

typedef Json = Map<String, dynamic>;

double _money(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime _date(Object? v) => DateTime.parse(v! as String);

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
  });

  factory BudgetStatus.fromJson(Json json) => BudgetStatus(
    id: json['id'] as String,
    category: json['category'] as String,
    icon: json['icon'] as String,
    horsBudget: json['hors_budget'] as bool,
    allocated: _money(json['allocated']),
    spent: _money(json['spent']),
    remaining: _money(json['remaining']),
  );

  final String id;
  final String category;
  final String icon;
  final bool horsBudget;
  final double allocated;
  final double spent;
  final double remaining;
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
    required this.installmentPlanId,
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
    installmentPlanId: json['installment_plan_id'] as String?,
  );

  final String id;
  final DateTime date;
  final TransactionType type;
  final double amount;
  final String label;
  final String? category;
  final bool horsBudget;
  final bool settled;
  final String? installmentPlanId;

  /// Ce que la RLS laisse modifier au client.
  bool get editable =>
      !settled &&
      installmentPlanId == null &&
      (type == TransactionType.depense || type == TransactionType.revenu);

  /// Montant signé du point de vue du compte courant.
  double get signedAmount => switch (type) {
    TransactionType.revenu || TransactionType.retraitEpargne => amount,
    _ => -amount,
  };
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
