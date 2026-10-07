import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/workspace_lsp_config_pool.dart';

void main() {
  test('shares one config across acquires in the same workspace', () async {
    var creations = 0;
    final pool = WorkspaceLspConfigPool<String>(
      create: (workspace) async {
        creations++;
        return 'config:$workspace';
      },
    );

    final first = await pool.acquire('/ws');
    final second = await pool.acquire('/ws');

    expect(creations, 1);
    expect(first.created, isTrue);
    expect(second.created, isFalse);
    expect(second.config, same(first.config));
  });

  test('separate workspaces create separate configs', () async {
    final created = <String>[];
    final pool = WorkspaceLspConfigPool<String>(
      create: (workspace) async {
        created.add(workspace);
        return 'config:$workspace';
      },
    );

    final first = await pool.acquire('/ws-a');
    final second = await pool.acquire('/ws-b');

    expect(created, ['/ws-a', '/ws-b']);
    expect(second.config, isNot(same(first.config)));
  });

  test('concurrent acquires await one in-flight creation', () async {
    final completerCompleted = <bool>[];
    final pool = WorkspaceLspConfigPool<String>(
      create: (workspace) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        completerCompleted.add(true);
        return 'config:$workspace';
      },
    );

    final results = await Future.wait([
      pool.acquire('/ws'),
      pool.acquire('/ws'),
    ]);

    expect(completerCompleted.length, 1);
    expect(results[0].created, isTrue);
    expect(results[1].created, isFalse);
    expect(results[1].config, same(results[0].config));
  });

  test('evicts and evict-notifies after the last user releases', () async {
    final evicted = <String>[];
    var creations = 0;
    final pool = WorkspaceLspConfigPool<String>(
      create: (_) async {
        creations++;
        return 'config';
      },
      onEvict: evicted.add,
    );
    final first = await pool.acquire('/ws');
    final second = await pool.acquire('/ws');

    pool.release(first.config);
    expect(evicted, isEmpty);

    pool.release(second.config);
    expect(evicted, ['config']);

    // The evicted config is gone; the next acquire starts a fresh one.
    final third = await pool.acquire('/ws');
    expect(creations, 2);
    expect(third.created, isTrue);
  });

  test('a failed creation returns null and allows a retry', () async {
    var attempts = 0;
    final pool = WorkspaceLspConfigPool<String>(
      create: (_) async {
        attempts++;
        return attempts == 1 ? null : 'config';
      },
    );

    final failed = await pool.acquire('/ws');
    final retried = await pool.acquire('/ws');

    expect(failed.config, isNull);
    expect(failed.created, isFalse);
    expect(retried.config, 'config');
  });

  test('releasing an unknown or null config is a no-op', () async {
    final evicted = <String>[];
    final pool = WorkspaceLspConfigPool<String>(
      create: (_) async => 'config',
      onEvict: evicted.add,
    );
    // Seed the pool with one user before testing unknown-config releases.
    await pool.acquire('/ws');

    pool.release(null);
    pool.release('never-acquired');

    expect(evicted, isEmpty);
    // The pooled config still has its user, so re-acquiring does not create.
    final reacquired = await pool.acquire('/ws');
    expect(reacquired.created, isFalse);
    expect(reacquired.config, 'config');
  });
}
