class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.baseServings,
    required this.imageUrl,
    required this.ingredients,
    required this.steps,
    required this.hasPersonalVersion,
    this.cookingMethod,
    this.dishType,
    this.hashtags = const [],
    this.latestPersonalVersionId,
    this.favorite = false,
  });

  final String id;
  final String title;
  final String description;
  final double baseServings;
  final String imageUrl;
  final List<Ingredient> ingredients;
  final List<CookStep> steps;
  final bool hasPersonalVersion;
  final String? latestPersonalVersionId;
  final bool favorite;

  /// 끓이기·굽기·볶기·찌기·튀기기 중 하나. 서버가 '기타'는 null로 준다.
  final String? cookingMethod;

  /// 반찬·일품·후식·밥·국·찌개 중 하나. 서버가 '기타'는 null로 준다.
  final String? dishType;

  final List<String> hashtags;

  /// 칩으로 그릴 순서. 분류가 앞, 해시태그가 뒤.
  List<String> get tagLabels => [?dishType, ?cookingMethod, ...hashtags];

  int get timerMinutes {
    final seconds = steps.fold<int>(
      0,
      (total, step) => total + (step.timerSeconds ?? 0),
    );
    return (seconds / 60).ceil();
  }

  String? get badge => hasPersonalVersion ? '나 맞춤' : null;

  String get memorySummary =>
      hasPersonalVersion ? '저장된 개인 레시피가 있어요.' : '아직 저장된 개인 레시피가 없어요.';
}

class Ingredient {
  const Ingredient({
    this.originalIngredientId,
    required this.name,
    required this.amount,
    required this.unit,
    required this.isRequired,
  });

  final String? originalIngredientId;
  final String name;
  final double? amount;
  final String unit;
  final bool isRequired;

  String get amountLabel {
    if (amount == null) return unit;
    final number = amount == amount!.roundToDouble()
        ? amount!.toInt().toString()
        : amount.toString();
    return '$number$unit';
  }

  String get requirementLabel => isRequired ? '필수 재료' : '선택 재료';
}

class CookStep {
  const CookStep({
    this.originalStepId,
    required this.stepIndex,
    required this.instruction,
    required this.timerSeconds,
    required this.cautionNote,
    required this.imageUrl,
  });

  final String? originalStepId;
  final int stepIndex;
  final String instruction;
  final int? timerSeconds;
  final String? cautionNote;
  final String imageUrl;

  String get title => '${stepIndex + 1}단계';

  String get description =>
      cautionNote == null ? instruction : '$instruction\n주의: $cautionNote';

  Duration get timerDuration => Duration(seconds: timerSeconds ?? 0);

  int get minutes => ((timerSeconds ?? 0) / 60).ceil();
}
