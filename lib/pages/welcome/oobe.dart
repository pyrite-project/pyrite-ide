import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:responsive_framework/responsive_framework.dart';

class WelcomeOobePage extends ConsumerStatefulWidget {
  const WelcomeOobePage({super.key});

  @override
  ConsumerState<WelcomeOobePage> createState() => _WelcomeOobePageState();
}

class _WelcomeOobePageState extends ConsumerState<WelcomeOobePage> {
  bool _checkingPermissions = false;
  bool _requestingPermissions = false;
  PermissionStatus? _storageStatus;
  PermissionStatus? _manageStorageStatus;
  PermissionStatus? _audioStatus;
  PermissionStatus? _videoStatus;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _refreshPermissions();
    }
  }

  Future<void> _refreshPermissions() async {
    setState(() => _checkingPermissions = true);
    final storage = await Permission.storage.status;
    final manageStorage = await Permission.manageExternalStorage.status;
    final audio = await Permission.audio.status;
    final video = await Permission.videos.status;
    if (!mounted) return;

    setState(() {
      _storageStatus = storage;
      _manageStorageStatus = manageStorage;
      _audioStatus = audio;
      _videoStatus = video;
      _checkingPermissions = false;
    });
  }

  Future<void> _requestAndroidPermissions() async {
    setState(() => _requestingPermissions = true);
    await [Permission.storage, Permission.audio, Permission.videos].request();
    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isPermanentlyDenied) {
      await openAppSettings();
    }
    if (!mounted) return;

    setState(() => _requestingPermissions = false);
    await _refreshPermissions();
  }

  Future<void> _complete() async {
    ref.read(welcomeCompletedProvider.notifier).state = true;
    await AppPersistence().save(
      AppPersistedData(
        themeMode: ref.read(themeMode).name,
        themeStyle: ref.read(themeStyle).value,
        themeColorValue: ref.read(themeColor)?.toARGB32(),
        editorThemeKey: ref.read(editorThemeKey),
        activePluginThemeId: ref.read(activePluginThemeId),
        welcomeCompleted: true,
      ),
    );
    if (!mounted) return;

    final target = ResponsiveBreakpoints.of(context).isDesktop
        ? '/file'
        : '/editor';
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/app_icon.webp',
                    width: 80,
                    height: 80,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '欢迎使用 PyriteIDE',
                    textAlign: TextAlign.center,
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (isAndroid) ...[
                    const SizedBox(height: 28),
                    _AndroidPermissionPanel(
                      checking: _checkingPermissions,
                      requesting: _requestingPermissions,
                      storageStatus: _storageStatus,
                      manageStorageStatus: _manageStorageStatus,
                      audioStatus: _audioStatus,
                      videoStatus: _videoStatus,
                      onRequest: _requestAndroidPermissions,
                      onRefresh: _refreshPermissions,
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _complete,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('开始'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AndroidPermissionPanel extends StatelessWidget {
  const _AndroidPermissionPanel({
    required this.checking,
    required this.requesting,
    required this.storageStatus,
    required this.manageStorageStatus,
    required this.audioStatus,
    required this.videoStatus,
    required this.onRequest,
    required this.onRefresh,
  });

  final bool checking;
  final bool requesting;
  final PermissionStatus? storageStatus;
  final PermissionStatus? manageStorageStatus;
  final PermissionStatus? audioStatus;
  final PermissionStatus? videoStatus;
  final VoidCallback onRequest;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Android 权限',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _PermissionRow(
              icon: Icons.folder_outlined,
              label: '文件读写',
              status: storageStatus,
            ),
            _PermissionRow(
              icon: Icons.folder_special_outlined,
              label: '所有文件访问',
              status: manageStorageStatus,
            ),
            _PermissionRow(
              icon: Icons.music_note_outlined,
              label: '音频媒体',
              status: audioStatus,
            ),
            _PermissionRow(
              icon: Icons.movie_outlined,
              label: '视频媒体',
              status: videoStatus,
            ),
            const _StaticPermissionRow(
              icon: Icons.usb,
              label: 'USB Host',
              value: '连接设备时授权',
            ),
            const _StaticPermissionRow(
              icon: Icons.public,
              label: '网络访问',
              value: '已由系统声明',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: requesting ? null : onRequest,
                  icon: requesting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(requesting ? '正在请求权限' : '设置权限'),
                ),
                OutlinedButton.icon(
                  onPressed: checking ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新状态'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.status,
  });

  final IconData icon;
  final String label;
  final PermissionStatus? status;

  @override
  Widget build(BuildContext context) {
    final granted = status?.isGranted == true || status?.isLimited == true;
    return _StaticPermissionRow(
      icon: icon,
      label: label,
      value: status == null ? '检查中' : (granted ? '已授权' : '未授权'),
      valueColor: granted
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error,
    );
  }
}

class _StaticPermissionRow extends StatelessWidget {
  const _StaticPermissionRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: valueColor ?? scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
