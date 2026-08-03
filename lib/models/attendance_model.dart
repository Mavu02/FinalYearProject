class Attendance {
  final String attendanceId;
  final String sessionId;
  final int studentId;
  final String status;
  final String? qrCheckInTime;
  final String? verifiedAt;

  Attendance({
    required this.attendanceId,
    required this.sessionId,
    required this.studentId,
    required this.status,
    this.qrCheckInTime,
    this.verifiedAt,
  });

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      attendanceId: map['attendance_id'],
      sessionId: map['session_id'],
      studentId: map['student_id'],
      status: map['status'],
      qrCheckInTime: map['qr_check_in_time'],
      verifiedAt: map['verified_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'attendance_id': attendanceId,
      'session_id': sessionId,
      'student_id': studentId,
      'status': status,
      'qr_check_in_time': qrCheckInTime,
      'verified_at': verifiedAt,
    };
  }

  bool get isCurrentlyAttending => status == 'Attending';
  bool get hasArrived => status != 'Upcoming';
}
