import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';

class LecturerStudentHistoryScreen extends StatefulWidget {
  final int studentId;
  final String studentName;
  final Map<String, dynamic> course;

  const LecturerStudentHistoryScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.course,
  });

  @override
  State<LecturerStudentHistoryScreen> createState() => _LecturerStudentHistoryScreenState();
}

class _LecturerStudentHistoryScreenState extends State<LecturerStudentHistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
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
      case 'Excused': return Colors.grey;
      default: return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studentName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              "${widget.course['course_code']} Attendance History",
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(child: Text("No session records found."))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    final status = session['status'];
                    return Card(
                      child: ListTile(
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
    );
  }
}
