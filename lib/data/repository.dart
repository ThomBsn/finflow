import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Accès Supabase. Les filtres par utilisateur sont assurés par la RLS.
class FinflowRepository {
  FinflowRepository(this._db);

  final SupabaseClient _db;

  // Mois -------------------------------------------------------------------

  Future<bool> isOnboarded() async {
    final rows = await _db.from('monthly_settlements').select('id').limit(1);
    return rows.isNotEmpty;
  }

  /// Mois en cours (`pending`), null avant l'onboarding.
  Future<DateTime?> currentMonth() async {
    final row = await _db
        .from('monthly_settlements')
        .select('month')
        .eq('status', 'pending')
        .maybeSingle();
    return row == null ? null : DateTime.parse(row['month'] as String);
  }

  /// Tous les mois connus, du plus récent au plus ancien.
  Future<List<DateTime>> months() async {
    final rows = await _db
        .from('monthly_settlements')
        .select('month')
        .order('month', ascending: false);
    return [for (final r in rows) DateTime.parse(r['month'] as String)];
  }

  /// Résumé du mois en cours, null avant l'onboarding.
  Future<MonthSummary?> monthSummary() async {
    final row = await _db.from('current_month_summary').select().maybeSingle();
    return row == null ? null : MonthSummary.fromJson(row);
  }

  // Transition -------------------------------------------------------------

  Future<CloseResult> previewCloseMonth({
    required double salary,
    required double sharedTransfer,
    required bool specialMonth,
  }) async => CloseResult.fromJson(
    await _db.rpc<Json>(
      'preview_close_month',
      params: {
        'p_salary': salary,
        'p_shared_transfer': sharedTransfer,
        'p_special_month': specialMonth,
      },
    ),
  );

  Future<CloseResult> closeMonth({
    required DateTime month,
    required double salary,
    required double sharedTransfer,
    required bool specialMonth,
  }) async => CloseResult.fromJson(
    await _db.rpc<Json>(
      'close_month',
      params: {
        'p_month': dbDate(month),
        'p_salary': salary,
        'p_shared_transfer': sharedTransfer,
        'p_special_month': specialMonth,
      },
    ),
  );

  Future<RebalanceResult> rebalanceFromSafetyFund() async =>
      RebalanceResult.fromJson(
        await _db.rpc<Json>('rebalance_from_safety_fund'),
      );

  // Onboarding -------------------------------------------------------------

  Future<double> safetyMargin() async {
    final row = await _db.from('settings').select('safety_margin').single();
    return (row['safety_margin'] as num).toDouble();
  }

  Future<void> completeOnboarding({
    required double courant,
    required double safetyFund,
    required double generalSavings,
  }) => _db.rpc<void>(
    'complete_onboarding',
    params: {
      'p_courant': courant,
      'p_safety_fund': safetyFund,
      'p_general_savings': generalSavings,
    },
  );

  // Budgets ----------------------------------------------------------------

  Future<List<Budget>> budgets() async {
    final rows = await _db.from('budgets').select().order('category');
    return rows.map(Budget.fromJson).toList();
  }

  Future<List<BudgetStatus>> budgetStatus() async {
    final rows = await _db
        .from('budget_status_current_month')
        .select()
        .order('category');
    return rows.map(BudgetStatus.fromJson).toList();
  }

  Future<void> saveBudget({
    String? id,
    required String category,
    required double monthlyAmount,
    required String icon,
    required bool horsBudget,
  }) async {
    final values = {
      'category': category,
      'monthly_amount': monthlyAmount,
      'icon': icon,
      'hors_budget': horsBudget,
    };
    if (id == null) {
      await _db.from('budgets').insert(values);
    } else {
      await _db.from('budgets').update(values).eq('id', id);
    }
  }

  Future<void> deleteBudget(String id) =>
      _db.from('budgets').delete().eq('id', id);

  // Transactions -----------------------------------------------------------

