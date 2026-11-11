class User {
  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.isActive,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    email: json['email'] as String,
    name: json['name'] as String,
    isActive: json['is_active'] as bool? ?? true,
  );

  final int id;
  final String email;
  final String name;
  final bool isActive;

  /// First word of the name, for greetings ("Assalam-o-Alaikum, Sana!").
  String get firstName => name.trim().split(RegExp(r'\s+')).first;
}

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
  );

  final String accessToken;
  final String refreshToken;
}
