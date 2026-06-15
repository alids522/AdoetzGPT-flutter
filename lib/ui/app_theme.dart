import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AppVisualTheme { classic, liquidGlass, auroraNeon, modernMinimal, ios26, midnightBloom }

class AppVisualThemeOption {
  const AppVisualThemeOption({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String key;
  final String label;
  final String description;
  final IconData icon;
}

const appVisualThemeOptions = [
  AppVisualThemeOption(
    key: 'default',
    label: 'Default',
    description: 'The original AdoetzGPT look.',
    icon: LucideIcons.circle,
  ),
  AppVisualThemeOption(
    key: 'liquid-glass',
    label: 'Liquid Glass',
    description: 'Frosted translucent panels with soft depth.',
    icon: LucideIcons.glassWater,
  ),
  AppVisualThemeOption(
    key: 'aurora-neon',
    label: 'Aurora Neon',
    description: 'Deep space contrast with electric glow.',
    icon: LucideIcons.sparkles,
  ),
  AppVisualThemeOption(
    key: 'modern-minimal',
    label: 'Modern Minimal',
    description: 'Clean, spacious, and productivity focused.',
    icon: LucideIcons.panelTop,
  ),
  AppVisualThemeOption(
    key: 'ios26',
    label: 'iOS 26 Vision',
    description: 'Extreme liquid glass with fluid animated depth.',
    icon: LucideIcons.box,
  ),
  AppVisualThemeOption(
    key: 'midnight-bloom',
    label: 'Midnight Bloom',
    description: 'Deep indigo garden with emerald, gold, and rose glow.',
    icon: LucideIcons.palette,
  ),
];

AppVisualTheme appVisualThemeFromKey(String value) {
  return switch (value.trim().toLowerCase()) {
    'liquid-glass' || 'liquidglass' || 'glass' => AppVisualTheme.liquidGlass,
    'aurora-neon' ||
    'auroraneon' ||
    'aurora' ||
    'neon' => AppVisualTheme.auroraNeon,
    'modern-minimal' ||
    'modernminimal' ||
    'minimal' => AppVisualTheme.modernMinimal,
    'ios26' || 'vision' => AppVisualTheme.ios26,
    'midnight-bloom' ||
    'midnightbloom' ||
    'midnight' ||
    'bloom' => AppVisualTheme.midnightBloom,
    _ => AppVisualTheme.classic,
  };
}

String appVisualThemeKey(AppVisualTheme theme) {
  return switch (theme) {
    AppVisualTheme.classic => 'default',
    AppVisualTheme.liquidGlass => 'liquid-glass',
    AppVisualTheme.auroraNeon => 'aurora-neon',
    AppVisualTheme.modernMinimal => 'modern-minimal',
    AppVisualTheme.ios26 => 'ios26',
    AppVisualTheme.midnightBloom => 'midnight-bloom',
  };
}

class _ThemeRuntime {
  static AppVisualTheme visualTheme = AppVisualTheme.classic;
}

class AppPalette {
  const AppPalette({
    required this.visualTheme,
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.primary,
    required this.secondary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.error,
    required this.highlight,
    required this.glow,
    required this.shadow,
    required this.panelRadius,
    required this.cardRadius,
    required this.controlRadius,
    required this.sidebarRadius,
    required this.glassBlur,
    required this.motionScale,
  });

  final AppVisualTheme visualTheme;
  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color primary;
  final Color secondary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color error;
  final Color highlight;
  final Color glow;
  final Color shadow;
  final double panelRadius;
  final double cardRadius;
  final double controlRadius;
  final double sidebarRadius;
  final double glassBlur;
  final double motionScale;

  bool get isClassic => visualTheme == AppVisualTheme.classic;
  bool get isLiquidGlass => visualTheme == AppVisualTheme.liquidGlass;
  bool get isAurora => visualTheme == AppVisualTheme.auroraNeon;
  bool get isMinimal => visualTheme == AppVisualTheme.modernMinimal;
  bool get isIos26 => visualTheme == AppVisualTheme.ios26;
  bool get isMidnightBloom => visualTheme == AppVisualTheme.midnightBloom;

  factory AppPalette.fromBrightness(bool dark, {AppVisualTheme? visualTheme}) {
    final theme = visualTheme ?? _ThemeRuntime.visualTheme;
    if (theme == AppVisualTheme.liquidGlass) {
      return AppPalette(
        visualTheme: theme,
        isDark: dark,
        background: dark ? const Color(0xff020304) : const Color(0xffedf3fb),
        surface: dark
            ? Colors.white.withValues(alpha: 0.105)
            : Colors.white.withValues(alpha: 0.62),
        surfaceDim: dark
            ? Colors.white.withValues(alpha: 0.065)
            : Colors.white.withValues(alpha: 0.42),
        surfaceBright: dark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.78),
        primary: const Color(0xff4f9cff),
        secondary: dark ? const Color(0xffc7d2fe) : const Color(0xff475569),
        onSurface: dark ? Colors.white : const Color(0xff111827),
        onSurfaceVariant: dark
            ? const Color(0xffb6c2d2)
            : const Color(0xff526070),
        outline: dark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.72),
        error: const Color(0xffff5c7a),
        highlight: Colors.white.withValues(alpha: dark ? 0.28 : 0.82),
        glow: const Color(0xff7dd3fc),
        shadow: Colors.black.withValues(alpha: dark ? 0.46 : 0.14),
        panelRadius: 34,
        cardRadius: 26,
        controlRadius: 22,
        sidebarRadius: 34,
        glassBlur: 22,
        motionScale: 1,
      );
    }
    if (theme == AppVisualTheme.auroraNeon) {
      return AppPalette(
        visualTheme: theme,
        isDark: dark,
        background: dark ? const Color(0xff030712) : const Color(0xffeef7ff),
        surface: dark
            ? const Color(0xcc090b1f)
            : Colors.white.withValues(alpha: 0.78),
        surfaceDim: dark ? const Color(0x99111a33) : const Color(0x88dff8ff),
        surfaceBright: dark ? const Color(0xff111936) : const Color(0xffffffff),
        primary: dark ? const Color(0xff22d3ee) : const Color(0xff2563eb),
        secondary: dark ? const Color(0xffa78bfa) : const Color(0xff7c3aed),
        onSurface: dark ? const Color(0xfff8fbff) : const Color(0xff0f172a),
        onSurfaceVariant: dark
            ? const Color(0xffa8b3cf)
            : const Color(0xff475569),
        outline: dark
            ? const Color(0xff22d3ee).withValues(alpha: 0.18)
            : const Color(0xff2563eb).withValues(alpha: 0.13),
        error: const Color(0xffff477e),
        highlight: const Color(0xff67e8f9).withValues(alpha: 0.26),
        glow: dark ? const Color(0xff8b5cf6) : const Color(0xff06b6d4),
        shadow: const Color(0xff020617).withValues(alpha: dark ? 0.68 : 0.16),
        panelRadius: 28,
        cardRadius: 22,
        controlRadius: 18,
        sidebarRadius: 30,
        glassBlur: 14,
        motionScale: 1,
      );
    }
    if (theme == AppVisualTheme.modernMinimal) {
      return AppPalette(
        visualTheme: theme,
        isDark: dark,
        background: dark ? const Color(0xff0f1115) : const Color(0xfff7f7f5),
        surface: dark ? const Color(0xff171a20) : const Color(0xffffffff),
        surfaceDim: dark ? const Color(0xff111318) : const Color(0xffeeeeec),
        surfaceBright: dark ? const Color(0xff20242c) : const Color(0xffffffff),
        primary: const Color(0xff2563eb),
        secondary: dark ? const Color(0xffa1a1aa) : const Color(0xff52525b),
        onSurface: dark ? const Color(0xfff4f4f5) : const Color(0xff18181b),
        onSurfaceVariant: dark
            ? const Color(0xffa1a1aa)
            : const Color(0xff71717a),
        outline: dark ? const Color(0xff27272a) : const Color(0xffe4e4e7),
        error: const Color(0xffdc2626),
        highlight: dark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.90),
        glow: const Color(0xff2563eb),
        shadow: Colors.black.withValues(alpha: dark ? 0.32 : 0.08),
        panelRadius: 18,
        cardRadius: 14,
        controlRadius: 14,
        sidebarRadius: 24,
        glassBlur: 0,
        motionScale: 0.65,
      );
    }
    if (theme == AppVisualTheme.ios26) {
      return AppPalette(
        visualTheme: theme,
        isDark: dark,
        background: dark ? const Color(0xff000000) : const Color(0xfff2f2f7),
        surface: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.55),
        surfaceDim: dark ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.35),
        surfaceBright: dark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.85),
        primary: const Color(0xff007aff),
        secondary: dark ? const Color(0xff8e8e93) : const Color(0xff8e8e93),
        onSurface: dark ? Colors.white : Colors.black,
        onSurfaceVariant: dark ? const Color(0xffebebf5).withValues(alpha: 0.6) : const Color(0xff3c3c43).withValues(alpha: 0.6),
        outline: dark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
        error: const Color(0xffff3b30),
        highlight: Colors.white.withValues(alpha: dark ? 0.25 : 0.9),
        glow: const Color(0xff5ac8fa),
        shadow: Colors.black.withValues(alpha: dark ? 0.8 : 0.15),
        panelRadius: 40,
        cardRadius: 32,
        controlRadius: 28,
        sidebarRadius: 40,
        glassBlur: 45,
        motionScale: 1.25,
      );
    }
    if (theme == AppVisualTheme.midnightBloom) {
      return AppPalette(
        visualTheme: theme,
        isDark: dark,
        background: dark ? const Color(0xff06060f) : const Color(0xfff0f4f2),
        surface: dark
            ? const Color(0xcc0c0c1f)
            : Colors.white.withValues(alpha: 0.72),
        surfaceDim: dark
            ? const Color(0x99101028)
            : const Color(0x88dbe8e0),
        surfaceBright: dark
            ? const Color(0xff151530)
            : const Color(0xffffffff),
        primary: dark ? const Color(0xff10b981) : const Color(0xff059669),
        secondary: dark ? const Color(0xfff59e0b) : const Color(0xffd97706),
        onSurface: dark ? const Color(0xffe8ecf0) : const Color(0xff111827),
        onSurfaceVariant: dark
            ? const Color(0xff94a3b8)
            : const Color(0xff475569),
        outline: dark
            ? const Color(0xff10b981).withValues(alpha: 0.16)
            : const Color(0xff059669).withValues(alpha: 0.14),
        error: const Color(0xfffb7185),
        highlight: dark
            ? const Color(0xffec4899).withValues(alpha: 0.10)
            : const Color(0xfff472b6).withValues(alpha: 0.16),
        glow: dark ? const Color(0xffa855f7) : const Color(0xfff472b6),
        shadow: const Color(0xff020617).withValues(alpha: dark ? 0.72 : 0.18),
        panelRadius: 30,
        cardRadius: 22,
        controlRadius: 20,
        sidebarRadius: 32,
        glassBlur: 18,
        motionScale: 1.1,
      );
    }
    return AppPalette(
      visualTheme: theme,
      isDark: dark,
      background: dark ? Colors.black : const Color(0xfff5f5f5),
      surface: dark
          ? const Color(0x991a1a1a)
          : Colors.white.withValues(alpha: 0.72),
      surfaceDim: dark ? const Color(0x660f0f0f) : const Color(0x88f5f5f5),
      surfaceBright: dark ? const Color(0xff1a1a1a) : Colors.white,
      primary: const Color(0xff3b82f6),
      secondary: dark ? const Color(0xffa0a0a0) : const Color(0xff666666),
      onSurface: dark ? Colors.white : const Color(0xff1a1a1a),
      onSurfaceVariant: dark
          ? const Color(0xff888888)
          : const Color(0xff666666),
      outline: dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.08),
      error: const Color(0xffef4444),
      highlight: Colors.white.withValues(alpha: dark ? 0.10 : 0.42),
      glow: const Color(0xff3b82f6),
      shadow: Colors.black.withValues(alpha: dark ? 0.36 : 0.08),
      panelRadius: 28,
      cardRadius: 18,
      controlRadius: 18,
      sidebarRadius: 24,
      glassBlur: 0,
      motionScale: 1,
    );
  }

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppThemeTokens>()?.palette ??
        AppPalette.fromBrightness(
          Theme.of(context).brightness == Brightness.dark,
        );
  }
}

