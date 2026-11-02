import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void ensureFilePickerInitialized() {
  try {
    FilePicker.platform;
  } catch (_) {
    FilePickerIO.registerWith();
  }
}

Future<Uint8List?> capturePhotoFromWebcam(
  BuildContext context, {
  required String docLabel,
}) async {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Webcam capture is supported in the Web Admin Panel. Please use Upload File or Hard Copy Filed.'),
    ),
  );
  return null;
}
