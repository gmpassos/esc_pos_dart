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

