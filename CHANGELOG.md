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

