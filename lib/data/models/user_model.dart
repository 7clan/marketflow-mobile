import '../../domain/entities/user.dart';
import 'json_reader.dart';

/// Wire representation of a marketplace user.
class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.memberSince,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: JsonReader.requireString(json, 'id'),
      name: JsonReader.requireString(json, 'name'),
      email: JsonReader.requireString(json, 'email'),
      memberSince: JsonReader.optionalDateTime(json, 'memberSince'),
    );
  }

  final String id;
  final String name;
  final String email;
  final DateTime? memberSince;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'memberSince': memberSince?.toIso8601String(),
  };

  User toDomain() =>
      User(id: id, name: name, email: email, memberSince: memberSince);

  static UserModel fromDomain(User user) => UserModel(
    id: user.id,
    name: user.name,
    email: user.email,
    memberSince: user.memberSince,
  );
}
