/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

enum PosAlign { left, center, right }

enum PosCutMode { full, partial }

enum PosFontType { fontA, fontB }

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
