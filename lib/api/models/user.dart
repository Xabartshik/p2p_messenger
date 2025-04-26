class User {
  final String userId;
  final String username;
  final String email;
  final String status;
  final String publicKey;
  final String identifier;
  final String? token;

  User({
    required this.userId,
    required this.username,
    required this.email,
    required this.status,
    required this.publicKey,
    required this.identifier,
    this.token,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: json['user_id'],
        username: json['username'],
        email: json['email'],
        status: json['status'],
        publicKey: json['public_key'],
        identifier: json['identifier'],
        token: json['token'],
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'email': email,
        'status': status,
        'public_key': publicKey,
        'identifier': identifier,
        'token': token,
      };
}
