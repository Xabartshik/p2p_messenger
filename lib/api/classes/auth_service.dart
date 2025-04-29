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
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/login'),
        body: jsonEncode({'email': email, 'password': password}),
        headers: {'Content-Type': 'application/json'},
      );
      print('Login response: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = User.fromJson(data);
        final token = data['token'];
        if (token == null) {
          throw Exception('No token received from server');
        }
        await storage.write(key: 'jwt_token_${user.userId}', value: token);
        await storage.write(key: 'private_key_${user.userId}', value: data['private_key']);
        return user;
      }
      throw Exception('Login failed: ${response.body}');
    } catch (e, stackTrace) {
      print('Login error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> logout(String userId) async {
    try {
      await storage.delete(key: 'jwt_token_$userId');
      await storage.delete(key: 'private_key_$userId');
      print('Logged out user $userId');
    } catch (e) {
      print('Logout error: $e');
      rethrow;
    }
  }

  @override
  Future<String> generateToken(User user) async {
    try {
      final token = await storage.read(key: 'jwt_token_${user.userId}');
      if (token == null) {
        throw Exception('No token found for user ${user.userId}');
      }
      final response = await http.post(
        Uri.parse('$serverUrl/refresh'),
        body: jsonEncode({'user_id': user.userId}),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      print('Refresh token response: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newToken = data['token'];
        await storage.write(key: 'jwt_token_${user.userId}', value: newToken);
        print('Refreshed token for user ${user.userId}: $newToken');
        return newToken;
      }
      throw Exception('Token refresh failed: ${response.body}');
    } catch (e, stackTrace) {
      print('Generate token error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }
}
