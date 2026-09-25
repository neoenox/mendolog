import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mendolog/domain.dart';
import 'package:mendolog/mutation_controller.dart';

class FakePersistence implements MendologPersistence {
  FakePersistence({this.initial = const MendologData(), this.onSave});

  final MendologData initial;
  Future<void> Function(MendologData data)? onSave;
  final List<MendologData> saved = [];
  int saveCalls = 0;

  @override
  MendologData load() => initial;

  @override
  Future<void> save(MendologData data) async {
    saveCalls += 1;
    await onSave?.call(data);
    saved.add(data);
  }
}

void main() {
  final now = DateTime.utc(2026, 9, 14, 1, 2, 3);

  test('successful mutation persists before publishing state', () async {
    final persistence = FakePersistence();
    final controller = MendologMutationController(
      persistence,
      now: () => now,
      generateId: () => 'event-1',
    );

    final changed = await controller.record(
      FrictionCategory.troublesome,
      '  爪きり  ',
    );

    expect(changed, isTrue);
    expect(persistence.saved, hasLength(1));
    expect(controller.data.events, hasLength(1));
    expect(controller.data.events.single.id, 'event-1');
    expect(controller.data.events.single.target, '爪切り');
    expect(controller.data.events.single.occurredAt, now);
    expect(persistence.saved.single.events.single.id, 'event-1');
  });

  test(
    'failed save leaves state unchanged and later mutation can recover',
    () async {
      var fail = true;
      final persistence = FakePersistence(
        onSave: (_) async {
          if (fail) throw StateError('save failed');
        },
      );
      var id = 0;
      final controller = MendologMutationController(
        persistence,
        now: () => now,
        generateId: () => 'event-${++id}',
      );

      await expectLater(
        controller.record(FrictionCategory.other, '失敗する記録'),
        throwsA(isA<StateError>()),
      );
      expect(controller.data.events, isEmpty);
      expect(persistence.saved, isEmpty);

      fail = false;
      expect(await controller.record(FrictionCategory.other, '次の記録'), isTrue);
      expect(controller.data.events, hasLength(1));
      expect(controller.data.events.single.target, '次の記録');
      expect(persistence.saved, hasLength(1));
    },
  );

  test('delayed saves serialize concurrent mutations', () async {
    final firstSaveGate = Completer<void>();
    final persistence = FakePersistence(
      onSave: (_) async {
        if (firstSaveGate.isCompleted == false) {
          await firstSaveGate.future;
        }
      },
    );
    var id = 0;
    final controller = MendologMutationController(
      persistence,
      now: () => now,
      generateId: () => 'event-${++id}',
    );

    final first = controller.record(FrictionCategory.searched, '鍵');
    await Future<void>.delayed(Duration.zero);
    final second = controller.record(FrictionCategory.forgot, '財布');
    await Future<void>.delayed(Duration.zero);

    expect(persistence.saveCalls, 1);
    expect(controller.data.events, isEmpty);

    firstSaveGate.complete();
    await Future.wait([first, second]);

    expect(persistence.saveCalls, 2);
    expect(controller.data.events.map((event) => event.target), ['鍵', '財布']);
  });

  test('improvement and delete mutations are UI independent', () async {
    final event = FrictionEvent(
      id: 'existing',
      category: FrictionCategory.waited,
      target: 'レジ',
      occurredAt: now.subtract(const Duration(days: 1)),
    );
    final persistence = FakePersistence(initial: MendologData(events: [event]));
    final controller = MendologMutationController(
      persistence,
      now: () => now,
      generateId: () => 'unused',
    );
    const suggestion = ImprovementSuggestion(
      category: FrictionCategory.waited,
      canonicalTarget: 'レジ',
      count: 3,
      title: '時間帯を変える',
    );

    await controller.startImprovement(suggestion, '朝に行く');
    final improvement = controller.data.improvements.single;
    expect(improvement.details, '朝に行く');
    expect(improvement.startedAt, now);

    await controller.finishImprovement(
      improvement,
      ImprovementStatus.completed,
    );
    expect(
      controller.data.improvements.single.status,
      ImprovementStatus.completed,
    );
    expect(controller.data.improvements.single.endedAt, now);

    await controller.deleteEvent(event);
    expect(controller.data.events, isEmpty);
  });
}
