import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_auto_detect.dart';

StubsProfileCandidate _candidate(
  String profile, {
  String provider = 'micropython-stubs',
  String label = '',
  String path = '',
  Map<String, dynamic> metadata = const {},
  int priority = 0,
}) => StubsProfileCandidate(
  provider: provider,
  profile: profile,
  label: label,
  path: path,
  metadata: metadata,
  priority: priority,
);

void main() {
  group('selectStubsProfileForFamily', () {
    test('matches a profile id that names the chip family', () {
      final match = selectStubsProfileForFamily(BoardFamily.esp32, [
        _candidate('rp2040', label: 'RP2040'),
        _candidate('esp32', label: 'ESP32'),
      ]);

      expect(match?.profile, 'esp32');
    });

    test('prefers the more specific chip when several match', () {
      final candidates = [
        _candidate('esp32', label: 'ESP32 family'),
        _candidate('esp32s3', label: 'ESP32-S3'),
      ];

      expect(
        selectStubsProfileForFamily(BoardFamily.esp32s3, candidates)?.profile,
        'esp32s3',
      );
      // The plain ESP32 query still answers from the broad profile: the S3
      // profile does not mention the generic name.
      expect(
        selectStubsProfileForFamily(BoardFamily.esp32, candidates)?.profile,
        'esp32',
      );
    });

    test('reads metadata values, not just ids and labels', () {
      final match = selectStubsProfileForFamily(BoardFamily.rp2040, [
        _candidate(
          'generic',
          label: 'Generic',
          metadata: {'board': 'Raspberry Pi Pico'},
        ),
      ]);

      expect(match?.profile, 'generic');
    });

    test('returns null when nothing names the family', () {
      expect(
        selectStubsProfileForFamily(BoardFamily.stm32, [
          _candidate('esp32'),
          _candidate('rp2040'),
        ]),
        isNull,
      );
    });

    test('returns null for an unknown board', () {
      expect(
        selectStubsProfileForFamily(BoardFamily.unknown, [_candidate('esp32')]),
        isNull,
      );
    });

    test('breaks priority ties by profile id for determinism', () {
      final match = selectStubsProfileForFamily(BoardFamily.esp32, [
        _candidate('zeta-esp32'),
        _candidate('alpha-esp32'),
      ]);

      expect(match?.profile, 'alpha-esp32');
    });

    test('higher priority wins over lower regardless of id', () {
      final match = selectStubsProfileForFamily(BoardFamily.esp32, [
        _candidate('alpha-esp32', priority: 0),
        _candidate('zeta-esp32', priority: 10),
      ]);

      expect(match?.profile, 'zeta-esp32');
    });
  });

  group('resolveAutoDetectedStubsLayers', () {
    test('replaces the configured layers with the detected one', () {
      final layers = resolveAutoDetectedStubsLayers(
        family: BoardFamily.esp32,
        candidates: [_candidate('esp32')],
        configuredLayers: const [
          {'provider': 'other', 'profile': 'manual'},
        ],
      );

      expect(layers, [
        {'provider': 'micropython-stubs', 'profile': 'esp32'},
      ]);
    });

    test('keeps the configured layers when the family is unknown', () {
      const configured = [
        {'provider': 'other', 'profile': 'manual'},
      ];
      final layers = resolveAutoDetectedStubsLayers(
        family: null,
        candidates: [_candidate('esp32')],
        configuredLayers: configured,
      );

      expect(layers, configured);
    });

    test('keeps the configured layers when no profile matches', () {
      const configured = [
        {'provider': 'other', 'profile': 'manual'},
      ];
      final layers = resolveAutoDetectedStubsLayers(
        family: BoardFamily.stm32,
        candidates: [_candidate('esp32')],
        configuredLayers: configured,
      );

      expect(layers, configured);
    });
  });
}