class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({required this.palette});

  final AppPalette palette;

  @override
  AppThemeTokens copyWith({AppPalette? palette}) {
    return AppThemeTokens(palette: palette ?? this.palette);
  }

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) return this;
    return t < 0.5 ? this : other;
  }
}

ThemeData buildTheme(
  bool dark, {
  AppVisualTheme visualTheme = AppVisualTheme.classic,
}) {
  _ThemeRuntime.visualTheme = visualTheme;
  final p = AppPalette.fromBrightness(dark, visualTheme: visualTheme);
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final textTheme = GoogleFonts.hankenGroteskTextTheme(
    base.textTheme,
  ).apply(bodyColor: p.onSurface, displayColor: p.onSurface);
  final theme = base.copyWith(
    extensions: [AppThemeTokens(palette: p)],
    scaffoldBackgroundColor: p.background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: p.primary,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          surface: p.background,
          primary: p.primary,
          onSurface: p.onSurface,
          error: p.error,
          outline: p.outline,
        ),
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: p.onSurface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceDim,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(p.isClassic ? 18 : p.controlRadius),
        borderSide: BorderSide(color: p.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(p.isClassic ? 18 : p.controlRadius),
        borderSide: BorderSide(color: p.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(p.isClassic ? 18 : p.controlRadius),
        borderSide: BorderSide(
          color: p.isAurora ? p.primary : p.primary.withValues(alpha: 0.55),
          width: p.isAurora ? 1.4 : 1,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  if (p.isClassic) {
    return theme;
  }

  return theme.copyWith(
    drawerTheme: DrawerThemeData(
      backgroundColor: p.surface,
      scrimColor: Colors.black.withValues(alpha: p.isAurora ? 0.72 : 0.60),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(p.sidebarRadius),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: p.isMinimal ? 1 : 0,
      shadowColor: p.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.cardRadius),
        side: BorderSide(color: p.outline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceBright,
      elevation: p.isMinimal ? 4 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.panelRadius),
        side: BorderSide(color: p.outline),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceBright,
      modalBackgroundColor: p.surfaceBright,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(p.panelRadius),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surfaceBright,
      contentTextStyle: TextStyle(color: p.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.controlRadius),
        side: BorderSide(color: p.outline),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.onSurfaceVariant,
      textColor: p.onSurface,
      selectedColor: p.onSurface,
      selectedTileColor: p.primary.withValues(alpha: p.isAurora ? 0.16 : 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(p.controlRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.controlRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.controlRadius),
        ),
      ),
    ),
  );
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 28,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final radiusValue = radius == 28 ? p.panelRadius : radius;
    final decoration = BoxDecoration(
      color: backgroundColor ?? p.surface,
      borderRadius: BorderRadius.circular(radiusValue),
      border: Border.all(color: borderColor ?? p.outline),
      gradient: p.isLiquidGlass || p.isAurora
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                p.highlight,
                (backgroundColor ?? p.surface),
                p.glow.withValues(alpha: p.isAurora ? 0.08 : 0.04),
              ],
              stops: const [0, 0.42, 1],
            )
          : null,
      boxShadow: [
        BoxShadow(
          color: p.isClassic
              ? Colors.black.withValues(alpha: p.isDark ? 0.36 : 0.08)
              : p.shadow,
          blurRadius: p.isClassic ? 30 : (p.isMinimal ? 18 : 34),
          offset: p.isClassic
              ? const Offset(0, 14)
              : Offset(0, p.isMinimal ? 8 : 16),
        ),
        if (p.isAurora)
          BoxShadow(
            color: p.glow.withValues(alpha: 0.18),
            blurRadius: 28,
            spreadRadius: -8,
          ),
      ],
    );
    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: padding,
      decoration: decoration,
      child: Stack(
        children: [
          if (p.isLiquidGlass)
            Positioned(
              left: 8,
              right: 8,
              top: 0,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: p.isDark ? 0.28 : 0.9),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          Material(color: Colors.transparent, child: child),
        ],
      ),
    );
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radiusValue),
      child: p.glassBlur <= 0
          ? panel
          : BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: p.glassBlur,
                sigmaY: p.glassBlur,
              ),
              child: panel,
            ),
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(radiusValue),
      onTap: onTap,
      child: content,
    );
  }
}

