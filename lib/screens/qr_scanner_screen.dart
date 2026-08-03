import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../database/database_helper.dart';
import '../services/ble_service.dart';

class QRScannerScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  final int studentId;
  final String universityId;

  const QRScannerScreen({
    super.key,
    required this.session,
    required this.studentId,
    required this.universityId,
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isScanning = true;

  void _handleCapture(BarcodeCapture capture) async {
    if (!_isScanning) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null) return;

    setState(() => _isScanning = false);

    try {
      final Map<String, dynamic> data = jsonDecode(code);
      final String scannedSessionId = data['s'];
      final bool isLecturerInDemoMode = data['d'] == 1;

      if (scannedSessionId != widget.session['session_id']) {
        _showError("Invalid QR: This code is for a different class.");
        return;
      }

      BLEService().toggleDemoMode(isLecturerInDemoMode);

      BLEService().setScannedQr(code, widget.session['session_id']);

      BLEService().startCyclicStudentBeacon(
        widget.session, 
        widget.universityId,
        code
      );
      
      await DatabaseHelper.instance.qrHandshake(widget.session['session_id'], widget.studentId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR Attendance Recorded!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError("Invalid QR Format");
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
      setState(() => _isScanning = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Class QR')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _handleCapture,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.black54,
                child: const Text(
                  'Center the QR code in the box',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
