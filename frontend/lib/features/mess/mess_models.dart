import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/server_config.dart';
import '../auth/providers/auth_providers.dart';

const meals = ['breakfast', 'lunch', 'snacks', 'dinner'];
const mealLabels = {'breakfast': 'Breakfast', 'lunch': 'Lunch', 'snacks': 'Snacks', 'dinner': 'Dinner'};
const weekdayLabels = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "07:30:00" -> (7, 30).
(int, int) parseClock(String value) {
  final parts = value.split(':');
  return (int.tryParse(parts[0]) ?? 0, parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
}

String formatClock(String value) {
  final (h, m) = parseClock(value);
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

class TodayMeal {
  final String meal;
  final DateTime startsAt;
  final String items;

  const TodayMeal(this.meal, this.startsAt, this.items);
}

class Mess {
  final int id;
  final String name;
  final Map<String, String> mealTimes;
  final List<String>? followingMeals;
  final int followerCount;
  final String? currentMenuId;
  final DateTime? nextMenuFrom;
  final List<TodayMeal> today;

  const Mess({
    required this.id,
    required this.name,
    required this.mealTimes,
    this.followingMeals,
    this.followerCount = 0,
    this.currentMenuId,
    this.nextMenuFrom,
    this.today = const [],
  });

  factory Mess.fromJson(Map<String, dynamic> j) => Mess(
        id: (j['id'] as num).toInt(),
        name: '${j['name']}',
        mealTimes: {for (final e in (j['meal_times'] as Map<String, dynamic>).entries) e.key: '${e.value}'},
        followingMeals: (j['following_meals'] as List?)?.map((e) => '$e').toList(),
        followerCount: (j['follower_count'] as num?)?.toInt() ?? 0,
        currentMenuId: j['current_menu_id'] as String?,
        nextMenuFrom: j['next_menu_from'] == null ? null : DateTime.parse('${j['next_menu_from']}'),
        today: [
          for (final t in (j['today'] as List? ?? const []))
            TodayMeal('${t['meal']}', DateTime.parse('${t['starts_at']}').toLocal(), '${t['items']}'),
        ],
      );
}

class MessMenu {
  final String id;
  final int messId;
  final String messName;
  final DateTime validFrom;
  final DateTime validTo;
  final String? fileUrl;
  final String? fileType;
  final String? notes;

  /// Dishes by (weekday 1-7, meal).
  final Map<(int, String), String> items;

  const MessMenu({
    required this.id,
    required this.messId,
    required this.messName,
    required this.validFrom,
    required this.validTo,
    this.fileUrl,
    this.fileType,
    this.notes,
    required this.items,
  });

  factory MessMenu.fromJson(Map<String, dynamic> j) => MessMenu(
        id: '${j['id']}',
        messId: (j['mess_id'] as num).toInt(),
        messName: '${j['mess_name']}',
        validFrom: DateTime.parse('${j['valid_from']}'),
        validTo: DateTime.parse('${j['valid_to']}'),
        fileUrl: j['file_url'] as String?,
        fileType: j['file_type'] as String?,
        notes: j['notes'] as String?,
        items: {
          for (final i in (j['items'] as List? ?? const []))
            ((i['weekday'] as num).toInt(), '${i['meal']}'): '${i['items']}',
        },
      );

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(validFrom) && !d.isAfter(validTo);
  }
}

class MessList {
  final List<Mess> messes;
  final bool canManage;

  const MessList(this.messes, this.canManage);
}

/// Every mess with today's meals. Empty in mock mode (there is no mock version).
final messListProvider = FutureProvider.autoDispose<MessList>((ref) async {
  ref.watch(currentUserProvider);
  if (ref.watch(serverConfigProvider).useMockData) return const MessList([], false);
  final res = await ref.watch(apiClientProvider).get(ApiEndpoints.messes);
  final data = res.data as Map<String, dynamic>;
  return MessList([for (final m in data['messes'] as List) Mess.fromJson(m as Map<String, dynamic>)],
      data['can_manage'] == true);
});

/// A mess's current and upcoming menus, then a few past ones.
final messMenusProvider = FutureProvider.autoDispose.family<List<MessMenu>, int>((ref, messId) async {
  final res = await ref.watch(apiClientProvider).get(ApiEndpoints.messMenus(messId));
  return [for (final m in res.data as List) MessMenu.fromJson(m as Map<String, dynamic>)];
});
