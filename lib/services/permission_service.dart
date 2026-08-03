import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';

class PermissionService {
  static Future<void> checkAndRequestPermissions() async {
    List<Permission> permissions = [
      Permission.location,
      Permission.camera,
      Permission.notification,
      Permission.bluetooth,
    ];

    if (Platform.isAndroid) {
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.ignoreBatteryOptimizations,
      ]);
    }

    for (var permission in permissions) {
      if (await permission.isDenied || await permission.isPermanentlyDenied) {
        await permission.request();
      }
    }

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
      }
    }
  }
}
