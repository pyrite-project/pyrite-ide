import 'package:flutter/material.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/models/serial_port_descriptor.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

/// The device panel's serial ports as a sliver, one expandable row each.
class SerialPortList extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
        return _SerialPortTile(
          key: ValueKey(port.path),
          port: port,
          onConnect: onConnect,
          compact: compact,
        );
      },
    );
  }
}

class _SerialPortTile extends StatelessWidget {
  const _SerialPortTile({
    super.key,
    required this.port,
    required this.onConnect,
    required this.compact,
  });

  final SerialPortDescriptor port;
  final ValueChanged<String>? onConnect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final onConnect = this.onConnect;
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
      leading: Icon(port.isUsb ? Icons.usb : Icons.developer_board_outlined),
      title: Text(port.path),
      subtitle: Text(port.description),
      childrenPadding: EdgeInsetsDirectional.fromSTEB(
        16,
        0,
        16,
        compact ? 8 : 12,
      ),
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onConnect == null ? null : () => onConnect(port.path),
            icon: const Icon(Icons.power_settings_new),
            label: const UseText(I18nKey.devicesConnectSerial),
          ),
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
