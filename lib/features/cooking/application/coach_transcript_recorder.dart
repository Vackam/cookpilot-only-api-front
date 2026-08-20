import 'dart:async';

import 'coach_transcript_store.dart';

/// 코치 대화 로그를 메모리에 쌓고 debounce로 로컬에 쓴다.
///
/// 코치를 껐다 켜면 SDK 세션이 0턴에서 시작하므로(서버 쪽 대화 이어받기가
/// 없다) 재주입은 앱이 한다. 화면은 [recentTurns]와 [summary]로 재개
/// 프롬프트를 만든다.
final class CoachTranscriptRecorder {
  CoachTranscriptRecorder({
    required this.sessionId,
    required this.store,
    this.debounce = const Duration(seconds: 2),
  });

  /// 이 로그가 속한 조리 세션. 다른 세션의 저장값은 복원하지 않는다.
  final String sessionId;
  final CoachTranscriptGateway store;

  /// 발화가 멈춘 뒤 이만큼 기다렸다 쓴다. 매 턴 저장은 로그 전체를 다시 쓰는
  /// 비용을 턴 수만큼 낸다.
  final Duration debounce;

  final List<CoachTranscriptTurn> _turns = <CoachTranscriptTurn>[];
  final Map<String, String> _substitutions = <String, String>{};
  String? _summary;
  bool _dirty = false;
  bool _cleared = false;
  bool _disposed = false;
  Timer? _autosaveTimer;
  Future<void> _tail = Future<void>.value();

  String? get summary => _summary;

  /// 이번 조리에서 확정된 재료 대체(원래 재료 → 대체 재료). 참고용 대화가
  /// 아니라 현재 상태이므로 화면이 재시작 프롬프트의 재료 목록에 반영한다.
  Map<String, String> get substitutions => Map.unmodifiable(_substitutions);

  bool get isEmpty => _turns.isEmpty && _summary == null;

  /// 뒤에서 [count]턴. 오래된 대화는 도움이 아니라 방해라 전부 넣지 않는다.
  List<CoachTranscriptTurn> recentTurns(int count) {
    if (count <= 0 || _turns.isEmpty) {
      return const <CoachTranscriptTurn>[];
    }
    final start = _turns.length > count ? _turns.length - count : 0;
    return List.unmodifiable(_turns.sublist(start));
  }

  /// 저장된 로그를 메모리로 읽어 온다. 다른 세션의 로그가 남아 있으면
  /// 이번 조리에 섞이지 않도록 지운다. 저장소 오류는 조리 진입을 막지
  /// 않아야 하므로 삼킨다.
  Future<void> restore() async {
    if (_cleared || _disposed) {
      return;
    }
    CoachTranscript? stored;
    try {
      stored = await store.load();
    } on Object {
      return;
    }
    if (_cleared || _disposed || stored == null) {
      return;
    }
    if (stored.sessionId != sessionId) {
      await _runSerialized(() => store.clear());
      return;
    }
    // 복원 대기 중 들어온 발화가 저장값보다 최신이다. 앞에 이어 붙인다.
    _turns.insertAll(0, stored.turns);
    _summary ??= stored.summary;
    for (final entry in stored.substitutions.entries) {
      _substitutions.putIfAbsent(entry.key, () => entry.value);
    }
    _trimToLimit();
  }

  void record(CoachTranscriptTurn turn) {
    if (_cleared || _disposed || turn.text.trim().isEmpty) {
      return;
    }
    _turns.add(
      CoachTranscriptTurn(isUser: turn.isUser, text: turn.text.trim()),
    );
    _trimToLimit();
    _markDirty();
  }

  /// 에이전트가 `save_context`로 넘긴 요약으로 갈아 끼운다. 항상 최신 하나만
  /// 들고 있으면 되므로 누적하지 않는다.
  void recordSummary(String summary) {
    final normalized = summary.trim();
    if (_cleared || _disposed || normalized.isEmpty || normalized == _summary) {
      return;
    }
    _summary = normalized;
    _markDirty();
  }

  /// 에이전트가 `substitute_ingredient`로 확정한 재료 대체를 기록한다.
  /// 같은 재료를 다시 바꾸면 마지막 것만 남는다. 상한을 넘으면 무시한다 —
  /// 오래된 대체를 버리면 코치가 이미 확정한 재료를 잊는다.
  void recordSubstitution(String original, String replacement) {
    final from = original.trim();
    final to = replacement.trim();
    if (_cleared ||
        _disposed ||
        from.isEmpty ||
        to.isEmpty ||
        _substitutions[from] == to ||
        (!_substitutions.containsKey(from) &&
            _substitutions.length >= CoachTranscript.maxSubstitutions)) {
      return;
    }
    _substitutions[from] = to;
    _markDirty();
  }

  /// 밀린 저장을 즉시 반영한다. 백그라운드 전환·코치 종료·화면 이탈처럼
  /// debounce를 기다릴 수 없는 시점에 부른다.
  Future<void> flush() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (!_dirty || _cleared) {
      return _tail;
    }
    return _runSerialized(_write);
  }

  /// 대화 전사본이 폰에 평문으로 남으므로 조리가 끝나면 반드시 부른다.
  /// 이후의 늦은 발화·debounce가 로그를 되살리지 못하게 영구히 막는다.
  Future<void> clear() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _cleared = true;
    _dirty = false;
    _turns.clear();
    _substitutions.clear();
    _summary = null;
    return _runSerialized(() => store.clear());
  }

  /// 예약된 저장만 끊는다. 남은 내용을 지킬지는 [flush] 호출자가 정한다.
  void dispose() {
    _disposed = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
  }

  void _trimToLimit() {
    final excess = _turns.length - CoachTranscript.maxTurns;
    if (excess > 0) {
      _turns.removeRange(0, excess);
    }
  }

  void _markDirty() {
    _dirty = true;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(debounce, () => unawaited(flush()));
  }

  Future<void> _write() async {
    // 쓰기 시작 시점의 내용만 dirty를 해제한다. 저장 중 들어온 발화는 다음
    // 저장이 가져간다.
    _dirty = false;
    final transcript = CoachTranscript(
      sessionId: sessionId,
      turns: List.unmodifiable(_turns),
      summary: _summary,
      substitutions: Map.unmodifiable(_substitutions),
    );
    try {
      await store.save(transcript);
    } on Object {
      // 실패한 내용은 아직 메모리에 있다. 다음 flush가 다시 시도한다.
      if (!_cleared) {
        _dirty = true;
      }
    }
  }

  Future<void> _runSerialized(Future<void> Function() operation) {
    final previous = _tail;
    final next = (() async {
      await previous;
      try {
        await operation();
      } on Object {
        // 저장·정리 실패가 조리 흐름을 막지 않는다.
      }
    })();
    _tail = next;
    return next;
  }
}
