import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Основная функция приложения
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Игнорирование HTTPS-сертификатов для локальных тестов
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

// Класс для обхода проверки HTTPS-сертификатов
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

// Главный виджет приложения
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC P2P Test',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WebRTCPage(),
    );
  }
}

// Виджет страницы с интерфейсом
class WebRTCPage extends StatefulWidget {
  const WebRTCPage({super.key});

  @override
  _WebRTCPageState createState() => _WebRTCPageState();
}

class _WebRTCPageState extends State<WebRTCPage> {
  // Список для хранения сообщений статуса
  final List<String> _statusMessages = [];
  // Флаг для отслеживания состояния подключения
  bool _isConnecting = false;
  // Контроллер для прокрутки списка сообщений
  final ScrollController _scrollController = ScrollController();
  // WebSocket-соединение
  IO.Socket? _socket;

  @override
  void initState() {
    super.initState();
    // Запрос разрешений при инициализации
    _requestPermissions();
  }

  // Функция для добавления сообщения в список и консоль
  void _addStatusMessage(String message) {
    setState(() {
      _statusMessages.add(message);
    });
    print(message);
    // Автоматическая прокрутка к последнему сообщению
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Функция для запроса разрешений
  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.storage,
        Permission.manageExternalStorage, // Для Android
      ].request();
      _addStatusMessage("Разрешения запрошены успешно");
    } catch (e) {
      _addStatusMessage("Ошибка при запросе разрешений: $e");
    }
  }

  // Функция для запуска теста WebRTC
  Future<void> _startP2PTest() async {
    if (_isConnecting) {
      _addStatusMessage("Подключение уже выполняется");
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      _addStatusMessage("Создание тестового файла...");
      // Создание тестового файла
      final tempDir = await getTemporaryDirectory();
      final testFile = File('${tempDir.path}/test.txt');
      await testFile.writeAsString("Привет, это тестовое сообщение!");
      _addStatusMessage("Тестовый файл создан: ${testFile.path}");

      // Установка идентификатора устройства
      const peerId = "deviceA"; // Измените на "deviceB" на втором телефоне
      const serverUrl = "http://192.168.0.101:5000"; // URL сервера для SocketIO
      _addStatusMessage("Инициализация WebRTC для $peerId...");
      // Инициализация WebRTC
      await _initWebRTC(peerId, serverUrl, testFile);
    } catch (e) {
      _addStatusMessage("Ошибка в _startP2PTest: $e");
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  // Функция для настройки WebRTC
  Future<void> _initWebRTC(String peerId, String serverUrl, File file) async {
    try {
      // Конфигурация RTCPeerConnection
      final configuration = {
        'iceServers': [], // Пустой для локальной сети
        'sdpSemantics': 'unified-plan'
      };
      final peerConnection = await createPeerConnection(configuration);
      _addStatusMessage("RTCPeerConnection создан");

      // Создание DataChannel
      final dataChannelInit = RTCDataChannelInit()..binaryType = 'binary';
      final dataChannel = await peerConnection.createDataChannel('file-transfer', dataChannelInit);
      _addStatusMessage("DataChannel создан");

      // Обработка сообщений DataChannel
      dataChannel.onMessage = (RTCDataChannelMessage message) {
        try {
          if (message.isBinary) {
            _addStatusMessage("Получено через WebRTC: ${utf8.decode(message.binary)}");
          } else {
            _addStatusMessage("Получено через WebRTC: ${message.text}");
          }
        } catch (e) {
          _addStatusMessage("Ошибка в обработке сообщения DataChannel: $e");
        }
      };
      dataChannel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          _addStatusMessage("DataChannel открыт");
        }
      };

      // Подключение к SocketIO
      try {
        _socket = IO.io(serverUrl, <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
        });
        _addStatusMessage("Инициализация SocketIO: $serverUrl");

        // Обработка событий SocketIO
        _socket!.onConnect((_) {
          _addStatusMessage("Подключено к SocketIO");
          // Регистрация устройства
          _socket!.emit('message', {
            'type': 'register',
            'id': peerId
          });
          _addStatusMessage("Устройство зарегистрировано: $peerId");
        });

        _socket!.onConnectError((error) {
          _addStatusMessage("Ошибка подключения SocketIO: $error");
        });

        _socket!.onError((error) {
          _addStatusMessage("Ошибка SocketIO: $error");
        });

        _socket!.onDisconnect((_) {
          _addStatusMessage("SocketIO отключён");
        });

        // Обработка сообщений от сервера
        _socket!.on('message', (data) async {
          try {
            _addStatusMessage("Получено от сервера: $data");
            if (data['type'] == 'offer') {
              await peerConnection.setRemoteDescription(
                RTCSessionDescription(data['sdp'], data['type']),
              );
              final answer = await peerConnection.createAnswer();
              await peerConnection.setLocalDescription(answer);
              _socket!.emit('message', {
                'type': 'answer',
                'sdp': answer.sdp,
                'from': peerId,
                'to': data['from']
              });
              _addStatusMessage("Отправлен SDP-answer");
            } else if (data['type'] == 'answer') {
              await peerConnection.setRemoteDescription(
                RTCSessionDescription(data['sdp'], data['type']),
              );
              _addStatusMessage("SDP-answer установлен");
            } else if (data['type'] == 'candidate') {
              await peerConnection.addCandidate(
                RTCIceCandidate(
                  data['candidate'],
                  data['sdpMid'],
                  data['sdpMLineIndex'],
                ),
              );
              _addStatusMessage("ICE-кандидат добавлен");
            }
          } catch (e) {
            _addStatusMessage("Ошибка обработки сообщения сервера: $e");
          }
        });

        // Подключение к серверу
        _socket!.connect();
      } catch (e) {
        _addStatusMessage("Ошибка инициализации SocketIO: $e");
        return;
      }

      // Обработка ICE-кандидатов
      peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
        try {
          _socket!.emit('message', {
            'type': 'candidate',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'from': peerId,
            'to': peerId == "deviceA" ? "deviceB" : "deviceA"
          });
          _addStatusMessage("Отправлен ICE-кандидат");
        } catch (e) {
          _addStatusMessage("Ошибка отправки ICE-кандидата: $e");
        }
      };

      // Обработка входящего DataChannel
      peerConnection.onDataChannel = (RTCDataChannel channel) {
        channel.onMessage = (RTCDataChannelMessage message) {
          try {
            if (message.isBinary) {
              _addStatusMessage("Получено через WebRTC: ${utf8.decode(message.binary)}");
            } else {
              _addStatusMessage("Получено через WebRTC: ${message.text}");
            }
          } catch (e) {
            _addStatusMessage("Ошибка обработки входящего DataChannel: $e");
          }
        };
        channel.onDataChannelState = (state) {
          if (state == RTCDataChannelState.RTCDataChannelOpen) {
            _addStatusMessage("DataChannel открыт (от удалённого устройства)");
            if (peerId == "deviceB") {
              file.readAsBytes().then((bytes) {
                channel.send(RTCDataChannelMessage.fromBinary(bytes));
                _addStatusMessage("Файл отправлен через WebRTC (ответчик)");
              }).catchError((e) {
                _addStatusMessage("Ошибка отправки файла (deviceB): $e");
              });
            }
          }
        };
      };

      // Инициирование соединения для deviceA
      if (peerId == "deviceA") {
        try {
          await Future.delayed(const Duration(seconds: 2));
          final offer = await peerConnection.createOffer();
          await peerConnection.setLocalDescription(offer);
          _socket!.emit('message', {
            'type': 'offer',
            'sdp': offer.sdp,
            'from': peerId,
            'to': "deviceB"
          });
          _addStatusMessage("Отправлен SDP-offer");

          dataChannel.onDataChannelState = (state) async {
            if (state == RTCDataChannelState.RTCDataChannelOpen) {
              try {
                final bytes = await file.readAsBytes();
                await dataChannel.send(RTCDataChannelMessage.fromBinary(bytes));
                _addStatusMessage("Файл отправлен через WebRTC (инициатор)");
              } catch (e) {
                _addStatusMessage("Ошибка отправки файла (deviceA): $e");
              }
            }
          };
        } catch (e) {
          _addStatusMessage("Ошибка инициации соединения (deviceA): $e");
        }
      }

      // Ожидание для теста
      await Future.delayed(const Duration(seconds: 10));
      // Закрытие соединений
      try {
        await peerConnection.close();
        _socket?.disconnect();
        _addStatusMessage("Соединения закрыты");
      } catch (e) {
        _addStatusMessage("Ошибка закрытия соединений: $e");
      }
    } catch (e) {
      _addStatusMessage("Ошибка в _initWebRTC: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebRTC P2P Test')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _isConnecting ? null : _startP2PTest,
              child: Text(_isConnecting ? 'Подключение...' : 'Подключиться'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _statusMessages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _statusMessages[index],
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _scrollController.dispose();
    super.dispose();
  }
}