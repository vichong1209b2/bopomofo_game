import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../game_config.dart';
import '../debug/app_logger.dart';
import '../models.dart';

enum DataFlavor { enhanced, raw }

class DbService {
  DbService._(this._db);
  final Database _db;
  int? _maxWordIdCache;

  /// 題庫不足時的等級放寬策略：
  /// - 只能在同學段內逐級放寬（不跨到下一學段）
  /// - 例如：國小二年級 → 2→3→4→5→6（不會跳到國中）
  static List<EducationLevel> _fallbackLevelsWithinStage(EducationLevel level) {
    // 若使用「All」則不需要再放寬
    if (level == EducationLevel.elementaryAll ||
        level == EducationLevel.juniorHighAll ||
        level == EducationLevel.seniorHighAll) {
      return [level];
    }

    final stage = stageForLevel(level);
    final out = <EducationLevel>[];

    switch (stage) {
      case EducationStage.elementary:
        final start = switch (level) {
          EducationLevel.elementary1 => 1,
          EducationLevel.elementary2 => 2,
          EducationLevel.elementary3 => 3,
          EducationLevel.elementary4 => 4,
          EducationLevel.elementary5 => 5,
          EducationLevel.elementary6 => 6,
          _ => 1,
        };
        for (var g = start; g <= 6; g++) {
          out.add(switch (g) {
            1 => EducationLevel.elementary1,
            2 => EducationLevel.elementary2,
            3 => EducationLevel.elementary3,
            4 => EducationLevel.elementary4,
            5 => EducationLevel.elementary5,
            _ => EducationLevel.elementary6,
          });
        }
        break;
      case EducationStage.juniorHigh:
        final start = switch (level) {
          EducationLevel.juniorHigh1 => 1,
          EducationLevel.juniorHigh2 => 2,
          EducationLevel.juniorHigh3 => 3,
          _ => 1,
        };
        for (var g = start; g <= 3; g++) {
          out.add(switch (g) {
            1 => EducationLevel.juniorHigh1,
            2 => EducationLevel.juniorHigh2,
            _ => EducationLevel.juniorHigh3,
          });
        }
        break;
      case EducationStage.seniorHigh:
        final start = switch (level) {
          EducationLevel.seniorHigh1 => 1,
          EducationLevel.seniorHigh2 => 2,
          EducationLevel.seniorHigh3 => 3,
          _ => 1,
        };
        for (var g = start; g <= 3; g++) {
          out.add(switch (g) {
            1 => EducationLevel.seniorHigh1,
            2 => EducationLevel.seniorHigh2,
            _ => EducationLevel.seniorHigh3,
          });
        }
        break;
      case EducationStage.higher:
        // 大學以上目前不分年級，直接回傳原等級
        out.add(level);
        break;
    }

    return out.isEmpty ? [level] : out;
  }

  // 讓「App 更新後的資料庫資源」可以覆蓋舊資料庫：
  // - 避免使用者裝過舊版後，Documents 裡的舊 DB 一直不會更新
  // - 不需要每次遊戲線上更新（維持離線）
  static const int _enhancedAssetVersion = 1;
  static const int _rawAssetVersion = 1;