class RoundIconButton extends StatefulWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
    this.iconSize = 20,
    this.color,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? background;

  @override
  State<RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<RoundIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = _hovered || _pressed;
    final scale = reducedMotion || p.isClassic
        ? 1.0
        : (_pressed ? 0.94 : (_hovered ? 1.04 : 1.0));
    final button = SizedBox(
      width: widget.size,
      height: widget.size,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        style: IconButton.styleFrom(
          backgroundColor:
              widget.background ??
              (active && !p.isClassic
                  ? p.surfaceBright.withValues(alpha: p.isAurora ? 0.22 : 0.48)
                  : Colors.transparent),
          foregroundColor: widget.color ?? p.onSurfaceVariant,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(widget.icon, size: widget.iconSize),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: widget.onPressed == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onPressed == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onPressed == null
            ? null
            : () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: Duration(milliseconds: reducedMotion ? 1 : 140),
          curve: Curves.easeOutCubic,
          child: button,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.accent,
  });

  final IconData icon;
  final String title;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: (accent ?? p.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: accent ?? p.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
              color: p.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class ThemedBackdrop extends StatefulWidget {
  const ThemedBackdrop({super.key});

  @override
  State<ThemedBackdrop> createState() => _ThemedBackdropState();
}

class _ThemedBackdropState extends State<ThemedBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate =
        (p.isAurora || p.isLiquidGlass || p.isIos26 || p.isMidnightBloom) &&
        !reducedMotion;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
    if (p.isClassic || p.isMinimal) {
      return DecoratedBox(decoration: BoxDecoration(color: p.background));
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = reducedMotion ? 0.0 : _controller.value;
        final alignmentA = Alignment(
          -0.85 + 0.28 * phase,
          -0.92 + 0.16 * phase,
        );
        final alignmentB = Alignment(0.95 - 0.36 * phase, 0.72 - 0.24 * phase);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: p.background,
            gradient: p.isMidnightBloom
                ? LinearGradient(
                    begin: alignmentA,
                    end: alignmentB,
                    colors: [
                      p.background,
                      const Color(0xff0f172a).withValues(alpha: 0.70),
                      p.glow.withValues(alpha: 0.22),
                      const Color(0xffec4899).withValues(alpha: 0.14),
                      p.background,
                    ],
                    stops: const [0, 0.22, 0.48, 0.74, 1],
                  )
                : p.isIos26
                ? LinearGradient(
                    begin: alignmentA,
                    end: alignmentB,
                    colors: [
                      p.background,
                      p.glow.withValues(alpha: p.isDark ? 0.25 : 0.35),
                      p.primary.withValues(alpha: p.isDark ? 0.35 : 0.45),
                      const Color(0xffa78bfa)
                          .withValues(alpha: p.isDark ? 0.25 : 0.35),
                      p.background,
                    ],
                    stops: const [0, 0.25, 0.5, 0.75, 1],
                  )
                : p.isAurora
                    ? LinearGradient(
                        begin: alignmentA,
                        end: alignmentB,
                        colors: [
                          p.background,
                          const Color(0xff111827),
                          const Color(0xff172554).withValues(alpha: 0.86),
                          const Color(0xff312e81).withValues(alpha: 0.78),
                          p.background,
                        ],
                        stops: const [0, 0.28, 0.52, 0.72, 1],
                      )
                    : RadialGradient(
                        center: alignmentA,
                        radius: 1.25,
                        colors: [
                          Colors.white
                              .withValues(alpha: p.isDark ? 0.10 : 0.62),
                          p.glow.withValues(alpha: p.isDark ? 0.10 : 0.20),
                          p.background,
                        ],
                      ),
          ),
        );
      },
    );
  }
}

