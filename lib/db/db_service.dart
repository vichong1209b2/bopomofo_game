import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../game_config.dart';
import '../models.dart';

enum DataFlavor { enhanced, raw }

class DbService {
  DbService._(this._db);
  final Database _db;

  static Future<DbService> open({DataFlavor flavor = DataFlavor.enhanced}) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, flavor == DataFlavor.enhanced ? 'moe_enhanced.db' : 'moe_raw.db');

    if (!File(dbPath).existsSync()) {
      final asset = flavor == DataFlavor.enhanced ? 'assets/db/moe_enhanced.db' : 'assets/db/moe_raw.db';
      final bytes = await rootBundle.load(asset);
      await File(dbPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }

    final db = await openDatabase(dbPath, readOnly: true);
    return DbService._(db);
  }

  Future<void> close() => _db.close();

  // ====== 等級過濾（教育分級） ======

  static ({String where, List<Object?> args}) _wordLevelWhere(EducationLevel level, {String alias = 'w'}) {
    final r = ruleForLevel(level);
    final parts = <String>[];
    final args = <Object?>[];

    parts.add('$alias.difficulty <= ?');
    args.add(r.maxWordDifficulty);

    // 國小：只用國小字詞
    if (r.requirePrimaryWords) {
      parts.add('$alias.is_primary_school = 1');
    }

    // 國中：至少是「常用」或「國小」
    if (level == EducationLevel.juniorHigh) {
      parts.add('($alias.is_common = 1 OR $alias.is_primary_school = 1)');
    }

    // 高中/大學：以常用為主
    if (r.requireCommonWords) {
      parts.add('$alias.is_common = 1');
    }

    if (!r.includeLowPriorityWords) {
      parts.add("$alias.game_priority != 'low'");
    }

    return (where: parts.join(' AND '), args: args);
  }

  static ({String where, List<Object?> args}) _charLevelWhere(EducationLevel level, {String alias = 'c'}) {
    final r = ruleForLevel(level);
    final parts = <String>[];
    final args = <Object?>[];

    if (r.requirePrimaryChars) {
      parts.add('$alias.is_primary_school = 1');
    } else if (r.requireCommonChars) {
      // 讓國小/常用都進來（高等級範圍涵蓋低等級）
      parts.add('($alias.is_common = 1 OR $alias.is_primary_school = 1)');
    }

    if (!r.includeLowPriorityChars) {
      parts.add("$alias.game_priority != 'low'");
    }

    return (where: parts.isEmpty ? '1=1' : parts.join(' AND '), args: args);
  }

  static ({String where, List<Object?> args}) _cpLevelWhere(EducationLevel level, {String alias = 'cp'}) {
    // pronunciation 沒有 primary/common 欄位，只有 priority
    final r = ruleForLevel(level);
    if (r.includeLowPriorityChars) return (where: '1=1', args: const []);
    return (where: "$alias.game_priority != 'low'", args: const []);
  }

  // ====== 題型 A：聽音選字（TTS 朗讀詞語） ======

  Future<AudioToCharQuestion> randomAudioToCharQuestion({
    int optionCount = 4,
    EducationLevel level = EducationLevel.juniorHigh,
  }) async {
    final wFilter = _wordLevelWhere(level, alias: 'w');
    final w = await _db.rawQuery(r'''
      SELECT w.word_id, w.word, w.bopomofo
      FROM word w
      WHERE ''' +
        wFilter.where +
        r'''
        AND w.allow_audio_to_char = 1
        AND EXISTS (
          SELECT 1 FROM word_char wc
          WHERE wc.word_id = w.word_id AND wc.cp_id IS NOT NULL
        )
      ORDER BY RANDOM()
      LIMIT 1
    ''', wFilter.args);
    if (w.isEmpty) {
      throw StateError('找不到可用的詞語（請確認資料庫已包含 enhanced schema）。');
    }

    final wordId = (w.first['word_id'] as int);
    final word = (w.first['word'] as String);
    final bopomofo = (w.first['bopomofo'] as String?) ?? '';

    final wc = await _db.rawQuery(r'''
      SELECT wc.position, c.char AS answer_char, cp.bopomofo AS answer_bopo
      FROM word_char wc
      JOIN character c ON c.char_id = wc.char_id
      JOIN character_pronunciation cp ON cp.cp_id = wc.cp_id
      WHERE wc.word_id = ?
        AND wc.cp_id IS NOT NULL
      ORDER BY RANDOM()
      LIMIT 1
    ''', [wordId]);

    final position = (wc.first['position'] as int);
    final answerChar = (wc.first['answer_char'] as String);
    final answerBopo = (wc.first['answer_bopo'] as String);

    // 同音干擾：同注音找其他字
    final distractors = <String>[];
    final tries = 24;
    for (var t = 0; t < tries && distractors.length < optionCount - 1; t++) {
      final rows = await _db.rawQuery(r'''
        SELECT DISTINCT c.char AS ch
        FROM character_pronunciation cp
        JOIN character c ON c.char_id = cp.char_id
        WHERE cp.bopomofo = ?
          AND c.char != ?
          AND cp.game_priority != 'low'
        ORDER BY RANDOM()
        LIMIT 1
      ''', [answerBopo, answerChar]);
      if (rows.isEmpty) continue;
      final cand = rows.first['ch'] as String;
      if (distractors.contains(cand)) continue;

      // 去歧義：替換後如果形成另一個常見詞，就跳過（避免雙解）
      final newWord = _replaceAt(word, position, cand);
      final check = await _db.rawQuery(
        'SELECT 1 FROM word WHERE word = ? AND is_common = 1 LIMIT 1',
        [newWord],
      );
      if (check.isNotEmpty) continue;
      distractors.add(cand);
    }

    while (distractors.length < optionCount - 1) {
      distractors.add(_randomCjkCharFallback(exclude: {answerChar, ...distractors}));
    }

    final options = <String>[answerChar, ...distractors]..shuffle(Random());

    return AudioToCharQuestion(
      wordId: wordId,
      word: word,
      bopomofo: bopomofo,
      position: position,
      answerChar: answerChar,
      answerBopomofo: answerBopo,
      options: options,
    );
  }

  // ====== 題型 B：看字選音（先用單音字避免歧義） ======

  Future<CharToBopoQuestion> randomCharToBopoQuestion({
    int optionCount = 4,
    EducationLevel level = EducationLevel.juniorHigh,
  }) async {
    final cFilter = _charLevelWhere(level, alias: 'c');
    final cpFilter = _cpLevelWhere(level, alias: 'cp');
    final rows = await _db.rawQuery(r'''
      SELECT c.char AS ch, cp.bopomofo AS bopo
      FROM character c
      JOIN character_pronunciation cp ON cp.char_id = c.char_id
      WHERE ''' +
        cFilter.where +
        r'''
        AND ''' +
        cpFilter.where +
        r'''
        AND (SELECT COUNT(*) FROM character_pronunciation cp2 WHERE cp2.char_id = c.char_id) = 1
      ORDER BY RANDOM()
      LIMIT 1
    ''', [...cFilter.args, ...cpFilter.args]);
    if (rows.isEmpty) {
      throw StateError('找不到可用的單音字題目。');
    }

    final ch = rows.first['ch'] as String;
    final answer = rows.first['bopo'] as String;

    final distractors = <String>[];
    final base = _stripTone(answer);
    final baseLen = _runeLen(base);

    // 優先：同一個注音但不同聲調（增加混淆）
    final toneLike = await _db.rawQuery(r'''
      SELECT DISTINCT bopomofo
      FROM character_pronunciation
      WHERE bopomofo != ''
        AND bopomofo != ?
        AND bopomofo LIKE ?
        AND length(bopomofo) <= ?
      ORDER BY RANDOM()
      LIMIT 24
    ''', [answer, '$base%', baseLen + 1]);
    for (final r in toneLike) {
      final b = (r['bopomofo'] as String?) ?? '';
      if (b.isEmpty) continue;
      if (_stripTone(b) != base) continue;
      if (!distractors.contains(b)) distractors.add(b);
      if (distractors.length >= optionCount - 1) break;
    }

    // 補齊：隨機其他注音（同題型不同難度可再調整）
    if (distractors.length < optionCount - 1) {
      final other = await _db.rawQuery(r'''
        SELECT DISTINCT bopomofo
        FROM character_pronunciation
        WHERE bopomofo != ''
          AND bopomofo != ?
        ORDER BY RANDOM()
        LIMIT ?
      ''', [answer, 60]);
      for (final r in other) {
        final b = (r['bopomofo'] as String?) ?? '';
        if (b.isEmpty) continue;
        if (b == answer) continue;
        if (!distractors.contains(b)) distractors.add(b);
        if (distractors.length >= optionCount - 1) break;
      }
    }

    while (distractors.length < optionCount - 1) {
      distractors.add(_randomBopoFallback(exclude: {answer, ...distractors}));
    }

    final options = <String>[answer, ...distractors]..shuffle(Random());
    return CharToBopoQuestion(character: ch, answerBopomofo: answer, options: options);
  }

  // ====== 題型 D：看注音選字（Bopo → Char） ======

  Future<BopoToCharQuestion> randomBopoToCharQuestion({
    int optionCount = 4,
    EducationLevel level = EducationLevel.juniorHigh,
  }) async {
    final cFilter = _charLevelWhere(level, alias: 'c');
    final cpFilter = _cpLevelWhere(level, alias: 'cp');
    final rows = await _db.rawQuery(r'''
      SELECT cp.bopomofo AS bopo, c.char AS ch
      FROM character_pronunciation cp
      JOIN character c ON c.char_id = cp.char_id
      WHERE ''' +
        cpFilter.where +
        r'''
        AND ''' +
        cFilter.where +
        r'''
        AND cp.bopomofo != ''
      ORDER BY RANDOM()
      LIMIT 1
    ''', [...cpFilter.args, ...cFilter.args]);
    if (rows.isEmpty) {
      throw StateError('找不到可用的「注音→選字」題目。');
    }

    final bopomofo = rows.first['bopo'] as String;
    final answerChar = rows.first['ch'] as String;

    final distractors = <String>[];
    final base = _stripTone(bopomofo);
    final baseLen = _runeLen(base);

    // 優先：同注音不同聲調的字（更容易混淆）
    final near = await _db.rawQuery(r'''
      SELECT DISTINCT c.char AS ch, cp.bopomofo AS bopo
      FROM character_pronunciation cp
      JOIN character c ON c.char_id = cp.char_id
      WHERE cp.game_priority != 'low'
        AND c.game_priority != 'low'
        AND cp.bopomofo != ''
        AND cp.bopomofo != ?
        AND cp.bopomofo LIKE ?
        AND length(cp.bopomofo) <= ?
      ORDER BY RANDOM()
      LIMIT 36
    ''', [bopomofo, '$base%', baseLen + 1]);
    for (final r in near) {
      final ch = (r['ch'] as String?) ?? '';
      final b = (r['bopo'] as String?) ?? '';
      if (ch.isEmpty) continue;
      if (ch == answerChar) continue;
      if (_stripTone(b) != base) continue;
      if (!distractors.contains(ch)) distractors.add(ch);
      if (distractors.length >= optionCount - 1) break;
    }

    // 補齊：隨機字
    if (distractors.length < optionCount - 1) {
      final other = await _db.rawQuery(r'''
        SELECT c.char AS ch
        FROM character c
        WHERE c.game_priority != 'low'
          AND c.char != ?
        ORDER BY RANDOM()
        LIMIT ?
      ''', [answerChar, 80]);
      for (final r in other) {
        final ch = (r['ch'] as String?) ?? '';
        if (ch.isEmpty) continue;
        if (!distractors.contains(ch)) distractors.add(ch);
        if (distractors.length >= optionCount - 1) break;
      }
    }

    final options = <String>[answerChar, ...distractors.take(optionCount - 1)]..shuffle(Random());
    return BopoToCharQuestion(bopomofo: bopomofo, answerChar: answerChar, options: options);
  }

  // ====== 題型 E：看詞語選注音（Word → Bopo） ======

  Future<WordToBopoQuestion> randomWordToBopoQuestion({
    int optionCount = 4,
    EducationLevel level = EducationLevel.juniorHigh,
  }) async {
    final wFilter = _wordLevelWhere(level, alias: 'w');
    final rows = await _db.rawQuery(r'''
      SELECT w.word_id, w.word, w.bopomofo
      FROM word w
      WHERE ''' +
        wFilter.where +
        r'''
        AND w.bopomofo != ''
      ORDER BY RANDOM()
      LIMIT 1
    ''', wFilter.args);
    if (rows.isEmpty) {
      throw StateError('找不到可用的「詞語→選注音」題目。');
    }

    final wordId = rows.first['word_id'] as int;
    final word = rows.first['word'] as String;
    final answer = (rows.first['bopomofo'] as String?) ?? '';

    final ansSyl = _syllables(answer);
    final ansBase = ansSyl.map(_stripTone).toList(growable: false);
    final ansBaseJoined = ansBase.join(' ');

    // 抽一批候選，再用 Dart 做「同音/同長度/同聲調變化」篩選
    final pool = await _db.rawQuery(r'''
      SELECT DISTINCT bopomofo
      FROM word
      WHERE bopomofo != ''
        AND bopomofo != ?
      ORDER BY RANDOM()
      LIMIT 320
    ''', [answer]);

    final sameLenToneVariant = <String>[];
    final sameLenSimilar = <String>[];
    final sameLenAny = <String>[];

    for (final r in pool) {
      final b = (r['bopomofo'] as String?) ?? '';
      if (b.isEmpty) continue;
      final syl = _syllables(b);
      if (syl.length != ansSyl.length) continue;
      sameLenAny.add(b);

      final base = syl.map(_stripTone).toList(growable: false).join(' ');
      if (base == ansBaseJoined && b != answer) {
        sameLenToneVariant.add(b); // 同音不同調（或部分不同調）
        continue;
      }

      // 至少有一個音節 base 相同
      var shared = 0;
      for (var i = 0; i < syl.length; i++) {
        if (_stripTone(syl[i]) == ansBase[i]) shared++;
      }
      if (shared >= 1) sameLenSimilar.add(b);
    }

    final distractors = <String>[];
    void pickFrom(List<String> src) {
      src.shuffle(Random());
      for (final b in src) {
        if (b == answer) continue;
        if (!distractors.contains(b)) distractors.add(b);
        if (distractors.length >= optionCount - 1) break;
      }
    }

    // 優先：同音不同調（最容易誤判）
    pickFrom(sameLenToneVariant);
    // 次要：同長度且部分音節相同
    if (distractors.length < optionCount - 1) pickFrom(sameLenSimilar);
    // 最後：同長度隨機
    if (distractors.length < optionCount - 1) pickFrom(sameLenAny);

    while (distractors.length < optionCount - 1) {
      // fallback：若真的找不到同長度，至少給一般隨機（避免卡住）
      distractors.add(_randomBopoFallback(exclude: {answer, ...distractors}));
    }

    final options = <String>[answer, ...distractors]..shuffle(Random());
    return WordToBopoQuestion(wordId: wordId, word: word, answerBopomofo: answer, options: options);
  }

  // ====== 題型 C：配對（詞語 ↔ 注音） ======

  Future<PairingRound> randomPairingRound({
    int pairCount = 4,
    EducationLevel level = EducationLevel.juniorHigh,
  }) async {
    final wFilter = _wordLevelWhere(level, alias: 'word');
    final rows = await _db.rawQuery(r'''
      SELECT word, bopomofo
      FROM word
      WHERE ''' +
        wFilter.where +
        r'''
        AND bopomofo != ''
        AND allow_pairing = 1
      ORDER BY RANDOM()
      LIMIT ?
    ''', [...wFilter.args, pairCount]);
    if (rows.length < pairCount) {
      throw StateError('可用配對題不足。');
    }
    final answerMap = <String, String>{};
    for (final r in rows) {
      answerMap[r['word'] as String] = (r['bopomofo'] as String?) ?? '';
    }
    final words = answerMap.keys.toList()..shuffle(Random());
    final bopomos = answerMap.values.toList()..shuffle(Random());
    return PairingRound(words: words, bopomos: bopomos, answerMap: answerMap);
  }

  // ====== 題型 F：語詞接龍（填空/選擇） ======

  /// 產生「接龍」題目：顯示 currentWord，下一個詞語必須以 lastChar 開頭。
  ///
  /// - 若傳入 currentWord，會以它的最後一字作為接龍條件
  /// - 否則會自動挑一個「有後繼」的詞語當作 currentWord
  Future<WordChainQuestion> randomWordChainQuestion({
    String? currentWord,
    int optionCount = 4,
    EducationLevel level = EducationLevel.juniorHigh,
  }) async {
    String baseWord = currentWord ?? '';
    final wFilter = _wordLevelWhere(level, alias: 'w');
    final w2Filter = _wordLevelWhere(level, alias: 'w2');

    // ⚠️ #18 開始卡住的主因：原本用 EXISTS + ORDER BY RANDOM 的「保證有後繼」挑字，
    // 在部分手機/資料量下會非常慢（看起來像 DB 卡住）。
    // 這裡改成「先隨機抽 baseWord，再檢查是否能接」，最多嘗試多次，避免一次就跑重查詢。

    Future<String> _lastCharOf(String w) async {
      final lastCharRows = await _db.rawQuery(
        'SELECT substr(?, length(?), 1) AS last_char',
        [w, w],
      );
      return (lastCharRows.first['last_char'] as String?) ?? '';
    }

    Future<String?> _randomNextWord(String base, String lastChar) async {
      final answerRows = await _db.rawQuery(r'''
        SELECT w2.word AS w
        FROM word w2
        WHERE ''' +
          w2Filter.where +
          r'''
          AND w2.is_common = 1
          AND w2.word != ?
          AND length(w2.word) BETWEEN 2 AND 6
          AND substr(w2.word, 1, 1) = ?
        ORDER BY RANDOM()
        LIMIT 1
      ''', [...w2Filter.args, base, lastChar]);
      if (answerRows.isEmpty) return null;
      return answerRows.first['w'] as String;
    }

    String lastChar = '';
    String answerWord = '';

    if (baseWord.isEmpty) {
      const maxPickTries = 40;
      for (var i = 0; i < maxPickTries; i++) {
        final rows = await _db.rawQuery(r'''
          SELECT w.word AS w
          FROM word w
          WHERE ''' +
            wFilter.where +
            r'''
            AND w.is_common = 1
            AND length(w.word) BETWEEN 2 AND 6
          ORDER BY RANDOM()
          LIMIT 1
        ''', wFilter.args);
        if (rows.isEmpty) break;
        final cand = rows.first['w'] as String;
        final lc = await _lastCharOf(cand);
        if (lc.isEmpty) continue;
        final ans = await _randomNextWord(cand, lc);
        if (ans == null) continue;
        baseWord = cand;
        lastChar = lc;
        answerWord = ans;
        break;
      }
      if (answerWord.isEmpty) {
        throw StateError('找不到可用的接龍詞語（請確認資料庫 word 表存在且有 common 標記）。');
      }
    } else {
      lastChar = await _lastCharOf(baseWord);
      if (lastChar.isEmpty) {
        throw StateError('接龍出題失敗：無法取得詞語最後一字。');
      }
      final ans = await _randomNextWord(baseWord, lastChar);
      if (ans == null) {
        // fallback：若 baseWord 是使用者指定、剛好接不到，就改抽一個能接的
        if (currentWord != null) {
          return randomWordChainQuestion(currentWord: null, optionCount: optionCount, level: level);
        }
        throw StateError('找不到可接「$lastChar」開頭的詞語。');
      }
      answerWord = ans;
    }

    // 干擾：不以 lastChar 開頭
    final distractors = <String>[];
    final need = max(0, optionCount - 1);
    if (need > 0) {
      final r = await _db.rawQuery(r'''
        SELECT w.word AS w
        FROM word w
        WHERE ''' +
          wFilter.where +
          r'''
          AND w.is_common = 1
          AND length(w.word) BETWEEN 2 AND 6
          AND w.word != ?
          AND w.word != ?
          AND substr(w.word, 1, 1) != ?
        ORDER BY RANDOM()
        LIMIT ?
      ''', [...wFilter.args, baseWord, answerWord, lastChar, need]);
      for (final row in r) {
        final w = row['w'] as String;
        if (w == answerWord) continue;
        if (distractors.contains(w)) continue;
        distractors.add(w);
      }
    }

    while (distractors.length < optionCount - 1) {
      distractors.add(_randomCjkCharFallback(exclude: {answerWord, ...distractors}));
    }

    final options = <String>[answerWord, ...distractors]..shuffle(Random());
    return WordChainQuestion(
      currentWord: baseWord,
      targetStartChar: lastChar,
      answerWord: answerWord,
      options: options,
    );
  }

  // ====== helpers ======

  static const _toneMarks = ['˙', 'ˊ', 'ˇ', 'ˋ'];

  static String _stripTone(String s) {
    var out = s;
    for (final t in _toneMarks) {
      out = out.replaceAll(t, '');
    }
    return out.trim();
  }

  static int _runeLen(String s) => s.runes.length;

  static List<String> _syllables(String bopomofo) {
    final s = bopomofo.trim();
    if (s.isEmpty) return const [];
    // 教育部資料通常用空白分隔音節
    final parts = s.split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? [s] : parts;
  }

  static String _randomBopoFallback({required Set<String> exclude}) {
    // 簡單 fallback：從常見注音符號中組合（避免完全空白）
    const pool = ['ㄅ', 'ㄆ', 'ㄇ', 'ㄈ', 'ㄉ', 'ㄊ', 'ㄋ', 'ㄌ', 'ㄍ', 'ㄎ', 'ㄏ', 'ㄐ', 'ㄑ', 'ㄒ', 'ㄓ', 'ㄔ', 'ㄕ', 'ㄖ', 'ㄗ', 'ㄘ', 'ㄙ', 'ㄧ', 'ㄨ', 'ㄩ', 'ㄚ', 'ㄛ', 'ㄜ', 'ㄝ', 'ㄞ', 'ㄟ', 'ㄠ', 'ㄡ', 'ㄢ', 'ㄣ', 'ㄤ', 'ㄥ', 'ㄦ', '˙', 'ˊ', 'ˇ', 'ˋ'];
    for (var i = 0; i < 60; i++) {
      final len = 2 + _rng.nextInt(3);
      var s = '';
      for (var j = 0; j < len; j++) {
        s += pool[_rng.nextInt(pool.length)];
      }
      if (!exclude.contains(s)) return s;
    }
    return 'ㄧ';
  }

  static String _replaceAt(String s, int index, String replacement) {
    final chars = s.split("");
    if (index < 0 || index >= chars.length) return s;
    chars[index] = replacement;
    return chars.join();
  }

  static final _rng = Random();
  static String _randomCjkCharFallback({required Set<String> exclude}) {
    const pool = "的一是不在人有我他這個們中來上大為和國地到以說時要就出會可也你對生能而子那得於著下自之年過發後作里用道行所然家種事成方多經麼去法學如都同現當沒動面起看定天分還進好小部其些主樣理心她本前開但因只從想實日軍者意無力它與長把機十民第公此已工使情明性知全三又關點正業外將兩高間由問很最重並物手應戰向頭文體政美相見被利什二等產或新己制身果加西斯月話合回特代內信表化老給世位次度門任常先海通教兒原東聲提立及比員解水名真論處走義各入幾口認條平系氣題活爾更別打女變四神總何電數安少報才結反受目太量再感建務做接必場件計管期市直德資命山金指克許統區保至隊形社便空決治展馬科司五基眼書非則聽白卻界達光放強即像難且權思王象完設式色路記南品住告類求據程北邊死張該交規萬取拉格望覺術領共確傳師觀清今切院讓識候帶導爭運笑飛風步改收根干造言聯持組每濟車親極林服快辦議往元英士證近失轉夫令準布始怎呢存未遠叫台單影具羅字愛擊流備兵連調深商算質團集百需價花黨華城石級整府離況亞請技際約示復病息究線似官火斷精滿支視消越器容照須九增研寫稱企八功嗎包片史委乎查輕易早曾除農找裝廣顯吧阿李標談吃圖念六引歷首醫局突專費號盡另周較注語僅考落青隨選列武紅響雖推勢參希古眾構房半節土投某案黑維革劃敵致陳律足態護七興派孩驗責營星夠章音跟志底站嚴巴例防族供效續施留講型料終答緊黃絕奇察母京段依批群項故按河米圍江織害斗雙境客紀採舉殺攻父蘇密低朝友訴止細願千值仍男錢破網熱助倒育屬坐帝限船臉職速刻樂否剛威毛狀率甚獨球般普怕彈校苦創假久錯承印晚蘭試股拿腦預誰益陽若哪微尼繼送急血驚傷素藥適波夜省初喜衛源食險待述陸習置居勞財環排福納歡雷警獲模充負雲停木遊龍樹疑層冷洲衝射略範竟句室異激漢村哈策演簡卡罪判擔州靜退既衣您宗積餘痛檢差富靈協角占配征修皮揮勝降階審沉堅善媽劉讀啊超免壓銀買皇養伊懷執副亂抗犯追幫宣佛歲航優怪香著田鐵控稅左右份穿藝背陣草腳概惡塊頓敢守酒島託央戶烈洋哥索胡款靠評版寶座釋景顧弟登貨互付伯慢歐換聞危忙核暗姐介壞討麗良序升監臨亮露永呼味野架域沙掉括艦魚雜誤灣吉減編楚肯測敗屋跑夢散溫困輪庫醒毫鼓播谷賣尚盤否";
    for (var i = 0; i < 20; i++) {
      final ch = pool[_rng.nextInt(pool.length)];
      if (!exclude.contains(ch)) return ch;
    }
    return "他";
  }
}
