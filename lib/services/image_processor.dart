import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/app_settings.dart';

class ImageProcessor {
  static int _bitswapByte(int b) {
    b = ((b & 0xF0) >> 4) | ((b & 0x0F) << 4);
    b = ((b & 0xCC) >> 2) | ((b & 0x33) << 2);
    b = ((b & 0xAA) >> 1) | ((b & 0x55) << 1);
    return b & 0xFF;
  }

  // =============================================
  //  LOAD FILE & EXTRACT FRAMES
  // =============================================

  static LoadedFile loadFile(String name, Uint8List bytes) {
    final ext = name.toLowerCase().split('.').last;
    final isGif = ext == 'gif';
    final List<ImageFrame> frames = [];

    if (isGif) {
      frames.addAll(_decodeGifFrames(name, bytes));
    } else {
      final image = img.decodeImage(bytes);
      if (image != null) {
        final baseName = name.split('.').first;
        frames.add(ImageFrame(
          name: name,
          sourceImage: image,
          glyph: baseName,
        ));
      }
    }

    return LoadedFile(
      name: name,
      bytes: bytes,
      isGif: isGif,
      frames: frames,
    );
  }

  /// Decode GIF with manual frame compositing.
  /// Handles disposal methods, transparency, and delta frames correctly.
  static List<ImageFrame> _decodeGifFrames(String name, Uint8List bytes) {
    final decoder = img.GifDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null) return [];

    final numFrames = info.numFrames;
    if (numFrames == 0) return [];

    // Decode frame 0 to get full canvas dimensions
    final frame0 = decoder.decodeFrame(0);
    if (frame0 == null) return [];

    final canvasW = frame0.width;
    final canvasH = frame0.height;

