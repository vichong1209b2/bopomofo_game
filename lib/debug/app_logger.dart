import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 簡易 app 日誌（寫入檔案 + 記憶體 ring buffer），方便使用者在手機上直接複製貼上。
class AppLogger {
  AppLogger._();

  static final _init = Completer<void>();
  static File? _file;
  static final List<String> _buffer = <String>[];
  static const int _maxLines = 400;

  static Future<void> ensureInitialized() async {
    if (_init.isCompleted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, 'bopomofo_game_log.txt');
      _file = File(path);
    } finally {
      _init.complete();
    }
  }

  static Future<String> logFilePath() async {
    await ensureInitialized();
    return _file?.path ?? '(unknown)';
  }

  static Future<void> log(String message) async {
    await ensureInitialized();
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $message';

    // 記憶體 ring buffer：就算檔案寫入失敗，也能看到最近的 log
    _buffer.add(line);
    if (_buffer.length > _maxLines) {
      _buffer.removeRange(0, _buffer.length - _maxLines);
    }

    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // ignore
    }
  }

  static Future<String> readAll({int maxChars = 20000}) async {
    await ensureInitialized();
    final mem = _buffer.join('\n');
    if (mem.isNotEmpty) {
      if (mem.length <= maxChars) return mem;
      return mem.substring(mem.length - maxChars);
    }

    final f = _file;
    if (f == null) return '';
    try {
      if (!await f.exists()) return '';
      final s = await f.readAsString();
      if (s.length <= maxChars) return s;
      return s.substring(s.length - maxChars);
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    await ensureInitialized();
    _buffer.clear();
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists()) {
        await f.writeAsString('', flush: true);
      }
    } catch (_) {}
  }
}

