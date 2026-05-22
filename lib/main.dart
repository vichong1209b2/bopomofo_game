import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'db/db_service.dart';
import 'debug/app_logger.dart';
import 'debug/log_page.dart';
import 'game_config.dart';
import 'models.dart';
import 'sfx/sfx_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runZonedGuarded(() async {
    await AppLogger.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLogger.log('[FlutterError] ${details.exceptionAsString()}\n${details.stack}');
    };
    runApp(const BopoGameApp());
  }, (e, st) {
    AppLogger.log('[ZoneError] $e\n$st');
  });
}

class BopoGameApp extends StatelessWidget {
  const BopoGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.pinkAccent, brightness: Brightness.light);
    return MaterialApp(
      title: '注音遊戲',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: scheme.surfaceContainerHighest,
          elevation: 0.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum GameMode {
  aAudioToChar,
  bCharToBopo,
  cPairing,
  dBopoToChar,
  eWordToBopo,
  fWordChain,
  mix,
}

/// 「題型」與「玩法」分開：
/// - GameMode：每題長什麼樣（A/B/C/D/E/混合）
/// - PlayMode：整體規則（計分/目標/限時/生命…）
enum PlayMode { practice, scoreTarget, correctTarget, timeAttack, survival }

String levelLabel(EducationLevel l) {
  switch (l) {
    case EducationLevel.elementary:
      return '國小';
    case EducationLevel.juniorHigh:
      return '國中';
    case EducationLevel.seniorHigh:
      return '高中';
    case EducationLevel.university:
      return '大學';
    case EducationLevel.graduate:
      return '研究所';
    case EducationLevel.working:
      return '社會人士';
    case EducationLevel.expert:
      return '專家';
    case EducationLevel.scholar:
      return '學者';
    case EducationLevel.master:
      return '大師';
  }
}

IconData levelIcon(EducationLevel l) {
  switch (l) {
    case EducationLevel.elementary:
      return Icons.school;
    case EducationLevel.juniorHigh:
      return Icons.book;
    case EducationLevel.seniorHigh:
      return Icons.menu_book;
    case EducationLevel.university:
      return Icons.account_balance;
    case EducationLevel.graduate:
      return Icons.science;
    case EducationLevel.working:
      return Icons.work;
    case EducationLevel.expert:
      return Icons.psychology;
    case EducationLevel.scholar:
      return Icons.auto_stories;
    case EducationLevel.master:
      return Icons.emoji_events;
  }
}

String themeLabel(ThemeStyle t) {
  switch (t) {
    case ThemeStyle.sakura:
      return '櫻花';
    case ThemeStyle.ocean:
      return '海洋';
    case ThemeStyle.forest:
      return '森林';
    case ThemeStyle.night:
      return '夜色';
    case ThemeStyle.kuromi:
      return '庫洛米風';
    case ThemeStyle.cinnamoroll:
      return '大耳狗風';
    case ThemeStyle.mymelody:
      return '美樂蒂風';
    case ThemeStyle.carbot:
      return '衝鋒戰士風';
    case ThemeStyle.ultraman:
      return '奧特曼風';
  }
}

class ThemeVisual {
  final List<Color> colors;
  final List<IconData> decoIcons;
  final String? badgeAsset; // 小圖示（設定頁/首頁顯示）
  final String? decoTopAsset; // 背景角落裝飾（PNG，透明底）
  final String? decoBottomAsset;

  const ThemeVisual({
    required this.colors,
    required this.decoIcons,
    this.badgeAsset,
    this.decoTopAsset,
    this.decoBottomAsset,
  });
}

ThemeVisual themeVisual(ThemeStyle t) {
  switch (t) {
    case ThemeStyle.sakura:
      return const ThemeVisual(
        colors: [Color(0xFFFFF1F7), Color(0xFFFFFFFF)],
        decoIcons: [Icons.local_florist, Icons.favorite],
      );
    case ThemeStyle.ocean:
      return const ThemeVisual(
        colors: [Color(0xFFE7F6FF), Color(0xFFFFFFFF)],
        decoIcons: [Icons.water_drop, Icons.waves],
      );
    case ThemeStyle.forest:
      return const ThemeVisual(
        colors: [Color(0xFFEAF7EE), Color(0xFFFFFFFF)],
        decoIcons: [Icons.park, Icons.eco],
      );
    case ThemeStyle.night:
      return const ThemeVisual(
        colors: [Color(0xFFEFEAFF), Color(0xFFFFFFFF)],
        decoIcons: [Icons.nightlight_round, Icons.star],
      );
    case ThemeStyle.kuromi:
      return const ThemeVisual(
        colors: [Color(0xFFF6ECFF), Color(0xFFFFFFFF)],
        decoIcons: [Icons.favorite, Icons.auto_awesome],
        badgeAsset: 'assets/themes/kuromi/badge.png',
        decoTopAsset: 'assets/themes/kuromi/deco_top.png',
        decoBottomAsset: 'assets/themes/kuromi/deco_bottom.png',
      );
    case ThemeStyle.cinnamoroll:
      return const ThemeVisual(
        colors: [Color(0xFFEAF7FF), Color(0xFFFFFFFF)],
        decoIcons: [Icons.cloud, Icons.air],
        badgeAsset: 'assets/themes/cinnamoroll/badge.png',
        decoTopAsset: 'assets/themes/cinnamoroll/deco_top.png',
        decoBottomAsset: 'assets/themes/cinnamoroll/deco_bottom.png',
      );
    case ThemeStyle.mymelody:
      return const ThemeVisual(
        colors: [Color(0xFFFFEEF5), Color(0xFFFFFFFF)],
        decoIcons: [Icons.cake, Icons.favorite],
        badgeAsset: 'assets/themes/mymelody/badge.png',
        decoTopAsset: 'assets/themes/mymelody/deco_top.png',
        decoBottomAsset: 'assets/themes/mymelody/deco_bottom.png',
      );
    case ThemeStyle.carbot:
      return const ThemeVisual(
        colors: [Color(0xFFEAF2FF), Color(0xFFFFFFFF)],
        decoIcons: [Icons.smart_toy, Icons.flash_on],
        badgeAsset: 'assets/themes/carbot/badge.png',
        decoTopAsset: 'assets/themes/carbot/deco_top.png',
        decoBottomAsset: 'assets/themes/carbot/deco_bottom.png',
      );
    case ThemeStyle.ultraman:
      return const ThemeVisual(
        colors: [Color(0xFFFFEFEF), Color(0xFFFFFFFF)],
        decoIcons: [Icons.shield, Icons.bolt],
        badgeAsset: 'assets/themes/ultraman/badge.png',
        decoTopAsset: 'assets/themes/ultraman/deco_top.png',
        decoBottomAsset: 'assets/themes/ultraman/deco_bottom.png',
      );
  }
}

Widget _themeBadge(ThemeStyle t, {double size = 22}) {
  final asset = themeVisual(t).badgeAsset;
  if (asset == null) return const SizedBox(width: 0, height: 0);
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.asset(asset, width: size, height: size, fit: BoxFit.contain),
  );
}

