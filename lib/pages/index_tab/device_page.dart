import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/pages/index_tab/device_qr_scan_page.dart'; // Updated import
import '../../l10n/app_localizations.dart';

// Placeholder for Device model, replace with actual model if available
class Device {
  final String name;
  Device(this.name);
}

class DevicePage extends StatelessWidget {
  static const sName = 'device'; // For named navigation

  const DevicePage({super.key});

  // Placeholder for device list, replace with actual data source
  final List<Device> devices = const []; // Start with an empty list

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myDevices)),
      body: devices.isEmpty
          ? Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  // Navigate to the QR code scanner page
                  // Ensure DeviceQrScanPage.sName is defined in your routes
                  context.goNamed(DeviceQrScanPage.sName);
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(l10n.scanQrToAddDevice),
              ),
            )
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return ListTile(
                  title: Text(device.name),
                  // Add more device details or actions here
                );
              },
            ),
    );
  }
}
