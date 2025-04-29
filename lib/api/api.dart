import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/message.dart';
import 'package:p2p_messenger/api/models/user.dart';

class MessengerAPI {
  final IUserRepository userRepository;
  final IMessageRepository messageRepository;
  final IFileStorage fileStorage;
  final IWebRTCService webRTCService;
  final IAuthService authService;

  MessengerAPI({
    required this.userRepository,
    required this.messageRepository,
    required this.fileStorage,
    required this.webRTCService,
    required this.authService,
  });

  Future<User> registerUser(String username, String email, String password, String publicKey, String identifier) async {
    final user = await userRepository.createUser(username, email, password, publicKey, identifier);
    return user;
  }

  Future<User> loginUser(String email, String password) async {
    return await authService.login(email, password);
  }

  Future<void> sendMessage(String senderId, String recipientId, Message message) async {
    print('Sending message from $senderId to $recipientId: ${message.toJson()}');
    if (message.type == MessageType.file && message.attachments != null) {
      final fileUrls = await fileStorage.uploadFiles(message.attachments!);
      message = Message(
        messageId: message.messageId,
        senderId: message.senderId,
        recipientId: message.recipientId,
        type: message.type,
        textContent: message.textContent,
        attachments: message.attachments!.asMap().entries.map((e) {
          final a = e.value;
          return FileAttachment(
            fileId: a.fileId,
            fileName: a.fileName,
            fileType: a.fileType,
            content: fileUrls[e.key],
            size: a.size,
          );
        }).toList(),
        timestamp: message.timestamp,
        status: message.status,
      );
    }
    await messageRepository.saveMessage(message);
    try {
      // Проверяем статус получателя
      final recipient = await userRepository.getUserById(recipientId, senderId);
      if (recipient == null) {
        throw Exception('Recipient not found');
      }
      print('Recipient status: ${recipient.status}');
      if (recipient.status == 'offline') {
        throw Exception('Recipient is offline');
      }
      await webRTCService.sendMessage(message);
      await messageRepository.saveMessage(message.copyWith(status: MessageStatus.delivered));
      print('Message marked as delivered: ${message.messageId}');
    } catch (e, stackTrace) {
      print('Failed to send message to $recipientId: $e\nStackTrace: $stackTrace');
      // Планируем повторную попытку синхронизации
      Future.delayed(Duration(seconds: 5), () {
        print('Scheduling sync for message ${message.messageId} to $recipientId');
        syncWithUser(senderId, recipientId);
      });
      throw Exception('Recipient offline or connection failed: $e');
    }
  }

  Future<List<Message>> getChatHistory(String userId, String recipientId) async {
    return await messageRepository.getMessagesForUser(userId, recipientId);
  }

  Future<void> deleteMessage(String messageId) async {
    final message = (await messageRepository.getMessagesForUser('', '')).firstWhere((m) => m.messageId == messageId);
    if (message.type == MessageType.file && message.attachments != null) {
      for (var attachment in message.attachments!) {
        await fileStorage.deleteFile(attachment.content);
      }
    }
    await messageRepository.deleteMessage(messageId);
  }

  Stream<Message> listenForMessages(String userId) {
    print('Listening for messages for user $userId');
    return webRTCService.onMessageReceived();
  }

  Future<void> initializeConnection(String userId, String serverUrl) async {
    final token = await FlutterSecureStorage().read(key: 'jwt_token_$userId');
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
        type: type,
        textContent: textContent,
        attachments: attachments,
        timestamp: timestamp,
        status: status ?? this.status,
      );
}
