import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'domain.dart';
import 'storage_policy.dart';

typedef MendologWriter = Future<bool> Function(String key, String value);

class MendologStore {
  static const _key = 'mendolog.data.v1';
  static const _recoveryKey = 'mendolog.data.recovery.v1';
  static const int _currentSchemaVersion = 2;

  final SharedPreferences preferences;
  final MendologWriter _writer;
  final int maxPayloadBytes;

  String? _protectedPayload;

  MendologStore(
    this.preferences, {
    MendologWriter? writer,
    this.maxPayloadBytes = MendologStoragePolicy.maxPayloadBytes,
  }) : assert(maxPayloadBytes > 0),
       _writer = writer ?? preferences.setString;

  bool get recoveryRequired => _protectedPayload != null;
  String? get protectedPayload => _protectedPayload;

  MendologData load() {
    final value = preferences.getString(_key);
    if (value == null) {
      _protectedPayload = null;
      return const MendologData();
    }

    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        return _protectAndReturnEmpty(value);
      }

      final schemaVersion = decoded['schemaVersion'];
      if (schemaVersion == null) {
        // Legacy v1 payloads stored the MendologData JSON directly.
        final data = MendologData.decode(value);
        _protectedPayload = null;
        return data;
      }
      if (schemaVersion != _currentSchemaVersion) {
        // Fail closed for future/unknown schemas. The original preference is
        // left untouched, and all writes are blocked until recovery is handled.
        return _protectAndReturnEmpty(value);
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return _protectAndReturnEmpty(value);
      }
      final loaded = MendologData.decode(jsonEncode(data));
      _protectedPayload = null;
      return loaded;
    } on Object {
      // Never let a corrupt payload crash startup. Mark it as protected so the
      // next mutation cannot silently replace the only recoverable copy.
      return _protectAndReturnEmpty(value);
    }
  }

  MendologData _protectAndReturnEmpty(String payload) {
    _protectedPayload = payload;
    return const MendologData();
  }

  Future<void> save(MendologData data) async {
    final protectedPayload = _protectedPayload;
    if (protectedPayload != null) {
      final backedUp = await preferences.setString(
        _recoveryKey,
        protectedPayload,
      );
      if (!backedUp) {
        throw StateError('破損した保存データを保護できなかったため、新しい内容を保存できません。');
      }
      throw StateError('保存データの復旧が必要なため、新しい内容を保存していません。');
    }

    final payload = jsonEncode({
      'schemaVersion': _currentSchemaVersion,
      'data': jsonDecode(data.encode()),
    });
    final payloadBytes = MendologStoragePolicy.encodedBytes(payload);
    if (payloadBytes > maxPayloadBytes) {
      throw StateError(
        '保存データが安全上限を超えるため、新しい内容を保存していません。'
        '現在の記録は保持されています。データを書き出して保管してください。',
      );
    }

    final saved = await _writer(_key, payload);
    if (!saved) {
      throw StateError('めんどログの保存に失敗しました。');
    }
  }
}
