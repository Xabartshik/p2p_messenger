import 'package:p2p_messenger/api/models/message.dart';
import 'package:p2p_messenger/api/models/user.dart';

abstract class IUserRepository {
  Future<User> createUser(String username, String email, String password, String publicKey, String identifier);
  Future<User?> getUserById(String userId, String currentUserId);
  Future<void> updateUser(User user);
  Future<void> deleteUser(String userId);
  Future<User?> getUserByIdentifier(String identifier, String currentUserId);
}


abstract class IMessageRepository {
  Future<Message> saveMessage(Message message);
  Future<List<Message>> getMessagesForUser(String userId, String recipientId);
  Future<void> deleteMessage(String messageId);
  Future<List<Map<String, dynamic>>> getMessageMetadata(String userId, String recipientId);
}

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
  Future<Map<String, String>> generateKeyPair();
  Future<List<int>> encrypt(List<int> data, String publicKey);
  Future<List<int>> decrypt(List<int> data, String privateKey);
}