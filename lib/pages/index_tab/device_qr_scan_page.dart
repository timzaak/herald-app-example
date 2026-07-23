import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:app/api/dio_util.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class DeviceQrScanPage extends StatefulWidget {
  static const sName = 'device_qr_scan'; // For named navigation

  const DeviceQrScanPage({super.key});

  @override
  State<DeviceQrScanPage> createState() => _DeviceQrScanPageState();
}

class _DeviceQrScanPageState extends State<DeviceQrScanPage> {
  MobileScannerController controller = MobileScannerController();
  bool _isProcessing = false;
  // final Dio _dio = Dio(); // Removed local Dio instance

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _bindDevice(String qrCodeContent) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });
    SmartDialog.showLoading(msg: 'Binding device...');

    try {
      final response = await DioUtil.dio.post(
        // Used DioUtil
        'https://www.example.com/device/bind/qr_code',
        data: {'qrcode': qrCodeContent},
      );

      SmartDialog.dismiss();

      if (response.statusCode == 200) {
        // Assuming a successful response means binding was successful
        SmartDialog.showToast('Device bound successfully!');
        // Navigate back to DevicePage and trigger a refresh
        // This might involve passing a parameter or using a state management solution
        // For now, just pop. A proper refresh mechanism should be added.
        if (mounted) {
          context.pop(true); // Pass true to indicate success / need for refresh
        }
      } else {
        SmartDialog.showToast(
          'Failed to bind device: ${response.statusMessage}',
        );
      }
    } on DioException catch (e) {
      SmartDialog.dismiss();
      String errorMessage = 'Failed to bind device.';
      if (e.response != null) {
        errorMessage +=
            ' Server error: ${e.response?.statusCode} ${e.response?.statusMessage}';
      } else {
        errorMessage += ' Network error: ${e.message}';
      }
      SmartDialog.showToast(errorMessage);
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (_isProcessing) return; // Don't process if already processing

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                final String code = barcodes.first.rawValue!;
                debugPrint('QR Code detected: $code');
                _bindDevice(code);
              }
            },
          ),
          // Optional: Add a viewfinder overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 4),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_isProcessing) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
