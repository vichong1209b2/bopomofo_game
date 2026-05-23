/// 遊戲的「等級」與「主題」設定。
///
/// 設計原則：
/// - 高等級的出題範圍要涵蓋所有低等級（用條件放寬方式達成）
/// - 目前資料庫提供：
///   - word.difficulty (1~5)、word.is_primary_school、word.is_common、word.game_priority
///   - character.is_primary_school、character.is_common、character.game_priority
/// 因此等級的範圍以這些欄位做「可解釋、可維護」的規則化映射。
enum EducationLevel {
  // ====== 國小 ======
  elementaryAll,
  elementary1,
  elementary2,
  elementary3,
  elementary4,
  elementary5,
  elementary6,

  // ====== 國中 ======
  juniorHighAll,
  juniorHigh1,
  juniorHigh2,
  juniorHigh3,

  // ====== 高中 ======
  seniorHighAll,
  seniorHigh1,
  seniorHigh2,
  seniorHigh3,

  // ====== 大學以上（不分年級） ======
  university,
  graduate,
  working,
  expert,
  scholar,
  master,
}

/// 設定頁「先選學段再選年級」用的分群。
enum EducationStage { elementary, juniorHigh, seniorHigh, higher }

EducationStage stageForLevel(EducationLevel level) {
  switch (level) {
    case EducationLevel.elementaryAll:
    case EducationLevel.elementary1:
    case EducationLevel.elementary2:
    case EducationLevel.elementary3:
    case EducationLevel.elementary4:
    case EducationLevel.elementary5:
    case EducationLevel.elementary6:
      return EducationStage.elementary;
    case EducationLevel.juniorHighAll:
    case EducationLevel.juniorHigh1:
    case EducationLevel.juniorHigh2:
    case EducationLevel.juniorHigh3:
      return EducationStage.juniorHigh;
    case EducationLevel.seniorHighAll:
    case EducationLevel.seniorHigh1:
    case EducationLevel.seniorHigh2:
    case EducationLevel.seniorHigh3:
      return EducationStage.seniorHigh;
    case EducationLevel.university:
    case EducationLevel.graduate:
    case EducationLevel.working:
    case EducationLevel.expert:
    case EducationLevel.scholar:
    case EducationLevel.master:
      return EducationStage.higher;
  }
}

List<EducationLevel> levelsForStage(EducationStage stage) {
  switch (stage) {
    case EducationStage.elementary:
      return const [
        EducationLevel.elementaryAll,
        EducationLevel.elementary1,
        EducationLevel.elementary2,
        EducationLevel.elementary3,
        EducationLevel.elementary4,
        EducationLevel.elementary5,
        EducationLevel.elementary6,
      ];
    case EducationStage.juniorHigh:
      return const [
        EducationLevel.juniorHighAll,
        EducationLevel.juniorHigh1,
        EducationLevel.juniorHigh2,
        EducationLevel.juniorHigh3,
      ];
    case EducationStage.seniorHigh:
      return const [
        EducationLevel.seniorHighAll,
        EducationLevel.seniorHigh1,
        EducationLevel.seniorHigh2,
        EducationLevel.seniorHigh3,
      ];
    case EducationStage.higher:
      return const [
        EducationLevel.university,
        EducationLevel.graduate,
        EducationLevel.working,
        EducationLevel.expert,
        EducationLevel.scholar,
        EducationLevel.master,
      ];
  }
}

enum ThemeStyle {
  sakura,
  ocean,
  forest,
  night,
  // 以下為新增主題（以靈感相似的原創風格呈現，避免直接複製原作素材）
  kuromi,
  cinnamoroll,
  mymelody,
  carbot,
  ultraman,
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
    // ====== 國小（越後面越放寬） ======
    case EducationLevel.elementary1:
    case EducationLevel.elementary2:
      // 小一/小二：先盡量收斂到最簡單的字詞（difficulty 1）
      return const LevelRule(
        maxWordDifficulty: 1,
        requirePrimaryWords: true,
        requireCommonWords: false,
        includeLowPriorityWords: false,
        requirePrimaryChars: true,
        requireCommonChars: false,
        includeLowPriorityChars: false,
      );
    case EducationLevel.elementary3:
    case EducationLevel.elementary4:
      return const LevelRule(
        maxWordDifficulty: 2,
        requirePrimaryWords: true,
        requireCommonWords: false,
        includeLowPriorityWords: false,
        requirePrimaryChars: true,
        requireCommonChars: false,
        includeLowPriorityChars: false,
      );
    case EducationLevel.elementary5:
    case EducationLevel.elementary6:
    case EducationLevel.elementaryAll:
      return const LevelRule(
        maxWordDifficulty: 2,
        requirePrimaryWords: true,
        requireCommonWords: false,
        includeLowPriorityWords: false,
        requirePrimaryChars: true,
        requireCommonChars: false,
        includeLowPriorityChars: false,
      );

    // ====== 國中 ======
    case EducationLevel.juniorHigh1:
      return const LevelRule(
        maxWordDifficulty: 2,
        requirePrimaryWords: false,
        requireCommonWords: false,
        includeLowPriorityWords: false,
        requirePrimaryChars: false,
        requireCommonChars: true,
        includeLowPriorityChars: false,
      );
    case EducationLevel.juniorHigh2:
    case EducationLevel.juniorHigh3:
    case EducationLevel.juniorHighAll:
      return const LevelRule(
        maxWordDifficulty: 3,
        requirePrimaryWords: false,
        requireCommonWords: false,
        includeLowPriorityWords: false,
        requirePrimaryChars: false,
        requireCommonChars: true,
        includeLowPriorityChars: false,
      );

    // ====== 高中 ======
    case EducationLevel.seniorHigh1:
    case EducationLevel.seniorHigh2:
    case EducationLevel.seniorHigh3:
    case EducationLevel.seniorHighAll:
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

/// 「發音提示/聽音」的可用次數（每局遊戲）。
///
/// 設計：等級越高次數越少，讓玩法更像遊戲資源管理。
int audioHintLimitForLevel(EducationLevel level) {
  switch (level) {
    case EducationLevel.elementary1:
    case EducationLevel.elementary2:
      return 6;
    case EducationLevel.elementary3:
    case EducationLevel.elementary4:
    case EducationLevel.elementary5:
    case EducationLevel.elementary6:
    case EducationLevel.elementaryAll:
      return 5;
    case EducationLevel.juniorHigh1:
    case EducationLevel.juniorHigh2:
    case EducationLevel.juniorHigh3:
    case EducationLevel.juniorHighAll:
      return 4;
    case EducationLevel.seniorHigh1:
    case EducationLevel.seniorHigh2:
    case EducationLevel.seniorHigh3:
    case EducationLevel.seniorHighAll:
      return 3;
    case EducationLevel.university:
      return 2;
    case EducationLevel.graduate:
      return 2;
    case EducationLevel.working:
      return 1;
    case EducationLevel.expert:
      return 1;
    case EducationLevel.scholar:
      return 1;
    case EducationLevel.master:
      return 1;
  }
}
