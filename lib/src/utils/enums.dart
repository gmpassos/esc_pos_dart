/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

enum PosAlign {
  left(0),
  center(1),
  right(2);

  final int value;

  const PosAlign(this.value);

  static PosAlign? from(String? s) {
    if (s == null) return null;
    s = s.trim();
    if (s.isEmpty) return null;

    switch (s.toLowerCase()) {
      case 'l':
      case 'left':
        return left;
      case 'c':
      case 'center':
        return center;
      case 'r':
      case 'right':
        return right;
      default:
        return null;
    }
  }
}

enum PosCutMode { full, partial }

enum PosFontType {
  fontA(0, 'a'),
  fontB(1, 'b');

  final int value;
  final String valueName;

  const PosFontType(this.value, this.valueName);

  static PosFontType? from(String? s) {
    if (s == null) return null;
    s = s.trim();
    if (s.isEmpty) return null;

    switch (s.toLowerCase()) {
      case '':
      case '0':
      case 'a':
      case 'fonta':
        return fontA;
      case '1':
      case 'b':
      case 'fontb':
        return fontB;
      default:
        return null;
    }
  }
}

enum PosDrawer { pin2, pin5 }

/// Choose image printing function
/// bitImageRaster: GS v 0 (obsolete)
/// graphics: GS ( L
enum PosImageFn { bitImageRaster, graphics }

enum PosTextSize {
  size1(1),
  size2(2),
  size3(3),
  size4(4),
  size5(5),
  size6(6),
  size7(7),
  size8(8);

  final int value;

  const PosTextSize(this.value);

  static int decSize(PosTextSize height, PosTextSize width) =>
      16 * (width.value - 1) + (height.value - 1);
}

enum PaperSize {
  mm58(1),
  mm80(2);

  final int value;

  const PaperSize(this.value);

  int get width => value == PaperSize.mm58.value ? 372 : 558;
}

enum PosBeepDuration {
  beep50ms(1),
  beep100ms(2),
  beep150ms(3),
  beep200ms(4),
  beep250ms(5),
  beep300ms(6),
  beep350ms(7),
  beep400ms(8),
  beep450ms(9);

  final int value;

  const PosBeepDuration(this.value);
}
