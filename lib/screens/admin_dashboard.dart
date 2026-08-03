import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _isUploading = false;
  String _statusMessage = "Select a CSV file to update class sessions.";

  Future<void> _pickAndUploadCsv() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String csvString = await file.readAsString();
        
        final List<List<dynamic>> fields = const CsvToListConverter().convert(csvString);

        if (fields.length <= 1) {
          setState(() => _statusMessage = "Error: CSV is empty.");
          return;
        }

        await _processCsvData(fields);
      }
    } catch (e) {
      setState(() => _statusMessage = "Error: $e");
    }
  }

  Future<void> _processCsvData(List<List<dynamic>> data) async {
    setState(() {
      _isUploading = true;
      _statusMessage = "Uploading...";
    });

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final rows = data.sublist(1);

    try {
      for (var row in rows) {
        if (row.length < 6) continue;
        String sid = row[0].toString();
        batch.set(firestore.collection('sessions').doc(sid), {
          'class_id': int.tryParse(row[1].toString()) ?? 0,
          'session_date': row[2].toString(),
          'start_time': row[3].toString(),
          'end_time': row[4].toString(),
          'room_number': row[5].toString(),
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      setState(() {
        _isUploading = false;
        _statusMessage = "Success! Cloud updated.";
      });
    } catch (e) {
      setState(() {
        _isUploading = false;
        _statusMessage = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.admin_panel_settings, size: 80, color: Colors.indigo),
            const Text('Importer', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(_statusMessage, textAlign: TextAlign.center),
            const Spacer(),
            if (_isUploading) const CircularProgressIndicator()
            else ElevatedButton(onPressed: _pickAndUploadCsv, child: const Text("Upload CSV")),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
