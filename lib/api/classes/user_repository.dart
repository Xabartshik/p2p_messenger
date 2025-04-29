import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/user.dart';

class UserRepository implements IUserRepository {
  final String _baseUrl;
  final IEncryptionService _encryptionService;
  final _storage = FlutterSecureStorage();

  UserRepository(this._baseUrl, this._encryptionService);

  Future<String?> _getToken(String userId) async {
    final token = await _storage.read(key: 'jwt_token_$userId');
    print('Retrieved token for user $userId: $token');
    return token;
  }

  @override
  Future<User> createUser(String username, String email, String password, String publicKey, String identifier) async {
    try {
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
      print('Register response: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);
        final token = userData['token'];
        if (token == null) {
          throw Exception('No token received from server');
        }
        final user = User.fromJson(userData);
        await _storage.write(key: 'jwt_token_${user.userId}', value: token);
        print('Saved token for user ${user.userId}: $token');
        return user;
      }
      throw Exception('Failed to register user: ${response.body}');
    } catch (e, stackTrace) {
      print('Create user error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<User?> getUserById(String userId, String currentUserId) async {
    final token = await _getToken(currentUserId);
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found for user $currentUserId');
    }
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/$userId'),
        headers: headers,
      );
      print('Get user by ID response: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        return User.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or missing token');
      }
      return null;
    } catch (e, stackTrace) {
      print('Get user by ID error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> updateUser(User user) async {
    final token = await _getToken(user.userId);
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found for user ${user.userId}');
    }
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/user/${user.userId}'),
        headers: headers,
        body: jsonEncode(user.toJson()),
      );
      print('Update user response: ${response.statusCode} ${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Failed to update user: ${response.body}');
      }
    } catch (e, stackTrace) {
      print('Update user error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> deleteUser(String userId) async {
    final token = await _getToken(userId);
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found for user $userId');
    }
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/user/$userId'),
        headers: headers,
      );
      print('Delete user response: ${response.statusCode} ${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Failed to delete user: ${response.body}');
      }
    } catch (e, stackTrace) {
      print('Delete user error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<User?> getUserByIdentifier(String identifier, String currentUserId) async {
    final token = await _getToken(currentUserId);
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      throw Exception('No token found for user $currentUserId');
    }
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user_by_identifier?identifier=$identifier'),
        headers: headers,
      );
      print('Get user by identifier response: ${response.statusCode} ${response.body}');
      if (response.statusCode == 200) {
        return User.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 404) {
        return null;
      }
      throw Exception('Failed to fetch user by identifier: ${response.body}');
    } catch (e, stackTrace) {
      print('Get user by identifier error: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }
}
