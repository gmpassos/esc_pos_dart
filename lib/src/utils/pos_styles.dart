/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'enums.dart';

/// Text styles
class PosStyles {
  const PosStyles({
    this.bold = false,
    this.reverse = false,
    this.underline = false,
    this.turn90 = false,
    this.align,
    this.height = PosTextSize.size1,
    this.width = PosTextSize.size1,
    this.fontType,
    this.codeTable,
    this.isKanji = false,
  });

  // Init all fields with default values
  const PosStyles.defaults({
    this.bold = false,
    this.reverse = false,
    this.underline = false,
    this.turn90 = false,
    this.align = PosAlign.left,
    this.height = PosTextSize.size1,
    this.width = PosTextSize.size1,
    this.fontType = PosFontType.fontA,
    this.codeTable = "CP437",
    this.isKanji = false,
  });

  final bool bold;
  final bool reverse;
  final bool underline;
  final bool turn90;
  final PosAlign? align;
  final PosTextSize height;
  final PosTextSize width;
  final PosFontType? fontType;
  final String? codeTable;
  final bool isKanji;

  PosStyles copyWith({
    bool? bold,
    bool? reverse,
    bool? underline,
    bool? turn90,
    PosAlign? align,
    PosTextSize? height,
    PosTextSize? width,
    PosFontType? fontType,
    String? codeTable,
    bool? isKanji,
  }) {
    return PosStyles(
      bold: bold ?? this.bold,
      reverse: reverse ?? this.reverse,
      underline: underline ?? this.underline,
      turn90: turn90 ?? this.turn90,
      align: align ?? this.align,
      height: height ?? this.height,
      width: width ?? this.width,
      fontType: fontType ?? this.fontType,
      codeTable: codeTable ?? this.codeTable,
      isKanji: isKanji ?? this.isKanji,
    );
  }

  PosStyles ensureWithCodeTable({String defaultCodeTable = 'CP437'}) {
    if (codeTable == null || codeTable!.isEmpty) {
      return copyWith(codeTable: defaultCodeTable);
    }
    return this;
  }
}
