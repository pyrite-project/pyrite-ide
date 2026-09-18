import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pending file providers lifecycle', () {
    const path = '/tmp/project/main.py';

    test('ensure creates both upload and download entries', () {
      ensurePendingFileProviders(path);
      addTearDown(() => releasePendingFileProviders(path));
      expect(pendingUploadProviderMap.containsKey(path), isTrue);
      expect(pendingDownloadProviderMap.containsKey(path), isTrue);
    });

    test('ensure is idempotent: existing providers are kept', () {
      ensurePendingFileProviders(path);
      addTearDown(() => releasePendingFileProviders(path));
      final StateProvider<PendingUpload?> original =
          pendingUploadProviderMap[path]!;
      ensurePendingFileProviders(path);
      expect(identical(pendingUploadProviderMap[path], original), isTrue);
    });

    test('release drops the entries so closed tabs do not accumulate', () {
      ensurePendingFileProviders(path);
      releasePendingFileProviders(path);
      expect(pendingUploadProviderMap.containsKey(path), isFalse);
      expect(pendingDownloadProviderMap.containsKey(path), isFalse);
    });
  });
}
