import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

class EncryptionService implements IEncryptionService {
  @override
  Future<Map<String, String>> generateKeyPair() async {
    final random = FortunaRandom();
    final seed = Uint8List(32);
    final secureRandom = Random.secure();
    for (int i = 0; i < 32; i++) {
      seed[i] = secureRandom.nextInt(256);
    }
    random.seed(KeyParameter(seed));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64), random));

    final pair = keyGen.generateKeyPair();
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    return {
      'publicKey': base64Encode(_encodePublicKey(publicKey)),
      'privateKey': base64Encode(_encodePrivateKey(privateKey)),
    };
  }

  @override
  Future<Uint8List> encrypt(Uint8List data, String publicKey) async {
    final rsaPublicKey = _decodePublicKey(base64Decode(publicKey));

    // Если данные маленькие, шифруем RSA напрямую
    if (data.length <= 245) {
      final encryptor = RSAEngine()
        ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));
      return encryptor.process(data);
    } 
    // Иначе используем гибридное шифрование (AES-GCM + RSA)
    else {
      // Генерация AES-ключа и IV через FortunaRandom
      final aesKey = Uint8List(32);
      final iv = Uint8List(12);
      final secureRandom = FortunaRandom();
      secureRandom.seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => Random.secure().nextInt(256)))));
      secureRandom.nextBytes(aesKey as int);
      secureRandom.nextBytes(iv as int);

      // Шифрование данных AES-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
      final encryptedData = cipher.process(data);

      // Шифрование AES-ключа RSA
      final encryptor = RSAEngine()
        ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));
      final encryptedKey = encryptor.process(aesKey);

      // Объединяем: [зашифрованный ключ (256 байт)][IV (12 байт)][зашифрованные данные]
      return Uint8List.fromList([...encryptedKey, ...iv, ...encryptedData]);
    }
  }

  @override
  Future<Uint8List> decrypt(Uint8List data, String privateKey) async {
    final rsaPrivateKey = _decodePrivateKey(base64Decode(privateKey));

    // Если данные маленькие, расшифровываем RSA
    if (data.length <= 256) {
      final decryptor = RSAEngine()
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(rsaPrivateKey));
      return decryptor.process(data);
    } 
    // Иначе расшифровываем гибридный режим
    else {
      if (data.length < 256 + 12) {
        throw ArgumentError('Invalid encrypted data format');
      }

      final encryptedKey = data.sublist(0, 256);
      final iv = data.sublist(256, 256 + 12);
      final encryptedData = data.sublist(256 + 12);

      // Расшифровка AES-ключа
      final decryptor = RSAEngine()
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(rsaPrivateKey));
      final aesKey = decryptor.process(encryptedKey);

      // Расшифровка данных AES-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
      return cipher.process(encryptedData);
    }
  }

  // Кодирование публичного ключа: modulus:exponent
  Uint8List _encodePublicKey(RSAPublicKey publicKey) {
    return Uint8List.fromList(
      utf8.encode('${publicKey.modulus}:${publicKey.exponent}'),
    );
  }

  // Кодирование приватного ключа: modulus:privateExponent:p:q
  Uint8List _encodePrivateKey(RSAPrivateKey privateKey) {
    return Uint8List.fromList(
      utf8.encode('${privateKey.modulus}:${privateKey.privateExponent}:${privateKey.p}:${privateKey.q}'),
    );
  }

  RSAPublicKey _decodePublicKey(Uint8List encoded) {
    final parts = utf8.decode(encoded).split(':');
    if (parts.length != 2) throw FormatException('Invalid public key format');
    return RSAPublicKey(BigInt.parse(parts[0]), BigInt.parse(parts[1]));
  }

  RSAPrivateKey _decodePrivateKey(Uint8List encoded) {
    final parts = utf8.decode(encoded).split(':');
    if (parts.length != 4) throw FormatException('Invalid private key format');
    return RSAPrivateKey(
      BigInt.parse(parts[0]),  // modulus
      BigInt.parse(parts[1]),  // privateExponent
      BigInt.parse(parts[2]),  // p
      BigInt.parse(parts[3]),  // q
    );
  }
}