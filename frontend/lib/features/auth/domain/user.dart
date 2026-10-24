/// Roles defined in the 4-role permission model (PRD Sec 3.1 & FR-2).
enum UserRole {
  guest,
  signedIn,
  moderator,
  admin;

  String get label {
    switch (this) {
      case UserRole.guest:
        return 'Guest';
      case UserRole.signedIn:
        return 'Student';
      case UserRole.moderator:
        return 'Moderator';
      case UserRole.admin:
        return 'Admin';
    }
  }

  String get name => toString().split('.').last;
}

/// Represents an active moderator assignment for a specific module or scope (FR-3).
class ModeratorGrant {
  final String id;
  final String? userId;
  final String? userEmail;
  final String? userName;
  final String module; // 'buy_sell', 'lost_found', 'academic_help', 'placement_hub'
  final String scopeType; // 'all', 'module', 'department', 'course'
  final String? departmentId;
  final String? courseId;
  final DateTime grantedAt;
  final DateTime? revokedAt;

  const ModeratorGrant({
    required this.id,
    this.userId,
    this.userEmail,
    this.userName,
    required this.module,
    required this.scopeType,
    this.departmentId,
    this.courseId,
    required this.grantedAt,
    this.revokedAt,
  });

  factory ModeratorGrant.fromJson(Map<String, dynamic> json) {
    return ModeratorGrant(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      userEmail: json['user_email']?.toString(),
      userName: json['user_name']?.toString(),
      module: json['module']?.toString() ?? '',
      scopeType: json['scope_type']?.toString() ?? 'all',
      departmentId: json['department_id']?.toString(),
      courseId: json['course_id']?.toString(),
      grantedAt: json['granted_at'] != null
          ? DateTime.tryParse(json['granted_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      revokedAt: json['revoked_at'] != null
          ? DateTime.tryParse(json['revoked_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (userId != null) 'user_id': userId,
      if (userEmail != null) 'user_email': userEmail,
      if (userName != null) 'user_name': userName,
      'module': module,
      'scope_type': scopeType,
      'department_id': departmentId,
      'course_id': courseId,
      'granted_at': grantedAt.toIso8601String(),
      if (revokedAt != null) 'revoked_at': revokedAt!.toIso8601String(),
    };
  }
}

/// Represents the authenticated IISc user matching FastAPI `MyProfile`.
class User {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final String? departmentId;
  final String? programme;
  final int? graduationYear;
  final bool isAdmin;
  final bool isActive;
  final List<ModeratorGrant> moderatorGrants;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const User({
    required this.id,
    required this.email,
    this.name = '',
    this.phone,
    this.departmentId,
    this.programme,
    this.graduationYear,
    this.isAdmin = false,
    this.isActive = true,
    this.moderatorGrants = const [],
    required this.createdAt,
    this.updatedAt,
  });

  /// Guest instance
  static final guest = User(
    id: '',
    email: '',
    isActive: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  bool get isGuest => id.isEmpty || email.isEmpty;
  bool get isSignedIn => !isGuest;
  bool get isModerator => moderatorGrants.isNotEmpty || isAdmin;

  /// Scoped permission checks (FR-2, FR-3)
  bool canModerateModule(String module) =>
      isAdmin || moderatorGrants.any((g) => g.module == module);

  bool get canModerateBuySell => canModerateModule('buy_sell');
  bool get canModerateLostFound => canModerateModule('lost_found');

  bool canModerateDepartment(String deptId) =>
      isAdmin ||
      moderatorGrants.any(
        (g) => g.module == 'academic_help' && g.departmentId == deptId,
      );

  bool canModerateCourse(String courseId, [String? deptId]) =>
      isAdmin ||
      moderatorGrants.any(
        (g) =>
            g.module == 'academic_help' &&
            (g.courseId == courseId ||
                (deptId != null && g.departmentId == deptId)),
      );

  /// Backwards-compatible list of generic roles
  List<UserRole> get roles {
    if (isGuest) return [UserRole.guest];
    final list = [UserRole.signedIn];
    if (isAdmin) list.add(UserRole.admin);
    if (isModerator) list.add(UserRole.moderator);
    return list;
  }

  /// Convenient display name derived from name or email username
  String get displayName {
    if (name.isNotEmpty) return name;
    if (email.contains('@')) {
      return email.split('@').first;
    }
    return email.isNotEmpty ? email : 'Guest';
  }

  /// Single or double uppercase initials for avatars
  String get initials {
    if (name.isNotEmpty) {
      final parts = name.trim().split(RegExp(r'\s+'));
      if (parts.length > 1 && parts.last.isNotEmpty) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return name[0].toUpperCase();
    }
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return '?';
  }

  bool isOwnerOf(String resourceOwnerId) => id.isNotEmpty && id == resourceOwnerId;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'department_id': departmentId,
      'programme': programme,
      'graduation_year': graduationYear,
      'is_admin': isAdmin,
      'is_active': isActive,
      'moderator_grants': moderatorGrants.map((g) => g.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final grantsRaw = (json['moderator_grants'] as List<dynamic>?) ?? [];
    final grants = grantsRaw
        .map((g) => ModeratorGrant.fromJson(g as Map<String, dynamic>))
        .toList();

    // Check if roles array is present for backwards compatibility
    final bool isAdminFlag = json['is_admin'] == true ||
        (json['roles'] as List<dynamic>?)?.contains('admin') == true;

    return User(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      departmentId: json['department_id']?.toString(),
      programme: json['programme']?.toString(),
      graduationYear: json['graduation_year'] is int
          ? json['graduation_year'] as int
          : int.tryParse(json['graduation_year']?.toString() ?? ''),
      isAdmin: isAdminFlag,
      isActive: json['is_active'] != false,
      moderatorGrants: grants,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? departmentId,
    String? programme,
    int? graduationYear,
    bool? isAdmin,
    bool? isActive,
    List<ModeratorGrant>? moderatorGrants,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      departmentId: departmentId ?? this.departmentId,
      programme: programme ?? this.programme,
      graduationYear: graduationYear ?? this.graduationYear,
      isAdmin: isAdmin ?? this.isAdmin,
      isActive: isActive ?? this.isActive,
      moderatorGrants: moderatorGrants ?? this.moderatorGrants,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
