import 'dart:convert';

/// Safety policy for the current single-JSON SharedPreferences backend.
///
/// The limit is intentionally fail-closed: existing data is never truncated or
/// deleted automatically. If a mutation would exceed the cap, the existing
/// stored payload is left untouched so the user can still export/recover it.
abstract final class MendologStoragePolicy {
  static const int migrationRecommendedBytes = 4 * 1024 * 1024;
  static const int maxPayloadBytes = 8 * 1024 * 1024;

  static int encodedBytes(String payload) => utf8.encode(payload).length;

  static bool migrationRecommended(String payload) =>
      encodedBytes(payload) >= migrationRecommendedBytes;
}
