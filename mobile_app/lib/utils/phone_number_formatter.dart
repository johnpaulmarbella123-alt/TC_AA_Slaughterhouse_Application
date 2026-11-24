import 'package:flutter/services.dart';

/// Enforces digits-only phone numbers up to 11 digits, formatted as XXXX-XXX-XXXX
/// (e.g. 0917-123-4567 or 1654-456-5455).
class PhoneNumberFormatter extends TextInputFormatter {
  static String digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

  static bool isValidExact11(String input) => digitsOnly(input).length == 11;

  static String format(String input) {
    var digits = digitsOnly(input);
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 4 || i == 7) buf.write('-');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = format(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
