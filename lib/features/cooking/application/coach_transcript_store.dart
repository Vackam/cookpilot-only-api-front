import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 코치와 주고받은 발화 한 턴.
@immutable
final class CoachTranscriptTurn {
  const CoachTranscriptTurn({required this.isUser, required this.text});

  const CoachTranscriptTurn.user(this.text) : isUser = true;

  const CoachTranscriptTurn.coach(this.text) : isUser = false;

  final bool isUser;
  final String text;

  Map<String, Object> toJson() => <String, Object>{
    'isUser': isUser,
    'text': text,
  };

  /// 빈 발화는 재주입 프롬프트에서 잡음일 뿐이라 복원값으로 쓰지 않는다.
  static CoachTranscriptTurn? fromJson(Map<String, Object?> json) {
    if (json case {
      'isUser': final bool isUser,
      'text': final String text,
    } when text.trim().isNotEmpty) {
      return CoachTranscriptTurn(isUser: isUser, text: text);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is CoachTranscriptTurn &&
      other.isUser == isUser &&
      other.text == text;

  @override
  int get hashCode => Object.hash(isUser, text);

  @override
  String toString() => '${isUser ? '사용자' : '코치'}: $text';
}

/// 한 조리 세션에서 코치와 나눈 대화 로그.
///
/// [summary]는 에이전트가 `save_context` client tool로 넘긴 요약이다. 앱은
/// 요약을 만들지 않고 받아 적기만 한다(요약 주체 결정은 이슈 #1 참고).
///
/// [substitutions]는 `substitute_ingredient`로 확정된 재료 대체다. 요약과
/// 달리 자유 텍스트가 아니라 원래 재료 → 대체 재료의 구조화된 사실이라,
/// 재시작 프롬프트에서 참고용 대화가 아닌 현재 상태로 들어간다.
@immutable
final class CoachTranscript {
  const CoachTranscript({
    required this.sessionId,
    this.turns = const <CoachTranscriptTurn>[],
    this.summary,
    this.substitutions = const <String, String>{},
  });

  /// shared_preferences는 저장마다 전부 다시 쓰는 구조라 로그를 무한히
  /// 늘릴 수 없다. 상한을 넘으면 오래된 턴부터 버린다.
  static const maxTurns = 200;

  /// 재료 대체도 같은 이유로 상한을 둔다. 한 레시피의 재료 수를 넉넉히
  /// 넘는 값이라 정상 조리에서는 닿지 않는다.
  static const maxSubstitutions = 30;

  /// 저장된 로그가 어느 조리 세션의 것인지. 다른 세션이면 버린다.
  final String sessionId;
  final List<CoachTranscriptTurn> turns;
  final String? summary;

  /// 원래 재료 이름 → 대체 재료 이름.
  final Map<String, String> substitutions;

  bool get isEmpty => turns.isEmpty && summary == null && substitutions.isEmpty;

  Map<String, Object> toJson() {
    final json = <String, Object>{
      'sessionId': sessionId,
      'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
    };
    if (summary != null) {
      json['summary'] = summary!;
    }
    if (substitutions.isNotEmpty) {
      json['substitutions'] = Map<String, String>.from(substitutions);
    }
    return json;
  }

  /// 턴 하나라도 손상됐으면 전체를 버린다 — 순서가 어긋난 대화는 재주입할 때
  /// 원문보다 해롭다.
  static CoachTranscript? fromJson(Map<String, Object?> json) {
    final summary = json['summary'];
    if (summary != null && summary is! String) {
      return null;
    }
    final substitutions = _substitutionsFromJson(json['substitutions']);
    if (substitutions == null) {
      return null;
    }
    if (json case {
      'sessionId': final String sessionId,
      'turns': final List<Object?> rawTurns,
    } when sessionId.isNotEmpty && rawTurns.length <= maxTurns) {
      final turns = <CoachTranscriptTurn>[];
      for (final raw in rawTurns) {
        if (raw is! Map) {
          return null;
        }
        final turn = CoachTranscriptTurn.fromJson(
          Map<String, Object?>.from(raw),
        );
        if (turn == null) {
          return null;
        }
        turns.add(turn);
      }
      return CoachTranscript(
        sessionId: sessionId,
        turns: List.unmodifiable(turns),
        summary: summary as String?,
        substitutions: Map.unmodifiable(substitutions),
      );
    }
    return null;
  }

  /// 손상된 대체 항목이 하나라도 있으면 전체를 버린다 — 재료를 반쯤 잘못
  /// 아는 코치가 아예 모르는 코치보다 위험하다. 값이 없으면 빈 맵이다.
  static Map<String, String>? _substitutionsFromJson(Object? raw) {
    if (raw == null) {
      return const <String, String>{};
    }
    if (raw is! Map || raw.length > maxSubstitutions) {
      return null;
    }
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String ||
          value is! String ||
          key.trim().isEmpty ||
          value.trim().isEmpty) {
        return null;
      }
      result[key] = value;
    }
    return result;
  }
}

abstract interface class CoachTranscriptGateway {
  Future<void> save(CoachTranscript transcript);

  Future<CoachTranscript?> load();

  Future<void> clear();
}

typedef CoachTranscriptPreferencesLoader = Future<SharedPreferences> Function();

/// 대화 로그를 shared_preferences에 하나만 보관한다.
///
/// 전사본이 평문으로 남으므로 조리가 끝나면 반드시 [clear]가 돌아야 한다.
final class CoachTranscriptStore implements CoachTranscriptGateway {
  const CoachTranscriptStore({this.preferencesLoader});

  static const storageKey = 'cookpilot.coach_transcript.v1';

  final CoachTranscriptPreferencesLoader? preferencesLoader;

  Future<SharedPreferences> _loadPreferences() =>
      (preferencesLoader ?? SharedPreferences.getInstance)();

  @override
  Future<void> save(CoachTranscript transcript) async {
    final prefs = await _loadPreferences();
    final saved = await prefs.setString(
      storageKey,
      jsonEncode(transcript.toJson()),
    );
    if (!saved) {
      throw StateError('코치 대화 로그를 로컬에 저장하지 못했습니다.');
    }
  }

  /// 저장값이 없거나 손상됐으면 null. 손상값은 함께 정리한다.
  @override
  Future<CoachTranscript?> load() async {
    final prefs = await _loadPreferences();
    final raw = prefs.get(storageKey);
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          final transcript = CoachTranscript.fromJson(decoded);
          if (transcript != null) {
            return transcript;
          }
        }
      } catch (_) {
        // 손상된 JSON은 아래에서 제거한다.
      }
    }
    try {
      await prefs.remove(storageKey);
    } on Object {
      // 정리 실패가 조리 화면 진입을 막지 않게 한다. 다음 load가 재시도한다.
    }
    return null;
  }

  @override
  Future<void> clear() async {
    final prefs = await _loadPreferences();
    final removed = await prefs.remove(storageKey);
    if (!removed) {
      throw StateError('코치 대화 로그를 로컬에서 정리하지 못했습니다.');
    }
  }
}
