import 'user.dart';

/// An authenticated session: bearer token plus the signed-in user.
class AuthSession {
  const AuthSession({required this.token, required this.user});

  /// Opaque bearer token issued by the backend.
  final String token;

  final User user;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthSession && other.token == token && other.user == user;
  }

  @override
  int get hashCode => Object.hash(token, user);

  @override
  String toString() => 'AuthSession(token: ***, user: $user)';
}
