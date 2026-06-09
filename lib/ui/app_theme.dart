import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AppPalette {
  const AppPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceDim,
    required this.primary,
    required this.secondary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.error,
  });

  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceDim;
  final Color primary;
  final Color secondary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color error;

  factory AppPalette.fromBrightness(bool dark) {
    return AppPalette(
      isDark: dark,
      background: dark ? Colors.black : const Color(0xfff5f5f5),
      surface: dark
          ? const Color(0x991a1a1a)
          : Colors.white.withValues(alpha: 0.72),
      surfaceDim: dark ? const Color(0x660f0f0f) : const Color(0x88f5f5f5),
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
    );
  }
}

ThemeData buildTheme(bool dark) {
  final p = AppPalette.fromBrightness(dark);
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final textTheme = GoogleFonts.hankenGroteskTextTheme(
    base.textTheme,
  ).apply(bodyColor: p.onSurface, displayColor: p.onSurface);
  return base.copyWith(
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
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.primary.withValues(alpha: 0.55)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? p.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.36 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: content,
    );
  }
}

class RoundIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final button = SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background ?? Colors.transparent,
          foregroundColor: color ?? p.onSurfaceVariant,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: iconSize),
      ),
    );
    return button;
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
