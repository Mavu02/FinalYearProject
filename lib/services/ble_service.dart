import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../database/database_helper.dart';
import '../database/sync_service.dart';

class BLEService {
  static final BLEService _instance = BLEService._();
  factory BLEService() => _instance;
  BLEService._();

  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";

  bool _isProcessRunning = false;
  bool _isHardwareBusy = false;

  bool isDemoMode = false;

  int get _cycleDuration => isDemoMode ? 30 : 1200;
  int get _activeWindow => isDemoMode ? 15 : 600;

  void toggleDemoMode(bool enabled) {
    isDemoMode = enabled;
    print("[BLE_ENGINE] Demo Mode: ${enabled ? 'ON (30s cycles)' : 'OFF (20m cycles)'}");
  }

  bool _isForceEnded = false;

  void stopCyclicProcess() {
    _isForceEnded = true;
    print("[BLE_ENGINE] FORCE END REQUESTED.");
  }

  int _calculateTotalExpectedCycles(DateTime start, DateTime end) {
    int totalSeconds = end.difference(start).inSeconds;
    int cycles = (totalSeconds / _cycleDuration).ceil();
    return cycles > 0 ? cycles : 1;
  }

  Future<void> startCyclicLecturerRadar(Map<String, dynamic> session) async {
    if (_isProcessRunning || _isHardwareBusy) return;
    _isProcessRunning = true;
    _isHardwareBusy = true;
    _isForceEnded = false;

    final String sessionId = session['session_id'];
    final DateTime sessionStart = DateFormat('yyyy-MM-dd HH:mm:ss').parse("${session['session_date']} ${session['start_time']}");
    final DateTime sessionEnd = DateFormat('yyyy-MM-dd HH:mm:ss').parse("${session['session_date']} ${session['end_time']}");

    final int totalScheduledCycles = _calculateTotalExpectedCycles(sessionStart, sessionEnd);
    print("[LECTURER] CLASS STARTED: $sessionId");
    await FlutterBackgroundService().startService();

    int cycleCount = 0;
    while (DateTime.now().isBefore(sessionEnd) && !_isForceEnded) {
      final now = DateTime.now();
      final int cycleOffset = now.difference(sessionStart).inSeconds % _cycleDuration;

      if (cycleOffset < _activeWindow) {
        cycleCount = (now.difference(sessionStart).inSeconds / _cycleDuration).floor() + 1;
        print("[LECTURER] CYCLE BEGINS: Active Window (Cycle: $cycleCount, Offset: $cycleOffset sec)");
        await startLecturerRadar(sessionId);

        final int remaining = _activeWindow - cycleOffset;
        final DateTime target = now.add(Duration(seconds: remaining));
        while (DateTime.now().isBefore(target) && !_isForceEnded) {
          await Future.delayed(const Duration(seconds: 1));
        }
        print("[LECTURER] CYCLE ENDS: Stopping Radar.");
        await stopLecturerRadar();
      } else {
        print("[LECTURER] SLEEP WINDOW: Waiting for next cycle...");
        final int remainingSleep = _cycleDuration - cycleOffset;
        final DateTime target = now.add(Duration(seconds: remainingSleep));
        while (DateTime.now().isBefore(target) && !_isForceEnded) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    print("[BLE_ENGINE] Class Concluded. Finalizing");
    
    if (_isForceEnded) {
      await DatabaseHelper.instance.finalizeSessionAttendance(sessionId, cycleCount, isEarlyEnd: true);
    } else {
      await DatabaseHelper.instance.finalizeSessionAttendance(sessionId, totalScheduledCycles);
    }
    
    await SyncService().pushToCloud();

    _isProcessRunning = false;
    _isHardwareBusy = false;
    FlutterBackgroundService().invoke('stopService');
  }

  Future<void> startCyclicStudentBeacon(Map<String, dynamic> session, String universityId, String qrData) async {
    if (_isProcessRunning || _isHardwareBusy) return;
    _isProcessRunning = true;
    _isHardwareBusy = true;
    _isForceEnded = false;

    final String sessionId = session['session_id'];
    final DateTime sessionStart = DateFormat('yyyy-MM-dd HH:mm:ss').parse("${session['session_date']} ${session['start_time']}");
    final DateTime sessionEnd = DateFormat('yyyy-MM-dd HH:mm:ss').parse("${session['session_date']} ${session['end_time']}");

    print("[STUDENT] BEACON START: $universityId for $sessionId");
    setScannedQr(qrData, sessionId);
    await FlutterBackgroundService().startService();

    while (DateTime.now().isBefore(sessionEnd) && !_isForceEnded) {
      final now = DateTime.now();
      final int cycleOffset = now.difference(sessionStart).inSeconds % _cycleDuration;

      if (cycleOffset < _activeWindow) {
        print("[STUDENT] CYCLE BEGINS: Active Window (Offset: $cycleOffset sec)");
        await startStudentBeacon(universityId, sessionId);

        final int remaining = _activeWindow - cycleOffset;
        final DateTime target = now.add(Duration(seconds: remaining));
        while (DateTime.now().isBefore(target) && !_isForceEnded) {
          await Future.delayed(const Duration(seconds: 1));
        }
        print("[STUDENT] CYCLE ENDS: Stopping Beacon & Listener.");
        await stopStudentBeacon();
      } else {
        print("[STUDENT] SLEEP WINDOW: Waiting for next cycle...");
        final int remainingSleep = _cycleDuration - cycleOffset;
        final DateTime target = now.add(Duration(seconds: remainingSleep));
        while (DateTime.now().isBefore(target) && !_isForceEnded) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    _isProcessRunning = false;
    _isHardwareBusy = false;
    FlutterBackgroundService().invoke('stopService');
  }

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Set<String> _caughtInCurrentCycle = {};
  final Set<String> _processingStudents = {};
  List<String> _ackList = [];

  Function? onStatusUpdate;

  Future<void> startLecturerRadar(String sessionId) async {
    _caughtInCurrentCycle.clear();
    _ackList.clear();

    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(
      timeout: Duration(seconds: _activeWindow),
      androidUsesFineLocation: true,
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    print("[LECTURER] BLE Scan Started.");

    await _updateLecturerEcho("INIT");

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String data = (_extractRawPayload(r) ?? "").trim();
        if (data.startsWith("STU-")) {
          print("[LECTURER] RAW PACKET: '$data' | RSSI: ${r.rssi} dBm");
          final parts = data.replaceFirst("STU-", "").split('|');
          String studentUniId = parts[0];

          if (_caughtInCurrentCycle.contains(studentUniId) || _processingStudents.contains(studentUniId)) {
            continue; 
          }

          _processingStudents.add(studentUniId);
          
          try {
            print("[LECTURER] Processing packet from: $studentUniId");
            bool isValid = await _processBroadcast(studentUniId, parts.length > 1 ? parts[1] : null, sessionId);

            if (isValid) {
              _caughtInCurrentCycle.add(studentUniId);
              _addToAckList(studentUniId);
              await _updateLecturerEcho("${_ackList.join(",")}|${DateTime.now().millisecondsSinceEpoch}");
              if (onStatusUpdate != null) onStatusUpdate!();
            }
          } finally {
            _processingStudents.remove(studentUniId);
          }
        }
      }
    });
  }

  void _addToAckList(String id) {
    if (!_ackList.contains(id)) {
      _ackList.insert(0, id);
      if (_ackList.length > 3) _ackList.removeLast();
    }
  }

  Future<void> _updateLecturerEcho(String payload) async {
    print("[LECTURER] Broadcasting ACK: $payload");
    try {
      final localPeripheral = FlutterBlePeripheral();
      final AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: serviceUuid,
        localName: "ACK",
        manufacturerId: 0xFFFF,
        manufacturerData: utf8.encode("ACK:$payload"),
      );
      await localPeripheral.stop();
      await Future.delayed(const Duration(milliseconds: 300));
      await localPeripheral.start(advertiseData: advertiseData);
    } catch (e) {
      print("[LECTURER] Echo Update Error: $e");
    }
  }

  String? _extractRawPayload(ScanResult r) {
    if (r.advertisementData.manufacturerData.isNotEmpty) {
      for (var entry in r.advertisementData.manufacturerData.values) {
        return utf8.decode(entry, allowMalformed: true);
      }
    }
    return null;
  }

  Future<bool> _processBroadcast(String studentUniId, String? qrPayload, String sessionId) async {
    final dbHelper = DatabaseHelper.instance;
    final user = await dbHelper.getUserByUniversityId(studentUniId);
    
    if (user == null) {
      print("[LECTURER] Unknown Student ID: $studentUniId");
      return false;
    }
    int studentId = user['user_id'];

    String? qrData;
    String? studentScanTimeStr;
    if (qrPayload != null && qrPayload.contains(';')) {
       final parts = qrPayload.split(';');
       qrData = parts[0];
       studentScanTimeStr = parts[1];
    } else {
       qrData = qrPayload;
    }

    if (qrData != null) {
      try {
        final isValidQr = await dbHelper.verifyQrCode(sessionId, qrData);
        if (isValidQr) {
          final List<Map<String, dynamic>> qrHistory = await (await dbHelper.database).query(
            'qr_codes', where: 'qr_content = ?', whereArgs: [qrData],
          );
          if (qrHistory.isNotEmpty) {
            DateTime genTime = DateTime.parse(qrHistory.first['created_at']);
            DateTime scanTime = studentScanTimeStr != null ? DateTime.parse(studentScanTimeStr) : DateTime.now();

            if (scanTime.difference(genTime).inSeconds.abs() > 5) {
               print("[LECTURER] QR EXPIRED for $studentUniId (Delay: ${scanTime.difference(genTime).inSeconds.abs()}s)");
               return false;
            }
          }
        } else {
           print("[LECTURER] QR Code not recognized for $studentUniId");
           return false;
        }
      } catch (e) {
        print("[LECTURER] Validation Exception for $studentUniId: $e");
        return false;
      }
    }

    await dbHelper.saveAttendancePing(sessionId, studentId);

    final db = await dbHelper.database;
    final List<Map<String, dynamic>> current = await db.query(
      'attendance',
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
    );

    if (current.isEmpty || current.first['status'] == 'Upcoming') {
       await dbHelper.qrHandshake(sessionId, studentId);
       print("[LECTURER] Status updated to Attending for $studentUniId");
    }
    
    return true;
  }

  Future<void> stopLecturerRadar() async {
    print("[LECTURER] Stopping Radar Scan & ACK Broadcast.");
    await FlutterBlePeripheral().stop();
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
  }

  StreamSubscription<List<ScanResult>>? _studentScanSub;
  bool _isConfirmed = false;
  String? _lastScannedQr;
  String? _scanTimestamp;
  int _beaconCycleStartTime = 0;
  Function? onHandshakeSuccess;

  void setScannedQr(String qrData, String sessionId) {
    _lastScannedQr = qrData;
    _scanTimestamp = DateTime.now().toIso8601String();
  }

  Future<void> startStudentBeacon(String universityId, String sessionId, {String? qrData}) async {
    _isConfirmed = false;
    _beaconCycleStartTime = DateTime.now().millisecondsSinceEpoch;
    if (qrData != null) setScannedQr(qrData, sessionId);

    await _updateStudentBeacon(universityId);

    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(
      timeout: Duration(seconds: _activeWindow),
      androidUsesFineLocation: true,
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    print("[STUDENT] Scanning for ACK (Cycle Start: $_beaconCycleStartTime)...");

    _studentScanSub?.cancel();
    _studentScanSub = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String data = _extractRawPayload(r) ?? "";
        if (data.contains(universityId)) {
          if (data.contains('|')) {
            int ackTime = int.tryParse(data.split('|').last) ?? 0;
            if (ackTime < _beaconCycleStartTime) {
              continue;
            }
          }
          
          print("[STUDENT] SUCCESS! Received Fresh ACK: $data");
          _handleSuccessFeedback(universityId, sessionId);
          break;
        }
      }
    });
  }

  Future<void> _updateStudentBeacon(String universityId) async {
    String payload = "STU-$universityId";
    if (_lastScannedQr != null) {
      payload += "|$_lastScannedQr;$_scanTimestamp";
    }
    
    try {
      final localPeripheral = FlutterBlePeripheral();
      final AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: serviceUuid,
        localName: "STU",
        manufacturerId: 0xFFFF,
        manufacturerData: utf8.encode(payload),
      );
      await localPeripheral.stop();
      await Future.delayed(const Duration(milliseconds: 300));
      await localPeripheral.start(advertiseData: advertiseData);
    } catch (e) {
      print("[STUDENT] Beacon Error: $e");
    }
  }

  void _handleSuccessFeedback(String universityId, String sessionId) async {
    if (_isConfirmed) return;
    _isConfirmed = true;
    print("[STUDENT] Handshake Complete. Stopping broadcast.");

    final user = await DatabaseHelper.instance.getUserByUniversityId(universityId);
    if (user != null) {
      final db = await DatabaseHelper.instance.database;
      await db.insert('attendance_pings', {
        'session_id': sessionId,
        'student_id': user['user_id'],
        'ping_time': DateTime.now().toIso8601String(),
        'is_synced': 0,
      });
      
      final List<Map<String, dynamic>> current = await db.query(
        'attendance',
        where: 'session_id = ? AND student_id = ?',
        whereArgs: [sessionId, user['user_id']],
      );
      if (current.isEmpty || current.first['status'] == 'Upcoming') {
        await DatabaseHelper.instance.qrHandshake(sessionId, user['user_id']);
      }
    }

    await FlutterBlePeripheral().stop();
    await FlutterBluePlus.stopScan();
    _studentScanSub?.cancel();
    
    if (onHandshakeSuccess != null) onHandshakeSuccess!();
  }

  Future<void> stopStudentBeacon() async {
    print("[STUDENT] Stopping Beacon & Scan.");
    await FlutterBlePeripheral().stop();
    await FlutterBluePlus.stopScan();
    _studentScanSub?.cancel();
  }
}
