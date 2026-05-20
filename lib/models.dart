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
