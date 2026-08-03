import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../database/database_helper.dart';
import '../services/ble_service.dart';
import '../database/sync_service.dart';
import 'qr_generator_screen.dart';

class SessionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<Map<String, dynamic>> _roster = [];
  bool _isLoading = true;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadRoster();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadRoster());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRoster() async {
    final roster = await DatabaseHelper.instance.getSessionRoster(
      widget.session['session_id'],
      widget.session['class_id'],
    );
    if (mounted) {
      setState(() {
        _roster = roster;
        _isLoading = false;
      });
    }
  }

  int _calculateTotalSupposedPings() {
    try {
      DateTime start = DateFormat('HH:mm:ss').parse(widget.session['start_time']);
      DateTime end = DateFormat('HH:mm:ss').parse(widget.session['end_time']);
      int totalSecs = end.difference(start).inSeconds;
      
      int cycleSecs = BLEService().isDemoMode ? 60 : 1200;
      int total = (totalSecs / cycleSecs).ceil();
      return total > 0 ? total : 1;
    } catch (e) {
      return 1;
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

  Future<void> _showStatusPicker(Map<String, dynamic> student) async {
    final List<String> statuses = ['Present', 'Absent', 'Late', 'Excused', 'Left Early', 'Attending', 'Upcoming'];
    
    final String? selectedStatus = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Set Status for ${student['name']}"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: statuses.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(statuses[index]),
                onTap: () => Navigator.pop(context, statuses[index]),
              );
            },
          ),
        ),
      ),
    );

    if (selectedStatus != null) {
      await DatabaseHelper.instance.manuallyUpdateAttendance(
        widget.session['session_id'],
        student['user_id'],
        selectedStatus,
      );
      
      await SyncService().pushToCloud();
      
      _loadRoster(); 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Updated ${student['name']} to $selectedStatus")),
        );
      }
    }
  }

  Widget _buildStudentList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_roster.isEmpty) return const Center(child: Text("No students enrolled in this session."));

    int totalSupposed = _calculateTotalSupposedPings();

    return ListView.builder(
      itemCount: _roster.length,
      itemBuilder: (context, index) {
        final student = _roster[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ExpansionTile(
            leading: CircleAvatar(
              child: Text(student['name'][0]),
            ),
            title: Text("${student['name']} (${student['university_id']})", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Status: ${student['status']} | Pings: ${student['ping_count']}/$totalSupposed"),
            trailing: GestureDetector(
              onTap: () => _showStatusPicker(student),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(student['status']).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _getStatusColor(student['status'])),
                ),
                child: Text(
                  student['status'],
                  style: TextStyle(
                    color: _getStatusColor(student['status']),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            children: [
              FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper.instance.getStudentPingsForSession(
                  widget.session['session_id'],
                  student['user_id'],
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator());
                  final pings = snapshot.data!;
                  if (pings.isEmpty) return const ListTile(title: Text("No attendance pings received.", style: TextStyle(fontSize: 13, color: Colors.grey)));

                  return Container(
                    color: Colors.grey.withOpacity(0.05),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text("ATTENDANCE PINGS RECEIVED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        ...pings.map((p) {
                          DateTime time = DateTime.parse(p['ping_time']);
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                            title: Text(DateFormat('HH:mm:ss').format(time)),
                            subtitle: const Text("Verified BLE Handshake"),
                          );
                        }).toList(),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session['course_code']),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.blue.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.session['course_name'],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16),
                    const SizedBox(width: 4),
                    Text(widget.session['room_number'] ?? 'No Room'),
                    const Spacer(),
                    const Icon(Icons.access_time, size: 16),
                    const SizedBox(width: 4),
                    Text("${widget.session['start_time']} - ${widget.session['end_time']}"),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QRGeneratorScreen(
                          session: widget.session,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code),
                  label: const Text('GENERATE DYNAMIC QR'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    BLEService().startLecturerRadar(widget.session['session_id']);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('DEBUG: ECHO-RADAR Active (Scanning + Shouting ACKs)')),
                    );
                  },
                  icon: const Icon(Icons.radar),
                  label: const Text('DEBUG: FORCE ECHO RADAR'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("End Class Early?"),
                        content: const Text("This will stop the BLE radar and calculate attendance based on pings received so far."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("End Class", style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      BLEService().stopCyclicProcess();

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Class ended early. Calculating final attendance...')),
                      );
                    }
                  },
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('END CLASS EARLY'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text("STUDENT ROSTER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Spacer(),
              ],
            ),
          ),

          Expanded(child: _buildStudentList()),
        ],
      ),
    );
  }
}
