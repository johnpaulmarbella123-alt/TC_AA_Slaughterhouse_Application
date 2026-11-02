import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
// ignore: implementation_imports
import 'package:file_picker/_internal/file_picker_web.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

void ensureFilePickerInitialized() {
  try {
    FilePicker.platform;
  } catch (_) {
    FilePickerWeb.registerWith(Registrar());
  }
}

Future<Uint8List?> capturePhotoFromWebcam(
  BuildContext context, {
  required String docLabel,
}) async {
  web.MediaStream? stream;
  try {
    stream = await web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
        .toDart;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not access camera ($e). Please allow camera permission or use "Upload File" / "Hard Copy Filed".',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
    return null;
  }

  final video = web.document.createElement('video') as web.HTMLVideoElement
    ..autoplay = true
    ..muted = true
    ..srcObject = stream;

  try {
    await video.play().toDart;
  } catch (_) {}

  final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
  Uint8List? previewFrame;
  Timer? frameTimer;

  Uint8List? grabFrame({double quality = 0.85}) {
    final w = video.videoWidth > 0 ? video.videoWidth : 640;
    final h = video.videoHeight > 0 ? video.videoHeight : 480;
    canvas.width = w;
    canvas.height = h;
    final ctx2d = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx2d == null) return null;
    ctx2d.drawImage(video, 0, 0, w.toDouble(), h.toDouble());
    final dataUrl = canvas.toDataUrl('image/jpeg', quality);
    final commaIdx = dataUrl.indexOf(',');
    if (commaIdx == -1) return null;
    return base64Decode(dataUrl.substring(commaIdx + 1));
  }

  void stopStream() {
    frameTimer?.cancel();
    try {
      final tracks = stream?.getTracks().toDart ?? <web.MediaStreamTrack>[];
      for (final t in tracks) {
        t.stop();
      }
    } catch (_) {}
  }

  if (!context.mounted) {
    stopStream();
    return null;
  }

  final captured = await showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      bool timerStarted = false;
      return StatefulBuilder(
        builder: (ctx, setDlgState) {
          if (!timerStarted) {
            timerStarted = true;
            frameTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
              if (!ctx.mounted) {
                frameTimer?.cancel();
                return;
              }
              final bytes = grabFrame(quality: 0.7);
              if (bytes != null) {
                setDlgState(() => previewFrame = bytes);
              }
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Color(0xFF2D6A4F), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Capture Hard Copy — $docLabel',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A202C),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          stopStream();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Hold the physical document clearly in front of the camera and click "Capture & Attach".',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF718096)),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 320,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A202C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: previewFrame != null
                        ? Image.memory(
                            previewFrame!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 12),
                                Text(
                                  'Starting camera preview...',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          stopStream();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: previewFrame == null
                            ? null
                            : () {
                                final hiRes = grabFrame(quality: 0.92) ?? previewFrame;
                                stopStream();
                                Navigator.pop(ctx, hiRes);
                              },
                        icon: const Icon(Icons.camera, size: 18),
                        label: const Text('Capture & Attach'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  stopStream();
  return captured;
}
