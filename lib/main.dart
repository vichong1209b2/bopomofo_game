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

enum GameMode { aAudioToChar, bCharToBopo, cPairing }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GameMode _mode = GameMode.aAudioToChar;
  DataFlavor _flavor = DataFlavor.enhanced;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bopomofo Game')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const Spacer(),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GamePage(mode: _mode, flavor: _flavor),
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

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.mode, required this.flavor});
  final GameMode mode;
  final DataFlavor flavor;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  DbService? _db;
  final FlutterTts _tts = FlutterTts();

  int _score = 0;
  int _total = 0;
  String? _feedback;

  AudioToCharQuestion? _qA;
  CharToBopoQuestion? _qB;
  PairingRound? _qC;

  String? _pairingSelectedWord;

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
    await _next();
  }

  @override
  void dispose() {
    _db?.close();
    _tts.stop();
    super.dispose();
  }

  Future<void> _next() async {
    setState(() {
      _feedback = null;
      _qA = null;
      _qB = null;
      _qC = null;
      _pairingSelectedWord = null;
    });

    final db = _db;
    if (db == null) return;

    try {
      if (widget.mode == GameMode.aAudioToChar) {
        final q = await db.randomAudioToCharQuestion();
        setState(() => _qA = q);
        // 朗讀詞語（注音本身 TTS 不一定能順利朗讀）
        await _tts.speak(q.word);
      } else if (widget.mode == GameMode.bCharToBopo) {
        final q = await db.randomCharToBopoQuestion();
        setState(() => _qB = q);
      } else {
        final q = await db.randomPairingRound();
        setState(() => _qC = q);
      }
    } catch (e) {
      setState(() => _feedback = '出題失敗：$e');
    }
  }

  void _mark(bool correct) {
    setState(() {
      _total += 1;
      if (correct) _score += 1;
      _feedback = correct ? '答對！' : '答錯';
    });
  }

  @override
  Widget build(BuildContext context) {
    final dbReady = _db != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('作答'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('$_score / $_total')),
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
                    Text(_feedback!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                  ],
                  Expanded(child: _buildBody()),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _next, child: const Text('下一題')),
                ],
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

    switch (widget.mode) {
      case GameMode.aAudioToChar:
        final q = _qA;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return Column(
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
                    onPressed: () {
                      final correct = opt == q.answerChar;
                      _mark(correct);
                    },
                    child: Text(opt, style: const TextStyle(fontSize: 22)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _tts.speak(q.word),
              icon: const Icon(Icons.volume_up),
              label: const Text('再聽一次'),
            ),
          ],
        );
      case GameMode.bCharToBopo:
        final q = _qB;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return Column(
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
                  onPressed: () => _mark(opt == q.answerBopomofo),
                  child: Text(opt, style: const TextStyle(fontSize: 20)),
                ),
              );
            }),
          ],
        );
      case GameMode.cPairing:
        final q = _qC;
        if (q == null) return const Center(child: CircularProgressIndicator());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('配對：先點「詞語」，再點對應注音', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text('詞語', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: q.words.map((w) {
                final selected = _pairingSelectedWord == w;
                return ChoiceChip(
                  label: Text(w),
                  selected: selected,
                  onSelected: (_) => setState(() => _pairingSelectedWord = w),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('注音', style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: q.bopomos.map((b) {
                return ActionChip(
                  label: Text(b),
                  onPressed: () {
                    final w = _pairingSelectedWord;
                    if (w == null) {
                      setState(() => _feedback = '請先選一個詞語');
                      return;
                    }
                    final correct = q.answerMap[w] == b;
                    _mark(correct);
                    setState(() => _pairingSelectedWord = null);
                  },
                );
              }).toList(),
            ),
          ],
        );
    }
  }
}

