import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/file/canonical_path.dart';

void main() {
  group('canonicalLocalPathFor (windows style)', () {
    test('uppercases a lowercase drive letter', () {
      expect(
        canonicalLocalPathFor(r'e:\project\foo.py', path.Style.windows),
        r'E:\project\foo.py',
      );
    });

    test('normalizes separators and dot segments', () {
      expect(
        canonicalLocalPathFor('e:/project/./sub/../foo.py', path.Style.windows),
        r'E:\project\foo.py',
      );
    });

    test('leaves an already-canonical path unchanged', () {
      expect(
        canonicalLocalPathFor(r'E:\project\foo.py', path.Style.windows),
        r'E:\project\foo.py',
      );
    });

    test(
      'leaves relative paths and UNC roots unchanged apart from segments',
      () {
        expect(canonicalLocalPathFor('foo.py', path.Style.windows), 'foo.py');
        expect(
          canonicalLocalPathFor(r'\\server\share\foo.py', path.Style.windows),
          r'\\server\share\foo.py',
        );
      },
    );
  });

  group('canonicalLocalPathFor (posix style)', () {
    test('never uppercases: posix paths are case-sensitive', () {
      expect(
        canonicalLocalPathFor('e:/project/foo.py', path.Style.posix),
        'e:/project/foo.py',
      );
      expect(
        canonicalLocalPathFor('/a/./b/../c.py', path.Style.posix),
        '/a/c.py',
      );
    });
  });

  test('canonicalLocalPath follows the host platform style', () {
    expect(canonicalLocalPath('./a/b.py'), path.normalize('./a/b.py'));
    if (path.Style.platform == path.Style.windows) {
      expect(canonicalLocalPath('e:/x.py'), r'E:\x.py');
    } else {
      expect(canonicalLocalPath('e:/x.py'), 'e:/x.py');
    }
  });

  group('openFileIdentityFor', () {
    // The resolver is injected so the symlink branch is covered without
    // needing one to exist on the host running the suite.
    String Function(String) resolveViaMap(Map<String, String> targets) =>
        (String p) => targets[p] ?? p;

    test('folds directory casing only when the host is case-insensitive', () {
      expect(
        openFileIdentityFor(
          r'C:\Users\Foo\a.py',
          path.Style.windows,
          caseInsensitive: true,
          resolveLinks: resolveViaMap(const {}),
        ),
        r'c:\users\foo\a.py',
      );
      expect(
        openFileIdentityFor(
          r'C:\Users\Foo\a.py',
          path.Style.windows,
          caseInsensitive: false,
          resolveLinks: resolveViaMap(const {}),
        ),
        r'C:\Users\Foo\a.py',
      );
    });

    test('a symlink and its target collapse onto one identity', () {
      final links = {r'C:\work\link\main.py': r'C:\work\real\main.py'};
      expect(
        openFileIdentityFor(
          r'C:\work\link\main.py',
          path.Style.windows,
          caseInsensitive: true,
          resolveLinks: resolveViaMap(links),
        ),
        openFileIdentityFor(
          r'C:\work\real\main.py',
          path.Style.windows,
          caseInsensitive: true,
          resolveLinks: resolveViaMap(links),
        ),
      );
    });

    test('different files keep different identities', () {
      final links = {r'C:\work\link\main.py': r'C:\work\real\main.py'};
      expect(
        openFileIdentityFor(
          r'C:\work\link\main.py',
          path.Style.windows,
          caseInsensitive: true,
          resolveLinks: resolveViaMap(links),
        ),
        isNot(
          openFileIdentityFor(
            r'C:\work\real\other.py',
            path.Style.windows,
            caseInsensitive: true,
            resolveLinks: resolveViaMap(links),
          ),
        ),
      );
    });

    test('posix keeps Foo.py and foo.py apart', () {
      expect(
        openFileIdentityFor(
          '/work/Foo.py',
          path.Style.posix,
          caseInsensitive: false,
          resolveLinks: resolveViaMap(const {}),
        ),
        isNot(
          openFileIdentityFor(
            '/work/foo.py',
            path.Style.posix,
            caseInsensitive: false,
            resolveLinks: resolveViaMap(const {}),
          ),
        ),
      );
    });
  });

  test('the real resolver leaves an unresolvable path on its lexical form', () {
    final missing = path.join(
      Directory.systemTemp.path,
      'pyrite_identity_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.py',
    );
    // Still canonical: the lexical normalization ran, plus case folding on a
    // case-insensitive host. Only the symlink hop was skipped.
    expect(
      openFileIdentity(missing),
      pathCaseInsensitive
          ? canonicalLocalPath(missing).toLowerCase()
          : canonicalLocalPath(missing),
    );
  });

  test('the real resolver collapses a symlink onto its target', () async {
    if (Platform.isWindows) {
      return; // Creating links needs elevation on Windows.
    }
    final root = await Directory.systemTemp.createTemp('pyrite_identity_');
    addTearDown(() => root.delete(recursive: true));
    final target = File(path.join(root.path, 'main.py'))
      ..writeAsStringSync('x = 1\n');
    final link = Link(path.join(root.path, 'alias.py'));
    await link.create(target.path);

    expect(openFileIdentity(link.path), openFileIdentity(target.path));
  });
}
