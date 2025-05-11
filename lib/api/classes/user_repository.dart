import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/user.dart';

class UserRepository implements IUserRepository {
  final String _baseUrl;
  final IEncryptionService _encryptionService;
  final _storage = FlutterSecureStorage();

  // Ключи для хранения данных
  static const _currentUserIdKey = 'user_id';
  static const _currentUserDataKey = 'current_user_data';

  UserRepository(this._baseUrl, this._encryptionService);

  Future<String?> _getToken(String userId) async {
    final token = await _storage.read(key: 'jwt_token_$userId');
    print('Retrieved token for user $userId: $token');
    return token;
  }

  // Метод для сохранения текущего пользователя
  Future<void> _saveCurrentUser(User user, String token) async {
    await Future.wait([
      _storage.write(key: _currentUserIdKey, value: user.userId),
      _storage.write(key: 'jwt_token_${user.userId}', value: token),
      _storage.write(key: _currentUserDataKey, value: jsonEncode(user.toJson())),
    ]);
    print('Current user saved: ${user.userId}');
  }

  // Метод для получения текущего пользователя из хранилища
  @override
  Future<User?> getCurrentUser() async {
    try {
      // 1. Проверяем, есть ли сохраненные данные пользователя
      final userJson = await _storage.read(key: _currentUserDataKey);
      if (userJson != null) {
        return User.fromJson(jsonDecode(userJson));
      }

      // 2. Если данных нет, пробуем получить по ID
      final userId = await _storage.read(key: _currentUserIdKey);
      if (userId != null) {
        final token = await _getToken(userId);
        if (token != null) {
          // Получаем свежие данные с сервера
          final user = await getUserById(userId, userId);
          if (user != null) {
            // Обновляем локальные данные
            await _storage.write(
              key: _currentUserDataKey,
              value: jsonEncode(user.toJson()),
            );
            return user;
          }
        }
      }

      return null;
    } catch (e, stackTrace) {
      print('Error getting current user: $e\n$stackTrace');
      return null;
    }
  }

  @override
  Future<User> createUser(String username, String email, String password,
      String publicKey, String identifier) async {
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

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);
        final token = userData['token'];
        if (token == null) {
          throw Exception('No token received from server');
        }

        final user = User.fromJson(userData);
        await _saveCurrentUser(user, token); // Сохраняем пользователя
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
      logout();
      _saveCurrentUser(user, token);
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

    // Метод выхода (очистка данных)
  @override
  Future<void> logout() async {
    final userId = await _storage.read(key: _currentUserIdKey);
    await Future.wait([
      _storage.delete(key: _currentUserIdKey),
      _storage.delete(key: _currentUserDataKey),
      if (userId != null) _storage.delete(key: 'jwt_token_$userId'),
    ]);
    print('User logged out');
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
