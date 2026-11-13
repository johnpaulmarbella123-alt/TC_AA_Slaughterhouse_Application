import 'package:flutter/services.dart';

/// Capitalizes the first character of the text and the first character
/// immediately following any whitespace (space, tab, newline).
/// Preserves intentional mid-word uppercase characters (e.g. "III", "1B").
class WordsCapitalizationFormatter extends TextInputFormatter {
  const WordsCapitalizationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool capitalizeNext = true;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        buffer.write(char);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
      }
    }

    final formatted = buffer.toString();
    if (formatted == text) return newValue;

    return newValue.copyWith(
      text: formatted,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Capitalizes the first letter of the field and the first letter after
/// sentence-ending punctuation ('.', '!', '?') followed by whitespace or a newline.
class SentencesCapitalizationFormatter extends TextInputFormatter {
  const SentencesCapitalizationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool capitalizeNext = true;
    bool sawSentencePunctuation = false;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n' || char == '\r') {
        buffer.write(char);
        capitalizeNext = true;
        sawSentencePunctuation = false;
      } else if (char == '.' || char == '!' || char == '?') {
        buffer.write(char);
        sawSentencePunctuation = true;
      } else if (char == ' ' || char == '\t') {
        buffer.write(char);
        if (sawSentencePunctuation) {
          capitalizeNext = true;
        }
      } else if (capitalizeNext) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
        sawSentencePunctuation = false;
      } else {
        buffer.write(char);
        sawSentencePunctuation = false;
      }
    }

    final formatted = buffer.toString();
    if (formatted == text) return newValue;

    return newValue.copyWith(
      text: formatted,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Converts all alphabetic characters to uppercase (for Marking Tags, Plate Numbers, Employee IDs).
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return newValue.copyWith(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

