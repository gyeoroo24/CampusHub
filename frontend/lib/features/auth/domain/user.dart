/// Roles defined in the 4-role permission model (PRD Sec 3.1 & FR-2).
enum UserRole {
  guest,
  signedIn,
  moderator,
  admin,
}

/// Represents the authenticated IISc user.
///
/// Only the user's IISc email is collected and stored.
class User {
  final String id;
  final String email;
  final List<UserRole> roles;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    this.roles = const [UserRole.signedIn],
    required this.createdAt,
  });

  bool get isGuest => roles.contains(UserRole.guest) || roles.isEmpty;
  bool get isSignedIn => roles.contains(UserRole.signedIn);
  bool get isModerator => roles.contains(UserRole.moderator);
  bool get isAdmin => roles.contains(UserRole.admin);

  /// Convenient display name derived solely from the email username part (e.g. "kmukund" from "kmukund@iisc.ac.in")
  String get displayName {
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return email;
  }

  bool isOwnerOf(String resourceOwnerId) => id == resourceOwnerId;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'roles': roles.map((r) => r.name).toList(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final rolesRaw = (json['roles'] as List<dynamic>?) ?? ['signedIn'];
    final parsedRoles = rolesRaw.map((r) {
      switch (r.toString()) {
        case 'admin':
          return UserRole.admin;
        case 'moderator':
          return UserRole.moderator;
        case 'guest':
          return UserRole.guest;
        default:
          return UserRole.signedIn;
      }
    }).toList();

    return User(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      roles: parsedRoles,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  User copyWith({
    String? id,
    String? email,
    List<UserRole>? roles,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      roles: roles ?? this.roles,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
