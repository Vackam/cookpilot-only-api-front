import 'package:flutter/material.dart';

import '../../design/design_tokens.dart';
import '../user/data/beta_user_repository.dart';
import 'mvp_widgets.dart';

/// 하단 탭의 '내 정보'. 기기에 저장된 베타 계정을 보여 준다.
///
/// 베타 계정은 앱을 처음 켤 때 자동 발급되어 기기에 붙는다 — 로그아웃 개념이
/// 없으므로 여기서는 계정 확인만 한다.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.color;
    final type = context.type;
    final space = context.space;
    final user = BetaUserSession.currentUser;

    return PageShell(
      homeLogo: true,
      title: '내 정보',
      children: [
        SizedBox(height: space.sectionGap),
        Container(
          padding: EdgeInsets.all(space.cardPadding),
          decoration: BoxDecoration(
            color: color.wash,
            borderRadius: BorderRadius.circular(space.radiusXl),
            border: Border.all(color: color.line),
          ),
          child: Row(
            children: [
              Container(
                width: space.avatarLargeSize,
                height: space.avatarLargeSize,
                decoration: BoxDecoration(
                  color: color.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_rounded,
                  color: color.onAccent,
                  size: space.iconXl,
                ),
              ),
              SizedBox(width: space.blockGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? '베타 사용자',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.title.copyWith(
                        color: color.ink,
                        fontWeight: type.extraBold,
                      ),
                    ),
                    SizedBox(height: space.hairGap),
                    Text(
                      user == null
                          ? '계정을 준비하고 있어요'
                          : (user.betaNumber > 0
                                ? '베타 테스터 #${user.betaNumber}'
                                : '테스트 계정'),
                      style: type.caption.copyWith(color: color.slate),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: space.sectionGap),
        const InfoStrip(
          icon: Icons.phone_iphone_rounded,
          title: '이 기기에 저장된 계정이에요',
          body: '앱을 지우기 전까지 조리 기록·즐겨찾기·개인 레시피가 이 계정에 쌓여요.',
        ),
      ],
    );
  }
}
