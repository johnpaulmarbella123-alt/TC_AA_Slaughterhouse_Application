import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external factory _AudioContext();
  external JSObject get destination;
  external double get currentTime;
  external String get state;
  external JSPromise resume();
  external _OscillatorNode createOscillator();
  external _GainNode createGain();
}

@JS()
extension type _OscillatorNode._(JSObject _) implements JSObject {
  external set type(String value);
  external _AudioParam get frequency;
  external void connect(JSObject destination);
  external void start([double when]);
  external void stop([double when]);
}

@JS()
extension type _GainNode._(JSObject _) implements JSObject {
  external _AudioParam get gain;
  external void connect(JSObject destination);
}

@JS()
extension type _AudioParam._(JSObject _) implements JSObject {
  external void setValueAtTime(double value, double startTime);
  external void exponentialRampToValueAtTime(double value, double endTime);
}

_AudioContext? _sharedCtx;

/// Synthesizes a clean two-tone bell chime (A5 -> D6) via Web Audio API.
void playNotificationBellChimeImpl() {
  try {
    final hasAudioCtx = globalContext.has('AudioContext');
    if (!hasAudioCtx) return;

    _sharedCtx ??= _AudioContext();
    final ctx = _sharedCtx!;
    if (ctx.state == 'suspended') {
      ctx.resume();
    }

    final now = ctx.currentTime;
    _playTone(ctx, freq: 880.0, startTime: now, duration: 0.22, peakGain: 0.16);
    _playTone(ctx, freq: 1174.66, startTime: now + 0.14, duration: 0.35, peakGain: 0.18);
  } catch (_) {
    // Ignore autoplay/browser audio restrictions quietly.
  }
}

void _playTone(
  _AudioContext ctx, {
  required double freq,
  required double startTime,
  required double duration,
  required double peakGain,
}) {
  final osc = ctx.createOscillator();
  final gain = ctx.createGain();
  osc.type = 'sine';
  osc.frequency.setValueAtTime(freq, startTime);

  gain.gain.setValueAtTime(0.0001, startTime);
  gain.gain.exponentialRampToValueAtTime(peakGain, startTime + 0.015);
  gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(startTime);
  osc.stop(startTime + duration + 0.02);
}
