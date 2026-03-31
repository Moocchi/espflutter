import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Converts img.Image -> Flutter ui.Image for display
Future<ui.Image?> imgToUiImage(img.Image? image) async {
  if (image == null) return null;
  final rgba = img.encodeJpg(image);
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(rgba));
  final frame = await codec.getNextFrame();
  return frame.image;
}

class ProcessedFramePainter extends CustomPainter {
  final ui.Image? uiImage;
  ProcessedFramePainter(this.uiImage);

  @override
  void paint(Canvas canvas, Size size) {
    if (uiImage == null) return;
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: uiImage!,
      fit: BoxFit.contain, // Maintain aspect ratio
      filterQuality: FilterQuality.none, // Keep pixel art sharp
    );
  }

  @override
  bool shouldRepaint(covariant ProcessedFramePainter old) =>
      old.uiImage != uiImage;
}

class PreviewWidget extends StatefulWidget {
  final List<img.Image?> frames;
  final bool isGif;

  const PreviewWidget({
    super.key,
    required this.frames,
    required this.isGif,
  });

  @override
  State<PreviewWidget> createState() => _PreviewWidgetState();
}

class _PreviewWidgetState extends State<PreviewWidget> {
  int _currentFrame = 0;
  ui.Image? _currentUiImage;

  @override
  void initState() {
    super.initState();
    _loadFrame(0);
  }

  @override
  void didUpdateWidget(covariant PreviewWidget old) {
    super.didUpdateWidget(old);
    // Reload if the frames have been replaced/modified
    final newFrameIdx =
        _currentFrame.clamp(0, (widget.frames.length - 1).clamp(0, 9999));

    // Always reload because the image inside the frame might have been regenerated
    // with new settings (like canvas size changed)
    _loadFrame(newFrameIdx);
  }

  Future<void> _loadFrame(int idx) async {
    if (idx < 0 || idx >= widget.frames.length) return;
    final uiImg = await imgToUiImage(widget.frames[idx]);
    if (mounted) {
      setState(() {
        _currentFrame = idx;
        _currentUiImage = uiImg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final frames = widget.frames;
    if (frames.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Text('No frames', style: TextStyle(color: Colors.grey)),
      );
    }

    final frame = frames[_currentFrame];
    final w = (frame?.width ?? 128).toDouble();
    final h = (frame?.height ?? 64).toDouble();

    // Calculate a display size that strictly maintains the aspect ratio.
    const maxW = 400.0;
    const maxH = 400.0;

    // Determine the scale factor that fits width or height while keeping ratio
    double scale = 1.0;
    if (w > maxW || h > maxH) {
      final scaleW = maxW / w;
      final scaleH = maxH / h;
      scale = scaleW < scaleH ? scaleW : scaleH;
    } else if (w <= 64 && h <= 64) {
      scale = 3.0; // scale up tiny images for better visibility
    } else if (w <= 128 && h <= 128) {
      scale = 2.0;
    }

    final dispW = w * scale;
    final dispH = h * scale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Frame selector
        if (frames.length > 1) ...[
          Row(
            children: [
              const Text('Frame:',
                  style: TextStyle(color: Color(0xFF474C5E), fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _currentFrame.toDouble(),
                  min: 0,
                  max: (frames.length - 1).toDouble(),
                  divisions: frames.length - 1,
                  label: 'Frame $_currentFrame',
                  onChanged: (v) => _loadFrame(v.round()),
                ),
              ),
              Text(
                '$_currentFrame / ${frames.length - 1}',
                style: const TextStyle(color: Color(0xFF6D7385), fontSize: 11),
              ),
            ],
          ),
        ],
        // Canvas preview
        Container(
          width: dispW,
          height: dispH,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF6252E7), width: 2),
            color: Colors.black,
          ),
          child: _currentUiImage == null
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6252E7)))
              : CustomPaint(
                  painter: ProcessedFramePainter(_currentUiImage),
                  size: Size(dispW, dispH),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          '${frame?.width ?? 0} x ${frame?.height ?? 0} px   |   Frame ${_currentFrame + 1} of ${frames.length}',
          style: const TextStyle(color: Color(0xFF6D7385), fontSize: 10),
        ),
      ],
    );
  }
}

