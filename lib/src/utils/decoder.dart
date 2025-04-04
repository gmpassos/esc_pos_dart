/// Base class for decoding print commands from received data.
abstract class Decoder<C extends Command> {
  /// Resets the decoder state, preparing it for a new decoding process.
  void reset();

  /// Decodes a sequence of bytes ([serial]) into a list of commands.
  ///
  /// - [serial]: The raw data to decode.
  /// - [offset]: The starting position in [serial] (default: 0).
  /// - [length]: The number of bytes to decode (default: entire buffer).
  ///
  /// Returns a list of decoded commands of type [C].
  List<C> decode(List<int> serial, {int offset = 0, int? length});
}

/// Base class for representing a print command.
abstract class Command {
  /// Command name.
  final String name;

  const Command(this.name);

  /// Converts into a JSON-compatible map.
  Map<String, dynamic> toJson();
}

extension IterableCommandExtension on Iterable<Command> {
  List toJson() => map((e) => e.toJson()).toList();
}
