import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'db/db_service.dart';
import 'models.dart';

void main() {
  runApp(const BopoGameApp());
}

class BopoGameApp extends StatelessWidget {
  const BopoGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bopomofo Game',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
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
  mix,
}

/// 「題型」與「玩法」分開：
/// - GameMode：每題長什麼樣（A/B/C/D/E/混合）
/// - PlayMode：整體規則（計分/目標/限時/生命…）
enum PlayMode { practice, scoreTarget, correctTarget, timeAttack, survival }

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

  const GameSettings({
    required this.mode,
    required this.flavor,
    required this.playMode,
    required this.goal,
  });

  GameSettings copyWith({GameMode? mode, DataFlavor? flavor, PlayMode? playMode, GameGoal? goal}) {
    return GameSettings(
      mode: mode ?? this.mode,
      flavor: flavor ?? this.flavor,
      playMode: playMode ?? this.playMode,
      goal: goal ?? this.goal,
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
      return '限時';
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
    mode: GameMode.aAudioToChar,
    flavor: DataFlavor.enhanced,
    playMode: PlayMode.scoreTarget,
    goal: defaultGoalFor(PlayMode.scoreTarget),
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
        title: const Text('Bopomofo Game'),
        actions: [
          IconButton(
            tooltip: '設定',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                  ),
                ));
              },
              child: const Text('開始'),
            ),
          ],
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
    Navigator.of(context).pop(GameSettings(mode: _mode, flavor: _flavor, playMode: _playMode, goal: _goal));
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              ButtonSegment(value: PlayMode.timeAttack, label: Text('限時')),
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
  });
  final GameMode mode;
  final DataFlavor flavor;
  final PlayMode playMode;
  final GameGoal goal;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  DbService? _db;
  final FlutterTts _tts = FlutterTts();

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
    _init();
  }

  Future<void> _init() async {
    final db = await DbService.open(flavor: widget.flavor);
    await _tts.setLanguage('zh-TW');
    await _tts.setSpeechRate(0.45);
    setState(() => _db = db);

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
        final q = await db.randomAudioToCharQuestion();
        setState(() => _qA = q);
        // 朗讀詞語（注音本身 TTS 不一定能順利朗讀）
        await _tts.speak(q.word);
      } else if (_activeMode == GameMode.bCharToBopo) {
        final q = await db.randomCharToBopoQuestion();
        setState(() => _qB = q);
      } else if (_activeMode == GameMode.cPairing) {
        final q = await db.randomPairingRound();
        setState(() => _qC = q);
      } else if (_activeMode == GameMode.dBopoToChar) {
        final q = await db.randomBopoToCharQuestion();
        setState(() => _qD = q);
      } else if (_activeMode == GameMode.eWordToBopo) {
        final q = await db.randomWordToBopoQuestion();
        setState(() => _qE = q);
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
              Text('答對：$_correct / $_questions'),
              Text('錯誤點擊：$_wrongTaps'),
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

  ButtonStyle _styleForOption({required String opt, required String answer}) {
    final correctColor = Colors.blue;
    final wrongColor = Colors.red;

    if (_locked) {
      if (opt == answer) {
        return FilledButton.styleFrom(
          backgroundColor: correctColor.withOpacity(0.18),
          foregroundColor: correctColor.shade800,
        );
      }
      if (_wrongOptions.contains(opt)) {
        return FilledButton.styleFrom(
          backgroundColor: wrongColor.withOpacity(0.15),
          foregroundColor: wrongColor.shade800,
        );
      }
    } else {
      if (_wrongOptions.contains(opt)) {
        return FilledButton.styleFrom(
          backgroundColor: wrongColor.withOpacity(0.15),
          foregroundColor: wrongColor.shade800,
        );
      }
    }
    return FilledButton.styleFrom();
  }

  Widget _optionChild({required String opt, required String answer, double fontSize = 20}) {
    final isCorrect = _locked && opt == answer;
    if (!isCorrect) return Text(opt, style: TextStyle(fontSize: fontSize));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(opt, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700))),
        const SizedBox(width: 6),
        Icon(Icons.sentiment_satisfied_alt, size: fontSize, color: Colors.blue.shade700),
      ],
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
              child: Center(child: Text('$_score 分｜$_correct/$_questions 題')),
            )
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: !dbReady
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: q.options.map((opt) {
                  return SizedBox(
                    width: 72,
                    height: 56,
                    child: FilledButton.tonal(
                      style: _styleForOption(opt: opt, answer: q.answerChar),
                      onPressed: (_locked || _isFinished || _wrongOptions.contains(opt))
                          ? null
                          : () => _tapOption(opt: opt, answer: q.answerChar),
                      child: _optionChild(opt: opt, answer: q.answerChar, fontSize: 22),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isFinished ? null : () => _tts.speak(q.word),
                icon: const Icon(Icons.volume_up),
                label: const Text('再聽一次'),
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: q.options.map((opt) {
                  return SizedBox(
                    width: 72,
                    height: 56,
                    child: FilledButton.tonal(
                      style: _styleForOption(opt: opt, answer: q.answerChar),
                      onPressed: (_locked || _isFinished || _wrongOptions.contains(opt))
                          ? null
                          : () => _tapOption(opt: opt, answer: q.answerChar),
                      child: _optionChild(opt: opt, answer: q.answerChar, fontSize: 22),
                    ),
                  );
                }).toList(),
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
            ],
          ),
        );
      case GameMode.mix:
        // 不會走到這裡（mix 會在 _pickActiveMode 轉成實際題型）
        return const SizedBox.shrink();
    }
  }
}
