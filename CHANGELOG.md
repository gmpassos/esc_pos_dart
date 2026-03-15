## 1.3.2

- `PrinterDocument`:
  - `print`: added optional `selectCharCodeTable` parameter.
  - `print`: pass initial `PosStyles` with font size to `printer.reset()`.
  - `print`: ensure `fontSize` style is applied via `printer.setStyles()`.

- `PrinterCommandStyle`:
  - Changed all fields to nullable.
  - Added `const` constructor and `defaults` constructor.
  - `fromJson`: no longer provide default values; fields nullable.
  - `toJson`: serialize only non-null fields.
  - `toPosStyles`: treat null booleans as false; convert nullable width/height to `PosTextSize` or null.
  - Removed internal `getPosTextSize` method.

- `GenericPrinter`:
  - `reset` method now accepts optional `PosStyles` parameter and passes it to generator.

- `DecoderEscPos`:
  - Added support for GS command 0x21 to decode font size.
  - Added `CommandEscPosFontSize` command with width and height size parameters.
  - Updated `CommandEscPos.fromJson` to support `font-size` command.

- `enums.dart`:
  - Added `PosTextSize.encodeSize` to encode width and height into a single int.
  - Added `PosTextSize.decodeSize` to decode int into width and height `PosTextSize` values.

- `Generator`:
  - `reset` now accepts optional `PosStyles` parameter.
  - Added `setAlign` method with optional `force` parameter.
  - Updated `setGlobalCodeTable` and `setFont` to accept `force` parameter.
  - Updated `setStyles` to handle nullable width and height, and encode font size using `PosTextSize.encodeSize`.
  - Updated `getCharWidth` and `getCharsPerLine` to handle nullable width and global styles fallback.

- `GeneratorEscPos`:
  - Implemented `reset` with optional `styles` parameter, applying initial styles with defaults.
  - Implemented `setAlign` to update alignment if changed or forced.
  - Updated `setStyles` to handle nullable height and width, and encode font size accordingly.

- `PosStyles`:
  - Made `height` and `width` nullable.
  - Added `copyWithDefaults` method to fill null fields from defaults or parameters.
  - Updated constructors to allow nullable height and width.

## 1.3.1

- `PrinterDocument`:
  - Updated `print` method to apply text size styles using `PosTextSize.withValue` and `printer.setStyles` when `fontSize` is set.

- `enums.dart`:
  - Added import of `package:collection/collection.dart`.
  - `PosTextSize`:
    - Added static method `withValue(int value)` to return a `PosTextSize` enum matching the given value or null if none matches.

## 1.3.0

- `PrinterDocument`:
  - Added `fontSize` field with clamped range 1 to 8.
  - Updated constructor to accept optional `fontSize` parameter.
    - **Breaking change:** The constructor now uses named parameters.
  - Updated `fromJson` and `toJson` to handle `fontSize`.

- `Generator`:
  - Updated `getCharsPerLine` to adjust character count based on `PosStyles.width` scaling.

- Dependencies:
  - Updated `image` to ^4.8.0.
  - Updated `test` to ^1.30.0.
  - Updated `dependency_validator` to ^5.0.4.

## 1.2.1

- `PrinterDocument`:
  - `print`: added optional parameter `selectCharCodeTable` to select character code table before printing.

- `GenericPrinter`:
  - Added method `selectCharCodeTable({int codeTable = 0})` to send ESC/POS command to select character code table.

- `Generator` (abstract):
  - Added methods and properties for character code table support:
    - `selectCharCodeTable({int codeTable = 0})`
    - `int? get selectedCharCodeTable`
    - `String? get selectedCharset`
    - `CharsetEncoder? get selectedCharsetEncoder`

- `GeneratorEscPos`:
  - Implemented character code table selection and tracking:
    - `_selectedCharCodeTable`, `_selectedCharset`, `_selectedCharsetEncoder` fields.
    - `selectCharCodeTable` updates selected table and charset encoder.
    - `reset` clears selected character code table.
  - Added enum `CharCodeTableEscPos` mapping ESC/POS code tables to charset names and encoders.
  - Updated text encoding to use selected charset encoder if available.

- `char_encoder.dart`:
  - Added comprehensive charset encoder resolution via `getCharsetEncoder(String? name)` using `charset` package.
  - Updated `encodeChars` to accept optional `CharsetEncoder` or charset name and fallback to latin1 or utf8 if encoding fails.

