import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../services/background_manager.dart';
import '../services/ble_service.dart';

class QRGeneratorScreen extends StatefulWidget {
  final Map<String, dynamic> session;

  const QRGeneratorScreen({
    super.key,
    required this.session,
  });

  @override
  State<QRGeneratorScreen> createState() => _QRGeneratorScreenState();
}

class _QRGeneratorScreenState extends State<QRGeneratorScreen> {
  String _qrData = "";
  Timer? _timer;
  int _secondsRemaining = 5;

  @override
  void initState() {
    super.initState();
    _generateNewQR();

    BLEService().startCyclicLecturerRadar(widget.session);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 1) {
          _secondsRemaining--;
        } else {
          _generateNewQR();
          _secondsRemaining = 5;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _generateNewQR() async {
    final String sessionId = widget.session['session_id'];
    final int classId = widget.session['class_id'];
    final data = {
      "s": sessionId,
      "c": classId,
      "t": DateTime.now().toIso8601String(),
      "d": BLEService().isDemoMode ? 1 : 0,
    };
    final String encodedData = jsonEncode(data);
    
    await DatabaseHelper.instance.saveGeneratedQr(sessionId, encodedData);
    
    if (mounted) {
      setState(() {
        _qrData = encodedData;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dynamic Attendance QR')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.session['course_name'] ?? "Class",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Show this to students. Refreshes every 5s.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrData,
                version: QrVersions.auto,
                size: 280.0,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'Next refresh in: $_secondsRemaining s',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.blue),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 50),
              ),
              child: const Text('Stop Generating'),
            ),
          ],
        ),
      ),
    );
  }
}
