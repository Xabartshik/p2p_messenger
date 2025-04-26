import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/user.dart';

class AuthService implements IAuthService {
  final String serverUrl;
  final storage = FlutterSecureStorage();

  AuthService(this.serverUrl);

  @override
  Future<User> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$serverUrl/login'),
      body: jsonEncode({'email': email, 'password': password}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final user = User.fromJson(data);
      await storage.write(key: 'jwt_token_${user.userId}', value: data['token']);
      await storage.write(key: 'private_key_${user.userId}', value: data['private_key']);
      return user;
    }
    throw Exception('Login failed: ${response.body}');
  }

  @override
  Future<void> logout(String userId) async {
    await storage.delete(key: 'jwt_token_$userId');
    await storage.delete(key: 'private_key_$userId');
  }

  @override
  Future<String> generateToken(User user) async {
    final response = await http.post(
      Uri.parse('$serverUrl/refresh'),
      body: jsonEncode({'user_id': user.userId}),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await storage.read(key: 'jwt_token_${user.userId}')}',
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'];
    }
    throw Exception('Token refresh failed: ${response.body}');
  }
}