import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:p2p_messenger/api/api.dart';
import 'package:p2p_messenger/api/classes/auth_service.dart';
import 'package:p2p_messenger/api/classes/encryption_service.dart';
import 'package:p2p_messenger/api/classes/message_repository.dart';
import 'package:p2p_messenger/api/classes/user_repository.dart';
import 'package:p2p_messenger/api/classes/web_rtc_service.dart';
import 'package:p2p_messenger/api/models/message.dart';
import 'package:p2p_messenger/api/models/user.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

const String url_server = 'https://mc9nlj2g-5000.euw.devtunnels.ms/';

extension StringExtension on String {
  bool matches(Pattern pattern) => RegExp(pattern as String).hasMatch(this);
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Messenger',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MessengerPage(),
    );
  }
}

class MessengerPage extends StatefulWidget {
  const MessengerPage({super.key});

  @override
  _MessengerPageState createState() => _MessengerPageState();
}

class _MessengerPageState extends State<MessengerPage> {
  final _messengerApi = MessengerAPI(
    serverUrl: url_server,
    userRepository: UserRepository(url_server, EncryptionService()),
    messageRepository: MessageRepository(),
    webRTCService: WebRTCService(
        UserRepository(url_server, EncryptionService()),
        MessageRepository(),
        EncryptionService()),
    authService: AuthService(url_server),
  );
  final List<Message> _messages = [];
  final _scrollController = ScrollController();
  bool _isConnecting = false;
  final _textController = TextEditingController();
  final _emailController = TextEditingController(text: '1@example.com');
  final _passwordController = TextEditingController(text: '1');
  final _usernameController = TextEditingController(text: '1');
  final _identifierController = TextEditingController(text: '1');
  String? _userId;
  String? _currentIdentifier;
  String? _recipientId;
  String? _recipientName;
  File? _viewingFile;

