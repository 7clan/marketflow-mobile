import '../../domain/entities/auth_session.dart';
import 'json_reader.dart';
import 'user_model.dart';

/// Wire representation of a login/register response: the bearer token plus
/// the signed-in user.
class AuthSessionModel {
  const AuthSessionModel({required this.token, required this.user});

  factory AuthSessionModel.fromJson(Map<String, dynamic> json) {
    return AuthSessionModel(
      token: JsonReader.requireString(json, 'token'),
      user: UserModel.fromJson(JsonReader.requireMap(json, 'user')),
    );
  }

  final String token;
  final UserModel user;

  Map<String, dynamic> toJson() => {'token': token, 'user': user.toJson()};

  AuthSession toDomain() => AuthSession(token: token, user: user.toDomain());

  static AuthSessionModel fromDomain(AuthSession session) => AuthSessionModel(
    token: session.token,
    user: UserModel.fromDomain(session.user),
  );
}
