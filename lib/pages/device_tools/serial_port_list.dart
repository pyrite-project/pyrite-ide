import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/core/services/serial/serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/serial_session_registry.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

/// The device panel's serial ports as a sliver, one expandable row each.
///
/// A row is either offering to connect its port or showing the session that
/// already holds it: an open port can be switched to or disconnected without
/// dropping the other boards.
class SerialPortList extends ConsumerWidget {
  const SerialPortList({
    super.key,
    required this.ports,
    required this.onConnect,
    this.compact = false,
  });

  final List<SerialPortDescriptor> ports;

  /// Null disables connecting, e.g. while a WebREPL session is active.
  final ValueChanged<String>? onConnect;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the notifier so session changes rebuild the rows; the registry
    // itself is not part of the provider's state.
    ref.watch(serialProvider);
    final sessions = ref.read(serialProvider.notifier).sessions.sessions;
    return SliverList.builder(
      itemCount: ports.length,
      // Rows are keyed by path so an expanded row stays expanded while the
      // filter reorders or narrows the list.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = ports.indexWhere((port) => port.path == key.value);
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index) {
        final port = ports[index];
        final session = sessions
            .where((item) => item.portPath == port.path)
            .firstOrNull;
        return _SerialPortTile(
          key: ValueKey(port.path),
          port: port,
          session: session,
          onConnect: onConnect,
          compact: compact,
        );
      },
    );
  }
}

class _SerialPortTile extends ConsumerWidget {
  const _SerialPortTile({
    super.key,
    required this.port,
    required this.session,
    required this.onConnect,
    required this.compact,
  });

  final SerialPortDescriptor port;
  final SerialSession? session;
  final ValueChanged<String>? onConnect;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onConnect = this.onConnect;
    final session = this.session;
    final isActive = session?.isActive ?? false;
    final details = <(I18nKey, String?)>[
      (I18nKey.devicesDetailDescription, port.description),
      (I18nKey.devicesDetailHwid, port.hwid),
      (I18nKey.devicesDetailVidPid, port.vidPid),
      (I18nKey.devicesDetailSerialNumber, port.serialNumber),
      (I18nKey.devicesDetailManufacturer, port.manufacturer),
      (I18nKey.devicesDetailProduct, port.product),
      (I18nKey.devicesDetailInterface, port.interface),
      (I18nKey.devicesDetailLocation, port.location),
    ];
    return ExpansionTile(
      visualDensity: compact ? VisualDensity.compact : null,
      leading: Icon(
        isActive
            ? Icons.check_circle
            : session != null
            ? Icons.usb
            : port.isUsb
            ? Icons.usb
            : Icons.developer_board_outlined,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(port.path),
      subtitle: Text(
        isActive
            ? translateInContext(context, I18nKey.devicesSessionActive)
            : session != null
            ? translateInContext(context, I18nKey.devicesSessionInactive)
            : port.description,
      ),
      childrenPadding: EdgeInsetsDirectional.fromSTEB(
        16,
        0,
        16,
        compact ? 8 : 12,
      ),
      children: [
        if (session == null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onConnect == null ? null : () => onConnect(port.path),
              icon: const Icon(Icons.power_settings_new),
              label: const UseText(I18nKey.devicesConnectSerial),
            ),
          )
        else
          // The port is already open. Connecting it again would only switch to
          // it, so the two actions are labelled for what they do instead of
          // offering "connect" a second time.
          Row(
            children: [
              if (!isActive)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(serialProvider.notifier)
                        .activateSession(session.id),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(
                      translateInContext(context, I18nKey.devicesSessionSwitch),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      translateInContext(context, I18nKey.devicesSessionInUse),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(serialProvider.notifier)
                    .closeSessionFor(port.path),
                icon: const Icon(Icons.link_off),
                label: Text(
                  translateInContext(context, I18nKey.devicesSessionDisconnect),
                ),
              ),
            ],
          ),
        for (final (label, value) in details)
          if (value != null && value.isNotEmpty)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: SelectableText(value),
              subtitle: UseText(label),
            ),
      ],
    );
  }
}
