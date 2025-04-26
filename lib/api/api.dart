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
    await authService.generateToken(user);
    return user;
  }

  Future<User> loginUser(String email, String password) async {
    return await authService.login(email, password);
  }

  Future<void> sendMessage(String senderId, String recipientId, Message message) async {
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
      await webRTCService.sendMessage(message);
    } catch (e) {
      print('Recipient offline, message saved locally: $e');
      // Сообщение будет отправлено при следующем соединении
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
    return webRTCService.onMessageReceived();
  }

  Future<void> initializeConnection(String userId, String serverUrl) async {
    final token = await FlutterSecureStorage().read(key: 'jwt_token_$userId');
    await webRTCService.initialize(userId, serverUrl, token!);
  }

  Future<void> syncWithUser(String userId, String recipientId) async {
    final messages = await messageRepository.getMessagesForUser(userId, recipientId);
    for (var message in messages.where((m) => m.status == MessageStatus.sent)) {
      try {
        await webRTCService.sendMessage(message);
        await messageRepository.saveMessage(message.copyWith(status: MessageStatus.delivered));
      } catch (e) {
        print('Sync failed for message ${message.messageId}: $e');
      }
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