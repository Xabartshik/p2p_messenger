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
    final encryptor = RSAEngine()
      ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));

    final keySize = rsaPublicKey.modulus!.bitLength ~/ 8;

    // If data is small enough, encrypt directly with RSA
    if (data.length <= keySize - 42) {
      //  padding overhead
      return encryptor.process(data);
    }
    // Otherwise, use hybrid encryption (AES-GCM + RSA)
    else {
      // Generate AES key and IV using FortunaRandom
      final aesKey = Uint8List(32);
      final iv = Uint8List(12);
      final secureRandom = FortunaRandom();
      secureRandom.seed(KeyParameter(Uint8List.fromList(
          List.generate(32, (i) => Random.secure().nextInt(256)))));
      secureRandom.nextBytes(aesKey.length); // Исправлено
      for (int i = 0; i < aesKey.length; i++) {
        aesKey[i] = secureRandom.nextUint8();
      }
      secureRandom.nextBytes(iv.length); // Исправлено
      for (int i = 0; i < iv.length; i++) {
        iv[i] = secureRandom.nextUint8();
      }

      // Encrypt data using AES-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
            true, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
      final encryptedData = cipher.process(data);

      // Encrypt AES key with RSA
      final encryptedKey = encryptor.process(aesKey);

      // Combine: [encrypted key][IV][encrypted data]
      return Uint8List.fromList([...encryptedKey, ...iv, ...encryptedData]);
    }
  }

  @override
  Future<Uint8List> decrypt(Uint8List data, String privateKey) async {
    final rsaPrivateKey = _decodePrivateKey(base64Decode(privateKey));
    final decryptor = RSAEngine()
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(rsaPrivateKey));

    final keySize = rsaPrivateKey.modulus!.bitLength ~/ 8;

    // If data is small enough, decrypt directly with RSA
    if (data.length <= keySize) {
      return decryptor.process(data);
    }
    // Otherwise, decrypt hybrid mode
    else {
      final encryptedKeyLength = keySize;
      if (data.length < encryptedKeyLength + 12) {
        throw ArgumentError('Invalid encrypted data format');
      }

      final encryptedKey = data.sublist(0, encryptedKeyLength);
      final iv = data.sublist(encryptedKeyLength, encryptedKeyLength + 12);
      final encryptedData = data.sublist(encryptedKeyLength + 12);

      // Decrypt AES key
      final aesKey = decryptor.process(encryptedKey);

      // Decrypt data using AES-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
            false, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));
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
      utf8.encode(
          '${privateKey.modulus}:${privateKey.privateExponent}:${privateKey.p}:${privateKey.q}'),
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
      BigInt.parse(parts[0]), // modulus
      BigInt.parse(parts[1]), // privateExponent
      BigInt.parse(parts[2]), // p
      BigInt.parse(parts[3]), // q
    );
  }
}
