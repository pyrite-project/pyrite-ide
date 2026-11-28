import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/utils/display_path.dart';

void main() {
  group('displayPathName', () {
    test('keeps only the last segment of an absolute path', () {
      expect(displayPathName(r'E:\python\projects\alpha\main.py'), 'main.py');
      expect(displayPathName('/home/kaixin/projects/main.py'), 'main.py');
    });

    test('handles board paths, which are always posix', () {
      expect(displayPathName('/lib/boot.py'), 'boot.py');
      expect(displayPathName('/boot.py'), 'boot.py');
    });

    test('ignores a trailing separator', () {
      expect(displayPathName(r'E:\python\projects\'), 'projects');
      expect(displayPathName('/lib/sub/'), 'sub');
    });

    test('a mixed-separator path still ends at its last name', () {
      expect(displayPathName(r'E:\project/src/main.py'), 'main.py');
    });

    test('leaves roots and empty values alone', () {
      expect(displayPathName('/'), '/');
      expect(displayPathName(r'C:\'), r'C:\');
      expect(displayPathName(''), '');
    });

    test('a bare name is already the answer', () {
      expect(displayPathName('main.py'), 'main.py');
    });
  });
}
