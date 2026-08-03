import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';

class StudentCourseSessionsScreen extends StatefulWidget {
  final int studentId;
  final Map<String, dynamic> course;

  const StudentCourseSessionsScreen({
    super.key,
    required this.studentId,
    required this.course,
  });

  @override
  State<StudentCourseSessionsScreen> createState() => _StudentCourseSessionsScreenState();
}

class _StudentCourseSessionsScreenState extends State<StudentCourseSessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessionHistory();
  }

  Future<void> _loadSessionHistory() async {
    final history = await DatabaseHelper.instance.getStudentSessionsByClass(
      widget.studentId,
      widget.course['class_id'],
    );
    if (mounted) {
      setState(() {
        _sessions = history;
        _isLoading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course['course_code']),
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
                Text("Lecturer: ${widget.course['lecturer_name'] ?? 'TBA'}"),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? const Center(child: Text("No sessions found for this course."))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final status = session['status'];
                          
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(status).withOpacity(0.2),
                                child: Icon(
                                  _getStatusIcon(status),
                                  color: _getStatusColor(status),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                DateFormat('EEEE, d MMMM yyyy').format(DateTime.parse(session['session_date'])),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text("${session['start_time']} - ${session['end_time']}"),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _getStatusColor(status)),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Present': return Icons.check_circle;
      case 'Absent': return Icons.cancel;
      case 'Upcoming': return Icons.access_time;
      case 'Attending': return Icons.wifi_tethering;
      case 'Left Early': return Icons.exit_to_app;
      default: return Icons.help_outline;
    }
  }
}
