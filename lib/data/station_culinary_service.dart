import 'package:flutter/foundation.dart';

/// Represents a famous station delicacy or culinary recommendation.
@immutable
class StationFoodItem {
  const StationFoodItem({
    required this.stationCode,
    required this.foodName,
    required this.emoji,
    required this.description,
  });

  final String stationCode;
  final String foodName;
  final String emoji;
  final String description;
}

/// Curated database of iconic Indian Railways station delicacies.
class StationCulinaryService {
  StationCulinaryService._();

  static const Map<String, StationFoodItem> _db = {
    'RTM': StationFoodItem(
      stationCode: 'RTM',
      foodName: 'Ratlami Sev & Poha',
      emoji: '🌶️',
      description: 'Crispy spicy Ratlami Sev with fresh onion poha on Platform 2.',
    ),
    'AGC': StationFoodItem(
      stationCode: 'AGC',
      foodName: 'Agra Petha',
      emoji: '🍬',
      description: 'Authentic Panchhi Petha sweets available right on the platform.',
    ),
    'CLT': StationFoodItem(
      stationCode: 'CLT',
      foodName: 'Kozhikode Halwa & Chips',
      emoji: '🍌',
      description: 'Soft banana halwa & hot coconut oil fried banana chips.',
    ),
    'BHP': StationFoodItem(
      stationCode: 'BHP',
      foodName: 'Bardhaman Sitabhog & Mihidana',
      emoji: '🍯',
      description: 'Famous GI-tagged sweet rice delicacies on Platform 1.',
    ),
    'MDU': StationFoodItem(
      stationCode: 'MDU',
      foodName: 'Madurai Jigarthanda',
      emoji: '🥛',
      description: 'Refreshing cold almond gum & ice cream Jigarthanda drink.',
    ),
    'MYS': StationFoodItem(
      stationCode: 'MYS',
      foodName: 'Maddur Vada & Mysuru Pak',
      emoji: '🍘',
      description: 'Crunchy onion Maddur Vada served hot at station stalls.',
    ),
    'CNB': StationFoodItem(
      stationCode: 'CNB',
      foodName: 'Kanpur Thaggu Ke Laddu',
      emoji: '🧆',
      description: 'Famous Khoya laddus & hot kulhad chai.',
    ),
    'BSB': StationFoodItem(
      stationCode: 'BSB',
      foodName: 'Varanasi Malaiyo & Banarasi Paan',
      emoji: '🍵',
      description: 'Winter saffron milk foam Malaiyo & authentic paan.',
    ),
    'SBC': StationFoodItem(
      stationCode: 'SBC',
      foodName: 'Bengaluru Masala Dosa & Filter Coffee',
      emoji: '☕',
      description: 'Hot piping South Indian filter coffee & crisp vada.',
    ),
    'KYJ': StationFoodItem(
      stationCode: 'KYJ',
      foodName: 'Kayamkulam Hot Pazham Pori',
      emoji: '🍌',
      description: 'Crispy banana fritters & hot Kerala chai.',
    ),
    'ALLP': StationFoodItem(
      stationCode: 'ALLP',
      foodName: 'Alappuzha Fish Curry Meals',
      emoji: '🍛',
      description: 'Traditional backwater spicy fish roast & kappa.',
    ),
    'HWH': StationFoodItem(
      stationCode: 'HWH',
      foodName: 'Howrah Rosogolla & Mishti Doi',
      emoji: '🍮',
      description: 'Fresh clay pot Mishti Doi & warm Rosogolla.',
    ),
    'MAS': StationFoodItem(
      stationCode: 'MAS',
      foodName: 'Chennai Central Idli & Sambar',
      emoji: '🫓',
      description: 'Steaming soft idlis with spicy gun powder sambar.',
    ),
  };

  /// Lookup culinary specialty for station code.
  static StationFoodItem? getFoodForStation(String stationCode) {
    final codeUpper = stationCode.trim().toUpperCase();
    return _db[codeUpper];
  }
}
