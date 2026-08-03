import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../database/sync_service.dart';
import '../services/ble_service.dart';
import 'session_detail_screen.dart';
import 'lecturer_class_roster_screen.dart';
import 'lecturer_student_history_screen.dart';

class LecturerDashboard extends StatefulWidget {
  final int lecturerId;
  const LecturerDashboard({super.key, required this.lecturerId});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  int _currentIndex = 0;
  DateTime? _firstMonday;
  int _selectedWeek = 1;
  int _selectedDay = DateTime.now().weekday;
  int _totalWeeks = 16;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _lecturerCourses = [];

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredCourses = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  bool _isSearching = false;

  bool _isLoading = true;
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _initializeCalendar();
    _loadCourses();

    _syncService.pullFromCloud().then((_) {
      if (mounted) {
        _loadSessions();
        _loadCourses();
      }
    });

    BLEService().onStatusUpdate = () {
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

  Future<void> _loadCourses() async {
    final courses = await DatabaseHelper.instance.getLecturerCourses(widget.lecturerId);

    List<Map<String, dynamic>> coursesWithCount = [];
    for (var course in courses) {
      final roster = await DatabaseHelper.instance.getClassEnrollment(course['class_id']);
      coursesWithCount.add({
        ...course,
        'student_count': roster.length,
      });
    }

    if (mounted) {
      setState(() {
        _lecturerCourses = coursesWithCount;
        if (!_isSearching) {
          _filteredCourses = coursesWithCount;
        }
      });
    }
  }

  void _handleSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredCourses = _lecturerCourses;
        _filteredStudents = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    final results = await DatabaseHelper.instance.searchCoursesAndStudents(widget.lecturerId, query);
    
    if (mounted) {
      List<Map<String, dynamic>> searchedCourses = results['courses']!;
      List<Map<String, dynamic>> searchedCoursesWithCount = [];
      for (var c in searchedCourses) {
        final roster = await DatabaseHelper.instance.getClassEnrollment(c['class_id']);
        searchedCoursesWithCount.add({...c, 'student_count': roster.length});
      }

      setState(() {
        _filteredCourses = searchedCoursesWithCount;
        _filteredStudents = results['students']!;
      });
    }
  }

  Future<void> _initializeCalendar() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> classes = await db.query(
      'classes',
      where: 'lecturer_id = ?',
      whereArgs: [widget.lecturerId],
      limit: 1,
    );

    if (classes.isNotEmpty) {
      String semesterDateStr = classes.first['semester'];
      try {
        DateTime semesterDate = DateTime.parse(semesterDateStr);
        _firstMonday = semesterDate.subtract(Duration(days: semesterDate.weekday - 1));

        final maxDateStr = await DatabaseHelper.instance.getMaxSessionDate(widget.lecturerId);
        if (maxDateStr != null) {
          DateTime maxDate = DateTime.parse(maxDateStr);
          int diffDays = maxDate.difference(_firstMonday!).inDays;
          _totalWeeks = (diffDays / 7).ceil();
          if (_totalWeeks < 1) _totalWeeks = 1;
          if (_totalWeeks > 20) _totalWeeks = 20;
        }

        DateTime today = DateTime.now();
        if (today.isAfter(_firstMonday!)) {
          int diffDays = today.difference(_firstMonday!).inDays;
          _selectedWeek = (diffDays / 7).floor() + 1;
          if (_selectedWeek > _totalWeeks) _selectedWeek = _totalWeeks;
        }
      } catch (e) {
        print("Error parsing semester date: $e");
      }
    }
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    if (_currentIndex != 0) return;
    setState(() => _isLoading = true);
    
    if (_firstMonday != null) {
      DateTime targetDate = _firstMonday!.add(Duration(
        days: ((_selectedWeek - 1) * 7) + (_selectedDay - 1),
      ));
      String formattedDate = DateFormat('yyyy-MM-dd').format(targetDate);
      
      final sessions = await DatabaseHelper.instance.getSessionsByDate(widget.lecturerId, formattedDate);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Lecturer Schedule' : 'Lecturer Summary'),
        actions: [
          Row(
            children: [
              const Text("Demo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Switch(
                value: BLEService().isDemoMode,
                activeColor: Colors.orange,
                onChanged: (val) {
                  setState(() => BLEService().toggleDemoMode(val));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(val ? "⚡ Demo Mode: 1m Cycles" : "🕒 Production Mode: 20m Cycles"),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.sync), onPressed: () {
            _syncService.pullFromCloud().then((_) {
               _loadSessions();
               _loadCourses();
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
          else _loadCourses();
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
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                session['course_code'],
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                            ),
                            title: Text(session['course_name']),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${session['start_time']} - ${session['end_time']} | ${session['room_number']}"),
                                Text(
                                  "Date: ${session['session_date']}",
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SessionDetailScreen(session: session),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildMyCourses() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            onChanged: _handleSearch,
            decoration: InputDecoration(
              hintText: "Search course or student...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        
        Expanded(
          child: (_filteredCourses.isEmpty && _filteredStudents.isEmpty)
              ? const Center(child: Text("No courses or students found."))
              : ListView(
                  children: [
                    if (_filteredCourses.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
                        child: Text("COURSES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                      ),
                      ..._filteredCourses.map((course) => Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.book, color: Colors.blue),
                              title: Text("${course['course_code']}: ${course['course_name']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("Students: ${course['student_count'] ?? 0}"),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => LecturerClassRosterScreen(course: course)),
                                );
                              },
                            ),
                          )),
                    ],

                    if (_filteredStudents.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                        child: Text("STUDENTS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                      ),
                      ..._filteredStudents.map((student) => Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(child: Text(student['name'][0])),
                              title: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("ID: ${student['university_id']}"),
                              trailing: const Icon(Icons.history, color: Colors.orange),
                              onTap: () async {
                                final db = await DatabaseHelper.instance.database;
                                final courseResult = await db.rawQuery('''
                                  SELECT c.* FROM classes c 
                                  JOIN enrollment e ON c.class_id = e.class_id 
                                  WHERE e.student_id = ? LIMIT 1
                                ''', [student['user_id']]);

                                if (mounted && courseResult.isNotEmpty) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LecturerStudentHistoryScreen(
                                        studentId: student['user_id'],
                                        studentName: student['name'],
                                        course: courseResult.first,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          )),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
        ),
      ],
    );
  }
}
