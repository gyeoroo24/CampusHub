/// Minimal reference to a User (id + display name) in cards and summaries.
class UserRef {
  final String id;
  final String name;

  const UserRef({
    required this.id,
    required this.name,
  });

  factory UserRef.fromJson(Map<String, dynamic> json) {
    return UserRef(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserRef &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;

  @override
  String toString() => name;
}
