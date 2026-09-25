import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mendolog/domain.dart';
import 'package:mendolog/storage.dart';
import 'package:mendolog/storage_policy.dart';

void main() {
  test('encodedBytes measures UTF-8 bytes rather than Dart string length', () {
    expect(MendologStoragePolicy.encodedBytes('abc'), 3);
    expect(MendologStoragePolicy.encodedBytes('あ'), 3);
  });

  test('migrationRecommended turns on at the soft byte boundary', () {
    final below = List.filled(
      MendologStoragePolicy.migrationRecommendedBytes - 1,
      'a',
    ).join();
    final at = List.filled(
      MendologStoragePolicy.migrationRecommendedBytes,
      'a',
    ).join();

    expect(MendologStoragePolicy.migrationRecommended(below), isFalse);
    expect(MendologStoragePolicy.migrationRecommended(at), isTrue);
  });

  test(
    'oversized save fails before writer and preserves current payload',
    () async {
      final current = MendologData(
        events: [
          FrictionEvent(
            id: 'existing-1',
            category: FrictionCategory.searched,
            target: '鍵',
            occurredAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );
      final currentPayload = '{"schemaVersion":2,"data":${current.encode()}}';
      SharedPreferences.setMockInitialValues({
        'mendolog.data.v1': currentPayload,
      });
      final preferences = await SharedPreferences.getInstance();
      var writerCalled = false;
      final store = MendologStore(
        preferences,
        maxPayloadBytes: 32,
        writer: (_, _) async {
          writerCalled = true;
          return true;
        },
      );

      final loaded = store.load();
      expect(loaded.events.single.id, 'existing-1');

      await expectLater(
        store.save(loaded),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('安全上限'),
          ),
        ),
      );

      expect(writerCalled, isFalse);
      expect(preferences.getString('mendolog.data.v1'), currentPayload);
    },
  );

  test('payload at configured limit is still writable', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    String? written;
    final probeStore = MendologStore(
      preferences,
      writer: (_, value) async {
        written = value;
        return true;
      },
    );
    await probeStore.save(const MendologData());
    final exactBytes = MendologStoragePolicy.encodedBytes(written!);

    var exactWriterCalled = false;
    final exactStore = MendologStore(
      preferences,
      maxPayloadBytes: exactBytes,
      writer: (_, _) async {
        exactWriterCalled = true;
        return true;
      },
    );

    await exactStore.save(const MendologData());
    expect(exactWriterCalled, isTrue);
  });
}
