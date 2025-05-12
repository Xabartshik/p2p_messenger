import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:external_path/external_path.dart';
import 'package:p2p_messenger/api/models/message.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:path_provider/path_provider.dart';

class MessageRepository implements IMessageRepository {
  static const _dbName = 'p2p_messenger.db';
  static const _dbVersion = 1;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        message_id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        sender_identifier TEXT NOT NULL,
        sender_username TEXT NOT NULL,
        recipient_id TEXT,
        group_id TEXT,
        type TEXT NOT NULL,
        text_content TEXT,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        CHECK (recipient_id IS NOT NULL OR group_id IS NOT NULL)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_sender_recipient ON messages (sender_id, recipient_id);
    ''');
    await db.execute('''
      CREATE INDEX idx_messages_group ON messages (group_id);
    ''');

    await db.execute('''
      CREATE TABLE attachments (
        file_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        size INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages (message_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_attachments_message_id ON attachments (message_id);
    ''');

    await db.execute('''
      CREATE TABLE groups (
        group_id TEXT PRIMARY KEY,
        group_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE group_members (
        group_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        joined_at TEXT NOT NULL,
        PRIMARY KEY (group_id, user_id),
        FOREIGN KEY (group_id) REFERENCES groups (group_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_group_members_user_id ON group_members (user_id);
    ''');
  }

  @override
  Future<Message> saveMessage(Message message) async {
    final db = await database;

    await db.insert(
      'messages',
      message.toJson()..remove('attachments'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (message.attachments != null) {
      // Создаем новый список вложений с обновленными путями
      final updatedAttachments = <FileAttachment>[];

      for (final attachment in message.attachments!) {
        // Сохраняем файл и получаем путь
        final filePath = attachment.content is String
            ? attachment.content as String
            : await saveFileLocally(attachment);

        // Создаем новое вложение с путем вместо байтов
        updatedAttachments.add(FileAttachment(
          fileId: attachment.fileId,
          fileName: attachment.fileName,
          fileType: attachment.fileType,
          content: filePath, // Теперь всегда строка (путь)
          size: attachment.size,
        ));

        // Сохраняем в базу данных
        await db.insert(
          'attachments',
          {
            'file_id': attachment.fileId,
            'message_id': message.messageId,
            'file_name': attachment.fileName,
            'file_type': attachment.fileType,
            'file_path': filePath,
            'size': attachment.size,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Возвращаем сообщение с обновленными вложениями
      return message.copyWith(attachments: updatedAttachments);
    }

    return message;
  }

  @override
  Future<List<Message>> getMessagesForUser(
      String userId, String recipientId) async {
    final db = await database;

    final messages = await db.query(
      'messages',
      where:
          '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [userId, recipientId, recipientId, userId],
      orderBy: 'timestamp ASC',
    );

    return await _getMessagesWithAttachments(messages);
  }

  Future<List<Message>> getGroupMessages(String groupId) async {
    final db = await database;

    final messages = await db.query(
      'messages',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp ASC',
    );

    return await _getMessagesWithAttachments(messages);
  }

  Future<List<Message>> _getMessagesWithAttachments(
      List<Map<String, dynamic>> messages) async {
    final db = await database;
    final messageIds = messages.map((m) => m['message_id']).toList();
    if (messageIds.isEmpty) return [];

    // Получаем все вложения для указанных сообщений
    final attachments = await db.query(
      'attachments',
      where: 'message_id IN (${List.filled(messageIds.length, '?').join(',')})',
      whereArgs: messageIds,
    );

    // Группируем вложения по message_id
    final attachmentMap = <String, List<FileAttachment>>{};
    for (final att in attachments) {
      final messageId = att['message_id'] as String;
      attachmentMap.putIfAbsent(messageId, () => []).add(
            FileAttachment(
              fileId: att['file_id'] as String,
              fileName: att['file_name'] as String,
              fileType: att['file_type'] as String,
              content: att['file_path'],
              size: att['size'] as int,
            ),
          );
    }

    // Формируем список сообщений
    return messages.map((msg) {
      return Message.fromJson({
        ...msg,
        'attachments':
            attachmentMap[msg['message_id']]?.map((a) => a.toJson()).toList(),
      });
    }).toList();
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getMessageMetadata(
      String userId, String recipientId) async {
    final messages = await getMessagesForUser(userId, recipientId);

    return messages
        .where(
            (m) => m.status == MessageStatus.delivered) // Фильтруем по статусу
        .map((m) => {
              'message_id': m.messageId,
              'timestamp': m.timestamp.toIso8601String(),
            })
        .toList();
  }

  @override
  Future<List<Message>> getMessagesByIds(List<String> messageIds) async {
    if (messageIds.isEmpty) return [];

    final db = await database;
    final messages = await db.query(
      'messages',
      where: 'message_id IN (${List.filled(messageIds.length, '?').join(',')})',
      whereArgs: messageIds,
    );

    return await _getMessagesWithAttachments(messages);
  }

  Future<void> createGroup({
    required String groupId,
    required String groupName,
    required String creatorId,
    required List<String> memberIds,
  }) async {
    final db = await database;

    await db.insert('groups', {
      'group_id': groupId,
      'group_name': groupName,
      'created_at': DateTime.now().toIso8601String(),
      'created_by': creatorId,
    });

    for (final memberId in memberIds) {
      await db.insert('group_members', {
        'group_id': groupId,
        'user_id': memberId,
        'joined_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getUserGroups(String userId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT groups.group_id, groups.group_name, groups.created_at, groups.created_by
      FROM group_members
      INNER JOIN groups ON group_members.group_id = groups.group_id
      WHERE group_members.user_id = ?
    ''', [userId]);
  }

  Future<void> addGroupMembers(String groupId, List<String> memberIds) async {
    final db = await database;
    final batch = db.batch();

    for (final memberId in memberIds) {
      batch.insert('group_members', {
        'group_id': groupId,
        'user_id': memberId,
        'joined_at': DateTime.now().toIso8601String(),
      });
    }

    await batch.commit();
  }

  Future<void> syncMessages(List<Message> remoteMessages) async {
    final db = await database;
    final batch = db.batch();

    for (final message in remoteMessages) {
      batch.insert(
        'messages',
        message.toJson()..remove('attachments'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (message.attachments != null) {
        for (final attachment in message.attachments!) {
          batch.insert(
            'attachments',
            {
              'file_id': attachment.fileId,
              'message_id': message.messageId,
              'file_name': attachment.fileName,
              'file_type': attachment.fileType,
              'file_path':
                  attachment.content is String ? attachment.content : '',
              'size': attachment.size,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    }

    await batch.commit();
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<String> saveFileLocally(FileAttachment attachment) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final fileName = attachment.fileName;
    final filePath = '${documentsDir.path}/$fileName';
    final file = File(filePath);

    if (attachment.content is List<int>) {
      await file.writeAsBytes(attachment.content as List<int>);
    } else if (attachment.content is String) {
      // Если content - это путь или URL, копируем файл
      final sourceFile = File(attachment.content as String);
      if (await sourceFile.exists()) {
        await sourceFile.copy(filePath);
      } else {
        throw Exception('Source file does not exist: ${attachment.content}');
      }
    } else {
      throw Exception(
          'Unsupported content type for attachment: ${attachment.content.runtimeType}');
    }

    print('Saved file locally: $filePath');
    return filePath;
  }
}


