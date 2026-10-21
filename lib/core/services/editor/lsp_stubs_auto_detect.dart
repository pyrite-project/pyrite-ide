import 'package:pyrite_ide/core/services/device/board_identity.dart';

/// Picks the MicroPython stubs layer that matches an identified board.
///
/// Stubs layers are contributed by data plugins: each profile carries a path, a
/// label and free-form `metadata`. The layers a user pins by hand always win;
/// this is only the "自动探测层级" path, which until now was a switch that
/// nothing read.
///
/// Matching is deliberately conservative. A layer is selected only when its
/// provider/profile id, label or metadata explicitly names the board family —
/// guessing from a partial name would point the language server at the wrong
/// stubs and produce confidently wrong completions, which is worse than
/// leaving the switch on and doing nothing.
/// Terms that identify a family inside a profile id, label or metadata value.
///
/// The lists are lowercase because matching lowercases its inputs. ESP32-S3 is
/// listed before ESP32 on purpose: its stubs describe a different pin and
/// peripheral set, so a profile that names both must resolve to the more
/// specific one.
const Map<BoardFamily, List<String>> _familyTerms = {
  BoardFamily.esp32s3: ['esp32s3', 'esp32-s3', 'esp32_s3'],
  BoardFamily.esp32s2: ['esp32s2', 'esp32-s2', 'esp32_s2'],
  BoardFamily.esp32c6: ['esp32c6', 'esp32-c6', 'esp32_c6'],
  BoardFamily.esp32c3: ['esp32c3', 'esp32-c3', 'esp32_c3'],
  BoardFamily.esp32: ['esp32'],
  BoardFamily.esp8266: ['esp8266', 'esp-8266', 'esp_8266'],
  BoardFamily.rp2040: ['rp2040', 'pico', 'raspberrypi'],
  BoardFamily.stm32: ['stm32'],
  BoardFamily.k230: ['k230'],
};

/// One candidate profile offered by a data plugin.
class StubsProfileCandidate {
  const StubsProfileCandidate({
    required this.provider,
    required this.profile,
    this.label = '',
    this.path = '',
    this.metadata = const {},
    this.priority = 0,
  });

  /// Data plugin id that contributed the profile.
  final String provider;

  /// Profile id inside that provider.
  final String profile;

  final String label;
  final String path;
  final Map<String, dynamic> metadata;

  /// Higher priority wins when several profiles match the same family.
  final int priority;

  Map<String, String> toLayer() => {'provider': provider, 'profile': profile};
}

/// Selects the profile that describes [family], or null when nothing matches.
///
/// Returns the highest-priority match. Ties break on the profile id so the
/// choice is deterministic across runs instead of depending on registry order.
StubsProfileCandidate? selectStubsProfileForFamily(
  BoardFamily family,
  Iterable<StubsProfileCandidate> candidates,
) {
  final terms = _familyTerms[family];
  if (terms == null || terms.isEmpty) return null;

  StubsProfileCandidate? best;
  for (final candidate in candidates) {
    if (!_candidateMentionsFamily(candidate, terms)) continue;
    if (best == null) {
      best = candidate;
      continue;
    }
    final byPriority = candidate.priority.compareTo(best.priority);
    if (byPriority > 0) {
      best = candidate;
    } else if (byPriority == 0 &&
        candidate.profile.compareTo(best.profile) < 0) {
      best = candidate;
    }
  }
  return best;
}

bool _candidateMentionsFamily(
  StubsProfileCandidate candidate,
  List<String> terms,
) {
  final haystacks = <String>[
    candidate.profile,
    candidate.label,
    candidate.path,
    candidate.provider,
    for (final value in candidate.metadata.values)
      if (value is String) value,
  ];
  for (final raw in haystacks) {
    final haystack = raw.toLowerCase();
    if (haystack.isEmpty) continue;
    for (final term in terms) {
      if (haystack.contains(term)) return true;
    }
  }
  return false;
}

/// Builds the layer list the settings page writes when auto-detect is on.
///
/// A null [family] — an unidentified port, or no port at all — leaves the list
/// untouched: the user's explicit layers are the only ones worth keeping when
/// the IDE cannot tell what board is attached.
List<Map<String, String>> resolveAutoDetectedStubsLayers({
  required BoardFamily? family,
  required Iterable<StubsProfileCandidate> candidates,
  required List<Map<String, String>> configuredLayers,
}) {
  if (family == null) return configuredLayers;
  final match = selectStubsProfileForFamily(family, candidates);
  if (match == null) return configuredLayers;
  return [match.toLayer()];
}
