import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/user.dart';

class UserRepository implements IUserRepository {
  final String _baseUrl;
  final IEncryptionService _encryptionService;
  final _storage = FlutterSecureStorage();

  UserRepository(this._baseUrl, this._encryptionService);

  Future<String?> _getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  @override
  Future<User> createUser(String username, String email, String password, String publicKey, String identifier) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'public_key': publicKey,
        'identifier': identifier,
      }),
    );
    if (response.statusCode == 200) {
      final userData = jsonDecode(response.body);
      final token = userData['token'];
      await _storage.write(key: 'jwt_token', value: token);
      return User.fromJson(userData);
    }
    throw Exception('Failed to register user: ${response.body}');
  }

  @override
  Future<User?> getUserById(String userId) async {
    final token = await _getToken();
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found');
    }
    final response = await http.get(
      Uri.parse('$_baseUrl/user/$userId'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized: Invalid or missing token');
    }
    return null;
  }

  @override
  Future<void> updateUser(User user) async {
    final token = await _getToken();
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found');
    }
    final response = await http.put(
      Uri.parse('$_baseUrl/user/${user.userId}'),
      headers: headers,
      body: jsonEncode(user.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update user: ${response.body}');
    }
  }

  @override
  Future<void> deleteUser(String userId) async {
    final token = await _getToken();
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found');
    }
    final response = await http.delete(
      Uri.parse('$_baseUrl/user/$userId'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete user: ${response.body}');
    }
  }

  @override
  Future<User?> getUserByIdentifier(String identifier) async {
    final token = await _getToken();
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found');
    }
    final response = await http.get(
      Uri.parse('$_baseUrl/user_by_identifier?identifier=$identifier'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      return null;
    }
    throw Exception('Failed to fetch user by identifier: ${response.body}');
  }
}
