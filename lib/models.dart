class AudioToCharQuestion {
  final int wordId;
  final String word;
  final String bopomofo;
  final int position;
  final String answerChar;
  final String answerBopomofo;
  final List<String> options;

  AudioToCharQuestion({
    required this.wordId,
    required this.word,
    required this.bopomofo,
    required this.position,
    required this.answerChar,
    required this.answerBopomofo,
    required this.options,
  });

  String get maskedWord {
    final chars = word.split("");
    if (position >= 0 && position < chars.length) {
      chars[position] = "＿";
    }
    return chars.join();
  }
}

class CharToBopoQuestion {
  final String character;
  final String answerBopomofo;
  final List<String> options;
  final String? contextWord;

  CharToBopoQuestion({
    required this.character,
    required this.answerBopomofo,
    required this.options,
    this.contextWord,
  });
}

class BopoToCharQuestion {
  final String bopomofo;
  final String answerChar;
  final List<String> options;

  BopoToCharQuestion({
    required this.bopomofo,
    required this.answerChar,
    required this.options,
  });
}

class WordToBopoQuestion {
  final int wordId;
  final String word;
  final String answerBopomofo;
  final List<String> options;

  WordToBopoQuestion({
    required this.wordId,
    required this.word,
    required this.answerBopomofo,
    required this.options,
  });
}

class PairingRound {
  final List<String> words; // shuffled
  final List<String> bopomos; // shuffled
  final Map<String, String> answerMap; // word -> bopomofo

  PairingRound({
    required this.words,
    required this.bopomos,
    required this.answerMap,
  });
}

/// 語詞接龍（填空/選擇）：
/// - 顯示 currentWord
/// - 下一個詞語必須以 targetStartChar 開頭
/// - 本題只有一個正確選項 answerWord（其他選項不以 targetStartChar 開頭）
class WordChainQuestion {
  final String currentWord;
  final String targetStartChar;
  final String answerWord;
  final List<String> options;

  WordChainQuestion({
    required this.currentWord,
    required this.targetStartChar,
    required this.answerWord,
    required this.options,
  });
}

/// 注音接龍（棋盤填空）：
/// - 類似成語填字/接龍的棋盤玩法，但每個格子填的是「注音音節」（例如：ㄅㄚˊ）。
/// - 下面提供可重複使用的注音方塊（不會像字母遊戲那樣被消耗）。
/// - puzzleCells：棋盤中「需要玩家填」的格子索引
/// - fixedCells：棋盤中「已給定」的格子索引（顯示答案，不能修改）
class BopoChainGridPuzzle {
  final int rows;
  final int cols;
  final Set<int> usedCells; // 這局有用到的格子
  final Set<int> fixedCells;
  final Set<int> puzzleCells;
  final Map<int, String> solution; // cellIndex -> bopomofo syllable
  final List<String> tiles; // 可點擊填入的注音方塊（可重複使用）
  final List<String> words; // 用於「查看解釋」的詞語清單（按出題順序）

  BopoChainGridPuzzle({
    required this.rows,
    required this.cols,
    required this.usedCells,
    required this.fixedCells,
    required this.puzzleCells,
    required this.solution,
    required this.tiles,
    required this.words,
  });
}
