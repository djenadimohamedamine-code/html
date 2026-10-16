class FuelRefill {
  final String id;
  final int timestamp;
  final String date;
  final double liters;
  final double pricePerLiter;
  final double totalAmount;
  final double levelBefore;
  final double levelAfter;
  final bool isCanceled;
  final int? expenseId;

  FuelRefill({
    required this.id,
    required this.timestamp,
    required this.date,
    required this.liters,
    required this.pricePerLiter,
    required this.totalAmount,
    required this.levelBefore,
    required this.levelAfter,
    this.isCanceled = false,
    this.expenseId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'date': date,
      'liters': liters,
      'price_per_liter': pricePerLiter,
      'total_amount': totalAmount,
      'level_before': levelBefore,
      'level_after': levelAfter,
      'canceled': isCanceled ? 1 : 0,
      'expense_id': expenseId,
    };
  }

  factory FuelRefill.fromMap(Map<String, dynamic> map) {
    return FuelRefill(
      id: map['id'] as String,
      timestamp: map['timestamp'] as int,
      date: map['date'] as String,
      liters: (map['liters'] as num).toDouble(),
      pricePerLiter: (map['price_per_liter'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      levelBefore: (map['level_before'] as num).toDouble(),
      levelAfter: (map['level_after'] as num).toDouble(),
      isCanceled: (map['canceled'] as int? ?? 0) == 1,
      expenseId: map['expense_id'] as int?,
    );
  }
}