class GameGoal {
  final int? targetScore;
  final int? targetCorrect;
  final int? timeLimitSec;
  final int? lives;

  const GameGoal({this.targetScore, this.targetCorrect, this.timeLimitSec, this.lives});

  GameGoal copyWith({int? targetScore, int? targetCorrect, int? timeLimitSec, int? lives}) {
    return GameGoal(
      targetScore: targetScore ?? this.targetScore,
      targetCorrect: targetCorrect ?? this.targetCorrect,
      timeLimitSec: timeLimitSec ?? this.timeLimitSec,
      lives: lives ?? this.lives,
    );
  }
}

GameGoal defaultGoalFor(PlayMode mode) {
  switch (mode) {
    case PlayMode.practice:
      return const GameGoal(targetCorrect: 10);
    case PlayMode.scoreTarget:
      return const GameGoal(targetScore: 80);
    case PlayMode.correctTarget:
      return const GameGoal(targetCorrect: 20);
    case PlayMode.timeAttack:
      return const GameGoal(timeLimitSec: 60);
    case PlayMode.survival:
      return const GameGoal(lives: 3, targetCorrect: 20);
  }
}

class ScoringRules {
  final int correctFirstTry;
  final int correctAfterWrong;
  final int wrongPenalty;

  const ScoringRules({
    required this.correctFirstTry,
    required this.correctAfterWrong,
    required this.wrongPenalty,
  });
}

const _defaultScoring = ScoringRules(correctFirstTry: 10, correctAfterWrong: 6, wrongPenalty: -2);

class GameSettings {
  final GameMode mode;
  final DataFlavor flavor;
  final PlayMode playMode;
  final GameGoal goal;
  final EducationLevel level;
  final ThemeStyle themeStyle;
  final bool soundEnabled; // 答對/答錯音效（不含 TTS）

  const GameSettings({
    required this.mode,
    required this.flavor,
    required this.playMode,
    required this.goal,
    required this.level,
    required this.themeStyle,
    required this.soundEnabled,
  });

  GameSettings copyWith({
    GameMode? mode,
    DataFlavor? flavor,
    PlayMode? playMode,
    GameGoal? goal,
    EducationLevel? level,
    ThemeStyle? themeStyle,
    bool? soundEnabled,
  }) {
    return GameSettings(
      mode: mode ?? this.mode,
      flavor: flavor ?? this.flavor,
      playMode: playMode ?? this.playMode,
      goal: goal ?? this.goal,
      level: level ?? this.level,
      themeStyle: themeStyle ?? this.themeStyle,
      soundEnabled: soundEnabled ?? this.soundEnabled,
    );
  }
}

String modeLabel(GameMode m) {
  switch (m) {
    case GameMode.aAudioToChar:
      return 'A 聽音選字';
    case GameMode.bCharToBopo:
      return 'B 看字選音';
    case GameMode.cPairing:
      return 'C 配對';
    case GameMode.dBopoToChar:
      return 'D 看注音選字';
    case GameMode.eWordToBopo:
      return 'E 看詞語選注音';
    case GameMode.fWordChain:
      return '接龍填空';
    case GameMode.mix:
      return '混合';
  }
}

String playModeLabel(PlayMode m) {
  switch (m) {
    case PlayMode.practice:
      return '練習';
    case PlayMode.scoreTarget:
      return '目標分數';
    case PlayMode.correctTarget:
      return '目標題數';
    case PlayMode.timeAttack:
      return '限時挑戰';
    case PlayMode.survival:
      return '生存';
  }
}

