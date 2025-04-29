import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:p2p_messenger/api/api.dart';
import 'package:p2p_messenger/api/classes/auth_service.dart';
import 'package:p2p_messenger/api/classes/encryption_service.dart';
import 'package:p2p_messenger/api/classes/file_storage.dart';
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
  @override
  _MessengerPageState createState() => _MessengerPageState();
}

class _MessengerPageState extends State<MessengerPage> {
  final _messengerApi = MessengerAPI(
    userRepository: UserRepository(url_server, EncryptionService()),
    messageRepository: MessageRepository(),
    fileStorage: FileStorage(),
    webRTCService: WebRTCService(UserRepository(url_server, EncryptionService()), MessageRepository(), EncryptionService()),
    authService: AuthService(url_server),
  );
  final List<String> _messages = [];
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

  void _addMessage(String message, {VoidCallback? onSelectRecipient, String? foundUserId}) {
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
        _messages.add('Select as Recipient?');
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
    setState(() { _isConnecting = true; });
    try {
      if (!_identifierController.text.matches(r'^[a-z0-9_]+$')) {
        _addMessage('Invalid identifier: use only lowercase letters, numbers, and underscores');
        return;
      }
      final keyPair = await _messengerApi.webRTCService.encryptionService.generateKeyPair();
      final user = await _messengerApi.registerUser(
        _usernameController.text,
        _emailController.text,
        _passwordController.text,
        keyPair['publicKey']!,
        _identifierController.text,
      );
      await FlutterSecureStorage().write(key: 'private_key_${user.userId}', value: keyPair['privateKey']);
      final privateKey = await FlutterSecureStorage().read(key: 'private_key_${user.userId}');
      print('Stored private key for user ${user.userId}: $privateKey');
      setState(() {
        _currentIdentifier = _identifierController.text;
        _userId = user.userId;
      });
      _addMessage('Registered as ${user.username}, Identifier: ${user.identifier}, User ID: ${user.userId}');
    } catch (e, stackTrace) {
      print('Registration error: $e\nStackTrace: $stackTrace');
      _addMessage('Registration error: $e');
    } finally {
      setState(() { _isConnecting = false; });
    }
  }