  void _addMessage(Message message,
      {VoidCallback? onSelectRecipient, String? foundUserId}) {
    setState(() {
      _messages.add(message);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    if (onSelectRecipient != null && foundUserId != null) {
      setState(() {
        _messages.add(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Select as Recipient?',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _registerUser() async {
    setState(() => _isConnecting = true);
    try {
      if (!_identifierController.text.matches(r'^[a-z0-9_]+$')) {
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent:
              'Invalid identifier: use only lowercase letters, numbers, and underscores',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
        return;
      }
      final user = await _messengerApi.registerUser(
        _usernameController.text,
        _emailController.text,
        _passwordController.text,
        _identifierController.text,
      );
      setState(() {
        _currentIdentifier = user.identifier;
        _userId = user.userId;
      });
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent:
            'Registered as ${user.username}, Identifier: ${user.identifier}, User ID: ${user.userId}',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));

      // Подписка на сообщения
      _messengerApi.listenForMessages(user.userId).listen((msg) {
        print('Received message in UI for user $_userId: ${msg.toJson()}');
        _addMessage(msg);
      }, onError: (e, stackTrace) {
        print('Error in listenForMessages: $e\nStackTrace: $stackTrace');
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Error receiving message: $e',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      });
    } catch (e, stackTrace) {
      print('Registration error: $e\nStackTrace: $stackTrace');
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Registration error: $e',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _startMessenger() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);
    try {
      final user = await _messengerApi.loginUser(
          _emailController.text, _passwordController.text);
      setState(() {
        _userId = user.userId;
        _currentIdentifier = user.identifier;
      });
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent:
            'Logged in as ${user.username}, User ID: ${user.userId}, Identifier: ${user.identifier}',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));

      // Подписка на сообщения
      _messengerApi.listenForMessages(user.userId).listen((msg) {
        print('Received message in UI for user $_userId: ${msg.toJson()}');
        _addMessage(msg);
      }, onError: (e, stackTrace) {
        print('Error in listenForMessages: $e\nStackTrace: $stackTrace');
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Error receiving message: $e',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      });
    } catch (e, stackTrace) {
      print('Login error details: $e\nStackTrace: $stackTrace');
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error: $e',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _updateUserId() async {
    final newId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change User ID'),
        content: TextField(
          controller: TextEditingController(text: _userId),
          onChanged: (value) => _userId = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _userId),
            child: Text('Save'),
          ),
        ],
      ),
    );
    if (newId != null && newId.isNotEmpty) {
      try {
        final user =
            await _messengerApi.userRepository.getUserById(_userId!, _userId!);
        if (user != null) {
          await _messengerApi.userRepository.updateUser(
            User(
              userId: newId,
              username: user.username,
              email: user.email,
              status: user.status,
              publicKey: user.publicKey,
              identifier: user.identifier,
            ),
          );
          setState(() {
            _userId = newId;
          });
          _addMessage(Message(
            messageId: Uuid().v4(),
            senderId: '',
            recipientId: '',
            senderIdentifier: '',
            senderUsername: '',
            type: MessageType.text,
            textContent: 'User ID updated to $newId',
            timestamp: DateTime.now(),
            status: MessageStatus.sent,
          ));
        }
      } catch (e, stackTrace) {
        print('Update user ID error: $e\nStackTrace: $stackTrace');
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Error updating User ID: $e',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_recipientId == null) {
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error: Please select a recipient',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      return;
    }
    if (_userId == null) {
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error: Please login first',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      return;
    }
    try {
      if (_textController.text.isNotEmpty) {
        final message = Message(
          messageId: Uuid().v4(),
          senderId: _userId!,
          recipientId: _recipientId!,
          senderIdentifier: _messengerApi.currentUser!.identifier,
          senderUsername: _messengerApi.currentUser!.username,
          type: MessageType.text,
          textContent: _textController.text,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        );
        print(
            'Sending message from $_userId to $_recipientId: ${message.textContent}');
        await _messengerApi.sendMessage(_userId!, _recipientId!, message);
        _addMessage(message);
        _textController.clear();
      }
    } catch (e, stackTrace) {
      print('Send message error: $e\nStackTrace: $stackTrace');
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error sending message: $e',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      if (e.toString().contains('Recipient is offline')) {
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Recipient is offline, message saved locally',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      } else if (e
          .toString()
          .contains('Failed to establish WebRTC connection')) {
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Failed to connect to recipient, please try again',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      }
    }
  }

  Future<void> _attachFiles() async {
    if (_recipientId == null) {
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error: Please select a recipient',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      return;
    }
    if (_userId == null) {
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error: Please login first',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null) {
        final attachments = await Future.wait(result.files.map((file) async {
          final bytes = await File(file.path!).readAsBytes();
          return FileAttachment(
            fileId: Uuid().v4(),
            fileName: file.name,
            fileType: file.extension ?? 'document',
            content: bytes,
            size: bytes.length,
          );
        }));

        final message = Message(
          messageId: Uuid().v4(),
          senderId: _userId!,
          recipientId: _recipientId!,
          senderIdentifier: _messengerApi.currentUser!.identifier,
          senderUsername: _messengerApi.currentUser!.username,
          type: MessageType.file,
          attachments: attachments,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        );
        print(
            'Sending files from $_userId to $_recipientId: ${attachments.map((a) => a.fileName).join(', ')}');
        await _messengerApi.sendMessage(_userId!, _recipientId!, message);
        _addMessage(message);
      }
    } catch (e, stackTrace) {
      print('Attach files error: $e\nStackTrace: $stackTrace');
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error sending files: $e',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      if (e.toString().contains('Recipient is offline')) {
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Recipient is offline, files saved locally',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      } else if (e
          .toString()
          .contains('Failed to establish WebRTC connection')) {
        _addMessage(Message(
          messageId: Uuid().v4(),
          senderId: '',
          recipientId: '',
          senderIdentifier: '',
          senderUsername: '',
          type: MessageType.text,
          textContent: 'Failed to connect to recipient, please try again',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        ));
      }
    }
  }

  Future<void> _retryConnection() async {
    if (_userId == null || _recipientId == null) {
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error: Please login and select a recipient',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      return;
    }
    try {
      await _messengerApi.syncWithUser(_userId!, _recipientId!);
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Retried connection to $_recipientName',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
    } catch (e, stackTrace) {
      print('Retry connection error: $e\nStackTrace: $stackTrace');
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error retrying connection: $e',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
    }
  }

  Future<void> _clearMessages() async {
    setState(() {
      _messages.clear();
    });
    _addMessage(Message(
      messageId: Uuid().v4(),
      senderId: '',
      recipientId: '',
      senderIdentifier: '',
      senderUsername: '',
      type: MessageType.text,
      textContent: 'Messages cleared',
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    ));
  }

  Future<void> _loadMessages() async {
    if (_userId == null || _recipientId == null) {
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error: Please login and select a recipient',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      return;
    }
    try {
      final messages =
          await _messengerApi.getChatHistory(_userId!, _recipientId!);
      setState(() {
        _messages.addAll(messages);
      });
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Loaded ${messages.length} messages',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e, stackTrace) {
      print('Load messages error: $e\nStackTrace: $stackTrace');
      _addMessage(Message(
        messageId: Uuid().v4(),
        senderId: '',
        recipientId: '',
        senderIdentifier: '',
        senderUsername: '',
        type: MessageType.text,
        textContent: 'Error loading messages: $e',
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('WebRTC Messenger')),
      body: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('User ID: ${_userId ?? "Not logged in"}'),
              ElevatedButton(
                onPressed: _isConnecting ? null : _updateUserId,
                child: Text('Change User ID'),
              ),
              Text(
                  'Current Identifier: ${_currentIdentifier ?? "Not logged in"}'),
              Text(
                  'Current Recipient: ${_recipientName ?? "None selected"} (ID: ${_recipientId ?? "None"})'),
              TextField(
                controller: TextEditingController(),
                decoration: InputDecoration(
                  labelText: 'Search by Identifier',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) async {
                  if (value.matches(r'^[a-z0-9_]+$')) {
                    try {
                      if (_userId == null) {
                        _addMessage(Message(
                          messageId: Uuid().v4(),
                          senderId: '',
                          recipientId: '',
                          senderIdentifier: '',
                          senderUsername: '',
                          type: MessageType.text,
                          textContent: 'Error: Please login first',
                          timestamp: DateTime.now(),
                          status: MessageStatus.sent,
                        ));
                        return;
                      }
                      final user = await _messengerApi.userRepository
                          .getUserByIdentifier(value, _userId!);
                      if (user != null) {
                        _addMessage(
                          Message(
                            messageId: Uuid().v4(),
                            senderId: '',
                            recipientId: '',
                            senderUsername: '',
                            senderIdentifier: '',
                            type: MessageType.text,
                            textContent:
                                'Found user: ${user.username} (${user.identifier}, ID: ${user.userId})',
                            timestamp: DateTime.now(),
                            status: MessageStatus.sent,
                          ),
                          onSelectRecipient: () {
                            setState(() {
                              _recipientId = user.userId;
                              _recipientName = user.username;
                            });
                            _addMessage(Message(
                              messageId: Uuid().v4(),
                              senderId: '',
                              recipientId: '',
                              senderIdentifier: '',
                              senderUsername: '',
                              type: MessageType.text,
                              textContent:
                                  'Selected recipient: ${user.username} (ID: ${user.userId})',
                              timestamp: DateTime.now(),
                              status: MessageStatus.sent,
                            ));
                          },
                          foundUserId: user.userId,
                        );
                      } else {
                        _addMessage(Message(
                          messageId: Uuid().v4(),
                          senderId: '',
                          recipientId: '',
                          senderIdentifier: '',
                          senderUsername: '',
                          type: MessageType.text,
                          textContent: 'User with identifier $value not found',
                          timestamp: DateTime.now(),
                          status: MessageStatus.sent,
                        ));
                      }
                    } catch (e, stackTrace) {
                      print('Search user error: $e\nStackTrace: $stackTrace');
                      _addMessage(Message(
                        messageId: Uuid().v4(),
                        senderId: '',
                        recipientId: '',
                        senderIdentifier: '',
                        senderUsername: '',
                        type: MessageType.text,
                        textContent: 'Error searching user: $e',
                        timestamp: DateTime.now(),
                        status: MessageStatus.sent,
                      ));
                    }
                  } else {
                    _addMessage(Message(
                      messageId: Uuid().v4(),
                      senderId: '',
                      recipientId: '',
                      senderIdentifier: '',
                      senderUsername: '',
                      type: MessageType.text,
                      textContent:
                          'Invalid identifier: use only lowercase letters, numbers, and underscores',
                      timestamp: DateTime.now(),
                      status: MessageStatus.sent,
                    ));
                  }
                },
              ),
              SizedBox(height: 16),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Display Name'),
              ),
              TextField(
                controller: _identifierController,
                decoration: InputDecoration(labelText: 'Identifier'),
              ),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isConnecting ? null : _registerUser,
                child: Text(_isConnecting ? 'Registering...' : 'Register'),
              ),
              ElevatedButton(
                onPressed: _isConnecting ? null : _startMessenger,
                child: Text(_isConnecting
                    ? 'Connecting...'
                    : 'Login & Start Messenger'),
              ),
              ElevatedButton(
                onPressed: _isConnecting ? null : _retryConnection,
                child: Text('Retry Connection'),
              ),
              ElevatedButton(
                onPressed: _isConnecting ? null : _loadMessages,
                child: Text('Load Messages'),
              ),
              ElevatedButton(
                onPressed: _isConnecting ? null : _clearMessages,
                child: Text('Clear Messages'),
              ),
              SizedBox(height: 16),
              Container(
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    if (message.textContent == 'Select as Recipient?' &&
                        index > 0) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: ElevatedButton(
                          onPressed: () {
                            final prevMessage = _messages[index - 1];
                            final userIdMatch = RegExp(r'ID: ([^\)]+)')
                                .firstMatch(prevMessage.textContent ?? '');
                            if (userIdMatch != null) {
                              setState(() {
                                _recipientId = userIdMatch.group(1);
                                _recipientName = prevMessage.textContent!
                                    .split('Found user: ')[1]
                                    .split(' (')[0];
                              });
                              _addMessage(Message(
                                messageId: Uuid().v4(),
                                senderId: '',
                                recipientId: '',
                                senderIdentifier: '',
                                senderUsername: '',
                                type: MessageType.text,
                                textContent:
                                    'Selected recipient ID: $_recipientId',
                                timestamp: DateTime.now(),
                                status: MessageStatus.sent,
                              ));
                            }
                          },
                          child: Text('Select as Recipient'),
                        ),
                      );
                    }
                    if (message.type == MessageType.text) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          message.textContent ?? '',
                          style: TextStyle(fontSize: 14),
                        ),
                      );
                    } else if (message.type == MessageType.file &&
                        message.attachments != null) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: message.attachments!.map((attachment) {
                            final file = File(attachment.content as String);
                            final isImage =
                                attachment.fileType.startsWith('image');
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'File: ${attachment.fileName} (${attachment.fileType})',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _viewingFile =
                                          file.existsSync() ? file : null;
                                    });
                                  },
                                  child: Text(
                                      isImage ? 'View Image' : 'Download File'),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      );
                    }
                    return SizedBox.shrink();
                  },
                ),
              ),
              if (_viewingFile != null && _viewingFile!.existsSync()) ...[
                SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: Image.file(
                    _viewingFile!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Text('Error loading image: $error'),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _viewingFile = null;
                    });
                  },
                  child: Text('Close Image'),
                ),
              ],
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Enter message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.attach_file),
                    onPressed: _attachFiles,
                  ),
                  IconButton(
                    icon: Icon(Icons.send),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _identifierController.dispose();
    _scrollController.dispose();
    _userId = null;
    _currentIdentifier = null;
    _recipientId = null;
    _recipientName = null;
    super.dispose();
  }
}
