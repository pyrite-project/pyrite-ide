import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/runtime_inspection.dart';

class _Emission {
  _Emission(this.topic, this.payload);
  final String topic;
  final Map<String, dynamic> payload;
}

void main() {
  group('RuntimeReference', () {
    test('encodes and parses round-trip', () {
      const ref = RuntimeReference(
        sessionId: 's1',
        generation: 4,
        objectId: '42',
      );
      expect(ref.encode(), 'runtime-s1:generation-4:obj-42');
      final parsed = RuntimeReference.tryParse(ref.encode());
      expect(parsed, ref);
    });

    test('rejects malformed tokens', () {
      expect(RuntimeReference.tryParse('nonsense'), isNull);
      expect(RuntimeReference.tryParse('runtime-s:generation-x:obj-1'), isNull);
    });
  });

  group('RuntimeLimits', () {
    test('clamps repr length with an ellipsis', () {
      const limits = RuntimeLimits(maxRepr: 5);
      expect(limits.clampRepr('12345'), '12345');
      expect(limits.clampRepr('1234567'), '12345…');
    });

    test('clamps child page count into range', () {
      const limits = RuntimeLimits(maxChildrenPerPage: 100);
      expect(limits.clampCount(0), 100);
      expect(limits.clampCount(50), 50);
      expect(limits.clampCount(999), 100);
    });
  });

  group('RuntimeInspectionService', () {
    late List<_Emission> emissions;
    late RuntimeInspectionService service;

    setUp(() {
      emissions = [];
      service = RuntimeInspectionService(
        emit: (topic, payload) => emissions.add(_Emission(topic, payload)),
      );
    });

    List<String> topics() => emissions.map((e) => e.topic).toList();

    test('createSession emits session.created at generation 1', () {
      final session = service.createSession('s1');
      expect(session.generation, 1);
      expect(topics(), [RuntimeTopics.sessionCreated]);
    });

    test('references are valid in the current generation', () {
      service.createSession('s1');
      final ref = service.reference('s1', '42')!;
      expect(service.validate(ref.encode()), ReferenceStatus.valid);
    });

    test('backend restart invalidates every prior reference', () {
      service.createSession('s1');
      final ref = service.reference('s1', '42')!;
      emissions.clear();
      service.restartBackend('s1');

      expect(service.validate(ref.encode()), ReferenceStatus.stale);
      expect(topics(), [
        RuntimeTopics.backendRestarted,
        RuntimeTopics.sessionStateChanged,
      ]);
      // A fresh reference in the new generation is valid again.
      final fresh = service.reference('s1', '42')!;
      expect(service.validate(fresh.encode()), ReferenceStatus.valid);
    });

    test('malformed and unknown-session tokens are reported distinctly', () {
      expect(service.validate('garbage'), ReferenceStatus.malformed);
      expect(
        service.validate('runtime-ghost:generation-1:obj-1'),
        ReferenceStatus.stale,
      );
    });

    test('program state transitions emit matching lifecycle events', () {
      service.createSession('s1');
      emissions.clear();
      service.setProgramState('s1', RuntimeProgramState.running);
      service.setProgramState('s1', RuntimeProgramState.paused);
      service.resumeProgram('s1');
      service.setProgramState('s1', RuntimeProgramState.finished);

      expect(topics(), [
        RuntimeTopics.programStarted,
        RuntimeTopics.sessionStateChanged,
        RuntimeTopics.programPaused,
        RuntimeTopics.sessionStateChanged,
        RuntimeTopics.programResumed,
        RuntimeTopics.sessionStateChanged,
        RuntimeTopics.programFinished,
        RuntimeTopics.sessionStateChanged,
      ]);
    });

    test('setCapability toggles and emits only on change', () {
      service.createSession('s1');
      emissions.clear();
      service.setCapability('s1', RuntimeCapability.unavailable);
      service.setCapability('s1', RuntimeCapability.unavailable);
      expect(topics(), [RuntimeTopics.sessionStateChanged]);
      expect(service.session('s1')!.capability, RuntimeCapability.unavailable);
    });

    test('variables.changed carries the session id', () {
      service.createSession('s1');
      emissions.clear();
      service.notifyVariablesChanged('s1');
      expect(topics(), [RuntimeTopics.variablesChanged]);
      expect(emissions.single.payload['sessionId'], 's1');
    });

    test('resume only fires from paused', () {
      service.createSession('s1');
      service.setProgramState('s1', RuntimeProgramState.running);
      emissions.clear();
      service.resumeProgram('s1'); // running, not paused -> no-op
      expect(emissions, isEmpty);
    });

    test('endSession removes the session and emits session.ended', () {
      service.createSession('s1');
      final ref = service.reference('s1', '42')!;
      emissions.clear();
      service.endSession('s1');
      expect(service.sessions, isEmpty);
      expect(topics(), [RuntimeTopics.sessionEnded]);
      expect(service.validate(ref.encode()), ReferenceStatus.stale);
    });
  });
}
