import 'package:campus_hub/core/utils/numbers_only_formatter.dart';
import 'package:campus_hub/features/mess/mess_models.dart';
import 'package:campus_hub/features/mess/ui/menu_editor.dart';
import 'package:campus_hub/features/placement/ui/company_seniors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a pasted menu table fills the week, either way round', () {
    final byDay = parseMenuTable('Day\tBreakfast\tLunch\tSnacks\tDinner\n'
        'Monday\tPoha, Kesari bath\tChapati, Matta rice\tMasala vada\tGhee rice\n'
        'Tue\tIdli, Vada\t\tPizza\tFulka\n');
    expect(byDay[(1, 'breakfast')], 'Poha, Kesari bath');
    expect(byDay[(2, 'snacks')], 'Pizza');
    expect(byDay.containsKey((2, 'lunch')), isFalse);
    expect(byDay.length, 7);

    final byMeal = parseMenuTable('Meal,Monday,Tuesday\nLunch,"Chapati, Sambar",Dal\nDinner,Biryani,Fulka\n');
    expect(byMeal[(1, 'lunch')], 'Chapati, Sambar');
    expect(byMeal[(2, 'dinner')], 'Fulka');
    expect(parseMenuTable('just some text'), isEmpty);
  });

  test('mess and menu payloads parse', () {
    final mess = Mess.fromJson({
      'id': 1, 'name': 'C Mess', 'follower_count': 2, 'following_meals': ['lunch'],
      'meal_times': {'breakfast': '07:30:00', 'lunch': '12:30:00', 'snacks': '16:45:00', 'dinner': '19:30:00'},
      'today': [{'meal': 'lunch', 'starts_at': '2026-11-02T07:00:00Z', 'items': 'Chapati'}],
    });
    expect(mess.followingMeals, ['lunch']);
    expect(formatClock(mess.mealTimes['dinner']!), '7:30 pm');
    expect(formatClock('00:05:00'), '12:05 am');
    final menu = MessMenu.fromJson({'id': 'm', 'mess_id': 1, 'mess_name': 'C Mess', 'valid_from': '2026-11-01',
        'valid_to': '2026-11-30', 'items': [{'weekday': 3, 'meal': 'dinner', 'items': 'Dosa'}]});
    expect(menu.items[(3, 'dinner')], 'Dosa');
    expect(menu.covers(DateTime(2026, 11, 30, 21)), isTrue);
    expect(menu.covers(DateTime(2026, 12, 1)), isFalse);
  });

  test('seniors parse, with chat only for people on CampusHub', () {
    final s = Senior.fromJson({'id': 'r1', 'source': 'placement_sheet', 'name': 'Asha', 'email': 'asha@iisc.ac.in',
        'user_id': 'u1', 'placement_year': 2026, 'offer_type': 'ppo', 'hidden': false});
    expect((s.fromSheet, s.offerLabel, s.userId), (true, 'PPO', 'u1'));
    expect(Senior.fromJson({'id': 'x', 'source': 'added', 'name': 'Dev', 'email': 'dev@gmail.com',
        'placement_year': 2025, 'offer_type': 'off_campus'}).userId, isNull);
  });

  test('the price field takes numbers only and says so', () {
    var rejected = 0;
    final f = NumbersOnlyFormatter(onRejected: () => rejected++);
    const old = TextEditingValue(text: '12');
    expect(f.formatEditUpdate(old, const TextEditingValue(text: '12.5')).text, '12.5');
    expect(f.formatEditUpdate(old, const TextEditingValue(text: '12a')).text, '12');
    expect(f.formatEditUpdate(old, const TextEditingValue(text: '1.2.')).text, '12');
    expect(rejected, 2);
  });
}
