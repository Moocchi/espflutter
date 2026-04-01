import 'dart:typed_data';
import 'package:image/image.dart' as img;

enum DrawMode {
  horizontal1bit,
  vertical1bit,
  horizontal565,
  horizontalAlpha,
  horizontal888,
}

enum DitheringMode {
  binary,
  bayer,
  floydSteinberg,
  atkinson,
}

enum OutputFormat {
  plain,
  arduino,
  arduinoSingle,
}

enum BackgroundColor {
  white,
  black,
  transparent,
}

enum ScaleMode {
  original,
  scaleToFit,
  stretchToFill,
  stretchHorizontally,
  stretchVertically,
}

enum AntiAliasMode {
  nearest,
  linear,
  cubic,
  average,
  gaussian3x3,
  smart,
}

class AppSettings {
  int canvasWidth;
  int canvasHeight;
  BackgroundColor backgroundColor;
  bool invertColors;
  DitheringMode ditheringMode;
  int ditheringThreshold;
  ScaleMode scale;
  bool centerHorizontally;
  bool centerVertically;
  int rotation; // 0, 90, 180, 270
  bool flipHorizontally;
  bool flipVertically;
  DrawMode drawMode;
  OutputFormat outputFormat;
  String identifier;
  bool bitswap;
  bool removeZeroesCommas;
  AntiAliasMode antiAlias;

  AppSettings({
    this.canvasWidth = 128,
    this.canvasHeight = 64,
    this.backgroundColor = BackgroundColor.white,
    this.invertColors = false,
    this.ditheringMode = DitheringMode.binary,
    this.ditheringThreshold = 128,
    this.scale = ScaleMode.stretchToFill,
    this.antiAlias = AntiAliasMode.smart,
    this.centerHorizontally = false,
    this.centerVertically = false,
    this.rotation = 0,
    this.flipHorizontally = false,
    this.flipVertically = false,
    this.drawMode = DrawMode.horizontal565,
    this.outputFormat = OutputFormat.arduino,
    this.identifier = 'epd_bitmap_',
    this.bitswap = false,
    this.removeZeroesCommas = false,
  });

  AppSettings copyWith({
    int? canvasWidth,
    int? canvasHeight,
    BackgroundColor? backgroundColor,
    bool? invertColors,
    DitheringMode? ditheringMode,
    int? ditheringThreshold,
    ScaleMode? scale,
    bool? centerHorizontally,
    bool? centerVertically,
    int? rotation,
    bool? flipHorizontally,
    bool? flipVertically,
    DrawMode? drawMode,
    OutputFormat? outputFormat,
    String? identifier,
    bool? bitswap,
    bool? removeZeroesCommas,
    AntiAliasMode? antiAlias,
  }) {
    return AppSettings(
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      invertColors: invertColors ?? this.invertColors,
      ditheringMode: ditheringMode ?? this.ditheringMode,
      ditheringThreshold: ditheringThreshold ?? this.ditheringThreshold,
      scale: scale ?? this.scale,
      centerHorizontally: centerHorizontally ?? this.centerHorizontally,
      centerVertically: centerVertically ?? this.centerVertically,
      rotation: rotation ?? this.rotation,
      flipHorizontally: flipHorizontally ?? this.flipHorizontally,
      flipVertically: flipVertically ?? this.flipVertically,
      drawMode: drawMode ?? this.drawMode,
      outputFormat: outputFormat ?? this.outputFormat,
      identifier: identifier ?? this.identifier,
      bitswap: bitswap ?? this.bitswap,
      removeZeroesCommas: removeZeroesCommas ?? this.removeZeroesCommas,
      antiAlias: antiAlias ?? this.antiAlias,
    );
  }
}

class ImageFrame {
  final String name;
  final img.Image sourceImage;
  img.Image? processedImage;
  String glyph;

  ImageFrame({
    required this.name,
    required this.sourceImage,
    this.processedImage,
    this.glyph = '',
  });
}

class LoadedFile {
  final String name;
  final Uint8List bytes;
  final bool isGif;
  final List<ImageFrame> frames;

  LoadedFile({
    required this.name,
    required this.bytes,
    required this.isGif,
    required this.frames,
  });
}
