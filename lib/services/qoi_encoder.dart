import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// QOI (Quite OK Image) encoder implementation
/// Based on QOI specification: https://qoiformat.org/qoi-specification.pdf
class QoiEncoder {
  static const int _qoiOpIndex = 0x00; // 00xxxxxx
  static const int _qoiOpDiff = 0x40; // 01xxxxxx
  static const int _qoiOpLuma = 0x80; // 10xxxxxx
  static const int _qoiOpRun = 0xc0; // 11xxxxxx
  static const int _qoiOpRgb = 0xfe; // 11111110
  static const int _qoiOpRgba = 0xff; // 11111111

  static const int _qoiMask2 = 0xc0; // 11000000

  static int _qoiColorHash(int r, int g, int b, int a) {
    return (r * 3 + g * 5 + b * 7 + a * 11) % 64;
  }

  /// Encode an image to QOI format
  static Uint8List encode(img.Image image) {
    final width = image.width;
    final height = image.height;
    final channels = image.numChannels >= 4 ? 4 : 3;

    // Max size: header(14) + pixels * (1 tag + 4 rgba) + end(8)
    final maxSize = 14 + (width * height * 5) + 8;
    final bytes = Uint8List(maxSize);
    var p = 0;

    // Write header
    // Magic "qoif"
    bytes[p++] = 0x71; // 'q'
    bytes[p++] = 0x6f; // 'o'
    bytes[p++] = 0x69; // 'i'
    bytes[p++] = 0x66; // 'f'

    // Width (big endian)
    bytes[p++] = (width >> 24) & 0xff;
    bytes[p++] = (width >> 16) & 0xff;
    bytes[p++] = (width >> 8) & 0xff;
    bytes[p++] = width & 0xff;

    // Height (big endian)
    bytes[p++] = (height >> 24) & 0xff;
    bytes[p++] = (height >> 16) & 0xff;
    bytes[p++] = (height >> 8) & 0xff;
    bytes[p++] = height & 0xff;

    // Channels
    bytes[p++] = channels;

    // Colorspace (0 = sRGB with linear alpha)
    bytes[p++] = 0;

    // Index array for seen pixels
    final index = List<int>.filled(64 * 4, 0);

    int prevR = 0, prevG = 0, prevB = 0, prevA = 255;
    int run = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final a = channels == 4 ? pixel.a.toInt() : 255;

        if (r == prevR && g == prevG && b == prevB && a == prevA) {
          run++;
          if (run == 62 || (y == height - 1 && x == width - 1)) {
            bytes[p++] = _qoiOpRun | (run - 1);
            run = 0;
          }
        } else {
          if (run > 0) {
            bytes[p++] = _qoiOpRun | (run - 1);
            run = 0;
          }

          final indexPos = _qoiColorHash(r, g, b, a);
          final indexOffset = indexPos * 4;

          if (index[indexOffset] == r &&
              index[indexOffset + 1] == g &&
              index[indexOffset + 2] == b &&
              index[indexOffset + 3] == a) {
            bytes[p++] = _qoiOpIndex | indexPos;
          } else {
            index[indexOffset] = r;
            index[indexOffset + 1] = g;
            index[indexOffset + 2] = b;
            index[indexOffset + 3] = a;

            if (a == prevA) {
              final dr = r - prevR;
              final dg = g - prevG;
              final db = b - prevB;

              final drDg = dr - dg;
              final dbDg = db - dg;

              if (dr >= -2 && dr <= 1 && dg >= -2 && dg <= 1 && db >= -2 && db <= 1) {
                bytes[p++] = _qoiOpDiff | ((dr + 2) << 4) | ((dg + 2) << 2) | (db + 2);
              } else if (drDg >= -8 &&
                  drDg <= 7 &&
                  dg >= -32 &&
                  dg <= 31 &&
                  dbDg >= -8 &&
                  dbDg <= 7) {
                bytes[p++] = _qoiOpLuma | (dg + 32);
                bytes[p++] = ((drDg + 8) << 4) | (dbDg + 8);
              } else {
                bytes[p++] = _qoiOpRgb;
                bytes[p++] = r;
                bytes[p++] = g;
                bytes[p++] = b;
              }
            } else {
              bytes[p++] = _qoiOpRgba;
              bytes[p++] = r;
              bytes[p++] = g;
              bytes[p++] = b;
              bytes[p++] = a;
            }
          }
        }

        prevR = r;
        prevG = g;
        prevB = b;
        prevA = a;
      }
    }

    // End marker
    for (int i = 0; i < 7; i++) {
      bytes[p++] = 0;
    }
    bytes[p++] = 1;

    // Return trimmed array
    return Uint8List.sublistView(bytes, 0, p);
  }
}
