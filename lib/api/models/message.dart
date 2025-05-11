enum MessageType { text, json, file }
enum MessageStatus { sent, delivered, undelivered, read }

class FileAttachment {
  final String fileId;
  final String fileName;
  final String fileType; // image, video, audio, document
  final dynamic content; // String (URL) или List<int> (байты)
  final int size; // Размер в байтах

  FileAttachment({
    required this.fileId,
    required this.fileName,
    required this.fileType,
    required this.content,
    required this.size,
  });

  factory FileAttachment.fromJson(Map<String, dynamic> json) => FileAttachment(
        fileId: json['file_id'],
        fileName: json['file_name'],
        fileType: json['file_type'],
        content: json['content'],
        size: json['size'],
      );

  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        'file_name': fileName,
        'file_type': fileType,
        'content': content,
        'size': size,
      };
}

class Message {
  final String messageId;
  final String senderId;
  final String senderIdentifier;
  final String senderUsername;
  final String? recipientId;  // Null для групповых сообщений
  final String? groupId;      // Null для личных сообщений
  final MessageType type;
  final String? textContent;
  final List<FileAttachment>? attachments;
  final DateTime timestamp;
  final MessageStatus status;

  Message({
    required this.messageId,
    required this.senderId,
    required this.senderIdentifier,
    required this.senderUsername,
    this.recipientId,
    this.groupId,
    required this.type,
    this.textContent,
    this.attachments,
    required this.timestamp,
    required this.status,
  }) : assert(recipientId != null || groupId != null, 'Either recipientId or groupId must be provided');

  Message copyWith({
    String? messageId,
    String? senderId,
    String? senderIdentifier,
    String? senderUsername,
    String? recipientId,
    String? groupId,
    MessageType? type,
    String? textContent,
    List<FileAttachment>? attachments,
    DateTime? timestamp,
    MessageStatus? status,
  }) {
    return Message(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      senderIdentifier: senderIdentifier ?? this.senderIdentifier,
      senderUsername: senderUsername ?? this.senderUsername,
      recipientId: recipientId ?? this.recipientId,
      groupId: groupId ?? this.groupId,
      type: type ?? this.type,
      textContent: textContent ?? this.textContent,
      attachments: attachments ?? this.attachments,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        messageId: json['message_id'],
        senderId: json['sender_id'],
        senderIdentifier: json['sender_identifier'],
        senderUsername: json['sender_username'],
        recipientId: json['recipient_id'],
        groupId: json['group_id'],
        type: MessageType.values.firstWhere((e) => e.name == json['type']),
        textContent: json['text_content'],
        attachments: json['attachments'] != null
            ? (json['attachments'] as List).map((a) => FileAttachment.fromJson(a)).toList()
            : null,
        timestamp: DateTime.parse(json['timestamp']),
        status: MessageStatus.values.firstWhere((e) => e.name == json['status']),
      );

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'sender_id': senderId,
        'sender_identifier': senderIdentifier,
        'sender_username': senderUsername,
        'recipient_id': recipientId,
        'group_id': groupId,
        'type': type.name,
        'text_content': textContent,
        'attachments': attachments?.map((a) => a.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
      };

  bool get isGroupMessage => groupId != null;
}
