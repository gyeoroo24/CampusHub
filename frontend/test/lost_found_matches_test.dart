import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_hub/core/models/category_ref.dart';
import 'package:campus_hub/core/models/user_ref.dart';
import 'package:campus_hub/features/lost_found/data/mock_lost_found_repository.dart';
import 'package:campus_hub/features/lost_found/domain/lost_found_item.dart';
import 'package:campus_hub/features/lost_found/domain/possible_match.dart';
import 'package:campus_hub/features/lost_found/providers/lost_found_providers.dart';
import 'package:campus_hub/features/lost_found/ui/widgets/possible_matches_section.dart';

LostFoundItem _report(String id, PostType kind, String description) => LostFoundItem(
      id: id,
      kind: kind,
      description: description,
      category: const CategoryRef(id: 1, name: 'Electronics'),
      occurredAt: DateTime.now().subtract(const Duration(hours: 2)),
      location: 'Library',
      reporter: UserRef(id: 'usr_$id', name: 'Someone'),
      createdAt: DateTime.now(),
    );

/// The server answers "pending" a few times while the matcher works, then "ready".
class _SlowMatcher extends MockLostFoundRepository {
  int calls = 0;

  @override
  Future<MatchResult> getPossibleMatches(String id, PostType kind) async {
    calls++;
    if (calls < 3) return const MatchResult(status: MatchStatus.pending);
    return MatchResult(status: MatchStatus.ready, matches: [
      PossibleMatch(
        item: _report('f1', PostType.found, 'Found wireless earphones in a black case'),
        score: 0.92,
        strength: MatchStrength.strong,
        reasons: const ['Similar description', 'Similar photo'],
      ),
    ]);
  }
}

void main() {
  setUp(() => matchPollInterval = const Duration(milliseconds: 1));

  test('match status and strength parse the API values', () {
    expect(MatchStatus.fromString('pending'), MatchStatus.pending);
    expect(MatchStatus.fromString('unavailable'), MatchStatus.unavailable);
    expect(MatchStatus.fromString('ready'), MatchStatus.ready);
    expect(MatchStrength.fromString('strong'), MatchStrength.strong);
    expect(MatchStrength.fromString(null), isNull);
  });

  test('the provider keeps asking while the server is still matching', () async {
    final repo = _SlowMatcher();
    final container = ProviderContainer(overrides: [lostFoundRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final key = (id: 'l1', kind: PostType.lost);
    final sub = container.listen(possibleMatchesProvider(key), (_, __) {});
    addTearDown(sub.close);
    final result = await container.read(possibleMatchesProvider(key).future);
    expect(repo.calls, 3);
    expect(result.status, MatchStatus.ready);
    expect(result.matches.single.strength, MatchStrength.strong);
  });

  testWidgets('the section shows each match with its badge and reasons', (tester) async {
    final lost = _report('l1', PostType.lost, 'Lost black JBL earbuds');
    await tester.pumpWidget(ProviderScope(
      overrides: [lostFoundRepositoryProvider.overrideWithValue(_SlowMatcher())],
      child: MaterialApp(home: Scaffold(body: PossibleMatchesSection(item: lost))),
    ));
    await tester.pump();
    expect(find.text('Looking for matching found reports…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Possible Matches (1)'), findsOneWidget);
    expect(find.text('Strong match'), findsOneWidget);
    expect(find.textContaining('Similar description · Similar photo'), findsOneWidget);
  });

  testWidgets('no matches says the owner will be notified', (tester) async {
    final lost = _report('l2', PostType.lost, 'Lost a blue umbrella');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        possibleMatchesProvider((id: lost.id, kind: lost.kind))
            .overrideWith((ref) => const MatchResult(status: MatchStatus.ready)),
      ],
      child: MaterialApp(home: Scaffold(body: PossibleMatchesSection(item: lost))),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining("you'll get a notification"), findsOneWidget);
  });
}
