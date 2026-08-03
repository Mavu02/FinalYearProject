import 'dart:async';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import 'ble_service.dart';
import 'notification_service.dart';
@pragma('vm:entry-point')
void warningAlarmCallback(int id, Map<String, dynamic> data) async {
  print("[ALARM] Warning Alarm Fired! ID: $id");
  try {
    final service = NotificationService();
    await service.init();
    await service.showNotification(
      id: id,
      title: 'Class Starting Soon',
      body: 'Ensure Bluetooth and Location are ON for attendance tracking.',
    );
  } catch (e) {
    print("[ALARM] Warning Notification Error: $e");
  }
}

@pragma('vm:entry-point')
void startRadarAlarmCallback(int id, Map<String, dynamic> data) async {
  print("[ALARM] Start Radar Alarm Fired! ID: $id");
  try {
    await DatabaseHelper.instance.queueBackgroundCommand('startRadar', data);
    print("[ALARM] Command queued in SQLite.");

    final service = FlutterBackgroundService();
    await service.startService();
  } catch (e) {
    print("[ALARM] Start Radar Callback Error: $e");
  }
}

@pragma('vm:entry-point')
class BackgroundManager {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'fyp_attendance_channel',
        initialNotificationTitle: 'Attendance Radar',
        initialNotificationContent: 'Monitoring classroom presence...',
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async => true;

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    print("[BG_SERVICE] Life-Support Service AWOKEN!");
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
    
    service.on('stopProcess').listen((event) {
      BLEService().stopCyclicProcess();
    });

    service.on('stopService').listen((event) {
      print("[BG_SERVICE] Stop signal received.");
      BLEService().stopCyclicProcess();
      service.stopSelf();
    });
  }

  static Future<void> startManualRadar(Map<String, dynamic> session, String role) async {
    print("[SCHEDULER] Manual Trigger: Starting Radar for ${session['session_id']}");
    final params = {
      'sessionId': session['session_id'],
      'role': role,
      'uniId': null,
      'sessionDate': session['session_date'],
      'startTime': session['start_time'],
      'endTime': session['end_time'],
    };

    await FlutterBackgroundService().startService();
  }

  static Future<void> startManualBeacon(Map<String, dynamic> session, String role, String uniId, String qrData) async {
    print("[SCHEDULER] Manual Trigger: Starting Beacon for ${session['session_id']}");

    await FlutterBackgroundService().startService();
  }

  static Future<void> scheduleNextSession(int userId, String role, String? uniId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    final List<Map<String, dynamic>> sessions = await db.rawQuery('''
      SELECT * FROM sessions 
      WHERE (session_date = ? AND start_time > ?) 
         OR (session_date > ?)
      ORDER BY session_date ASC, start_time ASC
      LIMIT 1
    ''', [dateStr, timeStr, dateStr]);

    if (sessions.isNotEmpty) {
      final session = sessions.first;
      final sessionId = session['session_id'];
      
      DateTime startTime = DateFormat('yyyy-MM-dd HH:mm:ss').parse("${session['session_date']} ${session['start_time']}");
      DateTime warningTime = startTime.subtract(const Duration(minutes: 5));

      final Map<String, dynamic> alarmParams = {
        'sessionId': sessionId,
        'role': role,
        'uniId': uniId,
        'sessionDate': session['session_date'],
        'startTime': session['start_time'],
        'endTime': session['end_time'],
      };

      if (warningTime.isAfter(now)) {
        await AndroidAlarmManager.oneShotAt(
          warningTime, 100 + sessionId.hashCode, warningAlarmCallback,
          exact: true, wakeup: true, params: alarmParams,
        );
        print("[SCHEDULER] Warning Alarm scheduled for $warningTime");
      }
    }
  }
}