    // Canvas that accumulates composited frames
    img.Image canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4);
    // Backup for disposal method 3 (restore to previous)
    img.Image? previousCanvas;

    final List<ImageFrame> result = [];

    for (int i = 0; i < numFrames; i++) {
      final frameInfo = info.frames[i];
      final disposal = frameInfo.disposal;
      final fx = frameInfo.x;
      final fy = frameInfo.y;

      // Save canvas state before drawing (for disposal=3)
      if (disposal == 3) {
        previousCanvas = img.Image.from(canvas);
      }

      // Decode the raw delta frame
      final rawFrame = decoder.decodeFrame(i);
      if (rawFrame == null) continue;

      // Convert raw frame to RGBA and composite onto canvas
      // Only draw non-transparent pixels
      for (int y = 0; y < rawFrame.height; y++) {
        for (int x = 0; x < rawFrame.width; x++) {
          final px = fx + x;
          final py = fy + y;
          if (px >= canvasW || py >= canvasH) continue;

          final pixel = rawFrame.getPixel(x, y);
          final a = pixel.a.toInt();
          if (a > 0) {
            canvas.setPixelRgba(px, py, pixel.r.toInt(), pixel.g.toInt(),
                pixel.b.toInt(), a);
          }
        }
      }

      // Snapshot the composited frame as a full RGBA image
      img.Image composited = img.Image.from(canvas);

      // Center-crop to 1:1 if not already square
      if (canvasW != canvasH) {
        final cropSize = canvasW < canvasH ? canvasW : canvasH;
        final cropX = (canvasW - cropSize) ~/ 2;
        final cropY = (canvasH - cropSize) ~/ 2;
        composited = img.copyCrop(composited,
            x: cropX, y: cropY, width: cropSize, height: cropSize);
      }

      result.add(ImageFrame(
        name: name,
        sourceImage: composited,
        glyph: '${name.split('.').first}_frm${i.toString().padLeft(4, '0')}',
      ));

      // Apply disposal method for the NEXT frame
      // 0 = no disposal (keep as-is)
      // 1 = do not dispose (keep as-is)
      // 2 = restore to background (clear the frame area)
      // 3 = restore to previous
      if (disposal == 2) {
        for (int y = 0; y < rawFrame.height; y++) {
          for (int x = 0; x < rawFrame.width; x++) {
            final px = fx + x;
            final py = fy + y;
            if (px < canvasW && py < canvasH) {
              canvas.setPixelRgba(px, py, 0, 0, 0, 0);
            }
          }
        }
      } else if (disposal == 3 && previousCanvas != null) {
        canvas = previousCanvas;
      }
    }

    return result;
  }

  // =============================================
  //  APPLY SETTINGS TO FRAME → processed image
  // =============================================

  static img.Image applySettings(img.Image source, AppSettings s) {
    // 1. Create canvas with background
    int canvasW = s.canvasWidth;
    int canvasH = s.canvasHeight;

    img.Image canvas = img.Image(width: canvasW, height: canvasH);

    // Fill background
    img.Color bgColor;
    if (s.backgroundColor == BackgroundColor.white) {
      bgColor = img.ColorRgb8(255, 255, 255);
    } else if (s.backgroundColor == BackgroundColor.black) {
      bgColor = img.ColorRgb8(0, 0, 0);
    } else {
      bgColor = img.ColorRgba8(0, 0, 0, 0);
    }
    img.fill(canvas, color: bgColor);

    img.Image src = source;

    // 1. Rotation (Apply to source FIRST before anything else)
    if (s.rotation == 90) {
      src = img.copyRotate(src, angle: 90);
    } else if (s.rotation == 180) {
      src = img.copyRotate(src, angle: 180);
    } else if (s.rotation == 270) {
      src = img.copyRotate(src, angle: 270);
    }

    // 2. Flip (Apply to source FIRST)
    if (s.flipHorizontally) {
      src = img.flipHorizontal(src);
    }
    if (s.flipVertically) {
      src = img.flipVertical(src);
    }

    // 3. Scale + placement
    int drawW = src.width;
    int drawH = src.height;
    int offsetX = 0;
    int offsetY = 0;

    // Map antiAlias setting to image package interpolation
    final interp = _mapInterpolation(s.antiAlias);

    switch (s.scale) {
      case ScaleMode.original:
        if (s.centerHorizontally) offsetX = (canvasW - drawW) ~/ 2;
        if (s.centerVertically) offsetY = (canvasH - drawH) ~/ 2;
        break;
      case ScaleMode.scaleToFit:
        {
          final ratio = [canvasW / src.width, canvasH / src.height]
              .reduce((a, b) => a < b ? a : b);
          drawW = (src.width * ratio).round();
          drawH = (src.height * ratio).round();
          src = img.copyResize(src,
              width: drawW,
              height: drawH,
              interpolation: interp);
          if (s.centerHorizontally) offsetX = (canvasW - drawW) ~/ 2;
          if (s.centerVertically) offsetY = (canvasH - drawH) ~/ 2;
          break;
        }
      case ScaleMode.stretchToFill:
        src = img.copyResize(src,
            width: canvasW,
            height: canvasH,
            interpolation: interp);
        drawW = canvasW;
        drawH = canvasH;
        break;
      case ScaleMode.stretchHorizontally:
        src = img.copyResize(src,
            width: canvasW,
            height: src.height,
            interpolation: interp);
        drawW = canvasW;
        drawH = src.height;
        if (s.centerVertically) offsetY = (canvasH - drawH) ~/ 2;
        break;
      case ScaleMode.stretchVertically:
        src = img.copyResize(src,
            width: src.width,
            height: canvasH,
            interpolation: interp);
        drawW = src.width;
        drawH = canvasH;
        if (s.centerHorizontally) offsetX = (canvasW - drawW) ~/ 2;
        break;
    }

    // Copy onto canvas
    img.compositeImage(canvas, src, dstX: offsetX, dstY: offsetY);

    // 3b. Post-resize Gaussian blur + sharpen (smooth anti-alias without over-blur)
    if (s.antiAlias == AntiAliasMode.gaussian3x3 &&
        s.scale != ScaleMode.original) {
      canvas = img.gaussianBlur(canvas, radius: 1);
      // Light sharpen kernel (sum=1): edges stay crisp after blur
      canvas = img.convolution(canvas,
          filter: [0, -1, 0, -1, 5, -1, 0, -1, 0], div: 1.0);
    }

    // 4. Dithering (only for 1-bit modes)
    if (s.drawMode == DrawMode.horizontal1bit ||
        s.drawMode == DrawMode.vertical1bit ||
        s.drawMode == DrawMode.horizontalAlpha) {
      canvas = _applyDithering(canvas, s);
    }

    // 5. Quantize to RGB565 precision (so processedImage & QOI reflect actual 565 data)
    if (s.drawMode == DrawMode.horizontal565) {
      canvas = _quantize565(canvas);
    }

    // 6. Invert colors
    if (s.invertColors) {
      canvas = img.invert(canvas);
    }

    return canvas;
  }

  static img.Interpolation _mapInterpolation(AntiAliasMode mode) {
    switch (mode) {
      case AntiAliasMode.nearest: return img.Interpolation.nearest;
      case AntiAliasMode.linear: return img.Interpolation.linear;
      case AntiAliasMode.cubic: return img.Interpolation.cubic;
      case AntiAliasMode.average: return img.Interpolation.average;
      case AntiAliasMode.gaussian3x3: return img.Interpolation.linear;
    }
  }

  static img.Image _quantize565(img.Image src) {
    final out = img.Image.from(src);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final r = pixel.r.toInt() & 0xF8; // top 5 bits → zero lower 3
        final g = pixel.g.toInt() & 0xFC; // top 6 bits → zero lower 2
        final b = pixel.b.toInt() & 0xF8; // top 5 bits → zero lower 3
        final a = pixel.a.toInt();
        out.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return out;
  }

  static img.Image _applyDithering(img.Image src, AppSettings s) {
    // Convert to grayscale first
    final grayscale = img.grayscale(img.Image.from(src));

    switch (s.ditheringMode) {
      case DitheringMode.binary:
        return _ditheringBinary(grayscale, s.ditheringThreshold);
      case DitheringMode.bayer:
        return _ditheringBayer(grayscale, s.ditheringThreshold);
      case DitheringMode.floydSteinberg:
        return _ditheringFloydSteinberg(grayscale, s.ditheringThreshold);
      case DitheringMode.atkinson:
        return _ditheringAtkinson(grayscale, s.ditheringThreshold);
    }
  }

  static img.Image _ditheringBinary(img.Image src, int threshold) {
    final out = img.Image.from(src);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final lum = pixel.r.toInt();
        final v = lum < threshold ? 0 : 255;
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  static img.Image _ditheringBayer(img.Image src, int threshold) {
    const bayerMap = [
      [15, 135, 45, 165],
      [195, 75, 225, 105],
      [60, 180, 30, 150],
      [240, 120, 210, 90],
    ];
    final out = img.Image.from(src);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final lum = pixel.r.toInt();
        final map = ((lum + bayerMap[x % 4][y % 4]) / 2).floor();
        final v = map < threshold ? 0 : 255;
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  static img.Image _ditheringFloydSteinberg(img.Image src, int threshold) {
    final pixels = List.generate(src.height,
        (y) => List.generate(src.width, (x) => src.getPixel(x, y).r.toInt()));
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final oldVal = pixels[y][x].clamp(0, 255);
        final newVal = oldVal < 129 ? 0 : 255;
        final err = ((oldVal - newVal) / 16).floor();
        pixels[y][x] = newVal;
        if (x + 1 < src.width) pixels[y][x + 1] += err * 7;
        if (y + 1 < src.height) {
          if (x - 1 >= 0) pixels[y + 1][x - 1] += err * 3;
          pixels[y + 1][x] += err * 5;
          if (x + 1 < src.width) pixels[y + 1][x + 1] += err * 1;
        }
      }
    }
    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final v = pixels[y][x].clamp(0, 255);
        out.setPixelRgba(x, y, v, v, v, 255);  // Set alpha to 255 (opaque)
      }
    }
    return out;
  }

  static img.Image _ditheringAtkinson(img.Image src, int threshold) {
    final pixels = List.generate(src.height,
        (y) => List.generate(src.width, (x) => src.getPixel(x, y).r.toInt()));
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final oldVal = pixels[y][x].clamp(0, 255);
        final newVal = oldVal < threshold ? 0 : 255;
        final err = ((oldVal - newVal) / 8).floor();
        pixels[y][x] = newVal;
        void add(int dy, int dx, int factor) {
          final ny = y + dy;
          final nx = x + dx;
          if (ny >= 0 && ny < src.height && nx >= 0 && nx < src.width) {
            pixels[ny][nx] += err * factor;
          }
        }

        add(0, 1, 1);
        add(0, 2, 1);
        add(1, -1, 1);
        add(1, 0, 1);
        add(1, 1, 1);
        add(2, 0, 1);
      }
    }
    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final v = pixels[y][x].clamp(0, 255);
        out.setPixelRgba(x, y, v, v, v, 255);  // Set alpha to 255 (opaque)
      }
    }
    return out;
  }

  // =============================================
  //  CONVERSION FUNCTIONS → byte list
  // =============================================

  static List<int> imageToBytes(img.Image image, AppSettings s) {
    switch (s.drawMode) {
      case DrawMode.horizontal1bit:
        return _horizontal1bit(image, s);
      case DrawMode.vertical1bit:
        return _vertical1bit(image, s);
      case DrawMode.horizontal565:
        return _horizontal565(image, s);
      case DrawMode.horizontalAlpha:
        return _horizontalAlpha(image, s);
      case DrawMode.horizontal888:
        return _horizontal888(image, s);
    }
  }

  static List<int> _horizontal1bit(img.Image image, AppSettings s) {
    final List<int> bytes = [];
    int byteVal = 0;
    int bitIdx = 7;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final avg = (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) ~/ 3;
        if (avg > s.ditheringThreshold) {
          byteVal |= (1 << bitIdx);
        }
        bitIdx--;
        if (bitIdx < 0) {
          bytes.add(s.bitswap ? _bitswapByte(byteVal) : byteVal);
          byteVal = 0;
          bitIdx = 7;
        }
      }
      // Pad end of row
      if (bitIdx < 7) {
        bytes.add(s.bitswap ? _bitswapByte(byteVal) : byteVal);
        byteVal = 0;
        bitIdx = 7;
      }
    }
    return bytes;
  }

  static List<int> _vertical1bit(img.Image image, AppSettings s) {
    final List<int> bytes = [];
    final pages = (image.height / 8).ceil();
    for (int p = 0; p < pages; p++) {
      for (int x = 0; x < image.width; x++) {
        int byteVal = 0;
        for (int y = 7; y >= 0; y--) {
          final py = p * 8 + y;
          if (py < image.height) {
            final pixel = image.getPixel(x, py);
            final avg =
                (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) ~/ 3;
            if (avg > s.ditheringThreshold) {
              byteVal |= (1 << (7 - y));
            }
          }
        }
        bytes.add(s.bitswap ? _bitswapByte(byteVal) : byteVal);
      }
    }
    return bytes;
  }

  static List<int> _horizontal565(img.Image image, AppSettings s) {
    final List<int> bytes = [];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        int rgb565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | ((b & 0xF8) >> 3);
        if (s.bitswap)
          rgb565 =
              _bitswapByte(rgb565 >> 8) | (_bitswapByte(rgb565 & 0xFF) << 8);
        bytes.add((rgb565 >> 8) & 0xFF);
        bytes.add(rgb565 & 0xFF);
      }
    }
    return bytes;
  }

  static List<int> _horizontal888(img.Image image, AppSettings s) {
    final List<int> bytes = [];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();
        if (s.bitswap) {
          r = _bitswapByte(r);
          g = _bitswapByte(g);
          b = _bitswapByte(b);
        }
        bytes.add(r);
        bytes.add(g);
        bytes.add(b);
      }
    }
    return bytes;
  }

  static List<int> _horizontalAlpha(img.Image image, AppSettings s) {
    final List<int> bytes = [];
    int byteVal = 0;
    int bitIdx = 7;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final alpha = pixel.a.toInt();
        if (alpha > s.ditheringThreshold) {
          byteVal |= (1 << bitIdx);
        }
        bitIdx--;
        if (bitIdx < 0) {
          bytes.add(s.bitswap ? _bitswapByte(byteVal) : byteVal);
          byteVal = 0;
          bitIdx = 7;
        }
      }
      if (bitIdx < 7) {
        bytes.add(s.bitswap ? _bitswapByte(byteVal) : byteVal);
        byteVal = 0;
        bitIdx = 7;
      }
    }
    return bytes;
  }

  // =============================================
  //  OUTPUT STRING GENERATION (.cpp)
  // =============================================

  static String bytesToHexString(List<int> bytes, AppSettings s,
      {bool removeTrailingComma = false}) {
    final buf = StringBuffer();
    int col = 0;
    for (int i = 0; i < bytes.length; i++) {
      if (s.removeZeroesCommas) {
        buf.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      } else {
        buf.write('0x${bytes[i].toRadixString(16).padLeft(2, '0')}');
        if (i < bytes.length - 1 || !removeTrailingComma) buf.write(', ');
      }
      col++;
      if (col >= 16) {
        if (!s.removeZeroesCommas) buf.write('\n');
        col = 0;
      }
    }
    return buf.toString();
  }

  static String getImageType(AppSettings s) {
    if (s.drawMode == DrawMode.horizontal565) return 'uint16_t';
    return 'unsigned char';
  }

  static String generateCppOutput(List<ImageFrame> frames, AppSettings s) {
    switch (s.outputFormat) {
      case OutputFormat.arduino:
        return _generateArduino(frames, s);
      case OutputFormat.arduinoSingle:
        return _generateArduinoSingle(frames, s);
      case OutputFormat.plain:
        return _generatePlain(frames, s);
    }
  }

  static String _generateArduino(List<ImageFrame> frames, AppSettings s) {
    final buf = StringBuffer();
    final varNames = <String>[];
    int bytesUsed = 0;

    for (final frame in frames) {
      if (frame.processedImage == null) continue;
      final bytes = imageToBytes(frame.processedImage!, s);
      final hexStr = bytesToHexString(bytes, s, removeTrailingComma: true);
      final indented = '\t${hexStr.split('\n').join('\n\t')}';
      final imgW = frame.processedImage!.width;
      final imgH = frame.processedImage!.height;
      final glyph = frame.glyph.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final varName = '${s.identifier}$glyph';
      varNames.add(varName);
      bytesUsed += bytes.length;

      buf.writeln("// '${frame.glyph}', ${imgW}x${imgH}px");
      buf.writeln('const ${getImageType(s)} $varName [] PROGMEM = {');
      buf.writeln('$indented');
      buf.writeln('};');
      buf.writeln();
    }

    varNames.sort();
    buf.writeln(
        '// Array of all bitmaps for convenience. (Total bytes used to store images in PROGMEM = $bytesUsed)');
    buf.writeln('const int ${s.identifier}allArray_LEN = ${varNames.length};');
    buf.writeln(
        'const ${getImageType(s)}* ${s.identifier}allArray[${varNames.length}] = {');
    buf.writeln('\t${varNames.join(',\n\t')}');
    buf.writeln('};');

    return buf.toString();
  }

  static String _generateArduinoSingle(List<ImageFrame> frames, AppSettings s) {
    final buf = StringBuffer();
    for (final frame in frames) {
      if (frame.processedImage == null) continue;
      final bytes = imageToBytes(frame.processedImage!, s);
      final hexStr = bytesToHexString(bytes, s);
      final imgW = frame.processedImage!.width;
      final imgH = frame.processedImage!.height;
      buf.writeln("\t// '${frame.glyph}', ${imgW}x${imgH}px");
      buf.write('\t${hexStr.split('\n').join('\n\t')}');
    }
    String content =
        buf.toString().trimRight().replaceAll(RegExp(r',\s*$'), '');
    return 'const ${getImageType(s)} ${s.identifier} [] PROGMEM = {\n$content\n};';
  }

  static String _generatePlain(List<ImageFrame> frames, AppSettings s) {
    final buf = StringBuffer();
    for (int i = 0; i < frames.length; i++) {
      final frame = frames[i];
      if (frame.processedImage == null) continue;
      final bytes = imageToBytes(frame.processedImage!, s);
      if (frame.glyph.isNotEmpty) {
        if (i > 0) buf.write('\n');
        final imgW = frame.processedImage!.width;
        final imgH = frame.processedImage!.height;
        buf.writeln("// '${frame.glyph}', ${imgW}x${imgH}px");
      }
      buf.write(bytesToHexString(bytes, s));
    }
    return buf.toString().trimRight().replaceAll(RegExp(r',\s*$'), '');
  }

  // =============================================
  //  BIN GENERATION
  // =============================================

  static Uint8List frameToBin(img.Image image, AppSettings s) {
    final bytes = imageToBytes(image, s);
    return Uint8List.fromList(bytes);
  }

  /// Returns map of filename -> bytes for all frames
  static Map<String, Uint8List> generateBinFiles(
      List<ImageFrame> frames, AppSettings s, String baseName) {
    final result = <String, Uint8List>{};
    if (frames.length == 1) {
      // Single image → one .bin file
      if (frames[0].processedImage != null) {
        result['$baseName.bin'] = frameToBin(frames[0].processedImage!, s);
      }
    } else {
      // GIF multi-frame → frame0000.bin, frame0001.bin ...
      for (int i = 0; i < frames.length; i++) {
        if (frames[i].processedImage != null) {
          final fname = 'frame${i.toString().padLeft(4, '0')}.bin';
          result[fname] = frameToBin(frames[i].processedImage!, s);
        }
      }
    }
    return result;
  }
}
