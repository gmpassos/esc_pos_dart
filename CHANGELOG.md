## 1.1.0

- Converted to Dart enums:
  - `PaperSize`, `PosTextSize`, `PosBeepDuration`.

- `Generator` now is an interface.
  - Implementations:
    - `GeneratorEscPos` (ESC/POS)
    - `GeneratorEscP` (ESC/P) (new)

- `PrinterCommandStyle`:
  - Field `align` now is a `PosAlign`.
  - Field `fontType` now is a `PosFontType`.

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

