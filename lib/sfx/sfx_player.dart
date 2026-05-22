import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 只用於「答對/答錯」的短音效（不影響 TTS）。
class SfxPlayer {
  SfxPlayer._();

  static const int _sr = 44100;

  static final AudioPlayer _player = AudioPlayer(playerId: 'sfx');
  static bool _ready = false;
  static String? _correctPath;
  static String? _wrongPath;

  static Future<void> playCorrect() async {
    await _ensureReady();
    final path = _correctPath;
    if (path == null) return;
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  static Future<void> playWrong() async {
    await _ensureReady();
    final path = _wrongPath;
    if (path == null) return;
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  static Future<void> _ensureReady() async {
    if (_ready) return;

    final dir = await getApplicationDocumentsDirectory();
    final sfxDir = Directory(p.join(dir.path, 'bopomofo_sfx'));
    if (!await sfxDir.exists()) {
      await sfxDir.create(recursive: true);
    }

    final correct = p.join(sfxDir.path, 'correct.wav');
    final wrong = p.join(sfxDir.path, 'wrong.wav');

    if (!await File(correct).exists()) {
      final bytes = _makeCorrectWav();
      await File(correct).writeAsBytes(bytes, flush: true);
    }
    if (!await File(wrong).exists()) {
      final bytes = _makeWrongWav();
      await File(wrong).writeAsBytes(bytes, flush: true);
    }

    _correctPath = correct;
    _wrongPath = wrong;
    _ready = true;
  }

  static Uint8List _makeCorrectWav() {
    // 叮咚叮咚：兩段偏高音
    final s = <double>[];
    s.addAll(_tone(880, 0.12, 0.65));
    s.addAll(_silence(0.03));
    s.addAll(_tone(660, 0.14, 0.65));
    return _toWavPcm16(s);
  }

  static Uint8List _makeWrongWav() {
    // 答答：兩段偏低音
    final s = <double>[];
    s.addAll(_tone(220, 0.09, 0.70));
    s.addAll(_silence(0.04));
    s.addAll(_tone(180, 0.11, 0.70));
    return _toWavPcm16(s);
  }

  static List<double> _silence(double seconds) {
    final n = max(0, (seconds * _sr).round());
    return List<double>.filled(n, 0.0);
  }

  static List<double> _tone(double freq, double seconds, double amp) {
    final n = max(0, (seconds * _sr).round());
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      final t = i / _sr;
      // 簡單衰減，避免「啪」的爆音
      final env = exp(-4 * t / seconds);
      out.add(amp * env * sin(2 * pi * freq * t));
    }
    return out;
  }

  static Uint8List _toWavPcm16(List<double> samples) {
    const channels = 1;
    const bitsPerSample = 16;
    final bytesPerSample = bitsPerSample ~/ 8;
    final dataSize = samples.length * bytesPerSample;
    final byteRate = _sr * channels * bytesPerSample;
    final blockAlign = channels * bytesPerSample;
    final riffSize = 36 + dataSize;

    final b = BytesBuilder(copy: false);
    b.add(ascii.encode('RIFF'));
    b.add(_u32le(riffSize));
    b.add(ascii.encode('WAVE'));
    b.add(ascii.encode('fmt '));
    b.add(_u32le(16)); // PCM
    b.add(_u16le(1)); // PCM format
    b.add(_u16le(channels));
    b.add(_u32le(_sr));
    b.add(_u32le(byteRate));
    b.add(_u16le(blockAlign));
    b.add(_u16le(bitsPerSample));
    b.add(ascii.encode('data'));
    b.add(_u32le(dataSize));

    final bd = ByteData(dataSize);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i] * 32767.0).round().clamp(-32768, 32767);
      bd.setInt16(i * 2, v, Endian.little);
    }
    b.add(bd.buffer.asUint8List());
    return b.toBytes();
  }

  static Uint8List _u16le(int v) {
    final bd = ByteData(2)..setUint16(0, v, Endian.little);
    return bd.buffer.asUint8List();
  }

  static Uint8List _u32le(int v) {
    final bd = ByteData(4)..setUint32(0, v, Endian.little);
    return bd.buffer.asUint8List();
  }
}

