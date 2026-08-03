import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../database/sync_service.dart';

import '../services/ble_service.dart';
import 'qr_scanner_screen.dart';
import 'student_course_sessions_screen.dart';

class StudentDashboard extends StatefulWidget {
  final int studentId;
  const StudentDashboard({super.key, required this.studentId});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  int _currentIndex = 0;
  DateTime? _firstMonday;
  int _selectedWeek = 1;
  int _selectedDay = DateTime.now().weekday;
  int _totalWeeks = 16;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _enrolledCourses = [];
  bool _isLoading = true;
  final SyncService _syncService = SyncService();
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initializeCalendar();
    _loadEnrolledCourses();

    _syncService.pullFromCloud().then((_) {
      if (mounted) {
        _loadSessions();
        _loadEnrolledCourses();
      }
    });

    BLEService().onHandshakeSuccess = () {
      if (mounted && _currentIndex == 0) {
        _loadSessions();
      }
    };
  }

  List<Map<String, dynamic>> _sortSessionsLooping(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return [];
    final nowTime = DateFormat('HH:mm:ss').format(DateTime.now());
    
    List<Map<String, dynamic>> ongoing = [];
    List<Map<String, dynamic>> future = [];
    List<Map<String, dynamic>> past = [];

    for (var s in sessions) {
      final startTime = s['start_time'];
      final endTime = s['end_time'];

      if (nowTime.compareTo(startTime) >= 0 && nowTime.compareTo(endTime) <= 0) {
        ongoing.add(s);
      } else if (startTime.compareTo(nowTime) > 0) {
        future.add(s);
      } else {
        past.add(s);
      }
    }
    return [...ongoing, ...future, ...past];
  }

  Future<void> _loadEnrolledCourses() async {
    final courses = await DatabaseHelper.instance.getStudentEnrolledCourses(widget.studentId);

    final List<Map<String, dynamic>> coursesWithStats = [];
    for (var course in courses) {
      final stats = await DatabaseHelper.instance.getCourseAttendanceStats(
        widget.studentId,
        course['class_id']
      );
      coursesWithStats.add({
        ...course,
        'stats': stats,
      });
    }

    if (mounted) {
      setState(() {
        _enrolledCourses = coursesWithStats;
      });
    }
  }

  Future<void> _initializeCalendar() async {
    final minSemesterStr = await DatabaseHelper.instance.getStudentMinSemesterDate(widget.studentId);
    
    if (minSemesterStr != null) {
      DateTime semesterDate = DateTime.parse(minSemesterStr);
      _firstMonday = semesterDate.subtract(Duration(days: semesterDate.weekday - 1));

      final maxDateStr = await DatabaseHelper.instance.getStudentMaxSessionDate(widget.studentId);
      if (maxDateStr != null) {
        DateTime maxDate = DateTime.parse(maxDateStr);
        int diffDays = maxDate.difference(_firstMonday!).inDays;
        _totalWeeks = (diffDays / 7).ceil();
        if (_totalWeeks < 1) _totalWeeks = 1;
      }

      DateTime today = DateTime.now();
      if (today.isAfter(_firstMonday!)) {
        int diffDays = today.difference(_firstMonday!).inDays;
        _selectedWeek = (diffDays / 7).floor() + 1;
        if (_selectedWeek > _totalWeeks) _selectedWeek = _totalWeeks;
      }
    }
    _loadSessions();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Present': return Colors.green;
      case 'Late': return Colors.orange;
      case 'Attending': return Colors.blue;
      case 'Left Early': return Colors.purple;
      case 'Absent': return Colors.red;
      default: return Colors.grey;
    }
  }

  Future<void> _loadSessions() async {
    if (_currentIndex != 0) return;
    setState(() => _isLoading = true);

    if (_firstMonday != null) {
      DateTime targetDate = _firstMonday!.add(Duration(
        days: ((_selectedWeek - 1) * 7) + (_selectedDay - 1),
      ));
      String formattedDate = DateFormat('yyyy-MM-dd').format(targetDate);

      final sessions = await DatabaseHelper.instance.getStudentSessionsByDate(widget.studentId, formattedDate);
      if (mounted) {
        setState(() {
          _sessions = _sortSessionsLooping(sessions);
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _calculateTotalSupposedPings(Map<String, dynamic> session) {
    try {
      DateTime start = DateFormat('HH:mm:ss').parse(session['start_time']);
      DateTime end = DateFormat('HH:mm:ss').parse(session['end_time']);
      int totalSecs = end.difference(start).inSeconds;
      int cycleSecs = BLEService().isDemoMode ? 60 : 1200;
      int total = (totalSecs / cycleSecs).ceil();
      return total > 0 ? total : 1;
    } catch (e) {
      return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Student Schedule' : 'Student Summary'),
        actions: [
          if (BLEService().isDemoMode)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Chip(
                label: Text("DEMO", style: TextStyle(fontSize: 10, color: Colors.white)),
                backgroundColor: Colors.orange,
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(icon: const Icon(Icons.sync), onPressed: () {
            _syncService.pullFromCloud().then((_) {
               _loadSessions();
               _loadEnrolledCourses();
            });
          }),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildDailySchedule(),
          _buildMyCourses(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) _loadSessions();
          else _loadEnrolledCourses();
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Schedule'),
          BottomNavigationBarItem(icon: Icon(Icons.summarize), label: 'Summary'),
        ],
      ),
    );
  }

  Widget _buildDailySchedule() {
    return Column(
      children: [
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _totalWeeks,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              int week = index + 1;
              bool isSelected = _selectedWeek == week;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Text("Week $week"),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedWeek = week);
                      _loadSessions();
                    }
                  },
                ),
              );
            },
          ),
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [1, 2, 3, 4, 5, 6, 7].map((day) {
            String name = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1];
            bool isSelected = _selectedDay == day;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedDay = day);
                _loadSessions();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  name.substring(0, 3),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const Divider(),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _sessions.isEmpty
                  ? const Center(child: Text("No classes scheduled for this day."))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      session['course_code'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      "Pings: ${session['ping_count']}/${_calculateTotalSupposedPings(session)}",
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(session['status']).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: _getStatusColor(session['status'])),
                                      ),
                                      child: Text(
                                        session['status'],
                                        style: TextStyle(
                                          color: _getStatusColor(session['status']),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  session['course_name'],
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(session['session_date'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text("${session['start_time']} - ${session['end_time']}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(session['room_number'] ?? 'TBA', style: const TextStyle(color: Colors.grey)),
                                    const Spacer(),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final user = await DatabaseHelper.instance.getUserByFirebaseUid(
                                          FirebaseAuth.instance.currentUser!.uid
                                        );
                                        if (user == null) return;

                                        final result = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => QRScannerScreen(
                                              session: session,
                                              studentId: widget.studentId,
                                              universityId: user['university_id'],
                                            ),
                                          ),
                                        );
                                        if (result == true) {
                                          _loadSessions();
                                        }
                                      },
                                      icon: const Icon(Icons.qr_code_scanner, size: 16),
                                      label: const Text("SCAN QR"),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildMyCourses() {
    return _enrolledCourses.isEmpty
        ? const Center(child: Text("You are not enrolled in any courses yet."))
        : ListView.builder(
            itemCount: _enrolledCourses.length,
            itemBuilder: (context, index) {
              final course = _enrolledCourses[index];
              final stats = course['stats'] ?? {'percentage': 0.0, 'attended': 0, 'concluded': 0};
              final double percentage = stats['percentage'] ?? 0.0;
              
              Color progressColor = Colors.red;
              if (percentage >= 80) {
                progressColor = Colors.green;
              } else if (percentage >= 70) {
                progressColor = Colors.orange;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.book, color: Colors.blue),
                  title: Text(
                    "${course['course_code']}: ${course['course_name']}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("Lecturer: ${course['lecturer_name'] ?? 'TBA'}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 45,
                        height: 45,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: percentage / 100,
                              backgroundColor: Colors.grey[200],
                              color: progressColor,
                              strokeWidth: 5,
                            ),
                            Text(
                              "${percentage.toInt()}%",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: progressColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StudentCourseSessionsScreen(
                          studentId: widget.studentId,
                          course: course,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
  }
}
