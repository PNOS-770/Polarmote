import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class SecretEncryption {
  static Map<String, dynamic> encryptSecrets({
    required Map<String, dynamic> secrets,
    required String password,
  }) {
    final random = Random.secure();
    final salt = List<int>.generate(32, (_) => random.nextInt(256));
    final iv = List<int>.generate(16, (_) => random.nextInt(256));
    final plaintext = utf8.encode(jsonEncode(secrets));
    final key = _deriveKey(password, salt);

    final encrypter = enc.Encrypter(
      enc.AES(
        enc.Key(Uint8List.fromList(key)),
        mode: enc.AESMode.cbc,
      ),
    );
    final encrypted = encrypter.encryptBytes(
      plaintext,
      iv: enc.IV(Uint8List.fromList(iv)),
    );

    return {
      'salt': base64.encode(salt),
      'iv': base64.encode(iv),
      'ciphertext': encrypted.base64,
    };
  }

  static Map<String, dynamic>? decryptSecrets({
    required Map<String, dynamic> payload,
    required String password,
  }) {
    try {
      final salt = base64.decode(payload['salt'] as String);
      final iv = base64.decode(payload['iv'] as String);
      final ciphertext = payload['ciphertext'] as String;
      final key = _deriveKey(password, salt);

      final encrypter = enc.Encrypter(
        enc.AES(
          enc.Key(Uint8List.fromList(key)),
          mode: enc.AESMode.cbc,
        ),
      );
      final decrypted = encrypter.decryptBytes(
        enc.Encrypted.fromBase64(ciphertext),
        iv: enc.IV(Uint8List.fromList(iv)),
      );

      return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _deriveKey(String password, List<int> salt) {
    var key = utf8.encode(password) + salt;
    for (int i = 0; i < 100000; i++) {
      key = sha256.convert(key).bytes;
    }
    return Uint8List.fromList(key.take(32).toList());
  }
}

