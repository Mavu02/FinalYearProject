import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/background_manager.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  StreamSubscription? _sessionSubscription;
  Function? onUpdate;

  static bool _isPulling = false;
  static DateTime? _lastPullTime;

  static final StreamController<void> _syncCompletedController = StreamController<void>.broadcast();
  static Stream<void> get onSyncCompleted => _syncCompletedController.stream;

  Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  void startCloudListener(int userId, String role, String? uniId, {Function? onUpdate}) {
    this.onUpdate = onUpdate;
    _sessionSubscription?.cancel();

    _sessionSubscription = _firestore.collection('sessions').snapshots().listen((snapshot) async {
      if (!await isOnline()) return;

      final db = await _dbHelper.database;
      final now = DateTime.now().toIso8601String();

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data()!;
          await db.insert('sessions', {
            'session_id': change.doc.id,
            'class_id': data['class_id'],
            'session_date': data['session_date'],
            'start_time': data['start_time'],
            'end_time': data['end_time'],
            'room_number': data['room_number'],
            'is_synced': 1,
            'last_updated': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else if (change.type == DocumentChangeType.removed) {
          await db.delete('sessions', where: 'session_id = ?', whereArgs: [change.doc.id]);
        }
      }

      print("[CLOUD] Cloud Update Processed.");

      if (this.onUpdate != null) {
        this.onUpdate!();
      }

      await BackgroundManager.scheduleNextSession(userId, role, uniId);
    });
  }

  void stopCloudListener() {
    _sessionSubscription?.cancel();
  }

  Future<void> pushToCloud() async {
    if (!await isOnline()) {
      print("[CLOUD] Offline. Push deferred.");
      return;
    }

    print("[CLOUD] Pushing local attendance to Firebase");
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> unsyncedAttendance = await db.query(
      'attendance',
      where: 'is_synced = 0',
    );

    for (var record in unsyncedAttendance) {
      String docId = "${record['session_id']}_${record['student_id']}";
      await _firestore.collection('attendance').doc(docId).set({
        ...record,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await db.update('attendance', {'is_synced': 1},
        where: 'attendance_id = ?', whereArgs: [record['attendance_id']]);
    }
    print("[CLOUD] Push Complete");
  }

  Future<void> pullFromCloud({bool force = false}) async {
    if (_isPulling) return;

    if (!force && _lastPullTime != null && 
        DateTime.now().difference(_lastPullTime!).inSeconds < 30) {
      print("[CLOUD] Pull throttled");
      return;
    }

    if (!await isOnline()) {
      print("[CLOUD] Offline. Pull deferred.");
      return;
    }

    _isPulling = true;
    print("[CLOUD] Pulling fresh data from Firebase");
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    try {
      final userSnapshot = await _firestore.collection('users').get();
      for (var doc in userSnapshot.docs) {
        final data = doc.data();
        await db.insert('users', {
          'user_id': data['user_id'],
          'firebase_uid': doc.id,
          'university_id': data['university_id'],
          'name': data['name'],
          'role': data['role'],
          'last_updated': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final classSnapshot = await _firestore.collection('classes').get();
      for (var doc in classSnapshot.docs) {
        final data = doc.data();
        final int classId = data['class_id'];
        await db.insert('classes', {
          'class_id': classId,
          'lecturer_id': data['lecturer_id'],
          'course_name': data['course_name'],
          'course_code': data['course_code'],
          'semester': data['semester'],
          'is_synced': 1,
          'last_updated': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        if (data['enrolled_student_ids'] != null) {
          List<dynamic> studentIds = data['enrolled_student_ids'];
          for (var studentId in studentIds) {
            await db.insert('enrollment', {'student_id': studentId, 'class_id': classId},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }

      final sessionSnapshot = await _firestore.collection('sessions').get();
      for (var doc in sessionSnapshot.docs) {
        final data = doc.data();
        await db.insert('sessions', {
          'session_id': doc.id,
          'class_id': data['class_id'],
          'session_date': data['session_date'],
          'start_time': data['start_time'],
          'end_time': data['end_time'],
          'room_number': data['room_number'],
          'is_synced': 1,
          'last_updated': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final attendanceSnapshot = await _firestore.collection('attendance').get();
      for (var doc in attendanceSnapshot.docs) {
        final data = doc.data();
        final String attendanceId = data['attendance_id'] ?? doc.id;

        final List<Map<String, dynamic>> local = await db.query(
          'attendance',
          where: 'attendance_id = ?',
          whereArgs: [attendanceId],
        );

        if (local.isNotEmpty && local.first['is_synced'] == 0) {
          print(" Sync Shield: Preserving local attendance for ${attendanceId}");
          continue;
        }

        await db.insert('attendance', {
          'attendance_id': attendanceId,
          'session_id': data['session_id'],
          'student_id': data['student_id'],
          'status': data['status'],
          'qr_check_in_time': data['qr_check_in_time'],
          'is_synced': 1,
          'last_updated': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      print("Pull Complete");
      _lastPullTime = DateTime.now();
      _syncCompletedController.add(null);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final localUser = await _dbHelper.getUserByFirebaseUid(user.uid);
        if (localUser != null) {
          await BackgroundManager.scheduleNextSession(localUser['user_id'], localUser['role'], localUser['university_id']);
        }
      }
    } catch (e) {
      print("[CLOUD] Pull Error: $e");
    } finally {
      _isPulling = false;
    }
  }
}


