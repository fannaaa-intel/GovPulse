import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
//  On-screen QR code
//
//  Draws a QR with the `barcode` package — the same library the PDF uses for the
//  code printed on the endorsement letter, so what an admin sees on screen and
//  what comes out of the printer are generated from one implementation and
//  cannot drift.
//
//  Deliberately NOT a new dependency (qr_flutter or similar): `barcode` is
//  already in the tree, and it hands back plain rectangles, which is all a QR
//  is. Rendering them is a forty-line painter.
// ════════════════════════════════════════════════════════════════════════════

class QrView extends StatelessWidget {
  /// The payload — for endorsements, the full scan URL.
  final String data;

  final double size;

  /// Quiet zone. The QR spec wants clear margin around the symbol or scanners
  /// struggle to find the finder patterns; on a white card this reads as
  /// padding, but it is functional.
  final double padding;

  const QrView({
    super.key,
    required this.data,
    this.size = 180,
    this.padding = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      // The light background is required, not cosmetic: scanners expect dark
      // modules on a light field, so this must stay white even in a dark theme.
      color: Colors.white,
      child: CustomPaint(
        size: Size.square(size - padding * 2),
        painter: _QrPainter(data),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final String data;
  const _QrPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    // Medium correction leaves the code readable through the print-scan-photo
    // round trip a paper letter actually goes through.
    final barcode = Barcode.qrCode(
      errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
    );

    for (final element in barcode.make(
      data,
      width: size.width,
      height: size.height,
    )) {
      if (element is! BarcodeBar || !element.black) continue;
      // +0.5 on the extent closes the hairline seams that appear between
      // adjacent modules when the rects land on fractional device pixels — a
      // scanner reads those gaps as light and the symbol can fail to decode.
      canvas.drawRect(
        Rect.fromLTWH(
          element.left,
          element.top,
          element.width + 0.5,
          element.height + 0.5,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
