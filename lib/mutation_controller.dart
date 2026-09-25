import 'dart:async';

import 'domain.dart';
import 'storage.dart';

/// Persistence boundary used by [MendologMutationController].
///
/// Production adapts the existing [MendologStore], while tests can provide a
/// deterministic fake without SharedPreferences or Flutter bindings.
abstract interface class MendologPersistence {
  MendologData load();
  Future<void> save(MendologData data);
}

class MendologStorePersistence implements MendologPersistence {
  const MendologStorePersistence(this.store);

  final MendologStore store;

  @override
  MendologData load() => store.load();

  @override
  Future<void> save(MendologData data) => store.save(data);
}

/// Owns mutable application state and serializes persistence-backed mutations.
///
/// UI code is responsible only for collecting user input, displaying errors,
/// and rebuilding after a successful mutation. State is updated only after the
/// corresponding save succeeds.
class MendologMutationController {
  MendologMutationController(
    this._persistence, {
    DateTime Function()? now,
    String Function()? generateId,
  }) : _now = now ?? DateTime.now,
       _generateId = generateId ?? generateEventId,
       data = _persistence.load();

  final MendologPersistence _persistence;
  final DateTime Function() _now;
  final String Function() _generateId;

  MendologData data;
  Future<void> _mutationQueue = Future<void>.value();

  Future<bool> record(FrictionCategory category, String target) {
    final clean = canonicalizeTarget(target);
    if (clean.isEmpty) return Future<bool>.value(false);

    return _commit((current) {
      final event = FrictionEvent(
        id: _generateId(),
        category: category,
        target: clean,
        occurredAt: _now().toUtc(),
      );
      return MendologData(
        events: [...current.events, event],
        improvements: current.improvements,
      );
    });
  }

  Future<bool> startImprovement(
    ImprovementSuggestion suggestion,
    String details,
  ) => _commit(
    (current) => MendologData(
      events: current.events,
      improvements: [
        ...current.improvements,
        Improvement(
          category: suggestion.category,
          canonicalTarget: suggestion.canonicalTarget,
          title: suggestion.title,
          details: details,
          startedAt: _now().toUtc(),
        ),
      ],
    ),
  );

  Future<bool> finishImprovement(
    Improvement improvement,
    ImprovementStatus status,
  ) => _commit((current) {
    final index = current.improvements.indexOf(improvement);
    if (index < 0 || !current.improvements[index].isActive) return current;
    final updated = [...current.improvements];
    updated[index] = improvement.finish(status, _now().toUtc());
    return MendologData(events: current.events, improvements: updated);
  });

  Future<bool> deleteEvent(FrictionEvent event) => _commit((current) {
    final index = current.events.indexWhere((item) => item.id == event.id);
    if (index < 0) return current;
    return MendologData(
      events: [...current.events]..removeAt(index),
      improvements: current.improvements,
    );
  });

  Future<bool> _commit(MendologData Function(MendologData current) buildNext) {
    final result = Completer<bool>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        final next = buildNext(data);
        await _persistence.save(next);
        data = next;
        result.complete(true);
      } catch (error, stackTrace) {
        // Keep the internal queue healthy so one failed save does not poison
        // later user actions, while still surfacing the original failure to UI.
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