  Future<List<Transaction>> transactions({
    required DateTime month,
    String? category,
  }) async {
    var query = _db
        .from('transactions')
        .select('*, installment_plans(installments)')
        .eq('month', dbDate(month));
    if (category != null) query = query.eq('category', category);
    final rows = await query
        .order('date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(Transaction.fromJson).toList();
  }

  /// Crée ou modifie la transaction ; renvoie son id.
  Future<String> saveTransaction(TransactionDraft draft) async {
    if (draft.id == null) {
      final row = await _db
          .from('transactions')
          .insert(draft.toJson())
          .select('id')
          .single();
      return row['id'] as String;
    }
    await _db.from('transactions').update(draft.toJson()).eq('id', draft.id!);
    return draft.id!;
  }

  Future<void> deleteTransaction(String id) =>
      _db.from('transactions').delete().eq('id', id);

  // Abonnements ------------------------------------------------------------

  Future<List<Subscription>> subscriptions() async {
    final rows = await _db.from('subscriptions').select().order('name');
    return rows.map(Subscription.fromJson).toList();
  }

  Future<void> saveSubscription({
    String? id,
    required String name,
    required double amount,
    required int billingDay,
    required bool active,
  }) async {
    final values = {
      'name': name,
      'amount': amount,
      'billing_day': billingDay,
      'active': active,
    };
    if (id == null) {
      await _db.from('subscriptions').insert(values);
    } else {
      await _db.from('subscriptions').update(values).eq('id', id);
    }
  }

  Future<void> deleteSubscription(String id) =>
      _db.from('subscriptions').delete().eq('id', id);

  // Échelonnements ---------------------------------------------------------

  Future<List<InstallmentPlan>> installmentPlans() async {
    final rows = await _db
        .from('installment_plans_status')
        .select()
        .order('date', ascending: false);
    return rows.map(InstallmentPlan.fromJson).toList();
  }

  /// Étale (ou n'étale plus si [installments] est null) une dépense sur son
  /// budget. [current] : étalement actuel de la dépense.
  Future<void> setInstallments(
    String transactionId, {
    required int? installments,
    required int? current,
  }) async {
    if (installments == current) return;
    final plans = _db.from('installment_plans');
    if (installments == null) {
      await plans.delete().eq('transaction_id', transactionId);
    } else if (current == null) {
      await plans.insert({
        'transaction_id': transactionId,
        'installments': installments,
      });
    } else {
      await plans
          .update({'installments': installments})
          .eq('transaction_id', transactionId);
    }
  }

  Future<void> deleteInstallmentPlan(String id) =>
      _db.from('installment_plans').delete().eq('id', id);

  /// Ce qui compose le consommé d'un budget ce mois-ci.
  Future<List<BudgetLine>> budgetLines(String budgetId) async {
    final rows = await _db
        .from('budget_lines_current_month')
        .select()
        .eq('budget_id', budgetId)
        .order('amount', ascending: false);
    return rows.map(BudgetLine.fromJson).toList();
  }

  // Projets d'épargne ------------------------------------------------------

  /// Fond de sécurité en premier, Épargne générale en dernier.
  Future<List<SavingsProject>> savingsProjects() async {
    final rows = await _db.from('savings_projects').select().order('name');
    int rank(SavingsProject p) => p.isSafetyFund ? 0 : (p.isDefault ? 2 : 1);
    return rows.map(SavingsProject.fromJson).toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  Future<void> createSavingsProject({
    required String name,
    required double percentage,
    required double? target,
    required double initialAmount,
  }) => _db.rpc<void>(
    'create_savings_project',
    params: {
      'p_name': name,
      'p_percentage': percentage,
      'p_target': target,
      'p_initial_amount': initialAmount,
    },
  );

  Future<void> updateSavingsProject({
    required String id,
    required String name,
    required double percentage,
    required double? target,
  }) => _db
      .from('savings_projects')
      .update({'name': name, 'percentage': percentage, 'target_amount': target})
      .eq('id', id);

  /// La RLS ne laisse supprimer qu'un projet vide et non système.
  Future<void> deleteSavingsProject(String id) async {
    final deleted = await _db
        .from('savings_projects')
        .delete()
        .eq('id', id)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('Seul un projet vide peut être supprimé');
    }
  }

  Future<void> saveToSavings({
    required double amount,
    required DistributionMode mode,
    String? projectId,
  }) => _db.rpc<void>(
    'save_to_savings',
    params: {'p_amount': amount, 'p_mode': mode.db, 'p_project_id': projectId},
  );
}