  Future<void> _startMessenger() async {
    if (_isConnecting) return;
    setState(() { _isConnecting = true; });
    try {
      final user = await _messengerApi.loginUser(_emailController.text, _passwordController.text);
      final privateKey = await FlutterSecureStorage().read(key: 'private_key_${user.userId}');
      print('Loaded private key for user ${user.userId}: $privateKey');
      setState(() {
        _userId = user.userId;
        _currentIdentifier = user.identifier;
      });
      _addMessage('Logged in as ${user.username}, User ID: ${user.userId}, Identifier: ${user.identifier}');

      await _messengerApi.initializeConnection(user.userId, url_server);
      _addMessage('WebRTC initialized');

      _messengerApi.listenForMessages(user.userId).listen((msg) {
        print('Received message in UI for user $_userId: ${msg.toJson()}');
        if (msg.type == MessageType.text) {
          _addMessage('Received text: ${msg.textContent} from ${msg.senderId}');
        } else if (msg.type == MessageType.file) {
          _addMessage('Received files: ${msg.attachments!.map((a) => a.fileName).join(', ')} from ${msg.senderId}');
        }
      }, onError: (e, stackTrace) {
        print('Error in listenForMessages: $e\nStackTrace: $stackTrace');
        _addMessage('Error receiving message: $e');
      });
    } catch (e, stackTrace) {
      print('Login error details: $e\nStackTrace: $stackTrace');
      _addMessage('Error: $e');
    } finally {
      setState(() { _isConnecting = false; });
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
        final user = await _messengerApi.userRepository.getUserById(_userId!, _userId!);
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
          _addMessage('User ID updated to $newId');
        }
      } catch (e, stackTrace) {
        print('Update user ID error: $e\nStackTrace: $stackTrace');
        _addMessage('Error updating User ID: $e');
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_recipientId == null) {
      _addMessage('Error: Please select a recipient');
      return;
    }
    if (_userId == null) {
      _addMessage('Error: Please login first');
      return;
    }
    try {
      if (_textController.text.isNotEmpty) {
        final message = Message(
          messageId: Uuid().v4(),
          senderId: _userId!,
          recipientId: _recipientId!,
          type: MessageType.text,
          textContent: _textController.text,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        );
        print('Sending message from $_userId to $_recipientId: ${message.textContent}');
        await _messengerApi.sendMessage(_userId!, _recipientId!, message);
        _addMessage('Sent text: ${_textController.text} to $_recipientName (ID: $_recipientId)');
        _textController.clear();
      }
    } catch (e, stackTrace) {
      print('Send message error: $e\nStackTrace: $stackTrace');
      _addMessage('Error sending message: $e');
      if (e.toString().contains('Recipient is offline')) {
        _addMessage('Recipient is offline, message saved locally');
      } else if (e.toString().contains('Failed to establish WebRTC connection')) {
        _addMessage('Failed to connect to recipient, please try again');
      }
    }
  }

  Future<void> _attachFiles() async {
    if (_recipientId == null) {
      _addMessage('Error: Please select a recipient');
      return;
    }
    if (_userId == null) {
      _addMessage('Error: Please login first');
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
          type: MessageType.file,
          attachments: attachments,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        );
        print('Sending files from $_userId to $_recipientId: ${attachments.map((a) => a.fileName).join(', ')}');
        await _messengerApi.sendMessage(_userId!, _recipientId!, message);
        _addMessage('Sent files: ${attachments.map((a) => a.fileName).join(', ')} to $_recipientName (ID: $_recipientId)');
      }
    } catch (e, stackTrace) {
      print('Attach files error: $e\nStackTrace: $stackTrace');
      _addMessage('Error sending files: $e');
      if (e.toString().contains('Recipient is offline')) {
        _addMessage('Recipient is offline, files saved locally');
      } else if (e.toString().contains('Failed to establish WebRTC connection')) {
        _addMessage('Failed to connect to recipient, please try again');
      }
    }
  }

  Future<void> _retryConnection() async {
    if (_userId == null || _recipientId == null) {
      _addMessage('Error: Please login and select a recipient');
      return;
    }
    try {
      await _messengerApi.syncWithUser(_userId!, _recipientId!);
      _addMessage('Retried connection to $_recipientName');
    } catch (e, stackTrace) {
      print('Retry connection error: $e\nStackTrace: $stackTrace');
      _addMessage('Error retrying connection: $e');
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
              Text('Current Identifier: ${_currentIdentifier ?? "Not logged in"}'),
              Text('Current Recipient: ${_recipientName ?? "None selected"} (ID: ${_recipientId ?? "None"})'),
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
                        _addMessage('Error: Please login first');
                        return;
                      }
                      final user = await _messengerApi.userRepository.getUserByIdentifier(value, _userId!);
                      if (user != null) {
                        _addMessage(
                          'Found user: ${user.username} (${user.identifier}, ID: ${user.userId})',
                          onSelectRecipient: () {
                            setState(() {
                              _recipientId = user.userId;
                              _recipientName = user.username;
                            });
                            _addMessage('Selected recipient: ${user.username} (ID: ${user.userId})');
                          },
                          foundUserId: user.userId,
                        );
                      } else {
                        _addMessage('User with identifier $value not found');
                      }
                    } catch (e, stackTrace) {
                      print('Search user error: $e\nStackTrace: $stackTrace');
                      _addMessage('Error searching user: $e');
                    }
                  } else {
                    _addMessage('Invalid identifier: use only lowercase letters, numbers, and underscores');
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
                child: Text(_isConnecting ? 'Connecting...' : 'Login & Start Messenger'),
              ),
              ElevatedButton(
                onPressed: _isConnecting ? null : _retryConnection,
                child: Text('Retry Connection'),
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
                    if (_messages[index].startsWith('Select as Recipient?') && index > 0) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: ElevatedButton(
                          onPressed: () {
                            final prevMessage = _messages[index - 1];
                            final userIdMatch = RegExp(r'ID: ([^\)]+)').firstMatch(prevMessage);
                            if (userIdMatch != null) {
                              setState(() {
                                _recipientId = userIdMatch.group(1);
                                _recipientName = prevMessage.split('Found user: ')[1].split(' (')[0];
                              });
                              _addMessage('Selected recipient ID: $_recipientId');
                            }
                          },
                          child: Text('Select as Recipient'),
                        ),
                      );
                    }
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(_messages[index], style: TextStyle(fontSize: 14)),
                    );
                  },
                ),
              ),
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
