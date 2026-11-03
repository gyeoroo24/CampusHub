import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_hub/core/utils/numbers_only_formatter.dart';
import 'package:campus_hub/core/utils/text_file_picker.dart';
import 'package:campus_hub/features/academics/ui/course_materials.dart';
import 'package:campus_hub/features/placement/ui/placement_dialogs.dart' show seasonFromFileName;
import 'package:campus_hub/features/mess/mess_models.dart';
import 'package:campus_hub/features/mess/ui/menu_editor.dart';
import 'package:campus_hub/features/placement/domain/placement_models.dart';
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

  test('compensation shows in LPA, ranges and crores', () {
    expect(formatCtc(4800000, 4800000), '₹48 LPA');
    expect(formatCtc(1200000, 1500000), '₹12–15 LPA');
    expect(formatCtc(960000, null), '₹9.6 LPA');
    expect(formatCtc(1505000, 1505000), '₹15.05 LPA');
    expect(formatCtc(12000000, 12000000), '₹1.2 Cr');
    expect(formatCtc(2000000, 10000000), '₹20 LPA–₹1 Cr');
    expect(formatCtc(null, null), '');
  });

  test('roles carry season, type and compensation', () {
    final jd = JobDescription.fromJson({'id': 'j', 'company_id': 'c', 'role_title': 'NLP', 'compensation': '₹ 48,00,000',
        'ctc_min': 4800000, 'ctc_max': 4800000, 'base': 'INR 30,00,000', 'base_annual': 3000000,
        'placement_year': 2026, 'job_type': 'internship', 'skills': 'Python'});
    expect((jd.placementYear, jd.jobTypeLabel, jd.ctcMin, jd.baseAnnual), (2026, 'Internship', 4800000, 3000000));
    final c = Company.fromJson({'id': 'c', 'name': 'Observe', 'ctc_year': 2026, 'ctc_min': 2500000, 'ctc_max': 4800000});
    expect(formatCtc(c.ctcMin, c.ctcMax), '₹25–48 LPA');
  });

  test('CSV files decode as UTF-8 or, from Excel on Windows, Windows-1252', () {
    final utf = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Company,Role\nCafé,SDE')]);
    expect(decodeText(utf), 'Company,Role\nCafé,SDE');
    // "Founder’s Office" with a Windows-1252 curly quote (0x92) and a non-breaking space (0xA0).
    final cp1252 = Uint8List.fromList([...latin1.encode('Founder'), 0x92, ...latin1.encode('s'), 0xA0, ...latin1.encode('Office')]);
    expect(decodeText(cp1252), 'Founder’s Office');
  });

  test('the season comes from the file name', () {
    expect(seasonFromFileName('Placement Updates_FT 2025-26(Selection).csv'), 2026);
    expect(seasonFromFileName('placement data 2025_26.csv'), 2026);
    expect(seasonFromFileName('placement data 2026.csv'), 2026);
    expect(seasonFromFileName('selections.csv'), isNull);
  });

  test('shared course materials parse with tags and file details', () {
    final m = CourseMaterial.fromJson({'id': 'm', 'title': 'Endsem 2025', 'tags': ['pyq', 'solutions'],
        'file_name': 'endsem.pdf', 'size_bytes': 2500000, 'content_type': 'application/pdf', 'held': true,
        'can_edit': true, 'download_url': 'https://x', 'uploaded_by': {'id': 'u', 'name': 'Asha'},
        'created_at': '2026-11-02T10:00:00Z'});
    expect((m.kindLabel, m.held, m.canEdit, m.uploaderName), ('PDF', true, true, 'Asha'));
    expect(formatBytes(m.sizeBytes), '2.4 MB');
    expect(materialTags[m.tags.first], 'PYQs');
  });
}
