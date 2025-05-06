import 'package:open_file/open_file.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/message.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class MessageRepository implements IMessageRepository {
  Future<String> _getMessagesPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/messages.json';
  }

  @override
  Future<Message> saveMessage(Message message) async {
    final file = File(await _getMessagesPath());
    List<dynamic> messages = [];
    if (await file.exists()) {
      messages = jsonDecode(await file.readAsString());
    }
    messages.add(message.toJson());
    await file.writeAsString(jsonEncode(messages));
    return message;
  }

  @override
  Future<List<Message>> getMessagesForUser(String userId, String recipientId) async {
    final file = File(await _getMessagesPath());
    if (!await file.exists()) return [];
    final messages = jsonDecode(await file.readAsString()) as List<dynamic>;
    return messages
        .map((m) => Message.fromJson(m))
        .where((m) =>
            (m.senderId == userId && m.recipientId == recipientId) ||
            (m.senderId == recipientId && m.recipientId == userId))
        .toList();
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final file = File(await _getMessagesPath());
    if (!await file.exists()) return;
    final messages = jsonDecode(await file.readAsString()) as List<dynamic>;
    final updated = messages.where((m) => m['message_id'] != messageId).toList();
    await file.writeAsString(jsonEncode(updated));
  }

  Future<List<Map<String, dynamic>>> getMessageMetadata(String userId, String recipientId) async {
    final messages = await getMessagesForUser(userId, recipientId);
    final filePath = await _getMessagesPath(); // Ваш метод получения пути
    final result = await OpenFile.open(filePath);
    
    print('Есть в файле: ${result.message}'); // Результат открытия файла
    return messages.map((m) => {
      'message_id': m.messageId,
      'timestamp': m.timestamp.toIso8601String(),
    }).toList();

  }

  Future<void> syncMessages(List<Message> remoteMessages) async {
    final file = File(await _getMessagesPath());
    List<dynamic> localMessages = [];
    if (await file.exists()) {
      localMessages = jsonDecode(await file.readAsString());
    }
    final localIds = localMessages.map((m) => m['message_id']).toSet();
    final newMessages = remoteMessages.where((m) => !localIds.contains(m.messageId)).map((m) => m.toJson());
    localMessages.addAll(newMessages);
    await file.writeAsString(jsonEncode(localMessages));
  }

  Future<List<Message>> getMessagesByIds(List<String> messageIds) async {
    try {
      final file = File(await _getMessagesPath());
      if (!await file.exists()) {
        return [];
      }

      final messages = jsonDecode(await file.readAsString()) as List<dynamic>;
      return messages
          .map((m) => Message.fromJson(m))
          .where((m) => messageIds.contains(m.messageId))
          .toList();
    } catch (e, stackTrace) {
      print('Error retrieving messages by IDs $messageIds: $e\nStackTrace: $stackTrace');
      rethrow;
    }
  }
}