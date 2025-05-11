import 'dart:typed_data';

import 'package:p2p_messenger/api/models/message.dart';
import 'package:p2p_messenger/api/models/user.dart';

abstract class IUserRepository {
  Future<User> createUser(String username, String email, String password, String publicKey, String identifier);
  Future<User?> getUserById(String userId, String currentUserId);
  Future<void> updateUser(User user);
  Future<void> deleteUser(String userId);
  Future<User?> getUserByIdentifier(String identifier, String currentUserId);
  Future<User?> getCurrentUser();
  Future<void> logout();
}


abstract class IMessageRepository {
  Future<Message> saveMessage(Message message);
  Future<List<Message>> getMessagesForUser(String userId, String recipientId);
  Future<void> deleteMessage(String messageId);
  Future<List<Map<String, dynamic>>> getMessageMetadata(String userId, String recipientId);
  Future<List<Message>> getMessagesByIds(List<String> messageIds);
}
//Предположительно, не будет использоваться
abstract class IFileStorage {
  Future<String> uploadFile(String fileName, List<int> bytes);
  Future<List<int>> downloadFile(String fileUrl);
  Future<void> deleteFile(String fileUrl);
  Future<List<String>> uploadFiles(List<FileAttachment> attachments);
}

abstract class IWebRTCService {
  get encryptionService => null;

  Future<void> initialize(String peerId, String serverUrl, String token);
  Future<void> sendMessage(Message message);
  Stream<Message> onMessageReceived();
  Future<void> close();
}

abstract class IAuthService {
  Future<User> login(String email, String password);
  Future<void> logout(String userId);
  Future<String> generateToken(User user);
}

abstract class IEncryptionService {
  /// Генерирует пару RSA-ключей (публичный и приватный) в формате Base64.
  /// 
  /// Возвращает Map с ключами 'publicKey' и 'privateKey'.
  Future<Map<String, String>> generateKeyPair();

  /// Шифрует данные с использованием публичного ключа.
  /// 
  /// - Если данные небольшие (<= 245 байт), используется чистое RSA-шифрование.
  /// - Если данные большие, используется гибридное шифрование (AES-GCM для данных,
  ///   RSA для ключа AES).
  /// 
  /// [data] - данные для шифрования в виде байтов.
  /// [publicKey] - публичный ключ в формате Base64.
  /// 
  /// Возвращает зашифрованные данные в виде байтов.
  Future<Uint8List> encrypt(Uint8List data, String publicKey);

  /// Расшифровывает данные с использованием приватного ключа.
  /// 
  /// - Если данные небольшие (<= 256 байт), используется чистое RSA-расшифрование.
  /// - Если данные большие, предполагается гибридное шифрование и сначала
  ///   расшифровывается AES-ключ, затем сами данные.
  /// 
  /// [data] - зашифрованные данные в виде байтов.
  /// [privateKey] - приватный ключ в формате Base64.
  /// 
  /// Возвращает расшифрованные данные в виде байтов.
  Future<Uint8List> decrypt(Uint8List data, String privateKey);
}