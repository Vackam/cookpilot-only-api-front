import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../design/design_spec.dart';
import '../../design/design_tokens.dart';
import '../user/data/beta_user_repository.dart';
import 'main_shell.dart';
import 'mvp_widgets.dart';

const _tasteOptions = [
  '마라탕',
  '김치찌개',
  '파스타',
  '초밥',
  '떡볶이',
  '삼겹살',
  '샐러드',
  '카레',
  '치킨',
  '냉면',
  '크림리조또',
  '제육볶음',
];

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PageShell(
      children: [
        SizedBox(height: space.iconHero),
        Center(
          child: Container(
            width: space.brandMarkSize,
            height: space.brandMarkSize,
            decoration: BoxDecoration(
              color: color.accent,
              borderRadius: BorderRadius.circular(space.radiusXl),
              boxShadow: [
                BoxShadow(
                  color: color.shadow,
                  blurRadius: space.shadowBlur,
                  offset: Offset(0, space.shadowLift),
                ),
              ],
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: color.onAccent,
              size: space.iconHero,
            ),
          ),
        ),
        SizedBox(height: space.sectionGap),
        Text(
          'CookPilot',
          textAlign: TextAlign.center,
          style: type.headlineLarge.copyWith(
            color: color.ink,
            fontWeight: type.black,
          ),
        ),
        SizedBox(height: space.snugGap),
        Text(
          '내 입맛을 기억하는 요리 파트너',
          textAlign: TextAlign.center,
          style: type.label.copyWith(
            color: color.slate,
            fontWeight: type.regular,
          ),
        ),
        SizedBox(height: space.majorGap),
        PressableScale(
          child: FilledButton.icon(
            // 카카오 브랜드 색은 디자인 안과 무관하게 고정한다.
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.kakao,
              foregroundColor: BrandColors.kakaoInk,
            ),
            onPressed: () => _openHome(context),
            icon: const Icon(Icons.chat_bubble_rounded),
            label: const Text('카카오로 시작하기'),
          ),
        ),
        SizedBox(height: space.itemGap),
        PressableScale(
          child: OutlinedButton.icon(
            onPressed: () => _openHome(context),
            icon: const Icon(Icons.g_mobiledata_rounded),
            label: const Text('Google로 시작하기'),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: space.sectionGap),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: space.blockGap),
                child: Text(
                  '또는 이메일로',
                  style: type.body.copyWith(color: color.muted),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),
        const TextField(decoration: InputDecoration(labelText: '이메일')),
        SizedBox(height: space.itemGap),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(labelText: '비밀번호'),
        ),
        SizedBox(height: space.blockGap),
        PressableScale(
          child: FilledButton(
            onPressed: () => _openHome(context),
            child: const Text('로그인'),
          ),
        ),
        TextButton(
          onPressed: () => _openHome(context),
          child: const Text('게스트로 둘러보기'),
        ),
        TextButton(
          onPressed: () {
            unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TasteProfileScreen(),
                ),
              ),
            );
          },
          child: const Text('계정이 없나요? 회원가입'),
        ),
      ],
    );
  }

  Future<void> _openHome(BuildContext context) async {
    try {
      await BetaUserRepository().ensureUser();
      if (!context.mounted) return;
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const MainShell()),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사용자 준비에 실패했습니다: $error')));
    }
  }
}

class TasteProfileScreen extends StatefulWidget {
  const TasteProfileScreen({super.key});

  @override
  State<TasteProfileScreen> createState() => _TasteProfileScreenState();
}

class _TasteProfileScreenState extends State<TasteProfileScreen> {
  final Set<String> selected = {'마라탕', '김치찌개', '치킨'};

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PageShell(
      title: '내 입맛 설정',
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      children: [
        Text(
          '끌리는 음식을 3개 이상 골라주세요',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: type.titleLarge.copyWith(
            fontWeight: type.black,
            color: color.ink,
          ),
        ),
        SizedBox(height: space.snugGap),
        Text(
          '고른 음식으로 입맛 프로필을 만들어요.',
          style: type.body.copyWith(color: color.slate),
        ),
        SizedBox(height: space.majorGap),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          mainAxisSpacing: space.itemGap,
          crossAxisSpacing: space.itemGap,
          childAspectRatio: 1,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final option in _tasteOptions)
              _TasteOption(
                label: option,
                selected: selected.contains(option),
                onTap: () {
                  setState(() {
                    if (selected.contains(option)) {
                      selected.remove(option);
                    } else {
                      selected.add(option);
                    }
                  });
                },
              ),
          ],
        ),
        const SectionTitle('매운맛, 어디까지 되세요?'),
        ...['진라면 순한맛도 부담돼요', '신라면 정도가 딱 좋아요', '불닭볶음면도 문제없어요', '핵불닭도 갑니다'].map(
          (label) => Card(
            child: ListTile(
              leading: Icon(
                label.startsWith('신라면')
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: label.startsWith('신라면') ? color.accent : color.muted,
              ),
              title: Text(label),
              subtitle: Text(label.startsWith('신라면') ? '맵기 2~3' : '맵기 선택'),
              dense: true,
            ),
          ),
        ),
      ],
      bottom: PressableScale(
        child: FilledButton(
          onPressed: selected.length >= 3
              ? () async {
                  try {
                    await BetaUserRepository().ensureUser();
                    if (!context.mounted) return;
                  } on Object catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('사용자 준비에 실패했습니다: $error')),
                    );
                    return;
                  }
                  unawaited(
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => const MainShell(),
                      ),
                      (route) => false,
                    ),
                  );
                }
              : null,
          child: Text('다음 · ${selected.length}개 선택됨'),
        ),
      ),
    );
  }
}

class _TasteOption extends StatelessWidget {
  const _TasteOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    return PressableScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(space.radiusLg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.short,
          curve: AppMotion.easeInOut,
          decoration: BoxDecoration(
            color: selected ? color.accentSoft : color.card,
            borderRadius: BorderRadius.circular(space.radiusLg),
            border: Border.all(
              color: selected ? color.accent : color.line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  // 아래쪽만 크게 비워 라벨이 앉을 자리를 남긴다.
                  padding: EdgeInsets.fromLTRB(
                    space.cardPadding,
                    space.blockGap,
                    space.cardPadding,
                    space.majorGap + space.tightGap,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.wash,
                      borderRadius: BorderRadius.circular(space.radiusMd),
                    ),
                    child: Icon(
                      Icons.restaurant_menu_rounded,
                      color: color.placeholderIcon,
                      size: space.iconLg,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: space.snugGap,
                top: space.snugGap,
                child: AnimatedScale(
                  scale: selected ? 1 : 0.6,
                  duration: AppMotion.fast,
                  curve: AppMotion.easeOut,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.easeOut,
                    child: Icon(
                      Icons.check_circle,
                      color: color.accent,
                      size: space.iconMd,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: space.snugGap,
                right: space.snugGap,
                bottom: space.snugGap,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.small.copyWith(
                    color: color.ink,
                    fontWeight: type.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
