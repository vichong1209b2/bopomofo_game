import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';
import '../game_config.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.title, required this.themeStyle});
  final String title;
  final ThemeStyle themeStyle;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  String _log = '';
  String _path = '';

  String? _iconAsset(String key) {
    switch (widget.themeStyle) {
      case ThemeStyle.kuromi:
        return 'assets/themes/kuromi/icons/$key.png';
      case ThemeStyle.cinnamoroll:
        return 'assets/themes/cinnamoroll/icons/$key.png';
      case ThemeStyle.mymelody:
        return 'assets/themes/mymelody/icons/$key.png';
      case ThemeStyle.carbot:
        return 'assets/themes/carbot/icons/$key.png';
      case ThemeStyle.ultraman:
        return 'assets/themes/ultraman/icons/$key.png';
      case ThemeStyle.sakura:
      case ThemeStyle.ocean:
      case ThemeStyle.forest:
      case ThemeStyle.night:
        return null;
    }
  }

  Widget _icon({required String key, required IconData fallback, double size = 24}) {
    final asset = _iconAsset(key);
    if (asset == null) return Icon(fallback, size: size);
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (ctx, err, st) => Icon(fallback, size: size),
    );
  }

  ({List<Color> colors, String? heroAsset, String? decoTop, String? decoBottom, String? badge}) _bgSpec() {
    switch (widget.themeStyle) {
      case ThemeStyle.kuromi:
        return (
          colors: const [Color(0xFFF6ECFF), Color(0xFFFFFFFF)],
          heroAsset: 'assets/themes/kuromi/hero.png',
          decoTop: 'assets/themes/kuromi/deco_top.png',
          decoBottom: 'assets/themes/kuromi/deco_bottom.png',
          badge: 'assets/themes/kuromi/badge.png',
        );
      case ThemeStyle.cinnamoroll:
        return (
          colors: const [Color(0xFFEAF7FF), Color(0xFFFFFFFF)],
          heroAsset: 'assets/themes/cinnamoroll/hero.png',
          decoTop: 'assets/themes/cinnamoroll/deco_top.png',
          decoBottom: 'assets/themes/cinnamoroll/deco_bottom.png',
          badge: 'assets/themes/cinnamoroll/badge.png',
        );
      case ThemeStyle.mymelody:
        return (
          colors: const [Color(0xFFFFEEF5), Color(0xFFFFFFFF)],
          heroAsset: 'assets/themes/mymelody/hero.png',
          decoTop: 'assets/themes/mymelody/deco_top.png',
          decoBottom: 'assets/themes/mymelody/deco_bottom.png',
          badge: 'assets/themes/mymelody/badge.png',
        );
      case ThemeStyle.carbot:
        return (
          colors: const [Color(0xFFEAF2FF), Color(0xFFFFFFFF)],
          heroAsset: 'assets/themes/carbot/hero.png',
          decoTop: 'assets/themes/carbot/deco_top.png',
          decoBottom: 'assets/themes/carbot/deco_bottom.png',
          badge: 'assets/themes/carbot/badge.png',
        );
      case ThemeStyle.ultraman:
        return (
          colors: const [Color(0xFFFFEFEF), Color(0xFFFFFFFF)],
          heroAsset: 'assets/themes/ultraman/hero.png',
          decoTop: 'assets/themes/ultraman/deco_top.png',
          decoBottom: 'assets/themes/ultraman/deco_bottom.png',
          badge: 'assets/themes/ultraman/badge.png',
        );
      case ThemeStyle.sakura:
        return (colors: const [Color(0xFFFFF1F7), Color(0xFFFFFFFF)], heroAsset: null, decoTop: null, decoBottom: null, badge: null);
      case ThemeStyle.ocean:
        return (colors: const [Color(0xFFE7F6FF), Color(0xFFFFFFFF)], heroAsset: null, decoTop: null, decoBottom: null, badge: null);
      case ThemeStyle.forest:
        return (colors: const [Color(0xFFEAF7EE), Color(0xFFFFFFFF)], heroAsset: null, decoTop: null, decoBottom: null, badge: null);
      case ThemeStyle.night:
        return (colors: const [Color(0xFFEFEAFF), Color(0xFFFFFFFF)], heroAsset: null, decoTop: null, decoBottom: null, badge: null);
    }
  }

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
    final spec = _bgSpec();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: _reload, icon: _icon(key: 'refresh', fallback: Icons.refresh)),
          IconButton(onPressed: _copy, icon: _icon(key: 'copy', fallback: Icons.copy)),
          IconButton(onPressed: _clear, icon: _icon(key: 'delete', fallback: Icons.delete_outline)),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: spec.colors,
                ),
              ),
            ),
          ),
          if (spec.heroAsset != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: 0.10,
                    child: Image.asset(
                      spec.heroAsset!,
                      width: 520,
                      height: 520,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          if (spec.decoTop != null)
            Positioned(
              top: 18,
              right: 10,
              child: Opacity(
                opacity: 0.22,
                child: Image.asset(
                  spec.decoTop!,
                  width: 170,
                  height: 170,
                  errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (spec.decoBottom != null)
            Positioned(
              bottom: 10,
              left: 10,
              child: Opacity(
                opacity: 0.18,
                child: Image.asset(
                  spec.decoBottom!,
                  width: 200,
                  height: 200,
                  errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (spec.badge != null)
            Positioned(
              top: 86,
              left: 14,
              child: Opacity(
                opacity: 0.10,
                child: Image.asset(
                  spec.badge!,
                  width: 110,
                  height: 110,
                  errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                ),
              ),
            ),
          Padding(
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
                      color: Colors.white.withOpacity(0.92),
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
                  icon: _icon(key: 'copy', fallback: Icons.copy),
                  label: const Text('複製日誌'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
