import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import 'lecturer_student_history_screen.dart';

class LecturerClassRosterScreen extends StatefulWidget {
  final Map<String, dynamic> course;

  const LecturerClassRosterScreen({super.key, required this.course});

  @override
  State<LecturerClassRosterScreen> createState() => _LecturerClassRosterScreenState();
}

class _LecturerClassRosterScreenState extends State<LecturerClassRosterScreen> {
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    final roster = await DatabaseHelper.instance.getClassEnrollment(widget.course['class_id']);
    if (mounted) {
      setState(() {
        _students = roster;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Enrollment: ${widget.course['course_code']}"),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.course['course_name'],
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text("Total Enrolled: ${_students.length} Students"),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? const Center(child: Text("No students enrolled in this class."))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _students.length,
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text(student['name'][0])),
                              title: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("ID: ${student['university_id']}"),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => LecturerStudentHistoryScreen(
                                      studentId: student['user_id'],
                                      studentName: student['name'],
                                      course: widget.course,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
