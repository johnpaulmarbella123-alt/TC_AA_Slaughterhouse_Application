import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'document_upload_helper_stub.dart'
    if (dart.library.js_interop) 'document_upload_helper_web.dart';

class PickedDocumentResult {
  final String url;
  final String fileName;

  const PickedDocumentResult({
    required this.url,
    required this.fileName,
  });
}

class DocumentUploadHelper {
  static Future<PickedDocumentResult?> pickAndUpload(
    SupabaseClient supabase, {
    required String prefix,
  }) async {
    ensureFilePickerInitialized();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return null;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    return uploadBytes(
      supabase,
      bytes: bytes,
      ext: ext,
      prefix: prefix,
      fileName: file.name,
    );
  }

  static Future<PickedDocumentResult?> captureFromCameraAndUpload(
    BuildContext context,
    SupabaseClient supabase, {
    required String docLabel,
    required String prefix,
  }) async {
    final bytes = await capturePhotoFromWebcam(context, docLabel: docLabel);
    if (bytes == null) return null;

    return uploadBytes(
      supabase,
      bytes: bytes,
      ext: 'jpg',
      prefix: '${prefix}_cam',
      fileName: '${prefix}_camera.jpg',
    );
  }

  static Future<PickedDocumentResult> uploadBytes(
    SupabaseClient supabase, {
    required Uint8List bytes,
    required String ext,
    required String prefix,
    required String fileName,
  }) async {
    final contentType = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');
    final uid = supabase.auth.currentUser?.id ?? 'walk_in';
    final storagePath =
        '$uid/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    String resolvedUrl;
    try {
      await supabase.storage.from('request-documents').uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );
      try {
        resolvedUrl = await supabase.storage
            .from('request-documents')
            .createSignedUrl(storagePath, 60 * 60 * 24 * 30);
      } catch (_) {
        resolvedUrl =
            supabase.storage.from('request-documents').getPublicUrl(storagePath);
      }
    } catch (_) {
      resolvedUrl = 'data:$contentType;base64,${base64Encode(bytes)}';
    }

    return PickedDocumentResult(
      url: resolvedUrl,
      fileName: fileName,
    );
  }
}
