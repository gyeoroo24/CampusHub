import 'lost_found_item.dart';

/// `GET /{kind}-reports/{id}/matches`: reports of the other kind that may be
/// the same item, best first. Only the report's owner (or an admin) can ask.
enum MatchStatus {
  /// Ranked by description and photo similarity.
  ready,

  /// The matcher hasn't finished with the latest version of the report yet.
  pending,

  /// No matcher on this server: same-category reports, unranked.
  unavailable;

  static MatchStatus fromString(String? value) => switch (value) {
        'pending' => MatchStatus.pending,
        'unavailable' => MatchStatus.unavailable,
        _ => MatchStatus.ready,
      };
}

enum MatchStrength {
  /// The lost report's owner was alerted about it.
  strong('Strong match'),
  possible('Possible match');

  final String label;
  const MatchStrength(this.label);

  static MatchStrength? fromString(String? value) => switch (value) {
        'strong' => MatchStrength.strong,
        'possible' => MatchStrength.possible,
        _ => null,
      };
}

class PossibleMatch {
  final LostFoundItem item;
  final double? score;
  final MatchStrength? strength;

  /// e.g. "Similar description", "Similar photo", "Photo fits the description", "Same category".
  final List<String> reasons;

  const PossibleMatch({required this.item, this.score, this.strength, this.reasons = const []});
}

class MatchResult {
  final MatchStatus status;
  final List<PossibleMatch> matches;

  const MatchResult({required this.status, this.matches = const []});

  bool get isPending => status == MatchStatus.pending;
}
