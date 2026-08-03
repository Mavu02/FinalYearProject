import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('attendance_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onConfigure: _onConfigure,
    );
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future _createDB(Database db, int version) async {
    const textType = 'TEXT NOT NULL';
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const syncType = 'INTEGER NOT NULL DEFAULT 0';
    const updateType = 'TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP';

    await db.execute('''
      CREATE TABLE departments (
        department_id $idType,
        department_name TEXT NOT NULL UNIQUE,
        last_updated $updateType
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
        user_id $idType,
        firebase_uid TEXT NOT NULL UNIQUE,
        university_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        role TEXT CHECK(role IN ('Student', 'Lecturer', 'Admin')) NOT NULL,
        last_updated $updateType
      )
    ''');

    await db.execute('''
      CREATE TABLE user_departments (
        user_id INTEGER NOT NULL,
        department_id INTEGER NOT NULL,
        PRIMARY KEY (user_id, department_id),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE classes (
        class_id $idType,
        lecturer_id INTEGER,
        course_name $textType,
        course_code $textType,
        semester $textType,
        last_updated $updateType,
        is_synced $syncType,
        FOREIGN KEY (lecturer_id) REFERENCES users(user_id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE class_departments (
        class_id INTEGER NOT NULL,
        department_id INTEGER NOT NULL,
        PRIMARY KEY (class_id, department_id),
        FOREIGN KEY (class_id) REFERENCES classes(class_id) ON DELETE CASCADE,
        FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE enrollment (
        enrollment_id $idType,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        last_updated $updateType,
        is_synced $syncType,
        FOREIGN KEY (student_id) REFERENCES users(user_id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes(class_id) ON DELETE CASCADE,
        UNIQUE(student_id, class_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        session_id TEXT PRIMARY KEY, 
        class_id INTEGER NOT NULL,
        session_date TEXT NOT NULL,   
        start_time TEXT NOT NULL,     
        end_time TEXT NOT NULL,       
        room_number TEXT,
        last_updated $updateType,
        is_synced $syncType,
        FOREIGN KEY (class_id) REFERENCES classes(class_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance (
        attendance_id TEXT PRIMARY KEY, 
        session_id TEXT NOT NULL,       
        student_id INTEGER NOT NULL,
        status TEXT CHECK(status IN ('Upcoming', 'Attending', 'Present', 'Absent', 'Late', 'Left Early', 'Excused')) NOT NULL DEFAULT 'Upcoming',
        qr_check_in_time TEXT,          
        verified_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_updated $updateType,
        is_synced $syncType,
        FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
        FOREIGN KEY (student_id) REFERENCES users(user_id) ON DELETE CASCADE,
        UNIQUE(session_id, student_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance_pings (
        ping_id $idType,
        session_id TEXT NOT NULL,       
        student_id INTEGER NOT NULL,
        ping_time TEXT NOT NULL,        
        is_synced $syncType,
        FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
        FOREIGN KEY (student_id) REFERENCES users(user_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE qr_codes (
        qr_id $idType,
        session_id TEXT NOT NULL,
        qr_content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE background_commands (
        command_id INTEGER PRIMARY KEY AUTOINCREMENT,
        command_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> queueBackgroundCommand(String type, Map<String, dynamic> payload) async {
    final db = await instance.database;
    await db.delete('background_commands'); 

    await db.insert('background_commands', {
      'command_type': type,
      'payload': jsonEncode(payload),
    });
  }

  Future<Map<String, dynamic>?> getNextBackgroundCommand() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> results = await db.query(
      'background_commands',
      orderBy: 'command_id ASC',
      limit: 1,
    );
    
    if (results.isNotEmpty) {
      final id = results.first['command_id'];
      final data = jsonDecode(results.first['payload']);
      await db.delete('background_commands', where: 'command_id = ?', whereArgs: [id]);
      return data;
    }
    return null;
  }

  Future<void> saveGeneratedQr(String sessionId, String content) async {
    final db = await instance.database;
    await db.insert('qr_codes', {
      'session_id': sessionId,
      'qr_content': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> verifyQrCode(String sessionId, String content) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> results = await db.query(
      'qr_codes',
      where: 'session_id = ? AND qr_content = ?',
      whereArgs: [sessionId, content],
    );
    return results.isNotEmpty;
  }

  Future<void> qrHandshake(String sessionId, int studentId, {String? checkInTime}) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    final timeToSave = checkInTime ?? now;

    final List<Map<String, dynamic>> existing = await db.query(
      'attendance',
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'attendance',
        {
          'status': 'Attending',
          'qr_check_in_time': timeToSave,
          'verified_at': now,
        },
        where: 'attendance_id = ?',
        whereArgs: [existing.first['attendance_id']],
      );
    } else {
      final uuid = const Uuid().v4();
      await db.insert('attendance', {
        'attendance_id': uuid,
        'session_id': sessionId,
        'student_id': studentId,
        'status': 'Attending',
        'qr_check_in_time': timeToSave,
        'verified_at': now,
      });
    }
  }

  Future<Map<String, int>> getSessionSummary(String sessionId) async {
    final db = await instance.database;

    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT status, COUNT(*) as count
      FROM attendance
      WHERE session_id = ?
      GROUP BY status
    ''', [sessionId]);

    Map<String, int> summary = {
      'Upcoming': 0,
      'Attending': 0,
      'Present': 0,
      'Late': 0,
      'Left Early': 0,
      'Absent': 0,
      'Excused': 0,
    };

    for (var row in results) {
      summary[row['status'] as String] = row['count'] as int;
    }

    return summary;
  }

  Future<List<Map<String, dynamic>>> getSessionsByDate(int lecturerId, String date) async {
    final db = await instance.database;
    final nowTime = DateFormat('HH:mm:ss').format(DateTime.now());
    final isToday = date == DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (isToday) {
      return await db.rawQuery('''
        SELECT s.*, c.course_name, c.course_code, c.semester
        FROM sessions s
        JOIN classes c ON s.class_id = c.class_id
        WHERE c.lecturer_id = ? AND s.session_date = ? AND s.end_time >= ?
        ORDER BY s.start_time ASC
      ''', [lecturerId, date, nowTime]);
    } else {
      return await db.rawQuery('''
        SELECT s.*, c.course_name, c.course_code, c.semester
        FROM sessions s
        JOIN classes c ON s.class_id = c.class_id
        WHERE c.lecturer_id = ? AND s.session_date = ?
        ORDER BY s.start_time ASC
      ''', [lecturerId, date]);
    }
  }

  Future<String?> getSemesterStartDate(int classId) async {
    final db = await instance.database;
    final result = await db.query(
      'classes',
      columns: ['semester'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    return result.isNotEmpty ? result.first['semester'] as String? : null;
  }

  Future<List<Map<String, dynamic>>> getSessionRoster(String sessionId, int classId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        u.name, 
        u.university_id, 
        u.user_id,
        COALESCE(a.status, 'Upcoming') as status,
        (SELECT COUNT(*) FROM attendance_pings p WHERE p.session_id = ? AND p.student_id = u.user_id) as ping_count
      FROM enrollment e
      JOIN users u ON e.student_id = u.user_id
      LEFT JOIN attendance a ON (e.student_id = a.student_id AND a.session_id = ?)
      WHERE e.class_id = ?
      ORDER BY u.name ASC
    ''', [sessionId, sessionId, classId]);
  }

  Future<String?> getMaxSessionDate(int lecturerId) async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT MAX(s.session_date) as maxDate 
      FROM sessions s
      JOIN classes c ON s.class_id = c.class_id
      WHERE c.lecturer_id = ?
    ''', [lecturerId]);
    return result.first['maxDate'] as String?;
  }

  Future<List<Map<String, dynamic>>> getStudentSessionsByDate(int studentId, String date) async {
    final db = await instance.database;
    final nowTime = DateFormat('HH:mm:ss').format(DateTime.now());
    final isToday = date == DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (isToday) {
      return await db.rawQuery('''
        SELECT 
          s.*, 
          c.course_name, 
          c.course_code, 
          c.semester,
          COALESCE(a.status, 'Upcoming') as status,
          (SELECT COUNT(*) FROM attendance_pings p WHERE p.session_id = s.session_id AND p.student_id = ?) as ping_count
        FROM enrollment e
        JOIN sessions s ON e.class_id = s.class_id
        JOIN classes c ON s.class_id = c.class_id
        LEFT JOIN attendance a ON (s.session_id = a.session_id AND a.student_id = ?)
        WHERE e.student_id = ? 
        AND s.session_date = ? 
        AND s.end_time >= ?
        ORDER BY s.start_time ASC
      ''', [studentId, studentId, studentId, date, nowTime]);
    } else {
      return await db.rawQuery('''
        SELECT 
          s.*, 
          c.course_name, 
          c.course_code, 
          c.semester,
          COALESCE(a.status, 'Upcoming') as status,
          (SELECT COUNT(*) FROM attendance_pings p WHERE p.session_id = s.session_id AND p.student_id = ?) as ping_count
        FROM enrollment e
        JOIN sessions s ON e.class_id = s.class_id
        JOIN classes c ON s.class_id = c.class_id
        LEFT JOIN attendance a ON (s.session_id = a.session_id AND a.student_id = ?)
        WHERE e.student_id = ? 
        AND s.session_date = ?
        ORDER BY s.start_time ASC
      ''', [studentId, studentId, studentId, date]);
    }
  }

  Future<String?> getStudentMaxSessionDate(int studentId) async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT MAX(s.session_date) as maxDate 
      FROM enrollment e
      JOIN sessions s ON e.class_id = s.class_id
      WHERE e.student_id = ?
    ''', [studentId]);
    return result.first['maxDate'] as String?;
  }

  Future<String?> getStudentMinSemesterDate(int studentId) async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT MIN(c.semester) as minSemester 
      FROM enrollment e
      JOIN classes c ON e.class_id = c.class_id
      WHERE e.student_id = ?
    ''', [studentId]);
    return result.first['minSemester'] as String?;
  }

  Future<Map<String, dynamic>?> getUserByFirebaseUid(String uid) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'firebase_uid = ?',
      whereArgs: [uid],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<Map<String, dynamic>?> getUserByUniversityId(String uniId) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'university_id = ?',
      whereArgs: [uniId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> getPingCount(String sessionId, int studentId) async {
    final db = await instance.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM attendance_pings 
      WHERE session_id = ? AND student_id = ?
    ''', [sessionId, studentId]);
    return result.first['count'] as int;
  }

  Future<List<Map<String, dynamic>>> getStudentEnrolledCourses(int studentId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT c.*, u.name as lecturer_name
      FROM enrollment e
      JOIN classes c ON e.class_id = c.class_id
      LEFT JOIN users u ON c.lecturer_id = u.user_id
      WHERE e.student_id = ?
      ORDER BY c.course_code ASC
    ''', [studentId]);
  }

  Future<List<Map<String, dynamic>>> getStudentSessionsByClass(int studentId, int classId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT 
        s.*, 
        COALESCE(a.status, 'Upcoming') as status
      FROM sessions s
      LEFT JOIN attendance a ON (s.session_id = a.session_id AND a.student_id = ?)
      WHERE s.class_id = ?
      ORDER BY s.session_date DESC, s.start_time DESC
    ''', [studentId, classId]);
  }

  Future<void> finalizeSessionAttendance(String sessionId, int totalExpectedCycles, {bool isEarlyEnd = false}) async {
    final db = await instance.database;

    final List<Map<String, dynamic>> students = await db.rawQuery('''
      SELECT u.user_id 
      FROM users u
      JOIN enrollment e ON u.user_id = e.student_id
      JOIN sessions s ON e.class_id = s.class_id
      WHERE s.session_id = ?
    ''', [sessionId]);

    for (var student in students) {
      int studentId = student['user_id'];

      final pingCountResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM attendance_pings WHERE session_id = ? AND student_id = ?',
        [sessionId, studentId]
      );
      int pingCount = pingCountResult.first['count'] as int;

      int denominator = isEarlyEnd ? (totalExpectedCycles - 1) : totalExpectedCycles;
      if (denominator < 1) denominator = 1;

      double percentage = (pingCount / denominator) * 100;
      String finalStatus = 'Absent';

      if (pingCount == 0) {
        finalStatus = 'Absent';
      } else if (percentage >= 50) {
        finalStatus = 'Present';
      } else {
        finalStatus = 'Left Early';
      }

      await db.insert('attendance', {
        'attendance_id': "${sessionId}_$studentId",
        'session_id': sessionId,
        'student_id': studentId,
        'status': finalStatus,
        'is_synced': 0,
        'last_updated': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, dynamic>> getCourseAttendanceStats(int studentId, int classId) async {
    final db = await instance.database;
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    final List<Map<String, dynamic>> concludedSessions = await db.rawQuery('''
      SELECT session_id FROM sessions
      WHERE class_id = ? 
      AND (session_date < ? OR (session_date = ? AND end_time <= ?))
    ''', [classId, dateStr, dateStr, timeStr]);

    if (concludedSessions.isEmpty) {
      return {'attended': 0, 'concluded': 0, 'percentage': 100.0};
    }

    int totalConcluded = concludedSessions.length;

    final List<Map<String, dynamic>> presentCount = await db.rawQuery('''
      SELECT COUNT(*) as count FROM attendance
      WHERE student_id = ? 
      AND session_id IN (
        SELECT session_id FROM sessions
        WHERE class_id = ? 
        AND (session_date < ? OR (session_date = ? AND end_time <= ?))
      )
      AND status = 'Present'
    ''', [studentId, classId, dateStr, dateStr, timeStr]);

    int totalPresent = presentCount.first['count'] as int;
    double percentage = (totalPresent / totalConcluded) * 100;

    return {
      'attended': totalPresent,
      'concluded': totalConcluded,
      'percentage': percentage
    };
  }

  Future<void> manuallyUpdateAttendance(String sessionId, int studentId, String newStatus) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();

    await db.insert('attendance', {
      'attendance_id': "${sessionId}_$studentId",
      'session_id': sessionId,
      'student_id': studentId,
      'status': newStatus,
      'is_synced': 0,
      'last_updated': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getStudentPingsForSession(String sessionId, int studentId) async {
    final db = await instance.database;
    return await db.query(
      'attendance_pings',
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
      orderBy: 'ping_time ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getLecturerCourses(int lecturerId) async {
    final db = await instance.database;
    return await db.query(
      'classes',
      where: 'lecturer_id = ?',
      whereArgs: [lecturerId],
      orderBy: 'course_code ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getClassEnrollment(int classId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT u.* 
      FROM users u
      JOIN enrollment e ON u.user_id = e.student_id
      WHERE e.class_id = ?
      ORDER BY u.name ASC
    ''', [classId]);
  }

  Future<Map<String, List<Map<String, dynamic>>>> searchCoursesAndStudents(int lecturerId, String query) async {
    final db = await instance.database;
    final String lowercaseQuery = "%${query.toLowerCase()}%";

    final List<Map<String, dynamic>> courses = await db.rawQuery('''
      SELECT * FROM classes 
      WHERE lecturer_id = ? 
      AND (LOWER(course_code) LIKE ? OR LOWER(course_name) LIKE ?)
    ''', [lecturerId, lowercaseQuery, lowercaseQuery]);

    final List<Map<String, dynamic>> students = await db.rawQuery('''
      SELECT DISTINCT u.* 
      FROM users u
      JOIN enrollment e ON u.user_id = e.student_id
      JOIN classes c ON e.class_id = c.class_id
      WHERE c.lecturer_id = ? 
      AND (LOWER(u.name) LIKE ? OR LOWER(u.university_id) LIKE ?)
    ''', [lecturerId, lowercaseQuery, lowercaseQuery]);

    return {
      'courses': courses,
      'students': students,
    };
  }

  Future<void> saveAttendancePing(String sessionId, int studentId) async {
    final db = await instance.database;
    await db.insert('attendance_pings', {
      'session_id': sessionId,
      'student_id': studentId,
      'ping_time': DateTime.now().toIso8601String(),
      'is_synced': 0,
    });
    await db.rawQuery("PRAGMA wal_checkpoint(FULL);");
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