class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<SegmentItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surfaceDim,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.outline),
      ),
      child: Row(
        children: items.map((item) {
          final selected = item.value == value;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: selected ? p.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: p.primary.withValues(alpha: 0.25),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: TextButton.icon(
                onPressed: () => onChanged(item.value),
                icon: item.icon == null
                    ? const SizedBox.shrink()
                    : Icon(item.icon, size: 14),
                label: Text(item.label, overflow: TextOverflow.ellipsis),
                style: TextButton.styleFrom(
                  foregroundColor: selected ? Colors.white : p.onSurfaceVariant,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 11,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SegmentItem<T> {
  const SegmentItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class SparkleMark extends StatelessWidget {
  const SparkleMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SparklePainter());
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xff38bdf8),
          Color(0xff818cf8),
          Color(0xffc084fc),
          Color(0xfff472b6),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    final path = Path();
    final c = size.width / 2;
    path.moveTo(c, 0);
    path.cubicTo(
      c + size.width * 0.08,
      c * 0.72,
      c * 1.28,
      c * 0.92,
      size.width,
      c,
    );
    path.cubicTo(
      c * 1.28,
      c * 1.08,
      c + size.width * 0.08,
      c * 1.28,
      c,
      size.height,
    );
    path.cubicTo(c - size.width * 0.08, c * 1.28, c * 0.72, c * 1.08, 0, c);
    path.cubicTo(c * 0.72, c * 0.92, c - size.width * 0.08, c * 0.72, c, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const lucidePlus = LucideIcons.plus;
