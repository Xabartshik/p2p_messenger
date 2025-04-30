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
  String? _currentPeerId;
  String? _currentRecipientId;
  bool _isInitiator = false;
  int _connectionAttempts = 0;
  static const int _maxConnectionAttempts = 3;
  Timer? _offerTimeoutTimer;

  WebRTCService(this.userRepository, this.messageRepository, this.encryptionService);

  @override
  Future<void> initialize(String peerId, String serverUrl, String token) async {
    _currentPeerId = peerId;
    print('Initializing WebRTC for peer $peerId with server $serverUrl');

    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'extraHeaders': {'Authorization': 'Bearer $token'},
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
    });

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        // Замените на реальный TURN-сервер
        {
          'urls': 'turn:your-turn-server.com:3478',
          'username': 'your-username',
          'credential': 'your-credential',
        },
      ],
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
    };
    await _createPeerConnection(configuration);

    _socket!.on('connect', (_) {
      print('Socket connected for peer $peerId, SID: ${_socket!.id}');
      _socket!.emit('register', {'user_id': peerId, 'token': token});
    });

    _socket!.on('disconnect', (_) {
      print('Socket disconnected for peer $peerId, attempting to reconnect...');
      _socket!.connect();
    });

    _socket!.on('error', (data) {
      print('Socket.IO error for peer $peerId: $data');
    });

    _socket!.on('message', (data) async {
      print('Received Socket.IO message for peer $peerId: $data');
      try {
        if (data['type'] == 'offer') {
          print('Processing offer from ${data['from']}');
          await _handleOffer(data, peerId, token);
        } else if (data['type'] == 'answer') {
          print('Processing answer from ${data['from']}');
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
          _currentRecipientId = data['from'];
          await _startSync(peerId, data['from']);
        } else if (data['type'] == 'candidate') {
          print('Adding ICE candidate from ${data['from']}');
          await _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      } catch (e, stackTrace) {
        print('Error processing server message for peer $peerId: $e\nStackTrace: $stackTrace');
      }
    });

    _socket!.connect();
    print('Socket connection initiated for peer $peerId');
  }

  Future<void> _createPeerConnection(Map<String, dynamic> configuration) async {
    _peerConnection = await createPeerConnection(configuration);

    final dataChannelInit = RTCDataChannelInit()..binaryType = 'binary';
    _dataChannel = await _peerConnection!.createDataChannel('messenger', dataChannelInit);

    

    _dataChannel!.onMessage = (message) async {
      print('Received data channel message for peer $_currentPeerId: isBinary=${message.isBinary}');
      try {
        if (_pendingMetadata == null) {
          _pendingMetadata = jsonDecode(message.text);
          print('Received metadata: $_pendingMetadata');
          if (_pendingMetadata!['type'] == 'sync_metadata') {
            await _handleSyncMetadata(_pendingMetadata!, _currentPeerId!);
            _pendingMetadata = null;
          }
        } else {
          final metadata = _pendingMetadata!;
          print('Processing message with metadata: $metadata');
          if (metadata['type'] == 'MessageType.text' ||
              metadata['type'] == 'MessageType.json' ||
              metadata['type'] == 'MessageType.file') {
            final recipient = await userRepository.getUserById(metadata['recipient_id'], _currentPeerId!);
            if (recipient == null) {
              print('Recipient not found for ID: ${metadata['recipient_id']}');
              _pendingMetadata = null;
              return;
            }
            final privateKey = await FlutterSecureStorage().read(key: 'private_key_${recipient.userId}');
            if (privateKey == null) {
              print('Private key not found for user: ${recipient.userId}, saving message as undelivered');
              final msg = api_message.Message(
                messageId: metadata['message_id'],
                senderId: metadata['sender_id'],
                recipientId: metadata['recipient_id'],
                type: api_message.MessageType.values.firstWhere((e) => e.toString() == metadata['type']),
                textContent: metadata['text_content'],
                attachments: metadata['attachments']?.map<api_message.FileAttachment>((a) {
                  return api_message.FileAttachment(
                    fileId: a['file_id'],
                    fileName: a['file_name'],
                    fileType: a['file_type'],
                    content: null,
                    size: a['size'],
                  );
                })?.toList(),
                timestamp: DateTime.parse(metadata['timestamp']),
                status: api_message.MessageStatus.undelivered,
              );
              await messageRepository.saveMessage(msg);
              _messageStreamController.add(msg);
              _pendingMetadata = null;
              return;
            }

            final decryptedContent = await encryptionService.decrypt(
              message.isBinary ? message.binary : utf8.encode(message.text),
              privateKey,
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
            print('Saved message: ${msg.toJson()}');
            _messageStreamController.add(msg);
            print('Streamed message to UI: ${msg.textContent}');
            _pendingMetadata = null;
          }
        }
      } catch (e, stackTrace) {
        print('Error processing message for peer $_currentPeerId: $e\nStackTrace: $stackTrace');
        _pendingMetadata = null;
      }
    };

    _dataChannel!.onDataChannelState = (state) {
      print('Data channel state changed to: $state for peer $_currentPeerId');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _connectionAttempts = 0; // Сброс счетчика попыток
        if (_currentRecipientId != null) {
          _startSync(_currentPeerId!, _currentRecipientId!); // Повторная синхронизация
        }
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        print('Data channel closed, attempting to reconnect...');
        _reconnect();
      }
    };

    _peerConnection!.onDataChannel = (channel) {
    _dataChannel = channel;
    _dataChannel!.onMessage = (message) async {
      print('Received data channel message for peer $_currentPeerId: isBinary=${message.isBinary}');
      try {
        if (_pendingMetadata == null) {
          _pendingMetadata = jsonDecode(message.text);
          print('Received metadata: $_pendingMetadata');
          if (_pendingMetadata!['type'] == 'sync_metadata') {
            await _handleSyncMetadata(_pendingMetadata!, _currentRecipientId!);
            _pendingMetadata = null;
          }
        } else {
          final metadata = _pendingMetadata!;
          print('Processing message with metadata: $metadata');
          if (metadata['type'] == 'MessageType.text' || metadata['type'] == 'MessageType.json' || metadata['type'] == 'MessageType.file') {
            final recipient = await userRepository.getUserById(metadata['recipient_id'], _currentRecipientId!);
            if (recipient == null) {
              print('Recipient not found for ID: ${metadata['recipient_id']}');
              _pendingMetadata = null;
              return;
            }
            final privateKey = await FlutterSecureStorage().read(key: 'private_key_${recipient.userId}');
            if (privateKey == null) {
              print('Private key not found for user: ${recipient.userId}');
              _pendingMetadata = null;
              return;
            }

            final decryptedContent = await encryptionService.decrypt(
              message.isBinary ? message.binary : utf8.encode(message.text),
              privateKey,
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
            print('Saved message: ${msg.toJson()}');
            _messageStreamController.add(msg);
            print('Streamed message to UI: ${msg.textContent}');
            _pendingMetadata = null;
          }
        }
      } catch (e, stackTrace) {
        print('Error processing message for peer $_currentPeerId: $e\nStackTrace: $stackTrace');
        _pendingMetadata = null;
      }
    };
    _dataChannel!.onDataChannelState = (state) {
      print('Data channel state changed to: $state for peer $_currentRecipientId');
    };
  };

    _peerConnection!.onIceCandidate = (candidate) async {
      if (_currentRecipientId != null) {
        print('Sending ICE candidate for peer $_currentPeerId: ${candidate.candidate}');
        if (candidate.candidate!.contains('typ relay')) {
          print('Using TURN server for candidate: ${candidate.candidate}');
        }
        _socket!.emit('message', {
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'from': _currentPeerId,
          'to': _currentRecipientId,
          'token': await FlutterSecureStorage().read(key: 'jwt_token_$_currentPeerId'),
        });
      } else {
        print('Skipping ICE candidate for peer $_currentPeerId: no recipient set');
      }
    };

    _peerConnection!.onIceGatheringState = (state) {
      print('ICE gathering state changed to: $state for peer $_currentPeerId');
    };

    _peerConnection!.onConnectionState = (state) {
      print('Peer connection state changed to: $state for peer $_currentPeerId');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        print('Connection failed or disconnected, attempting to reconnect...');
        _reconnect();
      }
    };
  }

  void _cancelOfferTimeout() {
    _offerTimeoutTimer?.cancel();
    _offerTimeoutTimer = null;
    print("Offer timeout cancelled - offer received");
  }

  Future<void> _handleOffer(Map<String, dynamic> data, String peerId, String token) async {
    if (_peerConnection!.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      print('Conflict: Received offer while in have-local-offer state, rolling back...');
      await _peerConnection!.setLocalDescription(RTCSessionDescription('', '')); // Откат локального offer
    }
    try {
      _cancelOfferTimeout();
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
      print('Sent answer to ${data['from']}');
      _currentRecipientId = data['from'];
      await _startSync(peerId, data['from']);
    } catch (e, stackTrace) {
      print('Error handling offer: $e\nStackTrace: $stackTrace');
      _reconnect();
    }
  }

  Future<void> _reconnect() async {
    if (_connectionAttempts >= _maxConnectionAttempts) {
      print('Max connection attempts reached for peer $_currentPeerId');
      throw Exception('Failed to establish WebRTC connection after $_maxConnectionAttempts attempts');
    }
    _connectionAttempts++;
    print('Reconnection attempt $_connectionAttempts for peer $_currentPeerId');
    await _peerConnection?.close();
    await _dataChannel?.close();
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {
          'urls': 'turn:your-turn-server.com:3478',
          'username': 'your-username',
          'credential': 'your-credential',
        },
      ],
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
    };
    await _createPeerConnection(configuration);
    if (_currentRecipientId != null) {
      await _initiateConnection(_currentPeerId!, _currentRecipientId!);
    }
  }

  Future<void> _startSync(String peerId, String recipientId) async {
    print('Starting sync for peer $peerId with recipient $recipientId');
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      final metadata = await messageRepository.getMessageMetadata(peerId, recipientId);
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
        'type': 'sync_metadata',
        'sender_id': peerId,
        'recipient_id': recipientId,
        'metadata': metadata,
      })));
      print('Sent sync metadata to $recipientId');
    } else {
      print('Cannot start sync: data channel is not open, will retry when open');
    }
  }

  Future<void> _handleSyncMetadata(Map<String, dynamic> metadata, String peerId) async {
    print('Handling sync metadata for peer $peerId: $metadata');
    final remoteMetadata = metadata['metadata'] as List<dynamic>;
    final localMetadata = await messageRepository.getMessageMetadata(peerId, metadata['sender_id']);
    final localIds = localMetadata.map((m) => m['message_id']).toSet();

    final missingIds = remoteMetadata
        .where((m) => !localIds.contains(m['message_id']))
        .map((m) => m['message_id'])
        .toList();

    if (missingIds.isNotEmpty && _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
        'type': 'request_messages',
        'sender_id': peerId,
        'recipient_id': metadata['sender_id'],
        'message_ids': missingIds,
      })));
      print('Requested missing messages: $missingIds');
    }
  }

  @override
  Future<void> sendMessage(api_message.Message message) async {
    print('Sending message from ${message.senderId} to ${message.recipientId}');
    final recipient = await userRepository.getUserById(message.recipientId, message.senderId);
    if (recipient == null) {
      throw Exception('Recipient not found');
    }

    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      print('Data channel not open, initiating connection');
      await _initiateConnection(message.senderId, message.recipientId);
      for (var i = 0; i < 30; i++) {
        if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
          break;
        }
        await Future.delayed(Duration(milliseconds: 500));
      }
      if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
        throw Exception('Failed to establish WebRTC connection: data channel not open');
      }
    }
    final metadata = message.toJson();

    if (message.type == api_message.MessageType.text || message.type == api_message.MessageType.json) {
      final encryptedContent = await encryptionService.encrypt(
        utf8.encode(message.textContent!),
        recipient.publicKey,
      );
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(metadata)));
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(encryptedContent)));
      print('Sent text message: ${message.textContent}');
    } else if (message.type == api_message.MessageType.file) {
      for (var attachment in message.attachments!) {
        final encryptedContent = await encryptionService.encrypt(
          attachment.content is String ? (await File(attachment.content).readAsBytes()) : attachment.content,
          recipient.publicKey,
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
        print('Sent file: ${attachment.fileName}');
      }
    }
  }

  Future<void> _initiateConnection(String senderId, String recipientId) async {
    int result = senderId.compareTo(recipientId);
    if (result < 0){
      _isInitiator = true;
    } 
    print('Initiating WebRTC connection from $senderId to $recipientId, isInitiator: $_isInitiator');
    if (_peerConnection == null || _dataChannel == null) {
      throw Exception('WebRTC not initialized');
    }
    _currentRecipientId = recipientId;
    if (!_isInitiator) {
      print('Waiting for offer as non-initiator');
      _offerTimeoutTimer?.cancel();
      _offerTimeoutTimer = Timer(Duration(seconds: 10), () async {
        print('Таймер сработал');
        print('No offer received, becoming initiator');
        _isInitiator = true;
        await _sendOffer(senderId, recipientId);
        print('_peerConnection!.signalingState = ${_peerConnection!.signalingState}, _dataChannel?.state = ${_dataChannel?.state}');
        if (_peerConnection!.signalingState == RTCSignalingState.RTCSignalingStateStable &&
            _dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {

        }
        print('_peerConnection!.signalingState = ${_peerConnection!.signalingState}, _dataChannel?.state = ${_dataChannel?.state}');
      });
      return;
    }
    await _sendOffer(senderId, recipientId);
  }

  Future<void> _sendOffer(String senderId, String recipientId) async {
    try {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      final token = await FlutterSecureStorage().read(key: 'jwt_token_$senderId');
      _socket!.emit('message', {
        'type': 'offer',
        'sdp': offer.sdp,
        'from': senderId,
        'to': recipientId,
        'token': token,
      });
      print('Sent offer from $senderId to $recipientId');
    } catch (e, stackTrace) {
      print('Error sending offer: $e\nStackTrace: $stackTrace');
      _reconnect();
    }
  }

  @override
  Stream<api_message.Message> onMessageReceived() => _messageStreamController.stream;

  @override
  Future<void> close() async {
    print('Closing WebRTCService for peer $_currentPeerId');
    _offerTimeoutTimer?.cancel();
    await _dataChannel?.close();
    await _peerConnection?.close();
    _socket?.disconnect();
    await _messageStreamController.close();
    _currentRecipientId = null;
    _isInitiator = false;
    _connectionAttempts = 0;
  }

  Future<String?> getDataChannelState() async {
    return _dataChannel?.state.toString();
  }
}
