import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:p2p_messenger/api/classes/message_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/message.dart';
import 'package:p2p_messenger/api/models/user.dart';

class MessengerAPI {
  final String serverUrl;
  final IUserRepository userRepository;
  final IMessageRepository messageRepository;
  final IWebRTCService webRTCService;
  final IAuthService authService;
  final FlutterSecureStorage _secureStorage;
  User? currentUser;
  
  MessengerAPI({
    required this.serverUrl,
    required this.userRepository,
    required this.messageRepository,
    required this.webRTCService,
    required this.authService,
  }) : _secureStorage = FlutterSecureStorage();

  Future<User> registerUser(String username, String email, String password, String identifier) async {
    // Генерация ключей
    final keyPair = await webRTCService.encryptionService.generateKeyPair();
    final publicKey = keyPair['publicKey']!;
    final privateKey = keyPair['privateKey']!;

    print('Ключи при регистрации, PUBLIC: $publicKey, PRIVATE: $privateKey');

    // Регистрация пользователя
    final user = await userRepository.createUser(username, email, password, publicKey, identifier);

    // Сохранение приватного ключа и токена
    await _secureStorage.write(key: 'private_key_${user.userId}', value: privateKey);
    await _secureStorage.write(key: "user_id", value: user.userId);

    // Инициализация WebRTC
    await initializeConnection(user.userId, serverUrl);

    currentUser = await userRepository.getCurrentUser();

    return user;
  }

  Future<User> loginUser(String email, String password) async {
    // Логин пользователя
    final user = await authService.login(email, password);

    // Проверка и генерация ключей
    String? privateKey = await _secureStorage.read(key: 'private_key_${user.userId}');
    if (privateKey == null) {
      print('Private key not found for user ${user.userId}, generating new key pair...');
      final keyPair = await webRTCService.encryptionService.generateKeyPair();
      privateKey = keyPair['privateKey']!;
      final publicKey = keyPair['publicKey']!;
      await _secureStorage.write(key: 'private_key_${user.userId}', value: privateKey);
      await userRepository.updateUser(
        User(
          userId: user.userId,
          username: user.username,
          email: user.email,
          status: user.status,
          publicKey: publicKey,
          identifier: user.identifier,
          token: user.token,
        ),
      );
    }

    // Сохранение токена и userId
    await _secureStorage.write(key: 'jwt_token_${user.userId}', value: user.token!);
    await _secureStorage.write(key: "user_id", value: user.userId);
    // Инициализация WebRTC
    await initializeConnection(user.userId, serverUrl);

    currentUser = await userRepository.getCurrentUser();

    return user;
  }

  Future<void> sendMessage(String senderId, String recipientId, Message message) async {
    if (currentUser == null)
    {
        throw Exception('Current User is null');
    }
    print('Sending message from $senderId to $recipientId: ${message.toJson()}');
    Message updatedMessage = message;

    if (message.type == MessageType.file && message.attachments != null) {
      final updatedAttachments = <FileAttachment>[];
      for (final attachment in message.attachments!) {
        final localPath = await messageRepository.saveFileLocally(attachment);
        updatedAttachments.add(
          FileAttachment(
            fileId: attachment.fileId,
            fileName: attachment.fileName,
            fileType: attachment.fileType,
            content: localPath,
            size: attachment.size,
          ),
        );
      }
      updatedMessage = Message(
        messageId: message.messageId,
        senderId: message.senderId,
        recipientId: message.recipientId,
        senderIdentifier: currentUser!.identifier,
        senderUsername: currentUser!.username,
        groupId: message.groupId,
        type: message.type,
        textContent: message.textContent,
        attachments: updatedAttachments,
        timestamp: message.timestamp,
        status: message.status,
      );
    }

    await messageRepository.saveMessage(updatedMessage);
    try {
      final recipient = await userRepository.getUserById(recipientId, senderId);
      if (recipient == null) {
        throw Exception('Recipient not found');
      }
      print('Recipient status: ${recipient.status}');
      if (recipient.status == 'offline') {
        throw Exception('Recipient is offline');
      }
      await webRTCService.sendMessage(updatedMessage);
      await messageRepository.saveMessage(updatedMessage.copyWith(status: MessageStatus.delivered));
      print('Message marked as delivered: ${updatedMessage.messageId}');
    } catch (e, stackTrace) {
      print('Failed to send message to $recipientId: $e\nStackTrace: $stackTrace');
      Future.delayed(Duration(seconds: 5), () {
        print('Scheduling sync for message ${updatedMessage.messageId} to $recipientId');
        syncWithUser(senderId, recipientId);
      });
      throw Exception('Recipient offline or connection failed: $e');
    }
  }

  Future<List<Message>> getChatHistory(String userId, String recipientId) async {
    return await messageRepository.getMessagesForUser(userId, recipientId);
  }

  Future<void> deleteMessage(String messageId) async {
    final message = (await messageRepository.getMessagesByIds([messageId])).first;
    if (message.type == MessageType.file && message.attachments != null) {
      for (var attachment in message.attachments!) {
        final file = File(attachment.content as String);
        if (await file.exists()) {
          await file.delete();
          print('Deleted file: ${attachment.content}');
        }
      }
    }
    await messageRepository.deleteMessage(messageId);
  }

  Stream<Message> listenForMessages(String userId) {
    print('Listening for messages for user $userId');
    return webRTCService.onMessageReceived();
  }

  Future<void> initializeConnection(String userId, String serverUrl) async {
    final token = await _secureStorage.read(key: 'jwt_token_$userId');
    if (token == null) {
      throw Exception('No token found for user $userId');
    }
    print('Initializing WebRTC connection for user $userId with token $token');
    await webRTCService.initialize(userId, serverUrl, token);
  }

  Future<void> syncWithUser(String userId, String recipientId) async {
    try {
      final recipient = await userRepository.getUserById(recipientId, userId);
      print('Syncing with recipient $recipientId, status: ${recipient?.status}');
      if (recipient?.status == 'online') {
        final messages = await messageRepository.getMessagesForUser(userId, recipientId);
        for (var message in messages.where((m) => m.status == MessageStatus.sent)) {
          try {
            await webRTCService.sendMessage(message);
            await messageRepository.saveMessage(message.copyWith(status: MessageStatus.delivered));
            print('Synced message ${message.messageId} to $recipientId');
          } catch (e, stackTrace) {
            print('Sync failed for message ${message.messageId}: $e\nStackTrace: $stackTrace');
          }
        }
      } else {
        print('Recipient $recipientId is offline, skipping sync');
      }
    } catch (e, stackTrace) {
      print('Sync error: $e\nStackTrace: $stackTrace');
    }
  }


}

extension on Message {
  Message copyWith({MessageStatus? status}) => Message(
        messageId: messageId,
        senderId: senderId,
        recipientId: recipientId,
        senderUsername: senderUsername,
        senderIdentifier: senderIdentifier,
        groupId: groupId,
        type: type,
        textContent: textContent,
        attachments: attachments,
        timestamp: timestamp,
        status: status ?? this.status,
      );
}