  static Future<DbService> open({DataFlavor flavor = DataFlavor.enhanced}) async {
    // 使用 sqflite 的 databases 目錄（比 Documents 更符合 DB 用途，且在部分機型上更穩定）
    final dbDir = await getDatabasesPath();
    await Directory(dbDir).create(recursive: true);
    final dbPath = p.join(dbDir, flavor == DataFlavor.enhanced ? 'moe_enhanced.db' : 'moe_raw.db');
    final versionPath = '$dbPath.version';
    final wantVersion = flavor == DataFlavor.enhanced ? _enhancedAssetVersion : _rawAssetVersion;

    int haveVersion = -1;
    if (File(versionPath).existsSync()) {
      haveVersion = int.tryParse(File(versionPath).readAsStringSync().trim()) ?? -1;
    }

    final needCopy = !File(dbPath).existsSync() || haveVersion != wantVersion;
    if (needCopy) {
      final asset = flavor == DataFlavor.enhanced ? 'assets/db/moe_enhanced.db' : 'assets/db/moe_raw.db';
      AppLogger.log('[DB] copy asset to $dbPath (wantVersion=$wantVersion haveVersion=$haveVersion)');
      final bytes = await rootBundle.load(asset);
      await File(dbPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      // version 檔寫入失敗也不影響遊戲（下一次還是會再 copy 一次而已）
      try {
        await File(versionPath).writeAsString('$wantVersion', flush: true);
      } catch (_) {}
      AppLogger.log('[DB] copy done');
    }

    // 部分機型（例如某些 realme/OPPO）在 readOnly + singleInstance 可能出現不明卡住；
    // 這裡改成 readOnly=false 且 singleInstance=false（我們不會寫入資料表，只讀查詢）。
    AppLogger.log('[DB] openDatabase start: $dbPath');
    final db = await openDatabase(dbPath, readOnly: false, singleInstance: false);
    AppLogger.log('[DB] openDatabase done');
    return DbService._(db);
  }

  Future<void> close() => _db.close();

  Future<int> _maxWordId() async {
    final cached = _maxWordIdCache;
    if (cached != null) return cached;
    final rows = await _db.rawQuery('SELECT MAX(word_id) AS m FROM word');
    final m = (rows.isNotEmpty ? (rows.first['m'] as int?) : null) ?? 0;
    _maxWordIdCache = m;
    return m;
  }

  /// 取代 `ORDER BY RANDOM() LIMIT 1`（那個會全表掃描，某些手機可能看起來像卡住）
  /// 用「隨機起點 + 依 word_id 掃描」來取一筆，並在找不到時回退到原本的 RANDOM 作保底。
  Future<List<Map<String, Object?>>> _randomWordPick({
    required String selectSql, // 例如: "SELECT w.word_id, w.word, w.bopomofo FROM word w"
    required String whereSql, // 不要加 WHERE 關鍵字
    required List<Object?> args,
    int tries = 6,
  }) async {
    final maxId = await _maxWordId();
    if (maxId <= 0) {
      return _db.rawQuery('$selectSql WHERE $whereSql ORDER BY RANDOM() LIMIT 1', args);
    }
    final rnd = Random();
    for (var i = 0; i < tries; i++) {
      final start = rnd.nextInt(maxId + 1);
      // 先往後找
      final rows1 = await _db.rawQuery(
        '$selectSql WHERE $whereSql AND w.word_id >= ? ORDER BY w.word_id LIMIT 1',
        [...args, start],
      );
      if (rows1.isNotEmpty) return rows1;
      // 再從頭繞回
      final rows2 = await _db.rawQuery(
        '$selectSql WHERE $whereSql AND w.word_id < ? ORDER BY w.word_id LIMIT 1',
        [...args, start],
      );
      if (rows2.isNotEmpty) return rows2;
    }
    return _db.rawQuery('$selectSql WHERE $whereSql ORDER BY RANDOM() LIMIT 1', args);
  }

  // ====== 等級過濾（教育分級） ======

  static ({String where, List<Object?> args}) _wordLevelWhere(EducationLevel level, {String alias = 'w'}) {
    final r = ruleForLevel(level);
    final parts = <String>[];
    final args = <Object?>[];

    parts.add('$alias.difficulty <= ?');
    args.add(r.maxWordDifficulty);

    // 國小：理想上只用國小字詞（is_primary_school=1）。
    //
    // 但目前資料庫的 word.is_primary_school 標記可能不完整（例如某些來源的詞語沒有被標成 primary，
    // 但仍有完整 bopomofo / word_char.cp_id 可用來出題），會導致國小等級在題型 A/C/E 完全抓不到題目。
    // 因此這裡採用「primary OR common」作為國小的 stage guard，確保至少能出題且維持「官方常用詞」範圍。
    if (r.requirePrimaryWords) {
      parts.add('($alias.is_primary_school = 1 OR $alias.is_common = 1)');
    }

    // 國中：至少是「常用」或「國小」
    if (stageForLevel(level) == EducationStage.juniorHigh) {
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

  /// 等級過濾：嘗試用嚴格規則；若該等級在資料庫標記不足（例如 primary/common 欄位不完整）
  /// 導致完全無法出題，會逐步放寬條件，確保「所有等級都有題目可玩」。
  static List<({String where, List<Object?> args, String note})> _wordLevelWhereCandidates(
    EducationLevel level, {
    String alias = 'w',
  }) {
    final out = <({String where, List<Object?> args, String note})>[];

    // 1) 原本規則（最符合等級設計）
    final base = _wordLevelWhere(level, alias: alias);
    out.add((where: base.where, args: base.args, note: 'base'));

    // 2) 放寬：但仍「不跨學段」。
    // 使用者選了某個年級/學段時，最重要的是不要出到更高學段的字詞；
    // 因此 fallback 只放寬 difficulty/priority，不移除 primary/common 的門檻。
    final r = ruleForLevel(level);
    final guard = <String>[];
    // 國小：優先用國小字詞；但為避免資料庫 primary 標記不完整造成「完全無題」，
    // 這裡與 _wordLevelWhere 一致採用 primary OR common 當作 stage guard。
    if (r.requirePrimaryWords) {
      guard.add('($alias.is_primary_school = 1 OR $alias.is_common = 1)');
    }
    // 國中：至少是「常用」或「國小」
    if (stageForLevel(level) == EducationStage.juniorHigh) {
      guard.add('($alias.is_common = 1 OR $alias.is_primary_school = 1)');
    }
    // 高中/大學：以常用為主
    if (r.requireCommonWords) {
      guard.add('$alias.is_common = 1');
    }

    // 2a) 放寬：保留 primary/common + difficulty，但允許低 priority
    final partsA = <String>['$alias.difficulty <= ?', ...guard];
    final argsA = <Object?>[r.maxWordDifficulty];
    out.add((where: partsA.join(' AND '), args: argsA, note: 'relax-priority'));

    // 2b) 放寬：保留 primary/common，difficulty 提高到 5（仍排除 low priority）
    final partsB = <String>['$alias.difficulty <= 5', ...guard];
    if (!r.includeLowPriorityWords) {
      partsB.add("$alias.game_priority != 'low'");
    }
    out.add((where: partsB.join(' AND '), args: const <Object?>[], note: 'relax-difficulty'));

    // 2c) 放寬：只保留 primary/common（最後保底，但仍不跨學段）
    out.add((where: (guard.isEmpty ? '1=1' : guard.join(' AND ')), args: const <Object?>[], note: 'stage-guard-only'));

    return out;
  }

  static List<({String where, List<Object?> args, String note})> _charLevelWhereCandidates(
    EducationLevel level, {
    String alias = 'c',
  }) {
    final out = <({String where, List<Object?> args, String note})>[];

    final base = _charLevelWhere(level, alias: alias);
    out.add((where: base.where, args: base.args, note: 'base'));

    // 放寬：但仍不跨學段（不移除 primary/common 的門檻）
    final r = ruleForLevel(level);
    final guard = <String>[];
    if (r.requirePrimaryChars) {
      guard.add('$alias.is_primary_school = 1');
    } else if (r.requireCommonChars) {
      guard.add('($alias.is_common = 1 OR $alias.is_primary_school = 1)');
    }

    // 2a) 放寬：保留 primary/common，但允許 low priority
    out.add((where: (guard.isEmpty ? '1=1' : guard.join(' AND ')), args: const <Object?>[], note: 'relax-priority'));
    return out;
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
    EducationLevel level = EducationLevel.elementaryAll,
  }) async {
    // 依需求：題庫不足時只在同學段內逐級放寬（不跨學段）
    final levelChain = _fallbackLevelsWithinStage(level);
    List<Map<String, Object?>> w = const [];
    String? usedNote;
    bool usedAllowFlag = true;
    EducationLevel? usedLevel;

    // 內部一致性檢查：word.bopomofo 的音節數/內容要能對上 word_char.cp_id 的逐字注音
    // （否則會出現「題目朗讀/顯示」與答案注音不一致，或玩家覺得題目有兩個答案）。
    Future<bool> _wordBopoConsistent(int wordId, String wordBopo) async {
      final b = wordBopo.trim();
      if (b.isEmpty) return true; // 沒資料就不檢查
      final syl = _syllables(b);
      if (syl.isEmpty) return true;

      final rows = await _db.rawQuery(r'''
        SELECT wc.position, cp.bopomofo AS bopo
        FROM word_char wc
        JOIN character_pronunciation cp ON cp.cp_id = wc.cp_id
        WHERE wc.word_id = ?
          AND wc.cp_id IS NOT NULL
        ORDER BY wc.position ASC
      ''', [wordId]);

      if (rows.isEmpty) return true;
      if (rows.length != syl.length) return false;
      for (var i = 0; i < rows.length; i++) {
        final rb = (rows[i]['bopo'] as String?) ?? '';
        if (rb.trim() != syl[i].trim()) return false;
      }
      return true;
    }

    // 先試 allow_audio_to_char=1；若完全抓不到，再放寬移除 allow flag。
    // 並且遇到「注音資料不一致」的詞會跳過，避免出到怪題。
    //
    // 額外：若該等級完全無題可出，依 levelChain 逐級放寬到同學段較高年級（不跨學段）。
    for (final lv in levelChain) {
      for (var attempt = 0; attempt < 30; attempt++) {
        w = const [];
        usedNote = null;
        usedAllowFlag = true;
        usedLevel = null;

        for (final withAllow in [true, false]) {
          for (final cand in _wordLevelWhereCandidates(lv, alias: 'w')) {
            final where = cand.where +
                (withAllow ? " AND w.allow_audio_to_char = 1" : "") +
                r'''
        AND EXISTS (
          SELECT 1 FROM word_char wc
          WHERE wc.word_id = w.word_id AND wc.cp_id IS NOT NULL
        )''';
            w = await _randomWordPick(
              selectSql: 'SELECT w.word_id, w.word, w.bopomofo FROM word w',
              whereSql: where.trim(),
              args: cand.args,
            );
            if (w.isNotEmpty) {
              usedNote = cand.note;
              usedAllowFlag = withAllow;
              usedLevel = lv;
              break;
            }
          }
          if (w.isNotEmpty) break;
        }

        if (w.isEmpty) break;

        final wordId = (w.first['word_id'] as int);
        final bopo = (w.first['bopomofo'] as String?) ?? '';
        final ok = await _wordBopoConsistent(wordId, bopo);
        if (ok) break;
        AppLogger.log('[DB] A skip inconsistent word_id=$wordId');
      }
      if (w.isNotEmpty) break;
    }

    if (w.isEmpty) {
      throw StateError('找不到可用的「聽音選字」題目（此等級詞語注音/對應資料不足）。');
    }
    if (usedNote != null && usedNote != 'base') {
      AppLogger.log('[DB] A fallback level=${usedLevel ?? level} note=$usedNote allowFlag=$usedAllowFlag');
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
    EducationLevel level = EducationLevel.elementaryAll,
  }) async {
    final cpFilter = _cpLevelWhere(level, alias: 'cp');
    List<Map<String, Object?>> rows = const [];
    String? usedNote;
    String? contextWord;
    for (final cand in _charLevelWhereCandidates(level, alias: 'c')) {
      rows = await _db.rawQuery(r'''
      SELECT c.char AS ch, cp.bopomofo AS bopo
      FROM character c
      JOIN character_pronunciation cp ON cp.char_id = c.char_id
      WHERE ''' +
        cand.where +
        r'''
        AND ''' +
        cpFilter.where +
        r'''
        AND (SELECT COUNT(*) FROM character_pronunciation cp2 WHERE cp2.char_id = c.char_id) = 1
      ORDER BY RANDOM()
      LIMIT 1
    ''', [...cand.args, ...cpFilter.args]);
      if (rows.isNotEmpty) {
        usedNote = cand.note;
        break;
      }
    }

    // 若該等級剛好沒有足夠「單音字」可用，改用「詞語語境」提供去歧義（避免完全沒題目）。
    if (rows.isEmpty) {
      for (final cand in _wordLevelWhereCandidates(level, alias: 'w')) {
        rows = await _db.rawQuery(r'''
        SELECT c.char AS ch, cp.bopomofo AS bopo, w.word AS w
        FROM word_char wc
        JOIN word w ON w.word_id = wc.word_id
        JOIN character c ON c.char_id = wc.char_id
        JOIN character_pronunciation cp ON cp.cp_id = wc.cp_id
        WHERE ''' +
            cand.where +
            r'''
          AND wc.cp_id IS NOT NULL
          AND cp.bopomofo != ''
          AND ''' +
            cpFilter.where +
            r'''
          AND w.is_common = 1
          AND length(w.word) BETWEEN 2 AND 6
        ORDER BY RANDOM()
        LIMIT 1
      ''', [...cand.args, ...cpFilter.args]);
        if (rows.isNotEmpty) {
          usedNote = cand.note;
          contextWord = rows.first['w'] as String?;
          break;
        }
      }
    }

    if (rows.isEmpty) {
      throw StateError('找不到可用的「看字選音」題目。');
    }
    if (usedNote != null && usedNote != 'base') {
      AppLogger.log('[DB] B fallback level=$level note=$usedNote');
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
    return CharToBopoQuestion(
      character: ch,
      answerBopomofo: answer,
      options: options,
      contextWord: contextWord,
    );
  }

  // ====== 題型 D：看注音選字（Bopo → Char） ======

  Future<BopoToCharQuestion> randomBopoToCharQuestion({
    int optionCount = 4,
    EducationLevel level = EducationLevel.elementaryAll,
  }) async {
    final cpFilter = _cpLevelWhere(level, alias: 'cp');
    List<Map<String, Object?>> rows = const [];
    String? usedNote;
    for (final cand in _charLevelWhereCandidates(level, alias: 'c')) {
      rows = await _db.rawQuery(r'''
      SELECT cp.bopomofo AS bopo, c.char AS ch
      FROM character_pronunciation cp
      JOIN character c ON c.char_id = cp.char_id
      WHERE ''' +
        cand.where +
        r'''
        AND ''' +
        cpFilter.where +
        r'''
        AND cp.bopomofo != ''
      ORDER BY RANDOM()
      LIMIT 1
    ''', [...cand.args, ...cpFilter.args]);
      if (rows.isNotEmpty) {
        usedNote = cand.note;
        break;
      }
    }
    if (rows.isEmpty) {
      throw StateError('找不到可用的「注音→選字」題目。');
    }
    if (usedNote != null && usedNote != 'base') {
      AppLogger.log('[DB] D fallback level=$level note=$usedNote');
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
          AND c.char_id NOT IN (
            SELECT cp2.char_id
            FROM character_pronunciation cp2
            WHERE cp2.bopomofo = ?
          )
        ORDER BY RANDOM()
        LIMIT ?
      ''', [answerChar, bopomofo, 80]);
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
    EducationLevel level = EducationLevel.elementaryAll,
  }) async {
    List<Map<String, Object?>> rows = const [];
    String? usedNote;
    for (final cand in _wordLevelWhereCandidates(level, alias: 'w')) {
      rows = await _db.rawQuery(r'''
      SELECT w.word_id, w.word, w.bopomofo
      FROM word w
      WHERE ''' +
        cand.where +
        r'''
        AND w.bopomofo != ''
      ORDER BY RANDOM()
      LIMIT 1
    ''', cand.args);
      if (rows.isNotEmpty) {
        usedNote = cand.note;
        break;
      }
    }
    if (rows.isEmpty) {
      throw StateError('找不到可用的「詞語→選注音」題目（該等級篩選過嚴）。');
    }
    if (usedNote != null && usedNote != 'base') {
      AppLogger.log('[DB] E fallback level=$level note=$usedNote');
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
    EducationLevel level = EducationLevel.elementaryAll,
  }) async {
    // 配對題最容易因為條件不足而缺題：這裡做兩層 fallback
    // 1) pairCount: 4 -> 3 -> 2
    // 2) allow_pairing: 1 -> 不限制
    List<Map<String, Object?>> rows = const [];
    String? usedNote;
    bool usedAllow = true;
    int usedPairCount = pairCount;

    final pairCounts = <int>[
      pairCount,
      if (pairCount > 3) 3,
      if (pairCount > 2) 2,
    ];
    for (final pc in pairCounts) {
      for (final withAllow in [true, false]) {
        for (final cand in _wordLevelWhereCandidates(level, alias: 'word')) {
          final where = cand.where + (withAllow ? ' AND allow_pairing = 1' : '');
          // ⚠️ 配對題容易因為「不同詞語有相同注音」而造成一個注音對到多個答案（看起來像有兩個答案）。
          // 這裡改成先抽更大的池子，再在 Dart 端挑出「注音唯一」的組合。
          final pool = await _db.rawQuery(r'''
      SELECT word, bopomofo
      FROM word
      WHERE ''' +
              where +
              r'''
        AND bopomofo != ''
      ORDER BY RANDOM()
      LIMIT ?
    ''', [...cand.args, pc * 10]);

          final picked = <Map<String, Object?>>[];
          final usedBopo = <String>{};
          for (final r in pool) {
            final w = (r['word'] as String?) ?? '';
            final b = (r['bopomofo'] as String?) ?? '';
            if (w.isEmpty || b.isEmpty) continue;
            if (usedBopo.contains(b)) continue;
            usedBopo.add(b);
            picked.add({'word': w, 'bopomofo': b});
            if (picked.length >= pc) break;
          }

          rows = picked;
          if (rows.length >= pc) {
            usedNote = cand.note;
            usedAllow = withAllow;
            usedPairCount = pc;
            break;
          }
        }
        if (rows.length >= pc) break;
      }
      if (rows.length >= pc) break;
    }

    if (rows.length < usedPairCount) {
      throw StateError('可用配對題不足（已放寬條件仍不足）。');
    }
    if (usedNote != null && usedNote != 'base') {
      AppLogger.log('[DB] C fallback level=$level note=$usedNote allow=$usedAllow pairCount=$usedPairCount');
    }
    final answerMap = <String, String>{};
    for (final r in rows.take(usedPairCount)) {
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
    EducationLevel level = EducationLevel.elementaryAll,
  }) async {
    String baseWord = currentWord ?? '';
    final wCandidates = _wordLevelWhereCandidates(level, alias: 'w');
    final w2Candidates = _wordLevelWhereCandidates(level, alias: 'w2');
    String? usedNote;
    String? usedNoteNext;

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
      for (final cand in w2Candidates) {
        final answerRows = await _db.rawQuery(r'''
          SELECT w2.word AS w
          FROM word w2
          WHERE ''' +
            cand.where +
            r'''
            AND w2.is_common = 1
            AND w2.word != ?
            AND length(w2.word) BETWEEN 2 AND 6
            AND substr(w2.word, 1, 1) = ?
          ORDER BY RANDOM()
          LIMIT 1
        ''', [...cand.args, base, lastChar]);
        if (answerRows.isNotEmpty) {
          usedNoteNext = cand.note;
          return answerRows.first['w'] as String;
        }
      }
      return null;
    }

    Future<String?> _randomWrongWordFallback({required String notStartChar, required Set<String> exclude}) async {
      // 保底：從常用詞中撈一批，挑一個不是答案/不是 base，且不是指定開頭的詞。
      final pool = await _db.rawQuery(r'''
        SELECT w.word AS w
        FROM word w
        WHERE w.is_common = 1
          AND length(w.word) BETWEEN 2 AND 6
          AND substr(w.word, 1, 1) != ?
        ORDER BY RANDOM()
        LIMIT 80
      ''', [notStartChar]);
      for (final row in pool) {
        final w = row['w'] as String? ?? '';
        if (w.isEmpty) continue;
        if (exclude.contains(w)) continue;
        return w;
      }
      return null;
    }

    String lastChar = '';
    String answerWord = '';

    if (baseWord.isEmpty) {
      const maxPickTriesPerRule = 24;
      for (final candRule in wCandidates) {
        for (var i = 0; i < maxPickTriesPerRule; i++) {
          final rows = await _db.rawQuery(r'''
            SELECT w.word AS w
            FROM word w
            WHERE ''' +
              candRule.where +
              r'''
              AND w.is_common = 1
              AND length(w.word) BETWEEN 2 AND 6
            ORDER BY RANDOM()
            LIMIT 1
          ''', candRule.args);
          if (rows.isEmpty) break;
          final cand = rows.first['w'] as String;
          final lc = await _lastCharOf(cand);
          if (lc.isEmpty) continue;
          final ans = await _randomNextWord(cand, lc);
          if (ans == null) continue;
          baseWord = cand;
          lastChar = lc;
          answerWord = ans;
          usedNote = candRule.note;
          break;
        }
        if (answerWord.isNotEmpty) break;
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

    if (usedNote != null && usedNote != 'base') {
      AppLogger.log('[DB] F fallback level=$level note=$usedNote nextNote=${usedNoteNext ?? "base"}');
    }

    // 干擾：不以 lastChar 開頭
    final distractors = <String>[];
    final need = max(0, optionCount - 1);
    if (need > 0) {
      // 先用 base rule 撈，若不足再用保底填滿
      final baseRule = wCandidates.first;
      final r = await _db.rawQuery(r'''
          SELECT w.word AS w
          FROM word w
          WHERE ''' +
            baseRule.where +
            r'''
            AND w.is_common = 1
            AND length(w.word) BETWEEN 2 AND 6
            AND w.word != ?
            AND w.word != ?
            AND substr(w.word, 1, 1) != ?
          ORDER BY RANDOM()
          LIMIT ?
        ''', [...baseRule.args, baseWord, answerWord, lastChar, need]);
      for (final row in r) {
        final w = row['w'] as String;
        if (w == answerWord) continue;
        if (distractors.contains(w)) continue;
        distractors.add(w);
      }
    }

    while (distractors.length < optionCount - 1) {
      final w = await _randomWrongWordFallback(
        notStartChar: lastChar,
        exclude: {baseWord, answerWord, ...distractors},
      );
      if (w == null) break;
      distractors.add(w);
    }

    // 最後保底（理論上很少發生）：若資料庫不足，至少避免 crash
    while (distractors.length < optionCount - 1) {
      distractors.add('（無）');
    }

    final options = <String>[answerWord, ...distractors]..shuffle(Random());
    return WordChainQuestion(
      currentWord: baseWord,
      targetStartChar: lastChar,
      answerWord: answerWord,
      options: options,
    );
  }

  // ====== 題型 G：注音接龍（棋盤填空） ======

  Future<BopoChainGridPuzzle> randomBopoChainGridPuzzle({
    EducationLevel level = EducationLevel.elementaryAll,
    int wordCount = 6,
    // 依需求：詞語音節數不固定（可到 6），棋盤尺寸加大一點避免放不下
    int gridSize = 10,
  }) async {
    // 以「詞語注音」做接龍：上一個詞語最後一個音節 = 下一個詞語第一個音節
    // 再把每個音節放進棋盤的格子，形成可交錯的路徑。

    // 1) 先組出可用的詞語接龍序列（避免太長/太短）
    final chain = await _buildBopoWordChain(level: level, wordCount: wordCount);

    // 2) 把接龍放進固定棋盤模板（交錯 H/V/H/V...）
    final placed = _placeChainOnGrid(chain, gridSize: gridSize);
    if (placed == null) {
      // 理論上不太會發生，但保底：重試一次
      final chain2 = await _buildBopoWordChain(level: level, wordCount: wordCount);
      final placed2 = _placeChainOnGrid(chain2, gridSize: gridSize);
      if (placed2 == null) {
        throw StateError('無法產生注音接龍棋盤（請重試）。');
      }
      return await _attachExtraTiles(placed2);
    }
    return await _attachExtraTiles(placed);
  }

  Future<BopoChainGridPuzzle> _attachExtraTiles(BopoChainGridPuzzle p) async {
    final tileSet = p.tiles.toSet();
    // 追加少量干擾音節（避免題目太像「只剩抄答案」）
    final extra = await _db.rawQuery(r'''
      SELECT DISTINCT bopomofo
      FROM character_pronunciation
      WHERE bopomofo != ''
      ORDER BY RANDOM()
      LIMIT 40
    ''');
    for (final r in extra) {
      final b = (r['bopomofo'] as String?) ?? '';
      if (b.isEmpty) continue;
      tileSet.add(b);
      if (tileSet.length >= 14) break;
    }
    final tiles = tileSet.toList()..shuffle(Random());
    if (tiles.length > 14) tiles.removeRange(14, tiles.length);
    return BopoChainGridPuzzle(
      rows: p.rows,
      cols: p.cols,
      usedCells: p.usedCells,
      fixedCells: p.fixedCells,
      puzzleCells: p.puzzleCells,
      solution: p.solution,
      tiles: tiles,
      words: p.words,
    );
  }

  Future<List<({String word, List<String> syl})>> _buildBopoWordChain({
    required EducationLevel level,
    required int wordCount,
  }) async {
    // 限制字長，避免棋盤塞不下
    const minLen = 2;
    // 依需求：不一定固定 4 格，允許更長一些（2~6 音節）
    const maxLen = 6;

    // 挑起始詞（有注音、常用、長度合理）
    Future<({String word, String bopo})?> pickStart() async {
      for (final cand in _wordLevelWhereCandidates(level, alias: 'w')) {
        final rows = await _db.rawQuery(r'''
          SELECT w.word AS w, w.bopomofo AS b
          FROM word w
          WHERE ''' +
            cand.where +
            r'''
            AND w.is_common = 1
            AND w.bopomofo != ''
            AND length(w.word) BETWEEN ? AND ?
          ORDER BY RANDOM()
          LIMIT 20
        ''', [...cand.args, minLen, maxLen]);
        if (rows.isEmpty) continue;
        for (final r in rows) {
          final w = (r['w'] as String?) ?? '';
          final b = (r['b'] as String?) ?? '';
          if (w.isEmpty || b.isEmpty) continue;
          return (word: w, bopo: b);
        }
      }
      return null;
    }

    Future<List<({String word, String bopo})>> pickNext(String firstSyl, Set<String> excludeWords) async {
      final out = <({String word, String bopo})>[];
      // 用 LIKE 先縮小範圍（以「音節 + 空格」或「音節 + 結尾」開頭）
      final like1 = '$firstSyl %';
      final like2 = '$firstSyl%';
      for (final cand in _wordLevelWhereCandidates(level, alias: 'w')) {
        final rows = await _db.rawQuery(r'''
          SELECT w.word AS w, w.bopomofo AS b
          FROM word w
          WHERE ''' +
            cand.where +
            r'''
            AND w.is_common = 1
            AND w.bopomofo != ''
            AND length(w.word) BETWEEN ? AND ?
            AND (w.bopomofo LIKE ? OR w.bopomofo LIKE ?)
          ORDER BY RANDOM()
          LIMIT 40
        ''', [...cand.args, minLen, maxLen, like1, like2]);
        for (final r in rows) {
          final w = (r['w'] as String?) ?? '';
          final b = (r['b'] as String?) ?? '';
          if (w.isEmpty || b.isEmpty) continue;
          if (excludeWords.contains(w)) continue;
          final syl = _syllables(b);
          if (syl.isEmpty) continue;
          if (syl.first != firstSyl) continue; // 確保真的是「第一個音節」
          out.add((word: w, bopo: b));
          if (out.length >= 20) break;
        }
        if (out.isNotEmpty) break;
      }
      out.shuffle(Random());
      return out;
    }

    for (var attempt = 0; attempt < 30; attempt++) {
      final start = await pickStart();
      if (start == null) continue;
      final chain = <({String word, List<String> syl})>[];
      final usedWords = <String>{};

      final s0 = _syllables(start.bopo);
      if (s0.length < minLen || s0.length > maxLen) continue;
      chain.add((word: start.word, syl: s0));
      usedWords.add(start.word);

      var ok = true;
      while (chain.length < wordCount) {
        final lastSyl = chain.last.syl.last;
        final nexts = await pickNext(lastSyl, usedWords);
        if (nexts.isEmpty) {
          ok = false;
          break;
        }
        final n = nexts.first;
        final sn = _syllables(n.bopo);
        if (sn.length < minLen || sn.length > maxLen) continue;
        chain.add((word: n.word, syl: sn));
        usedWords.add(n.word);
      }
      if (ok && chain.length == wordCount) return chain;
    }
    throw StateError('找不到可用的注音接龍題目（請換等級或再試一次）。');
  }

  BopoChainGridPuzzle? _placeChainOnGrid(
    List<({String word, List<String> syl})> chain, {
    required int gridSize,
  }) {
    final rows = gridSize;
    final cols = gridSize;
    int idx(int r, int c) => r * cols + c;

    final sol = <int, String>{};
    final used = <int>{};

    // 依需求：棋盤路徑不再固定「H/V 交錯、只往右/往下」，
    // 改成允許上下左右轉彎，做出更像成語填字/接龍的不規則路徑。
    //
    // 放置策略：每個詞從上一個詞的終點開始（接點重疊），再選一個方向把音節依序放下去。
    // 方向每次盡量轉彎（避免一直直走），如果遇到邊界/衝突就整局重來。

    // 依需求：一般閱讀習慣是「由上往下」，
    // 因此接龍路徑不允許往上走（避免玩家需要由下往上解讀/回填）。
    // 左右移動沒問題、向下延伸沒問題。
    final dirs = const <(int, int)>[(0, 1), (1, 0), (0, -1)];

    bool placeWord(List<String> syl, {required int sr, required int sc, required (int, int) dir}) {
      final (dr, dc) = dir;
      for (var i = 0; i < syl.length; i++) {
        final r = sr + dr * i;
        final c = sc + dc * i;
        if (r < 0 || r >= rows || c < 0 || c >= cols) return false;
        final k = idx(r, c);
        final v = syl[i];
        if (sol.containsKey(k) && sol[k] != v) return false;
        sol[k] = v;
        used.add(k);
      }
      return true;
    }

    (int, int) addDir((int, int) p, (int, int) d, int step) => (p.$1 + d.$1 * step, p.$2 + d.$2 * step);

    // 起點放在偏上方，確保後續「只往下/左右」仍有足夠空間可放置整段接龍
    (int, int) start = (1, (cols / 2).floor());
    (int, int)? prevDir;

    // 嘗試多次隨機路徑（同一個 chain 內部重試），提高成功率
    var placedOk = false;
    for (var attempt = 0; attempt < 80; attempt++) {
      sol.clear();
      used.clear();
      start = (1, (cols / 2).floor());
      prevDir = null;

      bool okAll = true;
      var pos = start;
      for (var wi = 0; wi < chain.length; wi++) {
        final syl = chain[wi].syl;

        // 候選方向：盡量「轉彎」，其次才是直走；避免常常卡到邊界
        final candidates = <(int, int)>[];
        for (final d in dirs) {
          if (prevDir != null) {
            final same = (d.$1 == prevDir!.$1 && d.$2 == prevDir!.$2);
            final opposite = (d.$1 == -prevDir!.$1 && d.$2 == -prevDir!.$2);
            if (same || opposite) continue; // 優先轉彎
          }
          candidates.add(d);
        }
        // 若轉彎都不行，最後才允許直走/反向
        if (candidates.isEmpty) candidates.addAll(dirs);
        candidates.shuffle(Random());

        bool placed = false;
        for (final d in candidates) {
          if (!placeWord(syl, sr: pos.$1, sc: pos.$2, dir: d)) continue;
          prevDir = d;
          pos = addDir(pos, d, syl.length - 1);
          placed = true;
          break;
        }
        if (!placed) {
          okAll = false;
          break;
        }
      }

      if (okAll && used.isNotEmpty) {
        placedOk = true;
        break;
      }
    }

    if (!placedOk) return null;

    // 固定一些提示格：每個詞的接點（起點=上一詞終點）+ 第一個詞起點，再額外隨機給少量提示
    final fixed = <int>{};
    // 重走一次路徑，收集接點/尾端（用 sol 的內容重建）
    // 注意：我們用同樣的 chain + 放置結果去找接點位置會很複雜；
    // 這裡採取一個穩健作法：優先固定「每個 used cell 中度數>=3 的交會點」不一定存在；
    // 因此改成：固定一部分 usedCells（均勻抽樣），並一定包含起點。
    final startIdx = idx(start.$1, start.$2);
    fixed.add(startIdx);
    final usedList = used.toList()..sort();
    // 均勻抽樣：讓提示分散在棋盤上（太集中會看不懂）
    // 避免提示格過多導致「沒有空格可以填」：至少要保留一些 puzzleCells。
    const minPuzzleCells = 3;
    var hintCount = (usedList.length * 0.22).round().clamp(4, 14);
    // 至少保留 minPuzzleCells（若題目本身太短，至少保留 1 格可填）
    hintCount = min(hintCount, max(1, usedList.length - minPuzzleCells));
    // 也不能把所有格子都固定（至少留 1 格可填）
    hintCount = min(hintCount, usedList.length - 1);

    for (var i = 0; i < hintCount && i < usedList.length; i++) {
      final k = usedList[(i * usedList.length / hintCount).floor()];
      fixed.add(k);
    }

    // puzzleCells = used - fixed
    var puzzleCells = used.difference(fixed);
    // 最後保底：若仍然沒有可填格，移除部分提示（保留起點）
    if (puzzleCells.isEmpty) {
      final removable = fixed.where((k) => k != startIdx).toList()..shuffle(Random());
      for (final k in removable) {
        fixed.remove(k);
        puzzleCells = used.difference(fixed);
        if (puzzleCells.isNotEmpty) break;
      }
    }

    // tiles：把所有需要填的音節放進來（再加 2 個干擾）
    final tileSet = <String>{};
    for (final k in used) {
      final v = sol[k];
      if (v != null) tileSet.add(v);
    }
    final tiles = tileSet.toList();
    tiles.shuffle(Random());
    if (tiles.length > 14) tiles.removeRange(14, tiles.length);

    return BopoChainGridPuzzle(
      rows: rows,
      cols: cols,
      usedCells: used,
      fixedCells: fixed,
      puzzleCells: puzzleCells,
      solution: sol,
      tiles: tiles,
      words: chain.map((e) => e.word).toList(growable: false),
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
