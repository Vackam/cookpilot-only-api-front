import 'package:flutter/material.dart';

import '../design/design_catalog.dart';
import '../design/design_spec.dart';
import '../design/design_switcher.dart';
import '../features/mvp/auth_screen.dart';
import '../features/mvp/cook_layouts/cook_layout_switcher.dart';
import 'app_theme.dart';

class CookPilotApp extends StatefulWidget {
  const CookPilotApp({super.key});

  @override
  State<CookPilotApp> createState() => _CookPilotAppState();
}

class _CookPilotAppState extends State<CookPilotApp> {
  DesignSpec _spec = defaultDesignSpec;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CookPilot',
      debugShowCheckedModeBanner: false,
      theme: buildCookPilotTheme(_spec),
      // 디자인 전환 UI는 라우트 바깥에 두어 모든 화면에서 접근할 수 있게 한다.
      builder: (context, child) => DesignSwitcherOverlay(
        current: _spec,
        onChanged: (spec) => setState(() => _spec = spec),
        child: CookLayoutSwitcherOverlay(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const AuthScreen(),
    );
  }
}
