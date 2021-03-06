/*
 * Copyright 2020 Board of Trustees of the University of Illinois.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import "package:asn1lib/asn1lib.dart";
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:illinois/service/Log.dart';
import "package:pointycastle/export.dart";
import 'package:encrypt/encrypt.dart' as Encrypt;

class HealthServiceTest {

  static void test() {
    AsymmetricKeyPair<PublicKey, PrivateKey> rsaKeyPair = RsaKeyHelper.getRsaKeyPair(RsaKeyHelper.getSecureRandom());
    String rsaPublicKeyString = RsaKeyHelper.encodePublicKeyToPemPKCS1(rsaKeyPair.publicKey);
    String rsaPrivateKeyString = RsaKeyHelper.encodePrivateKeyToPemPKCS1(rsaKeyPair.privateKey);

    //Log.d('''Health Service Provider:
    //- Input: RSA Public Key, Plain Blob;
    //- Output: Ecrypted Blob, Ecrypted Key.
    //''');

    //Log.d("RSA Public Key: $rsaPublicKeyString");

    String plainBlob = '''Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut id sagittis nibh. Ut porttitor interdum bibendum. Sed in interdum ante, ac efficitur felis. In diam justo, molestie sed fermentum rhoncus, euismod nec mauris. Donec interdum at sem vitae volutpat. Quisque fermentum lobortis neque, vitae feugiat est malesuada nec. Cras vehicula dapibus elementum. In at nisi in leo gravida dapibus. Nulla facilisi. Fusce varius tortor non nibh euismod varius. Aenean condimentum velit a felis ornare congue. Donec interdum, leo sit amet iaculis elementum, nunc orci fringilla nulla, non pulvinar lectus turpis vitae ligula. Nam ullamcorper feugiat enim in ullamcorper. Phasellus dignissim nulla et mattis imperdiet.''';
    //Log.d("Plain Blob: $plainBlob");

    String aesKey = AESCrypt.randomKey();
    //Log.d("Random AES Key: $aesKey");

    String encryptedBlob = AESCrypt.encrypt(plainBlob, keyString: aesKey);
    //Log.d("Ecrypted Blob: $encryptedBlob");

    PublicKey rsaPublicKey = RsaKeyHelper.parsePublicKeyFromPem(rsaPublicKeyString);
    String encryptedKey = RSACrypt.encrypt(aesKey, rsaPublicKey);
    //Log.d("Ecrypted Key: $encryptedKey");

    //Log.d('''Client Processing:
    //- Input: RSA Private Key, Ecrypted Blob, Ecrypted Key;
    //- Output: Decrypted Blob.
    //''');

    //Log.d("RSA Private Key: $rsaPrivateKeyString");

    PrivateKey rsaPrivateKey = RsaKeyHelper.parsePrivateKeyFromPem(rsaPrivateKeyString);
    String decryptedKey = RSACrypt.decrypt(encryptedKey, rsaPrivateKey);
    //Log.d("Decrypted Key: $decryptedKey");

    String decryptedBlob = AESCrypt.decrypt(encryptedBlob, keyString: decryptedKey);
    //Log.d("Decrypted Blob: $decryptedBlob");

    String status = (plainBlob == decryptedBlob) ? "Test Succeeded" : "Test Failed";
    //Log.d("$status");

    Log.d('''
    Health Service Provider:
      - Input: Plain Blob, RSA Public Key;
      - Output: Ecrypted Blob, Ecrypted Key.
    
    Plain Blob: $plainBlob

    RSA Public Key: $rsaPublicKeyString

    Random AES Key: $aesKey

    Ecrypted Blob: $encryptedBlob

    Ecrypted Key: $encryptedKey

    Client Processing:
      - Input: RSA Private Key, Ecrypted Blob, Ecrypted Key;
      - Output: Decrypted Blob;
    
    RSA Private Key: $rsaPrivateKeyString
    
    Decrypted Key: $decryptedKey
    
    Decrypted Blob: $decryptedBlob
    
    $status
    ''');
  }
}

class AESCrypt {

  static const int kCCBlockSizeAES128 = 16;

  static String encrypt(String plainText, { String keyString, String keyBase64, Uint8List keyBytes, Encrypt.AESMode mode = Encrypt.AESMode.cbc, String padding = 'PKCS7' }) {
    try {
      Encrypt.Key key;
      if (keyString != null) {
        key = Encrypt.Key.fromUtf8(keyString);
      }
      else if (keyBase64 != null) {
        key = Encrypt.Key.fromBase64(keyBase64);
      }
      else if (keyBytes != null) {
        key = Encrypt.Key(keyBytes);
      }
      Encrypt.IV iv = Encrypt.IV.fromLength(key.length);
      Encrypt.Encrypter encrypter = Encrypt.Encrypter(Encrypt.AES(key, mode: mode, padding: padding));
      return encrypter.encrypt(plainText, iv: iv).base64;
    }
    catch(e) { print(e.toString()); }
    return null;
  }

  static String decrypt(String cipherBase64, { String keyString, String keyBase64, Uint8List keyBytes, Encrypt.AESMode mode = Encrypt.AESMode.cbc, String padding = 'PKCS7' }) {
    try {
      Encrypt.Key key;
      if (keyString != null) {
        key = Encrypt.Key.fromUtf8(keyString);
      }
      else if (keyBase64 != null) {
        key = Encrypt.Key.fromBase64(keyBase64);
      }
      else if (keyBytes != null) {
        key = Encrypt.Key(keyBytes);
      }
      Encrypt.IV iv = Encrypt.IV.fromLength(key.length);
      dynamic encrypter = Encrypt.Encrypter(Encrypt.AES(key, mode: mode, padding: padding));
      return encrypter.decrypt(Encrypt.Encrypted.fromBase64(cipherBase64), iv: iv);
    }
    catch(e) { print(e.toString()); }
    return null;
  }

  static String decode(String base64Data, { Encrypt.AESMode mode = Encrypt.AESMode.cbc, String padding = 'PKCS7' }) {
    var data;
    try { data = (base64Data != null) ? base64Decode(base64Data) : null; }
    catch (e) { print(e?.toString()); }
    if ((data != null) && (data.length > kCCBlockSizeAES128)) {
      try {
        var keyData = data.sublist(0, kCCBlockSizeAES128);
        var encryptedData = data.sublist(kCCBlockSizeAES128);

        final keyString = String.fromCharCodes(keyData);
        final key = Encrypt.Key.fromUtf8(keyString);
        final iv = Encrypt.IV.fromLength(kCCBlockSizeAES128);
        final encrypter = Encrypt.Encrypter(Encrypt.AES(key, mode: mode, padding: padding));

        return encrypter.decrypt(Encrypt.Encrypted(encryptedData), iv: iv);
      }
      catch(e) { print(e.toString()); }
    }
    return null;
  }

  static String encode(String dataString, { String keyString, Encrypt.AESMode mode = Encrypt.AESMode.cbc, String padding = 'PKCS7' }) {
    try {
      final keyString2 = (keyString != null) ? keyString : randomKey();
      final key = Encrypt.Key.fromUtf8(keyString2);
      final iv = Encrypt.IV.fromLength(kCCBlockSizeAES128);
      final encrypter = Encrypt.Encrypter(Encrypt.AES(key, mode: mode, padding: padding));

      Uint8List encryptedJson = encrypter.encrypt(dataString, iv: iv).bytes;

      List<int> list = [];
      list.addAll(keyString2.codeUnits);
      list.addAll(encryptedJson);
      Uint8List data = Uint8List.fromList(list);

      return base64Encode(data);
    }
    catch(e) { print(e.toString()); }
    return null;
  }

  static String randomKey({ int keySize = kCCBlockSizeAES128 }) {
    var rand = new Random();
    var codeUnits = List.generate(keySize, (index) {
      return rand.nextInt(33) + 89; // rand.nextInt(255);
    });
    return new String.fromCharCodes(codeUnits);
  }
}

class RSACrypt {

  static String encrypt(String plainText, PublicKey publicKey) {
      try {
        final encrypter = Encrypt.Encrypter(Encrypt.RSA(publicKey: publicKey, privateKey: null));
        return encrypter.encrypt(plainText).base64;
      }
      catch(e) { print(e.toString()); }
      return null;
  }

  static String decrypt(String cipherBase64, PrivateKey privateKey) {
      try {
        final encrypter = Encrypt.Encrypter(Encrypt.RSA(publicKey: null, privateKey: privateKey));
        return encrypter.decrypt(Encrypt.Encrypted.fromBase64(cipherBase64));
      }
      catch(e) { print(e.toString()); }
      return null;
  }
}

/// Helper class to handle RSA key generation and encoding
class RsaKeyHelper {
  
  /// Generate a [PublicKey] and [PrivateKey] pair
  ///
  /// Returns a [AsymmetricKeyPair] based on the [RSAKeyGenerator] with custom parameters,
  /// including a [SecureRandom]
  static Future<AsymmetricKeyPair<PublicKey, PrivateKey>> computeRSAKeyPair(SecureRandom secureRandom) async {
    return await compute(getRsaKeyPair, secureRandom);
  }

  /// Generates a [SecureRandom]
  ///
  /// Returns [FortunaRandom] to be used in the [AsymmetricKeyPair] generation
  static SecureRandom getSecureRandom() {
    var secureRandom = FortunaRandom();
    var random = Random.secure();
    List<int> seeds = [];
    for (int i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    secureRandom.seed(new KeyParameter(new Uint8List.fromList(seeds)));
    return secureRandom;
  }

  /// Decode Public key from PEM Format
  ///
  /// Given a base64 encoded PEM [String] with correct headers and footers, return a
  /// [RSAPublicKey]
  ///
  /// *PKCS1*
  /// RSAPublicKey ::= SEQUENCE {
  ///    modulus           INTEGER,  -- n
  ///    publicExponent    INTEGER   -- e
  /// }
  ///
  /// *PKCS8*
  /// PublicKeyInfo ::= SEQUENCE {
  ///   algorithm       AlgorithmIdentifier,
  ///   PublicKey       BIT STRING
  /// }
  ///
  /// AlgorithmIdentifier ::= SEQUENCE {
  ///   algorithm       OBJECT IDENTIFIER,
  ///   parameters      ANY DEFINED BY algorithm OPTIONAL
  /// }
  static RSAPublicKey parsePublicKeyFromPem(pemString) {
    return (pemString != null) ? parsePublicKeyFromPemData(_decodePEM(pemString)) : null;
  }

  static RSAPublicKey parsePublicKeyFromPemData(Uint8List pemData) {
    if (pemData == null) {
      return null;
    }

    var asn1Parser = new ASN1Parser(pemData);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    var modulus, exponent;
    // Depending on the first element type, we either have PKCS1 or 2
    if (topLevelSeq.elements[0].runtimeType == ASN1Integer) {
      modulus = topLevelSeq.elements[0] as ASN1Integer;
      exponent = topLevelSeq.elements[1] as ASN1Integer;
    } else {
      var publicKeyBitString = topLevelSeq.elements[1];

      var publicKeyAsn = new ASN1Parser(publicKeyBitString.contentBytes());
      ASN1Sequence publicKeySeq = publicKeyAsn.nextObject();
      modulus = publicKeySeq.elements[0] as ASN1Integer;
      exponent = publicKeySeq.elements[1] as ASN1Integer;
    }

    RSAPublicKey rsaPublicKey = RSAPublicKey(modulus.valueAsBigInteger, exponent.valueAsBigInteger);

    return rsaPublicKey;
  }

  /// Sign plain text with Private Key
  ///
  /// Given a plain text [String] and a [RSAPrivateKey], decrypt the text using
  /// a [RSAEngine] cipher
  static String sign(String plainText, RSAPrivateKey privateKey) {
    var signer = RSASigner(SHA256Digest(), "0609608648016503040201");
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return  base64Encode(signer.generateSignature(_createUint8ListFromString(plainText)).bytes);
  }


  /// Creates a [Uint8List] from a string to be signed
  static Uint8List _createUint8ListFromString(String s) {
    var codec = Utf8Codec(allowMalformed: true);
    return Uint8List.fromList(codec.encode(s));
  }

  /// Decode Private key from PEM Format
  ///
  /// Given a base64 encoded PEM [String] with correct headers and footers, return a
  /// [RSAPrivateKey]
  static RSAPrivateKey parsePrivateKeyFromPem(pemString) {
    return (pemString != null) ? parsePrivateKeyFromPemData(_decodePEM(pemString)) : null;
  }

  static RSAPrivateKey parsePrivateKeyFromPemData(Uint8List pemData) {
    if (pemData == null) {
      return null;
    }

    var asn1Parser = new ASN1Parser(pemData);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    var modulus, privateExponent, p, q;
    // Depending on the number of elements, we will either use PKCS1 or PKCS8
    if (topLevelSeq.elements.length == 3) {
      var privateKey = topLevelSeq.elements[2];

      asn1Parser = new ASN1Parser(privateKey.contentBytes());
      var pkSeq = asn1Parser.nextObject() as ASN1Sequence;

      modulus = pkSeq.elements[1] as ASN1Integer;
      privateExponent = pkSeq.elements[3] as ASN1Integer;
      p = pkSeq.elements[4] as ASN1Integer;
      q = pkSeq.elements[5] as ASN1Integer;
    } else {
      modulus = topLevelSeq.elements[1] as ASN1Integer;
      privateExponent = topLevelSeq.elements[3] as ASN1Integer;
      p = topLevelSeq.elements[4] as ASN1Integer;
      q = topLevelSeq.elements[5] as ASN1Integer;
    }

    RSAPrivateKey rsaPrivateKey = RSAPrivateKey(
        modulus.valueAsBigInteger,
        privateExponent.valueAsBigInteger,
        p.valueAsBigInteger,
        q.valueAsBigInteger);

    return rsaPrivateKey;
  }

  static Uint8List _decodePEM(String pem) {
    return base64.decode(_removePemHeaderAndFooter(pem));
  }

  static String _removePemHeaderAndFooter(String pem) {
    var startsWith = [
      "-----BEGIN PUBLIC KEY-----",
      "-----BEGIN RSA PRIVATE KEY-----",
      "-----BEGIN RSA PUBLIC KEY-----",
      "-----BEGIN PRIVATE KEY-----",
      "-----BEGIN PGP PUBLIC KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
      "-----BEGIN PGP PRIVATE KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
    ];
    var endsWith = [
      "-----END PUBLIC KEY-----",
      "-----END PRIVATE KEY-----",
      "-----END RSA PRIVATE KEY-----",
      "-----END RSA PUBLIC KEY-----",
      "-----END PGP PUBLIC KEY BLOCK-----",
      "-----END PGP PRIVATE KEY BLOCK-----",
    ];
    bool isOpenPgp = pem.indexOf('BEGIN PGP') != -1;

    pem = pem.replaceAll(' ', '');
    pem = pem.replaceAll('\n', '');
    pem = pem.replaceAll('\r', '');

    for (var s in startsWith) {
      s = s.replaceAll(' ', '');
      if (pem.startsWith(s)) {
        pem = pem.substring(s.length);
      }
    }

    for (var s in endsWith) {
      s = s.replaceAll(' ', '');
      if (pem.endsWith(s)) {
        pem = pem.substring(0, pem.length - s.length);
      }
    }

    if (isOpenPgp) {
      var index = pem.indexOf('\r\n');
      pem = pem.substring(0, index);
    }

    return pem;
  }

  /// Encode Private key to PEM Format
  ///
  /// Given [RSAPrivateKey] returns a base64 encoded [String] with standard PEM headers and footers
  static String encodePrivateKeyToPemPKCS1(RSAPrivateKey privateKey) {
    if (privateKey == null) {
      return null;
    }
    Uint8List dataBytes = encodePrivateKeyToPEMDataPKCS1(privateKey);
    var dataBase64 = base64.encode(dataBytes);
    return """-----BEGIN PRIVATE KEY-----\r\n$dataBase64\r\n-----END PRIVATE KEY-----""";
  }

  static Uint8List encodePrivateKeyToPEMDataPKCS1(RSAPrivateKey privateKey) {
    if (privateKey == null) {
      return null;
    }

    var topLevel = new ASN1Sequence();

    var version = ASN1Integer(BigInt.from(0));
    var modulus = ASN1Integer(privateKey.n);
    var publicExponent = ASN1Integer(privateKey.exponent);
    var privateExponent = ASN1Integer(privateKey.privateExponent);
    var p = ASN1Integer(privateKey.p);
    var q = ASN1Integer(privateKey.q);
    var dP = privateKey.privateExponent % (privateKey.p - BigInt.from(1));
    var exp1 = ASN1Integer(dP);
    var dQ = privateKey.privateExponent % (privateKey.q - BigInt.from(1));
    var exp2 = ASN1Integer(dQ);
    var iQ = privateKey.q.modInverse(privateKey.p);
    var co = ASN1Integer(iQ);

    topLevel.add(version);
    topLevel.add(modulus);
    topLevel.add(publicExponent);
    topLevel.add(privateExponent);
    topLevel.add(p);
    topLevel.add(q);
    topLevel.add(exp1);
    topLevel.add(exp2);
    topLevel.add(co);

    return topLevel.encodedBytes;
  }

  /// Encode Public key to PEM Format
  ///
  /// Given [RSAPublicKey] returns a base64 encoded [String] with standard PEM headers and footers
  static String encodePublicKeyToPemPKCS1(RSAPublicKey publicKey) {
    if (publicKey == null) {
      return null;
    }

    Uint8List pemData = encodePublicKeyToPemDataPKCS1(publicKey);
    var dataBase64 = base64.encode(pemData);
    return """-----BEGIN PUBLIC KEY-----\r\n$dataBase64\r\n-----END PUBLIC KEY-----""";
  }

  static Uint8List encodePublicKeyToPemDataPKCS1(RSAPublicKey publicKey) {
    if (publicKey == null) {
      return null;
    }
    
    var topLevel = new ASN1Sequence();

    topLevel.add(ASN1Integer(publicKey.modulus));
    topLevel.add(ASN1Integer(publicKey.exponent));

    return topLevel.encodedBytes;
  }
  
  /// Generate a [PublicKey] and [PrivateKey] pair
  ///
  /// Returns a [AsymmetricKeyPair] based on the [RSAKeyGenerator] with custom parameters,
  /// including a [SecureRandom]
  static AsymmetricKeyPair<PublicKey, PrivateKey> getRsaKeyPair(SecureRandom secureRandom) {
    var rsapars = new RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 5);
    var params = new ParametersWithRandom(rsapars, secureRandom);
    var keyGenerator = new RSAKeyGenerator();
    keyGenerator.init(params);
    return keyGenerator.generateKeyPair();
  }

  /// Verify a [PublicKey] and [PrivateKey] pair
  ///
  /// Returns a boolean based on the whether [AsymmetricKeyPair] is paired or not,
  static Future<bool> verifyRsaKeyPair(AsymmetricKeyPair<PublicKey, PrivateKey> rsaKeyPair) async {
    return await compute(_verifyRSAKeyPair, rsaKeyPair);
  }

  /// Decompess a [PrivateKey]
  ///
  /// Returns a private key decoded from base64 encoded string
  static Future<PrivateKey> decompressRsaPrivateKey(String data) async {
    return await compute(_decompressRsaPrivateKey, data);
  }

  /// Compess a [PrivateKey]
  ///
  /// Returns a base64 encoded string of compressed key content
  static Future<String> compressRsaPrivateKey(PrivateKey privateKey) async {
    return await compute(_compressRsaPrivateKey, privateKey);
  }
}

bool _verifyRSAKeyPair(AsymmetricKeyPair<PublicKey, PrivateKey> rsaKeyPair) {
  PublicKey rsaPublicKey = rsaKeyPair?.publicKey;
  PrivateKey rsaPrivateKey = rsaKeyPair?.privateKey;
  if ((rsaPublicKey != null) && (rsaPrivateKey != null)) {
    String aesKey = AESCrypt.randomKey();
    if (aesKey != null) {
      String encryptedAESKey = RSACrypt.encrypt(aesKey, rsaPublicKey);
      if (encryptedAESKey != null) {
        String decryptedAESKey = RSACrypt.decrypt(encryptedAESKey, rsaPrivateKey);
        return (decryptedAESKey == aesKey);
      }
    }
  }
  return null;
}

PrivateKey _decompressRsaPrivateKey(String data) {
  PrivateKey privateKey;
  try {
    Uint8List pemCompressedData = (data != null) ? base64.decode(data) : null;
    List<int> pemData = (pemCompressedData != null) ? GZipDecoder().decodeBytes(pemCompressedData) : null;
    privateKey = (pemData != null) ? RsaKeyHelper.parsePrivateKeyFromPemData(pemData) : null;
  }
  catch (e) {
    print(e?.toString());
  }
  return privateKey;
}

String _compressRsaPrivateKey(PrivateKey privateKey) {
  String privateKeyString;
  try {
    Uint8List privateKeyData = (privateKey != null) ? RsaKeyHelper.encodePrivateKeyToPEMDataPKCS1(privateKey) : null;
    List<int> privateKeyCompressedData = (privateKeyData != null) ? GZipEncoder().encode(privateKeyData) : null;
    privateKeyString = (privateKeyData != null) ? base64.encode(privateKeyCompressedData) : null;
  }
  catch (e) {
    print(e?.toString());
  }
  return privateKeyString;
}
