import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:pointycastle/export.dart';

enum SshKeyAlgorithm {
  ed25519,
  rsa2048,
  rsa4096,
  ecdsaP256,
  ecdsaP384,
  ecdsaP521,
}

class GeneratedSshKey {
  final String privateKeyPem;
  final String publicKeyLine;
  final String fingerprint;
  final SshKeyAlgorithm algorithm;
  final String comment;

  const GeneratedSshKey({
    required this.privateKeyPem,
    required this.publicKeyLine,
    required this.fingerprint,
    required this.algorithm,
    required this.comment,
  });
}

SecureRandom _createSecureRandom() {
  final random = FortunaRandom();
  final seed = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    seed[i] = Random.secure().nextInt(256);
  }
  random.seed(KeyParameter(seed));
  for (var i = 0; i < 1024; i++) {
    random.nextUint8();
  }
  return random;
}

String _sha256Fingerprint(Uint8List keyBlob) {
  final bytes = sha256.convert(keyBlob).bytes;
  return base64.encode(bytes);
}

Future<GeneratedSshKey> generateSshKey({
  required SshKeyAlgorithm algorithm,
  required String comment,
  String? passphrase,
}) async {
  switch (algorithm) {
    case SshKeyAlgorithm.ed25519:
      return _generateEd25519(comment, passphrase);
    case SshKeyAlgorithm.rsa2048:
      return _generateRsa(2048, comment, passphrase);
    case SshKeyAlgorithm.rsa4096:
      return _generateRsa(4096, comment, passphrase);
    case SshKeyAlgorithm.ecdsaP256:
      return _generateEcdsa('nistp256', ECCurve_secp256r1(), comment, passphrase);
    case SshKeyAlgorithm.ecdsaP384:
      return _generateEcdsa('nistp384', ECCurve_secp384r1(), comment, passphrase);
    case SshKeyAlgorithm.ecdsaP521:
      return _generateEcdsa('nistp521', ECCurve_secp521r1(), comment, passphrase);
  }
}

GeneratedSshKey _generateEd25519(String comment, String? passphrase) {
  final signingKey = ed25519.SigningKey.generate();
  final publicKeyBytes = signingKey.verifyKey.asTypedList;
  final privateKeyBytes = signingKey.asTypedList;

  final keyPair = OpenSSHEd25519KeyPair(publicKeyBytes, privateKeyBytes, comment);
  final privatePem = keyPair.toPem();

  final publicKeyBlob = keyPair.toPublicKey().encode();
  final publicB64 = base64.encode(publicKeyBlob);
  final publicLine = 'ssh-ed25519 $publicB64 $comment';

  final fingerprint = _sha256Fingerprint(publicKeyBlob);

  return GeneratedSshKey(
    privateKeyPem: privatePem,
    publicKeyLine: publicLine,
    fingerprint: fingerprint,
    algorithm: SshKeyAlgorithm.ed25519,
    comment: comment,
  );
}

GeneratedSshKey _generateRsa(int keySize, String comment, String? passphrase) {
  final secureRandom = _createSecureRandom();

  final keyGen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.parse('65537'), keySize, 64),
      secureRandom,
    ));
  final pair = keyGen.generateKeyPair();
  final rsaPrivate = pair.privateKey as RSAPrivateKey;

  final n = rsaPrivate.modulus!;
  final e = rsaPrivate.publicExponent!;
  final d = rsaPrivate.privateExponent!;
  final p = rsaPrivate.p!;
  final q = rsaPrivate.q!;

  final iqmp = q.modInverse(p);

  final keyPair = OpenSSHRsaKeyPair(n, e, d, iqmp, p, q, comment);
  final privatePem = keyPair.toPem();

  final publicKeyBlob = keyPair.toPublicKey().encode();
  final publicB64 = base64.encode(publicKeyBlob);
  final publicLine = 'ssh-rsa $publicB64 $comment';

  final fingerprint = _sha256Fingerprint(publicKeyBlob);

  return GeneratedSshKey(
    privateKeyPem: privatePem,
    publicKeyLine: publicLine,
    fingerprint: fingerprint,
    algorithm: keySize == 4096 ? SshKeyAlgorithm.rsa4096 : SshKeyAlgorithm.rsa2048,
    comment: comment,
  );
}

GeneratedSshKey _generateEcdsa(
  String curveId,
  ECDomainParameters curve,
  String comment,
  String? passphrase,
) {
  final secureRandom = _createSecureRandom();

  final keyGen = ECKeyGenerator()
    ..init(ParametersWithRandom(
      ECKeyGeneratorParameters(curve),
      secureRandom,
    ));
  final pair = keyGen.generateKeyPair();
  final ecPrivate = pair.privateKey as ECPrivateKey;
  final ecPublic = pair.publicKey as ECPublicKey;

  final d = ecPrivate.d!;
  final q = ecPublic.Q!.getEncoded(false);

  final keyPair = OpenSSHEcdsaKeyPair(curveId, q, d, comment);
  final privatePem = keyPair.toPem();

  final publicKeyBlob = keyPair.toPublicKey().encode();
  final publicB64 = base64.encode(publicKeyBlob);
  final sshType = 'ecdsa-sha2-$curveId';
  final publicLine = '$sshType $publicB64 $comment';

  final fingerprint = _sha256Fingerprint(publicKeyBlob);

  final algorithmMap = {
    'nistp256': SshKeyAlgorithm.ecdsaP256,
    'nistp384': SshKeyAlgorithm.ecdsaP384,
    'nistp521': SshKeyAlgorithm.ecdsaP521,
  };

  return GeneratedSshKey(
    privateKeyPem: privatePem,
    publicKeyLine: publicLine,
    fingerprint: fingerprint,
    algorithm: algorithmMap[curveId]!,
    comment: comment,
  );
}

