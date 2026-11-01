/// Contact information for sellers or reporters.
/// Only exposed to signed-in users (returns null for guests).
class Contact {
  final String email;
  final String? phone;

  const Contact({
    required this.email,
    this.phone,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'phone': phone,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Contact &&
          runtimeType == other.runtimeType &&
          email == other.email &&
          phone == other.phone;

  @override
  int get hashCode => email.hashCode ^ (phone?.hashCode ?? 0);

  @override
  String toString() => phone != null && phone!.isNotEmpty ? '$email ($phone)' : email;
}
