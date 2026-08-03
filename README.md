# Attendance Management System (Bluetooth Low Energy & Dynamic QR)
Mobile Attendance Management System built for tertiary education institutions using Flutter, SQLite, and Firebase

## Key Features
1. Two-Phase Verification Logic
-Dynamic QR Code Check-In: Lecturers generate a time-sensitive Dynamic QR code that refreshes every 5 seconds to prevent screenshot sharing or off-site check-ins.
-Continuous Bluetooth Low Energy Proximity Tracking: Implements a cyclic Bluetooth Low Energy (BLE) engine (20-minute cycles: 10 min active / 10 min sleep) where the lecturer's phone acts as a beacon scanner to verify student physical presence and catch early leavers.

2. Offline-First Architecture: Using SQLite relational database the application is functional in lecture halls with unstable internet or poor signal coverage.

3. Cloud Synchronization: Automatically pushes local attendance logs to Firebase Cloud Firestore once an active network connection is detected.

4. Role-Based Workflows: Custom dashboards for both Lecturers (Session control, QR generation, manual status overrides, filtered search) and Students (QR scanner, attendance stats/percentages).

## Tech Stack & Tools
Frontend/Framework: Flutter (Dart)
Local Database: SQLite (via sqflite)
Cloud Services: Firebase (Authentication & Cloud Firestore)
Proximity & Hardware: Bluetooth Low Energy (flutter_blue_plus) & Camera/Barcode Scanner
Architecture: Rapid Application Development (RAD) Lifecycle Model

Developed by Maverick Chan as part of a Bachelor of Engineering in Software Engineering (Honours) Final Year Project at Xiamen University Malaysia, supervised by Dr. Geetha Kanaparan.
