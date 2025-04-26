import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
  Future<List<int>> encrypt(List<int> data, String publicKey) async {
    if (data.length <= 245) {
      final rsaPublicKey = _decodePublicKey(base64Decode(publicKey));
      final encryptor = RSAEngine()
        ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));
      return encryptor.process(Uint8List.fromList(data));
    } else {
      final aesKey = Uint8List(32)
        ..setAll(0, List.generate(32, (i) => Random.secure().nextInt(256)));
      final iv = Uint8List(12)
        ..setAll(0, List.generate(12, (i) => Random.secure().nextInt(256)));

      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)));

      final encryptedData = cipher.process(Uint8List.fromList(data));

      final rsaPublicKey = _decodePublicKey(base64Decode(publicKey));
      final encryptor = RSAEngine()
        ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));
      final encryptedKey = encryptor.process(aesKey);

      return [...encryptedKey, ...iv, ...encryptedData];
    }
  }

  @override
  Future<List<int>> decrypt(List<int> data, String privateKey) async {
    if (data.length <= 256) {
      final rsaPrivateKey = _decodePrivateKey(base64Decode(privateKey));
      final decryptor = RSAEngine()
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(rsaPrivateKey));
      return decryptor.process(Uint8List.fromList(data));
    } else {
      final encryptedKey = data.sublist(0, 256);
      final iv = data.sublist(256, 256 + 12);
      final encryptedData = data.sublist(256 + 12);

      final rsaPrivateKey = _decodePrivateKey(base64Decode(privateKey));
      final decryptor = RSAEngine()
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(rsaPrivateKey));
      final aesKey = decryptor.process(Uint8List.fromList(encryptedKey));

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
            false,
            AEADParameters(
                KeyParameter(Uint8List.fromList(aesKey)),
                128,
                Uint8List.fromList(iv),
                Uint8List(0)));

      return cipher.process(Uint8List.fromList(encryptedData));
    }
  }

  Uint8List _encodePublicKey(RSAPublicKey publicKey) {
    return Uint8List.fromList(
      utf8.encode('${publicKey.modulus.toString()}:${publicKey.exponent.toString()}'),
    );
  }

  Uint8List _encodePrivateKey(RSAPrivateKey privateKey) {
    return Uint8List.fromList(
      utf8.encode('${privateKey.modulus.toString()}:${privateKey.exponent.toString()}'),
    );
  }

  RSAPublicKey _decodePublicKey(Uint8List encoded) {
    final parts = utf8.decode(encoded).split(':');
    return RSAPublicKey(BigInt.parse(parts[0]), BigInt.parse(parts[1]));
  }

  RSAPrivateKey _decodePrivateKey(Uint8List encoded) {
    final parts = utf8.decode(encoded).split(':');
    return RSAPrivateKey(BigInt.parse(parts[0]), BigInt.parse(parts[1]), BigInt.zero, BigInt.zero);
  }
}