- Dependency updates:
  - Added `charset: ^2.0.1`
  - Updated `image` to ^4.7.2
  - Updated `collection` to ^1.19.1
  - Updated `test` to ^1.29.0
  - Updated `dependency_validator` to ^5.0.3
  - Updated `coverage` to ^1.15.0

## 1.2.0

- Migrate to `image: ^4.5.4`.

- image: ^4.5.4

- test: ^1.26.2
- dependency_validator: ^5.0.2
- coverage: ^1.14.1

## 1.1.3

- `DecoderEscPos`:
  - Fix decoding of Bit Image, calculating the correct data length.

- `CommandEscPosBitImage`:
  - Added field `lineBreak`.

- coverage: ^1.13.1

## 1.1.2

- `Generator`:
  - Fix `getCharsPerLine` to use `styles.fontType`.
  - `cut`: change parameter to `extraLines = 4`.
  - `hr`: fix call to `getMaxCharsPerLine` to use `styles.fontType ?? globalFont`.

- `GeneratorEscPos`:
  - Consider character margin for max characters per line.

- `PrinterCommandHR`:
  - Fix JSON: add parameter `style`.

- `PrinterCommandImage`:
  - Added `decodeImage`.
  - Fix JSON: add parameter `mimeType`.

## 1.1.1

- `Generator`:
  - `cut`: rollback default value for `extraLines` to `3`. Most printers need at least 3 extra lines.

## 1.1.0

- Converted to Dart enums:
  - `PaperSize`, `PosTextSize`, `PosBeepDuration`.

- `PosStyles`:
  - `align` nullable.
  - `fontType` nullable.

- `Generator` now is a base class.
  - Added fields `newLine` and `normalizeNewLines`.
  - Renamed `setGlobalFont` to `setFont`.
  - Added `styledBlock`.
  - `cut`: parameter `extraLines = 2`.
  - `globalFont` now is a getter to `globalStyles.fontType ?? PosFontType.fontA`.
  - Implementation: `GeneratorEscPos` (ESC/POS)
    - Ensure that command styles won't affect global style.

- New `Decoder` and `DecoderEscPos`.

- `PrinterCommandStyle`:
  - Field `align` now is a `PosAlign`.
  - Field `fontType` now is a `PosFontType`.

- `PrinterDocument`:
  - `print`:
    - Added parameters `reset` and `endJob`.
    - Send a `reset` command before start printing.
    - Send a `endJob` command at the end of printing.
  - `addHR`: added parameter `style`.

- collection: ^1.19.0
- lints: ^5.1.1

## 1.0.6

🚀 Refactor: Refactor `NetworkPrinter` into `GenericPrinter` class.
🚀 New `BytesPrinter`.

- sdk: ^3.6.0

- resource_portable: ^3.1.2

- test: ^1.25.15
- coverage: ^1.11.1
- intl: ^0.20.2

## 1.0.5

- New `encodeChars`, to avoid encoding errors.

- Optimize imports.

- image: ^3.3.0
- resource_portable: ^3.1.0
- collection: ^1.18.0

- lints: ^4.0.0
- test: ^1.25.11
- dependency_validator: ^3.2.3
- coverage: ^1.11.0
- intl: ^0.20.1

## 1.0.4

- Fix `NetworkPrinter.disconnect` delay.

## 1.0.3

- Added support to optional command `GS r` (transmission of status).
- Added `end job` command.
- Added `NetworkPrinter.ensureConnected`.

## 1.0.2

- Added `PrinterCommand.toString`.
- Fixed load of resource: `package:esc_pos_dart/resources/capabilities.json`.
- collection: ^1.17.2

## 1.0.1

- New `PrinterDocument`.

## 1.0.0

- Dart pure version:
  - Adjusted for Dart 3.
  - Removed any Flutter dependency.
  - Fixed lints.
  - Added full printing example.

## Original Work

This package is based on the packages [esc_pos_printer](https://github.com/andrey-ushakov/esc_pos_printer) and
[esc_pos_utils](https://github.com/andrey-ushakov/esc_pos_utils) by
Andrey Ushakov ([andrey-ushakov@GitHub](https://github.com/andrey-ushakov)).
Both packages are Flutter dependent, which makes it impossible to use in Dart pure applications.

[esc_pos_printer]: https://github.com/andrey-ushakov/esc_pos_printer
[esc_pos_utils]: https://github.com/andrey-ushakov/esc_pos_utils

