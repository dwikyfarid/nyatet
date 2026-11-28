// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

/// Token UI v2 (D-70). Semua warna/radius lewat kelas ini — layar tidak boleh
/// memakai warna harfiah. Nilai kontras sudah diukur PM:
/// amber #7A5200 di #FFEFCF (6.1:1), primary #39579C (6.96:1), red #BA1A1A
/// (6.46:1), garis kontrol #767680, label chart #46464F.
@immutable
class NyatetTokens extends ThemeExtension<NyatetTokens> {
  const NyatetTokens({
    required this.primary,
    required this.surface,
    required this.divider,
    required this.controlLine,
    required this.label,
    required this.amberText,
    required this.amberBg,
    required this.redText,
    required this.redBg,
    required this.radius,
    required this.heroSize,
  });

  final Color primary;
  final Color surface;
  final Color divider;
  final Color controlLine;
  final Color label;
  final Color amberText;
  final Color amberBg;
  final Color redText;
  final Color redBg;
  final double radius;
  final double heroSize;

  static const NyatetTokens light = NyatetTokens(
    primary: Color(0xFF39579C),
    surface: Color(0xFFFFFFFF),
    divider: Color(0xFFECECF4),
    controlLine: Color(0xFF767680),
    label: Color(0xFF46464F),
    amberText: Color(0xFF7A5200),
    amberBg: Color(0xFFFFEFCF),
    redText: Color(0xFFBA1A1A),
    redBg: Color(0xFFFFDAD6),
    radius: 16,
    heroSize: 26,
  );

  static NyatetTokens of(BuildContext context) =>
      Theme.of(context).extension<NyatetTokens>() ?? light;

  @override
  NyatetTokens copyWith({
    Color? primary,
    Color? surface,
    Color? divider,
    Color? controlLine,
    Color? label,
    Color? amberText,
    Color? amberBg,
    Color? redText,
    Color? redBg,
    double? radius,
    double? heroSize,
  }) =>
      NyatetTokens(
        primary: primary ?? this.primary,
        surface: surface ?? this.surface,
        divider: divider ?? this.divider,
        controlLine: controlLine ?? this.controlLine,
        label: label ?? this.label,
        amberText: amberText ?? this.amberText,
        amberBg: amberBg ?? this.amberBg,
        redText: redText ?? this.redText,
        redBg: redBg ?? this.redBg,
        radius: radius ?? this.radius,
        heroSize: heroSize ?? this.heroSize,
      );

  @override
  NyatetTokens lerp(ThemeExtension<NyatetTokens>? other, double t) {
    if (other is! NyatetTokens) return this;
    return NyatetTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      controlLine: Color.lerp(controlLine, other.controlLine, t)!,
      label: Color.lerp(label, other.label, t)!,
      amberText: Color.lerp(amberText, other.amberText, t)!,
      amberBg: Color.lerp(amberBg, other.amberBg, t)!,
      redText: Color.lerp(redText, other.redText, t)!,
      redBg: Color.lerp(redBg, other.redBg, t)!,
      radius: lerpDouble(radius, other.radius, t),
      heroSize: lerpDouble(heroSize, other.heroSize, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// Tema v2: satu kelas, dipakai MaterialApp light & dark.
class NyatetTheme {
  const NyatetTheme._();

  /// D-73: hanya tema terang; tidak ada mode gelap.
  static ThemeData light() => _build(NyatetTokens.light, Brightness.light);

  static ThemeData _build(NyatetTokens t, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: t.primary,
      brightness: brightness,
    ).copyWith(
      primary: t.primary,
      surface: t.surface,
      error: t.redText,
      outline: t.controlLine,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.surface,
      dividerColor: t.divider,
      extensions: [t],
      appBarTheme: AppBarTheme(
        backgroundColor: t.surface,
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius),
          side: BorderSide(color: t.divider),
        ),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    );
  }
}
