enum MessageType { text, json, file }
enum MessageStatus { sent, delivered, read }

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
  final String recipientId;
  final MessageType type;
  final String? textContent; // Для text/json
  final List<FileAttachment>? attachments; // Для файлов
  final DateTime timestamp;
  final MessageStatus status;

  Message({
    required this.messageId,
    required this.senderId,
    required this.recipientId,
    required this.type,
    this.textContent,
    this.attachments,
    required this.timestamp,
    required this.status,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        messageId: json['message_id'],
        senderId: json['sender_id'],
        recipientId: json['recipient_id'],
        type: MessageType.values.firstWhere((e) => e.toString() == json['type']),
        textContent: json['text_content'],
        attachments: json['attachments'] != null
            ? (json['attachments'] as List).map((a) => FileAttachment.fromJson(a)).toList()
            : null,
        timestamp: DateTime.parse(json['timestamp']),
        status: MessageStatus.values.firstWhere((e) => e.toString() == json['status']),
      );

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'type': type.toString(),
        'text_content': textContent,
        'attachments': attachments?.map((a) => a.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
        'status': status.toString(),
      };
}