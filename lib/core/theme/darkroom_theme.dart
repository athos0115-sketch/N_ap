import 'package:material_ui/material_ui.dart';

/// Darkroom Filament v1.1 (Quiet Pro) 디자인 시스템 토큰 및 테마.
/// - 92% 딥 차콜 모노크롬 + 8% 써멀 필라멘트 (Gold / Solar Orange / Vermilion Red)
/// - 순흑(#000000) · 순백(#FFFFFF) 전면 배제
/// - 1px Warm Rim-Light는 상단 상태 필과 활성 문장 카드 2곳에만 절제 적용
class DarkroomTheme {
  DarkroomTheme._();

  // A. Surface Hierarchy (5)
  static const Color bgInset = Color(0xFF0E0F12);
  static const Color bgCanvas = Color(0xFF121316);
  static const Color bgSidebar = Color(0xFF15161A);
  static const Color bgSurface = Color(0xFF18191D);
  static const Color bgElevated = Color(0xFF1E2026);

  // B. Specular Hairlines & 1px Warm Rim-Light (8)
  static const Color borderSubtle = Color(0x0AFFFFFF);
  static const Color borderSpecular = Color(0x12FFFFFF);
  static const Color borderSpecularStrong = Color(0x1FFFFFFF);
  static const Color rimGold = Color(0x73F6C453);
  static const Color rimOrange = Color(0x47F06E35);
  static const Color rimRed = Color(0x5CE5484D);
  static const Color rimWash = Color(0x0DF6C453);

  // C. Thermal Filament Spectrum & Semantic Accents (14)
  static const Color filamentGold = Color(0xFFF6C453);
  static const Color filamentOrange = Color(0xFFF06E35);
  static const Color filamentOrangeText = Color(0xFFF48C5E);
  static const Color filamentRed = Color(0xFFE5484D);
  static const Color emberCore = Color(0xFFFFF5DC);

  static const Color filamentGoldBg = Color(0x1FF6C453);
  static const Color filamentGoldBorder = Color(0x47F6C453);
  static const Color filamentOrangeBg = Color(0x24F06E35);
  static const Color filamentOrangeBorder = Color(0x4DF06E35);
  static const Color filamentRedBg = Color(0x24E5484D);
  static const Color filamentRedBorder = Color(0x4DE5484D);
  static const Color filamentNeutralBg = Color(0x0FFFFFFF);
  static const Color filamentNeutralBorder = Color(0x1AFFFFFF);
  static const Color statusDangerText = Color(0xFFFCA5A5);

  // D. CTA, Ghost & Typography Colors (10)
  static const Color ctaBg = Color(0xFFF2F3F5);
  static const Color ctaHover = Color(0xFFE6E8EC);
  static const Color ctaPressed = Color(0xFFD8DBE0);
  static const Color ctaText = Color(0xFF121316);

  static const Color btnGhostBg = Color(0x0AFFFFFF);
  static const Color btnGhostHover = Color(0x14FFFFFF);

  static const Color textPrimary = Color(0xFFF2F3F5);
  static const Color textSecondary = Color(0xFF9EA3AE);
  static const Color textMuted = Color(0xFF848A96);
  static const Color textDisabled = Color(0xFF50545E);

  // E. Shadows & Backdrop
  static const Color shadowCard = Color(0x5908090C);
  static const Color shadowFloating = Color(0x8C08090C);
  static const Color backdropPalette = Color(0xAD08090C);

  // F. Spacing & Radius (4px grid)
  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusItem = 10;
  static const double radiusModal = 14;
  static const double radiusCard = 16;
  static const double radiusPill = 999;

  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionBase = Duration(milliseconds: 160);
  static const Duration motionOverlay = Duration(milliseconds: 220);
  static const Duration motionOptic = Duration(milliseconds: 320);
  static const Duration motionBreath = Duration(milliseconds: 3200);

  static ThemeData buildThemeData() {
    const colorScheme = ColorScheme.dark(
      surface: bgSurface,
      primary: ctaBg,
      onPrimary: ctaText,
      secondary: filamentGold,
      onSecondary: bgCanvas,
      error: filamentRed,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgCanvas,
      dividerColor: borderSpecular,
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSidebar,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: borderSpecular, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: borderSpecular, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgElevated,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusItem),
          side: const BorderSide(color: borderSpecularStrong),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusModal),
          side: const BorderSide(color: borderSpecular),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusCard)),
          side: BorderSide(color: borderSpecular),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: filamentGold,
        inactiveTrackColor: borderSpecularStrong,
        thumbColor: ctaBg,
        overlayColor: filamentGoldBg,
      ),
    );
  }
}
