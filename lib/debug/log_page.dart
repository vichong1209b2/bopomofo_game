import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.title});
  final String title;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  String _log = '';
  String _path = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await AppLogger.readAll();
    final p = await AppLogger.logFilePath();
    if (!mounted) return;
    setState(() {
      _log = s;
      _path = p;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _log.isEmpty ? '(no logs)' : _log));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已複製日誌到剪貼簿')));
  }

  Future<void> _clear() async {
    await AppLogger.clear();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除日誌')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _copy, icon: const Icon(Icons.copy)),
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('檔案：$_path', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(_log.isEmpty ? '(尚無日誌)' : _log),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy),
              label: const Text('複製日誌'),
            ),
          ],
        ),
      ),
    );
  }
}

