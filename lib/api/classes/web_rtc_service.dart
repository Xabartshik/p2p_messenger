import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/message.dart' as api_message;
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WebRTCService implements IWebRTCService {
  final IUserRepository userRepository;
  final IMessageRepository messageRepository;
  final IEncryptionService encryptionService;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  IO.Socket? _socket;
  final _messageStreamController = StreamController<api_message.Message>.broadcast();
  Map<String, dynamic>? _pendingMetadata;

  WebRTCService(this.userRepository, this.messageRepository, this.encryptionService);

  @override
  Future<void> initialize(String peerId, String serverUrl, String token) async {
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'extraHeaders': {'Authorization': 'Bearer $token'},
    });

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
    };
    _peerConnection = await createPeerConnection(configuration);
    
    final dataChannelInit = RTCDataChannelInit()..binaryType = 'binary';
    _dataChannel = await _peerConnection!.createDataChannel('messenger', dataChannelInit);

    _dataChannel!.onMessage = (message) async {
      try {
        if (_pendingMetadata == null) {
          _pendingMetadata = jsonDecode(message.text);
          if (_pendingMetadata!['type'] == 'sync_metadata') {
            await _handleSyncMetadata(_pendingMetadata!, peerId);
            _pendingMetadata = null;
          }
        } else {
          final metadata = _pendingMetadata!;
          if (metadata['type'] == 'MessageType.text' || metadata['type'] == 'MessageType.json' || metadata['type'] == 'MessageType.file') {
            final recipient = await userRepository.getUserById(metadata['recipient_id']);
            final privateKey = await FlutterSecureStorage().read(key: 'private_key_${recipient!.userId}');
            
            final decryptedContent = await encryptionService.decrypt(
              message.isBinary ? message.binary : utf8.encode(message.text),
              privateKey!,
            );

            final content = metadata['type'] == 'MessageType.text' || metadata['type'] == 'MessageType.json'
                ? utf8.decode(decryptedContent)
                : decryptedContent;

            List<api_message.FileAttachment>? attachments;
            if (metadata['type'] == 'MessageType.file') {
              attachments = metadata['attachments'].map<api_message.FileAttachment>((a) {
                return api_message.FileAttachment(
                  fileId: a['file_id'],
                  fileName: a['file_name'],
                  fileType: a['file_type'],
                  content: content,
                  size: a['size'],
                );
              }).toList();
            }

            final msg = api_message.Message(
              messageId: metadata['message_id'],
              senderId: metadata['sender_id'],
              recipientId: metadata['recipient_id'],
              type: api_message.MessageType.values.firstWhere((e) => e.toString() == metadata['type']),
              textContent: metadata['text_content'],
              attachments: attachments,
              timestamp: DateTime.parse(metadata['timestamp']),
              status: api_message.MessageStatus.delivered,
            );
            await messageRepository.saveMessage(msg);
            _messageStreamController.add(msg);
            _pendingMetadata = null;
          }
        }
      } catch (e) {
        print('Error processing message: $e');
      }
    };

    _socket!.on('message', (data) async {
      try {
        if (data['type'] == 'offer') {
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          _socket!.emit('message', {
            'type': 'answer',
            'sdp': answer.sdp,
            'from': peerId,
            'to': data['from'],
            'token': token,
          });
          // Запуск синхронизации после установления соединения
          await _startSync(peerId, data['from']);
        } else if (data['type'] == 'answer') {
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
          // Запуск синхронизации
          await _startSync(peerId, data['from']);
        } else if (data['type'] == 'candidate') {
          await _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      } catch (e) {
        print('Error processing server message: $e');
      }
    });

    _peerConnection!.onIceCandidate = (candidate) {
      _socket!.emit('message', {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'from': peerId,
        'to': peerId == '123' ? '456' : '123', // Пример
        'token': token,
      });
    };

    if (peerId == '123') { // Инициатор
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _socket!.emit('message', {
        'type': 'offer',
        'sdp': offer.sdp,
        'from': peerId,
        'to': '456',
        'token': token,
      });
    }

    _socket!.connect();
  }

  Future<void> _startSync(String peerId, String recipientId) async {
    final metadata = await messageRepository.getMessageMetadata(peerId, recipientId);
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
      'type': 'sync_metadata',
      'sender_id': peerId,
      'recipient_id': recipientId,
      'metadata': metadata,
    })));
  }

  Future<void> _handleSyncMetadata(Map<String, dynamic> metadata, String peerId) async {
    final remoteMetadata = metadata['metadata'] as List<dynamic>;
    final localMetadata = await messageRepository.getMessageMetadata(peerId, metadata['sender_id']);
    final localIds = localMetadata.map((m) => m['message_id']).toSet();
    
    final missingIds = remoteMetadata
        .where((m) => !localIds.contains(m['message_id']))
        .map((m) => m['message_id'])
        .toList();
    
    if (missingIds.isNotEmpty) {
      // Запросить недостающие сообщения
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
        'type': 'request_messages',
        'sender_id': peerId,
        'recipient_id': metadata['sender_id'],
        'message_ids': missingIds,
      })));
    }
  }

  @override
  Future<void> sendMessage(api_message.Message message) async {
    final recipient = await userRepository.getUserById(message.recipientId);
    final metadata = message.toJson();

    if (message.type == MessageType.text || message.type == api_message.MessageType.json) {
      final encryptedContent = await encryptionService.encrypt(
        utf8.encode(message.textContent!),
        recipient!.publicKey,
      );
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(metadata)));
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(encryptedContent)));
    } else if (message.type == api_message.MessageType.file) {
      for (var attachment in message.attachments!) {
        final encryptedContent = await encryptionService.encrypt(
          attachment.content is String ? (await File(attachment.content).readAsBytes()) : attachment.content,
          recipient!.publicKey,
        );
        final updatedMetadata = {
          ...metadata,
          'attachments': [
            {
              'file_id': attachment.fileId,
              'file_name': attachment.fileName,
              'file_type': attachment.fileType,
              'size': attachment.size,
            }
          ],
        };
        _dataChannel!.send(RTCDataChannelMessage(jsonEncode(updatedMetadata)));
        _dataChannel!.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(encryptedContent)));
      }
    }
  }

  @override
  Stream<api_message.Message> onMessageReceived() => _messageStreamController.stream;

  @override
  Future<void> close() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
    _socket?.disconnect();
    await _messageStreamController.close();
  }
}
