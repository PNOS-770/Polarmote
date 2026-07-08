import 'package:Polarmote/shared/utils/secret_encryption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecretEncryption', () {
    test('encrypt and decrypt round-trip', () {
      final secrets = {
        'password': 'my-secret-pass',
        'key': 'abcdef123456',
        'host': 'example.com',
      };
      const password = 'master-password-123';

      final encrypted = SecretEncryption.encryptSecrets(
        secrets: secrets,
        password: password,
      );

      expect(encrypted.containsKey('salt'), isTrue);
      expect(encrypted.containsKey('iv'), isTrue);
      expect(encrypted.containsKey('ciphertext'), isTrue);
      expect(encrypted['salt'], isA<String>());
      expect(encrypted['iv'], isA<String>());
      expect(encrypted['ciphertext'], isA<String>());

      final decrypted = SecretEncryption.decryptSecrets(
        payload: encrypted,
        password: password,
      );

      expect(decrypted, isNotNull);
      expect(decrypted!['password'], 'my-secret-pass');
      expect(decrypted['key'], 'abcdef123456');
      expect(decrypted['host'], 'example.com');
    });

    test('decrypt with wrong password returns null', () {
      final secrets = {'value': 'sensitive-data'};
      const correctPassword = 'correct-password';
      const wrongPassword = 'wrong-password';

      final encrypted = SecretEncryption.encryptSecrets(
        secrets: secrets,
        password: correctPassword,
      );

      final decrypted = SecretEncryption.decryptSecrets(
        payload: encrypted,
        password: wrongPassword,
      );

      expect(decrypted, isNull);
    });

    test('decrypt with tampered ciphertext returns null', () {
      final secrets = {'value': 'sensitive-data'};
      const password = 'my-password';

      final encrypted = SecretEncryption.encryptSecrets(
        secrets: secrets,
        password: password,
      );

      final ct = encrypted['ciphertext'].toString();
      encrypted['ciphertext'] = ct.substring(0, ct.length ~/ 2);

      final decrypted = SecretEncryption.decryptSecrets(
        payload: encrypted,
        password: password,
      );

      expect(decrypted, isNull);
    });

    test('produces different ciphertext each time', () {
      const secrets = {'key': 'value'};
      const password = 'password';

      final result1 = SecretEncryption.encryptSecrets(
        secrets: secrets,
        password: password,
      );
      final result2 = SecretEncryption.encryptSecrets(
        secrets: secrets,
        password: password,
      );

      expect(result1['salt'], isNot(result2['salt']));
      expect(result1['iv'], isNot(result2['iv']));
      expect(result1['ciphertext'], isNot(result2['ciphertext']));
    });

    test('decrypt empty secrets map', () {
      const secrets = <String, dynamic>{};
      const password = 'password';

      final encrypted = SecretEncryption.encryptSecrets(
        secrets: secrets,
        password: password,
      );
      final decrypted = SecretEncryption.decryptSecrets(
        payload: encrypted,
        password: password,
      );

      expect(decrypted, isNotNull);
      expect(decrypted, isEmpty);
    });
  });
}
