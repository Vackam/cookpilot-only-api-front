import 'package:flutter/material.dart';

import '../../../../design/design_tokens.dart';
import '../../application/cooking_ports.dart';

/// 음성 폴백용 질문 입력 시트. 제출한 질문 문자열을 반환하고,
/// 입력 없이 닫으면 null을 반환한다.
final class HelpQuestionSheet extends StatefulWidget {
  const HelpQuestionSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const HelpQuestionSheet(),
    );
  }

  @override
  State<HelpQuestionSheet> createState() => _HelpQuestionSheetState();
}

final class _HelpQuestionSheetState extends State<HelpQuestionSheet> {
  final TextEditingController _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  void _submit() {
    final question = _question.text.trim();
    if (question.isEmpty) {
      return;
    }
    Navigator.of(context).pop(question);
  }

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    // 키보드가 올라온 상태에서 가용 높이를 넘으면 스크롤로 대응한다.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(space.sectionGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('무엇이 문제인가요?', style: type.subtitle),
            SizedBox(height: space.hairGap),
            Text(
              '현재 단계에 맞춰 대처 방법을 알려드려요.',
              style: type.body.copyWith(color: color.slate),
            ),
            SizedBox(height: space.hairGap),
            Text(
              '질문은 Google Gemini로 전송될 수 있어요. '
              '개인정보·건강정보는 입력하지 마세요.',
              style: type.caption.copyWith(color: color.slate),
            ),
            SizedBox(height: space.blockGap),
            TextField(
              key: const Key('help-question-field'),
              controller: _question,
              maxLength: maxExceptionAdviceQuestionLength,
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: '예: 물이 안 끓어요',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: space.blockGap),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _question,
              builder: (context, value, _) => FilledButton(
                key: const Key('help-question-submit'),
                onPressed: value.text.trim().isEmpty ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(space.compactControlHeight),
                ),
                child: const Text('질문하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
