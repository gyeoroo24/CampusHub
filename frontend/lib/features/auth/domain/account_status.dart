/// Represents the account activation and admin status returned by `PATCH /api/v1/users/{id}`.
class AccountStatus {
  final String id;
  final String email;
  final String name;
  final bool isActive;
  final bool isAdmin;

  const AccountStatus({
    required this.id,
    required this.email,
    required this.name,
    required this.isActive,
    required this.isAdmin,
  });

  factory AccountStatus.fromJson(Map<String, dynamic> json) {
    return AccountStatus(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isActive: json['is_active'] == true,
      isAdmin: json['is_admin'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'is_active': isActive,
      'is_admin': isAdmin,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountStatus &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          name == other.name &&
          isActive == other.isActive &&
          isAdmin == other.isAdmin;

  @override
  int get hashCode =>
      id.hashCode ^
      email.hashCode ^
      name.hashCode ^
      isActive.hashCode ^
      isAdmin.hashCode;
}
