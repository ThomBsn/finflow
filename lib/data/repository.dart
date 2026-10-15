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
    var query = _db.from('transactions').select().eq('month', dbDate(month));
    if (category != null) query = query.eq('category', category);
    final rows = await query
        .order('date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(Transaction.fromJson).toList();
  }

  Future<void> saveTransaction(TransactionDraft draft) async {
    if (draft.id == null) {
      await _db.from('transactions').insert(draft.toJson());
    } else {
      await _db.from('transactions').update(draft.toJson()).eq('id', draft.id!);
    }
  }

  Future<void> deleteTransaction(String id) =>
      _db.from('transactions').delete().eq('id', id);
}
