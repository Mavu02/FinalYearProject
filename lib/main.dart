import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/lecturer_dashboard.dart';
import 'screens/student_dashboard.dart';
import 'database/database_helper.dart';
import 'database/sync_service.dart';
import 'services/background_manager.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await PermissionService.checkAndRequestPermissions();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final notificationService = NotificationService();
  await notificationService.init();

  await BackgroundManager.initializeService();

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance Radar',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  StreamSubscription? _syncSubscription;
  bool _isWaitingForProfile = false;

  @override
  void initState() {
    super.initState();
    _syncSubscription = SyncService.onSyncCompleted.listen((_) {
      if (mounted && _isWaitingForProfile) {
        setState(() {
          _isWaitingForProfile = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: DatabaseHelper.instance.getUserByFirebaseUid(snapshot.data!.uid),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (userSnapshot.hasData && userSnapshot.data != null) {
                _isWaitingForProfile = false; // User record found, we are safe
                final role = userSnapshot.data!['role'];
                if (role == 'Lecturer') {
                  return LecturerDashboard(lecturerId: userSnapshot.data!['user_id']);
                } else {
                  return StudentDashboard(studentId: userSnapshot.data!['user_id']);
                }
              }

              _isWaitingForProfile = true;
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Preparing your dashboard...", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              );
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}
