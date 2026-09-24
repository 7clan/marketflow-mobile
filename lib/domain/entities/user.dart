/// A registered marketplace account.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.memberSince,
  });

  final String id;
  final String name;
  final String email;

  /// When the account was created, when known.
  final DateTime? memberSince;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.memberSince == memberSince;
  }

  @override
  int get hashCode => Object.hash(id, name, email, memberSince);

  @override
  String toString() =>
      'User(id: $id, name: $name, email: $email, memberSince: $memberSince)';
}
