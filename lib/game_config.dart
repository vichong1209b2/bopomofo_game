/// 遊戲的「等級」與「主題」設定。
///
/// 設計原則：
/// - 高等級的出題範圍要涵蓋所有低等級（用條件放寬方式達成）
/// - 目前資料庫提供：
///   - word.difficulty (1~5)、word.is_primary_school、word.is_common、word.game_priority
///   - character.is_primary_school、character.is_common、character.game_priority
/// 因此等級的範圍以這些欄位做「可解釋、可維護」的規則化映射。
enum EducationLevel {
  elementary,
  juniorHigh,
  seniorHigh,
  university,
  graduate,
  working,
  expert,
  scholar,
  master,
}

enum ThemeStyle {
  sakura,
  ocean,
  forest,
  night,
}

/// 給 DbService 用的等級規則（避免 UI 端 Icon/Color 依賴 material）。
class LevelRule {
  final int maxWordDifficulty; // 1~5
  final bool requirePrimaryWords;
  final bool requireCommonWords;
  final bool includeLowPriorityWords;

  final bool requirePrimaryChars;
  final bool requireCommonChars;
  final bool includeLowPriorityChars;

  const LevelRule({
    required this.maxWordDifficulty,
    required this.requirePrimaryWords,
    required this.requireCommonWords,
    required this.includeLowPriorityWords,
    required this.requirePrimaryChars,
    required this.requireCommonChars,
    required this.includeLowPriorityChars,
  });
}

LevelRule ruleForLevel(EducationLevel level) {
  switch (level) {
    case EducationLevel.elementary:
      return const LevelRule(
        maxWordDifficulty: 2,
        requirePrimaryWords: true,
        requireCommonWords: false,
        includeLowPriorityWords: false,
        requirePrimaryChars: true,
        requireCommonChars: false,
        includeLowPriorityChars: false,
      );
    case EducationLevel.juniorHigh:
      return const LevelRule(
        maxWordDifficulty: 3,
        requirePrimaryWords: false,
        requireCommonWords: false,
        includeLowPriorityWords: false,
        requirePrimaryChars: false,
        requireCommonChars: true,
        includeLowPriorityChars: false,
      );
    case EducationLevel.seniorHigh:
      return const LevelRule(
        maxWordDifficulty: 4,
        requirePrimaryWords: false,
        requireCommonWords: true,
        includeLowPriorityWords: false,
        requirePrimaryChars: false,
        requireCommonChars: true,
        includeLowPriorityChars: false,
      );
    case EducationLevel.university:
      return const LevelRule(
        maxWordDifficulty: 5,
        requirePrimaryWords: false,
        requireCommonWords: true,
        includeLowPriorityWords: false,
        requirePrimaryChars: false,
        requireCommonChars: true,
        includeLowPriorityChars: false,
      );
    // 大學以上：允許 low priority，且不強制 common/primary（讓範圍覆蓋所有較低等級）。
    case EducationLevel.graduate:
    case EducationLevel.working:
    case EducationLevel.expert:
    case EducationLevel.scholar:
    case EducationLevel.master:
      return const LevelRule(
        maxWordDifficulty: 5,
        requirePrimaryWords: false,
        requireCommonWords: false,
        includeLowPriorityWords: true,
        requirePrimaryChars: false,
        requireCommonChars: false,
        includeLowPriorityChars: true,
      );
  }
}

