import 'package:pyrite_ide/core/models/editor.dart';
import 'package:tabbed_view/tabbed_view.dart';

void refreshFileTabTitles(Iterable<TabData> tabs) {
  final fileTabs = <TabData>[];
  final paths = <String>[];

  for (final tab in tabs) {
    final value = tab.value;
    if (value is! TabDataValue || value.type != 'file') continue;

    fileTabs.add(tab);
    final boardFilePath = value.boardFilePath;
    paths.add(
      value.isBoardFile == true &&
              boardFilePath != null &&
              boardFilePath.isNotEmpty
          ? boardFilePath
          : value.filePath,
    );
  }

  final titles = buildFileTabTitles(paths);
  for (var index = 0; index < fileTabs.length; index++) {
    fileTabs[index].text = titles[index];
  }
}

List<String> buildFileTabTitles(Iterable<String> paths) {
  final pathParts = paths.map(_FilePathParts.new).toList(growable: false);
  final titles = List<String>.filled(pathParts.length, '');
  final indexesByName = <String, List<int>>{};

  for (var index = 0; index < pathParts.length; index++) {
    indexesByName.putIfAbsent(pathParts[index].basename, () => []).add(index);
  }

  for (final indexes in indexesByName.values) {
    if (indexes.length == 1) {
      final index = indexes.single;
      titles[index] = pathParts[index].basename;
      continue;
    }

    final depths = <int, int>{
      for (final index in indexes)
        index: pathParts[index].segments.length < 2 ? 1 : 2,
    };

    while (true) {
      final indexesByTitle = <String, List<int>>{};
      for (final index in indexes) {
        final title = pathParts[index].suffix(depths[index]!);
        indexesByTitle.putIfAbsent(title, () => []).add(index);
      }

      var expanded = false;
      for (final collidingIndexes in indexesByTitle.values) {
        if (collidingIndexes.length < 2) continue;
        for (final index in collidingIndexes) {
          final depth = depths[index]!;
          if (depth < pathParts[index].segments.length) {
            depths[index] = depth + 1;
            expanded = true;
          }
        }
      }
      if (!expanded) break;
    }

    for (final index in indexes) {
      titles[index] = pathParts[index].suffix(depths[index]!);
    }
  }

  return titles;
}

class _FilePathParts {
  _FilePathParts(String path) : segments = _splitPath(path);

  final List<String> segments;

  String get basename {
    for (var index = segments.length - 1; index >= 0; index--) {
      if (segments[index].isNotEmpty) return segments[index];
    }
    return '';
  }

  String suffix(int depth) {
    if (segments.isEmpty) return '';
    final start = depth < segments.length ? segments.length - depth : 0;
    return segments.sublist(start).join('/');
  }

  static List<String> _splitPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    var rootSegmentCount = 0;
    while (rootSegmentCount < normalized.length &&
        normalized[rootSegmentCount] == '/' &&
        rootSegmentCount < 2) {
      rootSegmentCount++;
    }

    final segments = <String>[
      for (var index = 0; index < rootSegmentCount; index++) '',
    ];
    segments.addAll(
      normalized
          .substring(rootSegmentCount)
          .split('/')
          .where((segment) => segment.isNotEmpty),
    );
    return segments;
  }
}
