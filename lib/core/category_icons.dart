import 'package:flutter/material.dart';

/// Icônes proposées pour les budgets, stockées en base par leur nom.
const categoryIcons = <String, IconData>{
  'shopping_cart': Icons.shopping_cart,
  'home': Icons.home,
  'directions_car': Icons.directions_car,
  'restaurant': Icons.restaurant,
  'sports_esports': Icons.sports_esports,
  'medical_services': Icons.medical_services,
  'shopping_bag': Icons.shopping_bag,
  'subscriptions': Icons.subscriptions,
  'call_split': Icons.call_split,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'school': Icons.school,
  'flight': Icons.flight,
  'local_gas_station': Icons.local_gas_station,
  'fitness_center': Icons.fitness_center,
  'card_giftcard': Icons.card_giftcard,
  'phone_android': Icons.phone_android,
  'bolt': Icons.bolt,
  'checkroom': Icons.checkroom,
  'local_cafe': Icons.local_cafe,
  'two_wheeler': Icons.two_wheeler,
  'build': Icons.build,
  'beach_access': Icons.beach_access,
  'celebration': Icons.celebration,
  'laptop': Icons.laptop,
  'favorite': Icons.favorite,
  'savings': Icons.savings,
  'flag': Icons.flag,
  'shield': Icons.shield,
  'account_balance': Icons.account_balance,
  'category': Icons.category,
};

IconData categoryIcon(String? name) => categoryIcons[name] ?? Icons.category;