String goalSummary(PlayMode playMode, GameGoal goal) {
  switch (playMode) {
    case PlayMode.practice:
      return '目標：答對 ${goal.targetCorrect ?? 10} 題';
    case PlayMode.scoreTarget:
      return '目標：達到 ${goal.targetScore ?? 80} 分';
    case PlayMode.correctTarget:
      return '目標：答對 ${goal.targetCorrect ?? 20} 題';
    case PlayMode.timeAttack:
      return '目標：${goal.timeLimitSec ?? 60} 秒內盡量拿分';
    case PlayMode.survival:
      return '目標：${goal.lives ?? 3} 命，答對 ${goal.targetCorrect ?? 20} 題';
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GameSettings _settings = GameSettings(
    // 預設用較輕量的題型，避免第一次進入就跑接龍的大查詢造成「看起來卡住」。
    // 接龍題型仍可在設定頁手動切換。
    mode: GameMode.aAudioToChar,
    flavor: DataFlavor.enhanced,
    playMode: PlayMode.scoreTarget,
    goal: defaultGoalFor(PlayMode.scoreTarget),
    level: EducationLevel.juniorHigh,
    themeStyle: ThemeStyle.sakura,
    soundEnabled: true,
  );

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<GameSettings>(
      MaterialPageRoute(builder: (_) => SettingsPage(initial: _settings)),
    );
    if (result != null) {
      setState(() => _settings = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('注音遊戲'),
        actions: [
          IconButton(
            tooltip: '日誌',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogPage(title: '程式日誌')));
            },
            icon: const Icon(Icons.article_outlined),
          ),
          IconButton(
            tooltip: '設定',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Container(
        child: ThemedBackground(
          themeStyle: _settings.themeStyle,
          child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              '用遊戲練注音',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('目前設定', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('資料庫：${_settings.flavor == DataFlavor.enhanced ? "強化版" : "原始轉檔"}'),
                    Text('題型：${modeLabel(_settings.mode)}'),
                    Text('玩法：${playModeLabel(_settings.playMode)}'),
                    Row(
                      children: [
                        Icon(levelIcon(_settings.level), size: 18),
                        const SizedBox(width: 6),
                        Text('等級：${levelLabel(_settings.level)}'),
                        const SizedBox(width: 12),
                        _themeBadge(_settings.themeStyle, size: 18),
                        const SizedBox(width: 8),
                        Text('主題：${themeLabel(_settings.themeStyle)}'),
                      ],
                    ),
                    Text(goalSummary(_settings.playMode, _settings.goal)),
                    const SizedBox(height: 8),
                    Text(
                      '右上角「設定」可調整題型/玩法/目標',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GamePage(
                    mode: _settings.mode,
                    flavor: _settings.flavor,
                    playMode: _settings.playMode,
                    goal: _settings.goal,
                    level: _settings.level,
                    themeStyle: _settings.themeStyle,
                    soundEnabled: _settings.soundEnabled,
                  ),
                ));
              },
              child: const Text('開始'),
            ),
          ],
          ),
        ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initial});
  final GameSettings initial;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late GameMode _mode = widget.initial.mode;
  late DataFlavor _flavor = widget.initial.flavor;
  late PlayMode _playMode = widget.initial.playMode;
  late GameGoal _goal = widget.initial.goal;
  late EducationLevel _level = widget.initial.level;
  late ThemeStyle _themeStyle = widget.initial.themeStyle;
  late bool _soundEnabled = widget.initial.soundEnabled;

  Future<int?> _askInt({
    required String title,
    required int? initial,
    String? helper,
  }) async {
    final c = TextEditingController(text: initial?.toString() ?? '');
    return showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (helper != null) ...[
              Text(helper, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: c,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(c.text.trim());
              Navigator.pop(ctx, v);
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGoal() async {
    GameGoal g = _goal;
    switch (_playMode) {
      case PlayMode.practice: {
        final v = await _askInt(title: '練習模式：答對幾題算完成？', initial: g.targetCorrect ?? 10);
        if (v == null) return;
        g = g.copyWith(targetCorrect: v);
        break;
      }
      case PlayMode.scoreTarget: {
        final v = await _askInt(title: '分數目標：達到幾分算完成？', initial: g.targetScore ?? 80);
        if (v == null) return;
        g = g.copyWith(targetScore: v);
        break;
      }
      case PlayMode.correctTarget: {
        final v = await _askInt(title: '答題目標：答對幾題算完成？', initial: g.targetCorrect ?? 20);
        if (v == null) return;
        g = g.copyWith(targetCorrect: v);
        break;
      }
      case PlayMode.timeAttack: {
        final t = await _askInt(title: '限時：秒數', initial: g.timeLimitSec ?? 60, helper: '例如 30 / 60 / 90');
        if (t == null) return;
        g = g.copyWith(timeLimitSec: t);
        break;
      }
      case PlayMode.survival: {
        final lives = await _askInt(title: '生存模式：生命值', initial: g.lives ?? 3, helper: '答錯扣 1 命，歸零就結束');
        if (lives == null) return;
        final target = await _askInt(title: '生存模式：答對幾題算完成？', initial: g.targetCorrect ?? 20);
        if (target == null) return;
        g = g.copyWith(lives: lives, targetCorrect: target);
        break;
      }
    }
    setState(() => _goal = g);
  }

  void _save() {
    Navigator.of(context).pop(GameSettings(
      mode: _mode,
      flavor: _flavor,
      playMode: _playMode,
      goal: _goal,
      level: _level,
      themeStyle: _themeStyle,
      soundEnabled: _soundEnabled,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          TextButton(onPressed: _save, child: const Text('儲存')),
        ],
      ),
      body: Container(
        child: ThemedBackground(
          themeStyle: _themeStyle,
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          const Text('等級', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<EducationLevel>(
            value: _level,
            items: EducationLevel.values.map((l) {
              return DropdownMenuItem(
                value: l,
                child: Row(
                  children: [
                    Icon(levelIcon(l), size: 18),
                    const SizedBox(width: 8),
                    Text(levelLabel(l)),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) => setState(() => _level = v!),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('主題', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<ThemeStyle>(
            value: _themeStyle,
            items: ThemeStyle.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          _themeBadge(t, size: 20),
                          if (themeVisual(t).badgeAsset != null) const SizedBox(width: 8),
                          Text(themeLabel(t)),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _themeStyle = v!),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          const Text('音效', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _soundEnabled,
            onChanged: (v) => setState(() => _soundEnabled = v),
            title: const Text('答對 / 答錯音效'),
            subtitle: const Text('答對：叮咚叮咚｜答錯：答答'),
          ),
          const SizedBox(height: 20),
          const Text('資料庫', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<DataFlavor>(
            segments: const [
              ButtonSegment(value: DataFlavor.enhanced, label: Text('強化版')),
              ButtonSegment(value: DataFlavor.raw, label: Text('原始轉檔')),
            ],
            selected: {_flavor},
            onSelectionChanged: (s) => setState(() => _flavor = s.first),
          ),
          const SizedBox(height: 20),
          const Text('題型', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RadioListTile(
            value: GameMode.aAudioToChar,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('A：聽音選字（TTS 朗讀詞語）'),
          ),
          RadioListTile(
            value: GameMode.bCharToBopo,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('B：看字選音（單音字版）'),
          ),
          RadioListTile(
            value: GameMode.cPairing,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('C：配對（詞語 ↔ 注音）'),
          ),
          RadioListTile(
            value: GameMode.dBopoToChar,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('D：看注音選字（注音 → 字）'),
          ),
          RadioListTile(
            value: GameMode.eWordToBopo,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('E：看詞語選注音（詞語 → 注音）'),
          ),
          RadioListTile(
            value: GameMode.fWordChain,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('接龍填空：語詞接龍（選出下一個詞語）'),
          ),
          RadioListTile(
            value: GameMode.mix,
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            title: const Text('混合題型（每題隨機）'),
          ),
          const SizedBox(height: 12),
          const Text('玩法（規則/目標）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<PlayMode>(
            segments: const [
              ButtonSegment(value: PlayMode.practice, label: Text('練習')),
              ButtonSegment(value: PlayMode.scoreTarget, label: Text('目標分數')),
              ButtonSegment(value: PlayMode.correctTarget, label: Text('目標題數')),
              ButtonSegment(value: PlayMode.timeAttack, label: Text('限時挑戰')),
              ButtonSegment(value: PlayMode.survival, label: Text('生存')),
            ],
            selected: {_playMode},
            onSelectionChanged: (s) {
              final m = s.first;
              setState(() {
                _playMode = m;
                _goal = defaultGoalFor(m);
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text(goalSummary(_playMode, _goal), style: const TextStyle(color: Colors.black87))),
              OutlinedButton.icon(
                onPressed: _editGoal,
                icon: const Icon(Icons.tune),
                label: const Text('目標'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('儲存並返回')),
          ],
        ),
        ),
      ),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({
    super.key,
    required this.mode,
    required this.flavor,
    required this.playMode,
    required this.goal,
    required this.level,
    required this.themeStyle,
    required this.soundEnabled,
  });
  final GameMode mode;
  final DataFlavor flavor;
  final PlayMode playMode;
  final GameGoal goal;
  final EducationLevel level;
  final ThemeStyle themeStyle;
  final bool soundEnabled;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  DbService? _db;
  final FlutterTts _tts = FlutterTts();
  String? _initError;
  bool _ttsReady = false;
  String? _ttsLang; // 實際使用的 TTS 語言（不同手機支援狀況不同）
  late int _audioHintsLeft;

  int _score = 0;
  int _questions = 0; // 作答題數：每題/每輪只算 1 次（答錯重試不會一直 +1）
  int _correct = 0; // 答對題數
  int _streak = 0;
  int _bestStreak = 0;
  int _wrongTaps = 0; // 錯誤點擊次數（用於扣分/統計）
  int? _lives;
  int? _timeLeft;
  Timer? _timer;
  String? _feedback;
  bool _isFinished = false;

  AudioToCharQuestion? _qA;
  CharToBopoQuestion? _qB;
  PairingRound? _qC;
  BopoToCharQuestion? _qD;
  WordToBopoQuestion? _qE;
  WordChainQuestion? _qF;

  // 接龍模式：上一題答對後，將答案作為下一題的 currentWord（形成連續接龍）
  String? _chainCurrentWord;

  // 混合題型時，這一題實際使用的題型
  late GameMode _activeMode = widget.mode;

  String? _pairingSelectedWord;
  final Set<String> _pairingMatchedWords = {};
  final Set<String> _pairingMatchedBopos = {};

  // 單題作答狀態（A/B/D/E）
  bool _locked = false; // 答對後鎖定（不能再答）
  final Set<String> _wrongOptions = {};
  bool _currentCounted = false;
  bool _currentTouched = false;
  String? _selectedCorrectOption;

  @override
  void initState() {
    super.initState();
    _audioHintsLeft = audioHintLimitForLevel(widget.level);
    _init();
  }

  Future<void> _init() async {
    try {
      final db = await DbService.open(flavor: widget.flavor);
      if (!mounted) return;
      setState(() {
        _db = db;
        _initError = null;
      });

      // TTS 初始化如果失敗，不應該導致整個遊戲卡在 loading。
      try {
        _ttsReady = await _setupTts();
      } catch (e) {
        _ttsReady = false;
        if (mounted) {
          setState(() => _feedback = '語音初始化失敗（仍可遊玩非朗讀題型）：$e');
        }
      }

      if (widget.playMode == PlayMode.survival) {
        _lives = (widget.goal.lives ?? 3);
      }
      if (widget.playMode == PlayMode.timeAttack) {
        _timeLeft = (widget.goal.timeLimitSec ?? 60);
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || _isFinished) return;
          setState(() {
            _timeLeft = (_timeLeft ?? 0) - 1;
          });
          if ((_timeLeft ?? 0) <= 0) {
            _finish(reason: '時間到');
          }
        });
      }
      await _next();
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e.toString());
    }
  }

  bool get _canUseAudioHintLimited => !_isFinished && _ttsReady && _audioHintsLeft > 0;
  bool get _canUseAudioHintUnlimited => !_isFinished && _ttsReady;

  Future<bool> _setupTts() async {
    // 為什麼要做 fallback：
    // 某些手機（例如部分 realme/OPPO 系）若沒有安裝/下載「中文語音資料」，setLanguage('zh-TW') 可能不報錯但 speak 沒聲音。
    // 因此這裡會依序嘗試多個常見中文 locale，直到成功。
    List<dynamic> langs = const [];
    try {
      final r = await _tts.getLanguages;
      if (r is List) langs = r;
    } catch (_) {
      // ignore
    }

    bool supports(String code) {
      if (langs.isEmpty) return true; // 拿不到清單就直接嘗試
      return langs.contains(code);
    }

    final candidates = <String>[
      'zh-TW',
      'zh-Hant',
      'zh-Hant-TW',
      'cmn-Hant-TW',
      'zh-CN',
      'zh',
      'cmn-CN',
    ];

    String? chosen;
    for (final c in candidates) {
      if (!supports(c)) continue;
      try {
        await _tts.setLanguage(c);
        chosen = c;
        break;
      } catch (_) {
        // try next
      }
    }
    if (chosen == null) return false;
    _ttsLang = chosen;

    // 讓發音更清楚：放慢一點、音高略提高
    await _tts.setSpeechRate(0.40);
    await _tts.setPitch(1.05);
    await _tts.setVolume(1.0);
    // 盡量等朗讀完成（避免連續點擊時互相蓋掉）
    await _tts.awaitSpeakCompletion(true);

    // 某些機型會在第一次 speak 才真正初始化音源；用很短的測試避免「第一次點沒聲音」
    try {
      await _tts.speak(' ');
      await _tts.stop();
    } catch (_) {
      // ignore
    }

    return true;
  }

  Future<void> _useAudioHint(String text, {required bool consume}) async {
    if (_isFinished) return;
    if (!_ttsReady) {
      if (mounted) {
        setState(() => _feedback = '語音不可用：請到手機「文字轉語音(TTS)」設定下載中文語音/切換引擎後再試。');
      }
      return;
    }
    if (consume && _audioHintsLeft <= 0) {
      if (mounted) setState(() => _feedback = '發音提示次數已用完');
      return;
    }
    if (consume) {
      setState(() => _audioHintsLeft -= 1);
    }
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _db?.close();
    _tts.stop();
    _timer?.cancel();
    super.dispose();
  }

  GameMode _pickActiveMode() {
    if (widget.mode != GameMode.mix) return widget.mode;
    // 混合題型：每題隨機（排除 mix 自己）
    final pool = [
      GameMode.aAudioToChar,
      GameMode.bCharToBopo,
      GameMode.cPairing,
      GameMode.dBopoToChar,
      GameMode.eWordToBopo,
      GameMode.fWordChain,
    ];
    pool.shuffle();
    return pool.first;
  }

  Future<void> _next() async {
    // 若使用者點「下一題」但本題已作答過（至少點過一次），算作完成一題（可能是跳過）
    if (!_isFinished) {
      _finalizeSkippedIfNeeded();
    }
    setState(() {
      _feedback = null;
      _qA = null;
      _qB = null;
      _qC = null;
      _qD = null;
      _qE = null;
      _qF = null;
      _pairingSelectedWord = null;
      _pairingMatchedWords.clear();
      _pairingMatchedBopos.clear();
      _locked = false;
      _wrongOptions.clear();
      _currentCounted = false;
      _currentTouched = false;
      _selectedCorrectOption = null;
    });

    final db = _db;
    if (db == null) return;

    try {
      _activeMode = _pickActiveMode();
      if (_activeMode == GameMode.aAudioToChar) {
        final q = await db.randomAudioToCharQuestion(level: widget.level);
        setState(() => _qA = q);
        // 朗讀詞語（注音本身 TTS 不一定能順利朗讀）
        if (_ttsReady) {
          await _tts.speak(q.word);
        }
      } else if (_activeMode == GameMode.bCharToBopo) {
        final q = await db.randomCharToBopoQuestion(level: widget.level);
        setState(() => _qB = q);
      } else if (_activeMode == GameMode.cPairing) {
        final q = await db.randomPairingRound(level: widget.level);
        setState(() => _qC = q);
      } else if (_activeMode == GameMode.dBopoToChar) {
        final q = await db.randomBopoToCharQuestion(level: widget.level);
        setState(() => _qD = q);
      } else if (_activeMode == GameMode.eWordToBopo) {
        final q = await db.randomWordToBopoQuestion(level: widget.level);
        setState(() => _qE = q);
      } else if (_activeMode == GameMode.fWordChain) {
        final q = await db.randomWordChainQuestion(currentWord: _chainCurrentWord, level: widget.level);
        setState(() => _qF = q);
        // 為了清楚一點：自動唸出目前詞語（接龍提示）
        if (_ttsReady) {
          await _tts.speak(q.currentWord);
        }
      }
    } catch (e) {
      setState(() => _feedback = '出題失敗：$e');
    }
  }

  void _finalizeSkippedIfNeeded() {
    if (_currentTouched && !_currentCounted) {
      _questions += 1;
      _currentCounted = true;
      _streak = 0;
      // 接龍若跳過，避免一直卡在同一個詞，改為下一題重新抽起始詞
      if (_activeMode == GameMode.fWordChain) {
        _chainCurrentWord = null;
      }
    }
  }

  void _countSolvedIfNeeded({required bool solved, required bool firstTry}) {
    if (_currentCounted) return;
    _questions += 1;
    _currentCounted = true;
    if (solved) {
      _correct += 1;
      if (firstTry) {
        _streak += 1;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    } else {
      _streak = 0;
    }
  }

  void _mark(bool correct, {bool firstTry = true, bool countAsQuestion = true}) {
    if (_isFinished) return;
    _currentTouched = true;
    final rules = widget.playMode == PlayMode.practice
        ? const ScoringRules(correctFirstTry: 1, correctAfterWrong: 1, wrongPenalty: 0)
        : _defaultScoring;

    setState(() {
      if (correct) {
        if (countAsQuestion) {
          _countSolvedIfNeeded(solved: true, firstTry: firstTry);
        }
        _score += firstTry ? rules.correctFirstTry : rules.correctAfterWrong;
        _feedback = '答對！ +${firstTry ? rules.correctFirstTry : rules.correctAfterWrong}';
      } else {
        _wrongTaps += 1;
        _streak = 0;
        _score += rules.wrongPenalty;
        _feedback = rules.wrongPenalty == 0 ? '答錯（練習模式不扣分）' : '答錯 ${rules.wrongPenalty}';
        if (widget.playMode == PlayMode.survival) {
          _lives = (_lives ?? 0) - 1;
        }
      }
    });

    // 答題音效（不含 TTS，可在設定關閉）
    if (widget.soundEnabled) {
      Future.microtask(() async {
        try {
          if (correct) {
            await SfxPlayer.playCorrect();
          } else {
            await SfxPlayer.playWrong();
          }
        } catch (_) {
          // ignore: 音效失敗不應該影響遊戲
        }
      });
    }
    _checkEnd();
  }

  void _checkEnd() {
    if (_isFinished) return;
    final g = widget.goal;

    if (widget.playMode == PlayMode.survival && (_lives ?? 0) <= 0) {
      _finish(reason: '生命值用完');
      return;
    }
    if (g.targetScore != null && _score >= g.targetScore!) {
      _finish(reason: '達成目標分數');
      return;
    }
    if (g.targetCorrect != null && _correct >= g.targetCorrect!) {
      _finish(reason: '達成目標題數');
      return;
    }
  }

  void _finish({required String reason}) {
    if (_isFinished) return;
    setState(() {
      _isFinished = true;
      _locked = true;
    });
    _timer?.cancel();

    Future.microtask(() async {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('遊戲結束（$reason）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('分數：$_score'),
              Text('作答：$_questions 題'),
              Text('答對：$_correct 次'),
              Text('答錯：$_wrongTaps 次'),
              Text('最長連勝：$_bestStreak'),
              if (widget.playMode == PlayMode.survival) Text('剩餘生命：${_lives ?? 0}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('查看結果'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                  builder: (_) => GamePage(
                    mode: widget.mode,
                    flavor: widget.flavor,
                    playMode: widget.playMode,
                    goal: widget.goal,
                    level: widget.level,
                    themeStyle: widget.themeStyle,
                    soundEnabled: widget.soundEnabled,
                  ),
                ));
              },
              child: const Text('再玩一次'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('回首頁'),
            ),
          ],
        ),
      );
    });
  }

  // 依主題稍微調整色系，但仍保留「答對=偏綠、答錯=偏紅」的直覺。
  (Color correct, Color wrong) get _feedbackPalette => switch (widget.themeStyle) {
        ThemeStyle.sakura => (const Color(0xFF2E7D32), const Color(0xFFC62828)),
        ThemeStyle.ocean => (const Color(0xFF00695C), const Color(0xFFB71C1C)),
        ThemeStyle.forest => (const Color(0xFF1B5E20), const Color(0xFFC62828)),
        ThemeStyle.night => (const Color(0xFF2E7D32), const Color(0xFFD32F2F)),
        // 新主題：仍維持「答對=偏綠、答錯=偏紅」，但略調整色相以符合主題氛圍
        ThemeStyle.kuromi => (const Color(0xFF2E7D32), const Color(0xFFD81B60)),
        ThemeStyle.cinnamoroll => (const Color(0xFF00796B), const Color(0xFFC62828)),
        ThemeStyle.mymelody => (const Color(0xFF2E7D32), const Color(0xFFD81B60)),
        ThemeStyle.carbot => (const Color(0xFF1B5E20), const Color(0xFFB71C1C)),
        ThemeStyle.ultraman => (const Color(0xFF2E7D32), const Color(0xFFD32F2F)),
      };

  ButtonStyle _styleForOption({required String opt, required String answer}) {
    final (correctColor, wrongColor) = _feedbackPalette;
    final correctBg = correctColor.withOpacity(0.88);
    final wrongBg = wrongColor.withOpacity(0.82);

    if (_locked) {
      if (opt == answer) {
        return FilledButton.styleFrom(
          backgroundColor: correctBg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: correctBg, // disabled(鎖定)時仍要顯眼
          disabledForegroundColor: Colors.white,
          side: BorderSide(color: correctColor.withOpacity(0.95), width: 1.2),
        );
      }
      if (_wrongOptions.contains(opt)) {
        return FilledButton.styleFrom(
          backgroundColor: wrongBg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: wrongBg,
          disabledForegroundColor: Colors.white,
          side: BorderSide(color: wrongColor.withOpacity(0.92), width: 1.0),
        );
      }
    } else {
      if (_wrongOptions.contains(opt)) {
        return FilledButton.styleFrom(
          backgroundColor: wrongBg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: wrongBg,
          disabledForegroundColor: Colors.white,
          side: BorderSide(color: wrongColor.withOpacity(0.92), width: 1.0),
        );
      }
    }
    return FilledButton.styleFrom();
  }

  Widget _optionChild({required String opt, required String answer, double fontSize = 20}) {
    final isCorrect = _locked && opt == answer;
    final isWrong = _wrongOptions.contains(opt);
    return Text(
      isCorrect
          ? '✓ $opt'
          : (isWrong ? '✗ $opt' : opt),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: (isCorrect || isWrong) ? FontWeight.w900 : FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  void _tapOption({required String opt, required String answer}) {
    if (_isFinished) return;
    if (_locked) return;
    if (_wrongOptions.contains(opt)) return;

    final correct = opt == answer;
    if (correct) {
      final firstTry = _wrongOptions.isEmpty;
      setState(() => _locked = true);
      _selectedCorrectOption = opt;
      if (_activeMode == GameMode.fWordChain) {
        // 接龍：下一題用本題答案當作 currentWord
        _chainCurrentWord = opt;
      } else {
        _chainCurrentWord = null;
      }
      _mark(true, firstTry: firstTry, countAsQuestion: true);
    } else {
      setState(() => _wrongOptions.add(opt));
      _mark(false, countAsQuestion: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbReady = _db != null;
    return WillPopScope(
      onWillPop: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('要回首頁嗎？'),
            content: const Text('目前進度會結束。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('回首頁')),
            ],
          ),
        );
        return ok ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('作答（${modeLabel(_activeMode)}）'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: Row(
                  children: [
                    Icon(levelIcon(widget.level), size: 18),
                    const SizedBox(width: 4),
                    Text(levelLabel(widget.level)),
                  ],
                ),
              ),
            ),
            if (widget.playMode == PlayMode.timeAttack && _timeLeft != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(child: Text('剩餘 ${_timeLeft}s')),
              ),
            if (widget.playMode == PlayMode.survival && _lives != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Center(child: Text('命 $_lives')),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('$_score分｜✓$_correct｜✗$_wrongTaps｜$_questions題')),
            )
          ],
        ),
        body: Container(
          child: ThemedBackground(
            themeStyle: widget.themeStyle,
            child: Padding(
            padding: const EdgeInsets.all(16),
            child: !dbReady
                ? (_initError == null
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('初始化失敗', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                Text(_initError!, style: const TextStyle(color: Colors.black54)),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _init,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重試'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    if (widget.playMode == PlayMode.timeAttack && _timeLeft != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: (_timeLeft! / (widget.goal.timeLimitSec ?? 60)).clamp(0.0, 1.0),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_feedback != null) ...[
                      Text(_feedback!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                    ],
                    Expanded(child: _buildBody()),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _isFinished ? null : _next,
                      child: Text(_activeMode == GameMode.cPairing ? '下一輪 / 下一題' : '下一題'),
                    ),
                    ],
                  ),
          ),
        ),
          ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.flavor == DataFlavor.raw) {
      return const Text(
        '你目前選擇「原始轉檔」資料庫（moe_raw.db）。\n'
        '為了避免改作/衍生風險，原始轉檔版僅保留原欄位，'
        '本 MVP 的題型引擎需要強化版 schema（word/word_char/character_pronunciation...）。\n\n'
        '請回首頁切換成「強化版」後開始遊戲。',
        style: TextStyle(height: 1.4),
      );
    }

    switch (_activeMode) {
      case GameMode.aAudioToChar:
        final q = _qA;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('聽音選字（已朗讀）：', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text(q.maskedWord, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('提示注音：${q.answerBopomofo}', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final cols = ((constraints.maxWidth) / 120).floor().clamp(2, 4);
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.7,
                    children: q.options.map((opt) {
                      return FilledButton.tonal(
                        style: _styleForOption(opt: opt, answer: q.answerChar),
                        onPressed: (_locked || _isFinished || _wrongOptions.contains(opt))
                            ? null
                            : () => _tapOption(opt: opt, answer: q.answerChar),
                        child: _optionChild(opt: opt, answer: q.answerChar, fontSize: 22),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                // A 題型：聽音猜字，為避免聽不清楚，不限制重聽次數
                onPressed: _canUseAudioHintUnlimited ? () => _useAudioHint(q.word, consume: false) : null,
                icon: const Icon(Icons.volume_up),
                label: const Text('再聽一次（不限次）'),
              ),
            ],
          ),
        );
      case GameMode.bCharToBopo:
        final q = _qB;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('看字選音：', style: Theme.of(context).textTheme.titleMedium),
              if (q.contextWord != null) ...[
                const SizedBox(height: 8),
                Text('語境：${q.contextWord}', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 10),
              Center(child: Text(q.character, style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800))),
              const SizedBox(height: 12),
              ...q.options.map((opt) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.tonal(
                    style: _styleForOption(opt: opt, answer: q.answerBopomofo),
                    onPressed: (_locked || _isFinished || _wrongOptions.contains(opt))
                        ? null
                        : () => _tapOption(opt: opt, answer: q.answerBopomofo),
                    child: _optionChild(opt: opt, answer: q.answerBopomofo, fontSize: 20),
                  ),
                );
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _canUseAudioHintLimited ? () => _useAudioHint(q.character, consume: true) : null,
                icon: const Icon(Icons.volume_up),
                label: Text('唸一遍（剩$_audioHintsLeft）'),
              ),
            ],
          ),
        );
      case GameMode.cPairing:
        final q = _qC;
        if (q == null) return const Center(child: CircularProgressIndicator());
        final totalPairs = q.words.length;
        final donePairs = _pairingMatchedWords.length;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('配對：先點「詞語」，再點對應注音（$donePairs / $totalPairs）', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text('詞語', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: q.words.map((w) {
                  final selected = _pairingSelectedWord == w;
                  final matched = _pairingMatchedWords.contains(w);
                  return ChoiceChip(
                    label: Text(w),
                    selected: selected || matched,
                    selectedColor: matched ? Colors.green.withOpacity(0.22) : null,
                    onSelected: matched || _isFinished ? null : (_) => setState(() => _pairingSelectedWord = w),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('注音', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: q.bopomos.map((b) {
                  final matched = _pairingMatchedBopos.contains(b);
                  return ActionChip(
                    label: Text(b),
                    backgroundColor: matched ? Colors.green.withOpacity(0.22) : null,
                    onPressed: matched || _isFinished
                        ? null
                        : () {
                            final w = _pairingSelectedWord;
                            if (w == null) {
                              setState(() => _feedback = '請先選一個詞語');
                              return;
                            }
                            final correct = q.answerMap[w] == b;
                            if (correct) {
                              _pairingMatchedWords.add(w);
                              _pairingMatchedBopos.add(b);
                              setState(() => _pairingSelectedWord = null);
                              // 配對題：每個配對成功加分，但「題數」以整輪完成才算 1 題
                              _mark(true, firstTry: true, countAsQuestion: false);
                              if (_pairingMatchedWords.length == totalPairs) {
                                setState(() => _feedback = '本輪完成！');
                                _countSolvedIfNeeded(solved: true, firstTry: true);
                                _checkEnd();
                              }
                            } else {
                              setState(() => _pairingSelectedWord = null);
                              _mark(false, countAsQuestion: false);
                            }
                          },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      case GameMode.dBopoToChar:
        final q = _qD;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('看注音選字：', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Center(child: Text(q.bopomofo, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800))),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final cols = ((constraints.maxWidth) / 120).floor().clamp(2, 4);
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.7,
                    children: q.options.map((opt) {
                      return FilledButton.tonal(
                        style: _styleForOption(opt: opt, answer: q.answerChar),
                        onPressed: (_locked || _isFinished || _wrongOptions.contains(opt))
                            ? null
                            : () => _tapOption(opt: opt, answer: q.answerChar),
                        child: _optionChild(opt: opt, answer: q.answerChar, fontSize: 22),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      case GameMode.eWordToBopo:
        final q = _qE;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('看詞語選注音：', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Center(child: Text(q.word, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800))),
              const SizedBox(height: 12),
              ...q.options.map((opt) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.tonal(
                    style: _styleForOption(opt: opt, answer: q.answerBopomofo),
                    onPressed: (_locked || _isFinished || _wrongOptions.contains(opt))
                        ? null
                        : () => _tapOption(opt: opt, answer: q.answerBopomofo),
                    child: _optionChild(opt: opt, answer: q.answerBopomofo, fontSize: 20),
                  ),
                );
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _canUseAudioHintLimited ? () => _useAudioHint(q.word, consume: true) : null,
                icon: const Icon(Icons.volume_up),
                label: Text('唸一遍（剩$_audioHintsLeft）'),
              ),
            ],
          ),
        );
      case GameMode.fWordChain:
        final q = _qF;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('語詞接龍：選出下一個詞語', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text('目前詞語', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Center(child: Text(q.currentWord, style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900))),
              const SizedBox(height: 10),
              Text('下一個詞語要以「${q.targetStartChar}」開頭：', style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 10),
              ...q.options.map((opt) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.tonal(
                    style: _styleForOption(opt: opt, answer: q.answerWord),
                    onPressed: (_locked || _isFinished || _wrongOptions.contains(opt))
                        ? null
                        : () => _tapOption(opt: opt, answer: q.answerWord),
                    child: _optionChild(opt: opt, answer: q.answerWord, fontSize: 22),
                  ),
                );
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _canUseAudioHintLimited ? () => _useAudioHint(q.currentWord, consume: true) : null,
                icon: const Icon(Icons.volume_up),
                label: Text('再聽一次（剩$_audioHintsLeft）'),
              ),
            ],
          ),
        );
      case GameMode.mix:
        // 不會走到這裡（mix 會在 _pickActiveMode 轉成實際題型）
        return const SizedBox.shrink();
    }
  }
}

/// 用「漸層 + 淡淡的圖案」做背景，不影響題目/答案閱讀。
class ThemedBackground extends StatelessWidget {
  const ThemedBackground({super.key, required this.themeStyle, required this.child});
  final ThemeStyle themeStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = themeVisual(themeStyle);
    final icons = spec.decoIcons;

    return Stack(
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
        // 裝飾圖案：低透明度、避免遮擋內容（放在邊角）
        Positioned(
          top: 18,
          right: 10,
          child: Opacity(
            opacity: 0.22,
            child: spec.decoTopAsset != null
                ? Image.asset(spec.decoTopAsset!, width: 170, height: 170, fit: BoxFit.contain)
                : Icon(icons[0], size: 88),
          ),
        ),
        Positioned(
          bottom: 10,
          left: 10,
          child: Opacity(
            opacity: 0.18,
            child: spec.decoBottomAsset != null
                ? Image.asset(spec.decoBottomAsset!, width: 200, height: 200, fit: BoxFit.contain)
                : Icon(icons[1], size: 110),
          ),
        ),
        // 額外貼紙：讓「角色圖案」更明顯（仍保持不干擾閱讀）
        if (spec.badgeAsset != null)
          Positioned(
            top: 86,
            left: 14,
            child: Opacity(
              opacity: 0.10,
              child: Image.asset(spec.badgeAsset!, width: 110, height: 110, fit: BoxFit.contain),
            ),
          ),
        if (spec.badgeAsset != null)
          Positioned(
            bottom: 110,
            right: 18,
            child: Opacity(
              opacity: 0.08,
              child: Image.asset(spec.badgeAsset!, width: 120, height: 120, fit: BoxFit.contain),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}
