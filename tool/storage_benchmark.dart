import 'dart:convert';

import 'package:mendolog/domain.dart';
import 'package:mendolog/storage_policy.dart';

void main() {
  for (final count in const [1000, 5000, 10000]) {
    final data = _fixture(count);

    final encodeWatch = Stopwatch()..start();
    final encoded = data.encode();
    encodeWatch.stop();

    final wrappedPayload = jsonEncode({
      'schemaVersion': 2,
      'data': jsonDecode(encoded),
    });

    final decodeWatch = Stopwatch()..start();
    final decoded = MendologData.decode(encoded);
    decodeWatch.stop();

    if (decoded.events.length != count) {
      throw StateError(
        'Round-trip mismatch: expected $count events, '
        'got ${decoded.events.length}',
      );
    }

    final bytes = MendologStoragePolicy.encodedBytes(wrappedPayload);
    final softLimitReached =
        bytes >= MendologStoragePolicy.migrationRecommendedBytes;
    final hardLimitExceeded = bytes > MendologStoragePolicy.maxPayloadBytes;

    // Benchmark output is intentionally emitted to stdout for local/CI capture.
    // ignore: avoid_print
    print(
      'events=$count '
      'payloadBytes=$bytes '
      'encodeMs=${encodeWatch.elapsedMilliseconds} '
      'decodeMs=${decodeWatch.elapsedMilliseconds} '
      'migrationRecommended=$softLimitReached '
      'hardLimitExceeded=$hardLimitExceeded',
    );
  }
}

MendologData _fixture(int count) {
  final start = DateTime.utc(2023, 1, 1);
  return MendologData(
    events: List.generate(
      count,
      (index) => FrictionEvent(
        id: 'benchmark-event-${index.toString().padLeft(5, '0')}',
        category:
            FrictionCategory.values[index % FrictionCategory.values.length],
        target: 'benchmark target ${index % 50}',
        occurredAt: start.add(Duration(hours: index * 6)),
      ),
      growable: false,
    ),
  );
}
