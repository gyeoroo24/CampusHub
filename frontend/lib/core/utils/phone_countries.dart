/// Countries for the phone field: dial code and how many digits a number has after it.
/// India comes first and is the default; the rest are the countries IISc students most often
/// come from or have family in, alphabetically.
class PhoneCountry {
  final String name;
  final String iso;
  final String dialCode;

  /// Allowed lengths of the national number (without the country code).
  final int minDigits;
  final int maxDigits;

  const PhoneCountry(this.name, this.iso, this.dialCode, this.minDigits, [int? maxDigits])
      : maxDigits = maxDigits ?? minDigits;

  /// 🇮🇳 from "IN".
  String get flag => String.fromCharCodes(iso.codeUnits.map((c) => 0x1F1E6 + c - 0x41));

  /// Why [digits] isn't a valid number here, or null if it is.
  String? check(String digits) {
    if (digits.isEmpty) return null;
    if (digits.length < minDigits || digits.length > maxDigits) {
      return minDigits == maxDigits
          ? 'A $name number has $minDigits digits'
          : 'A $name number has $minDigits–$maxDigits digits';
    }
    if (iso == 'IN' && !'6789'.contains(digits[0])) return 'Indian mobile numbers start with 6, 7, 8 or 9';
    return null;
  }
}

const india = PhoneCountry('India', 'IN', '+91', 10);

const phoneCountries = <PhoneCountry>[
  india,
  PhoneCountry('Australia', 'AU', '+61', 9),
  PhoneCountry('Bangladesh', 'BD', '+880', 10),
  PhoneCountry('Bhutan', 'BT', '+975', 8),
  PhoneCountry('Canada', 'CA', '+1', 10),
  PhoneCountry('China', 'CN', '+86', 11),
  PhoneCountry('France', 'FR', '+33', 9),
  PhoneCountry('Germany', 'DE', '+49', 10, 11),
  PhoneCountry('Japan', 'JP', '+81', 10),
  PhoneCountry('Malaysia', 'MY', '+60', 9, 10),
  PhoneCountry('Nepal', 'NP', '+977', 10),
  PhoneCountry('Netherlands', 'NL', '+31', 9),
  PhoneCountry('Qatar', 'QA', '+974', 8),
  PhoneCountry('Saudi Arabia', 'SA', '+966', 9),
  PhoneCountry('Singapore', 'SG', '+65', 8),
  PhoneCountry('South Korea', 'KR', '+82', 9, 10),
  PhoneCountry('Sri Lanka', 'LK', '+94', 9),
  PhoneCountry('Switzerland', 'CH', '+41', 9),
  PhoneCountry('United Arab Emirates', 'AE', '+971', 9),
  PhoneCountry('United Kingdom', 'GB', '+44', 10),
  PhoneCountry('United States', 'US', '+1', 10),
];

/// Splits a saved number ("+919876543210") into its country and the digits after the code.
/// Unknown or old-style numbers come back as India with whatever digits they have.
({PhoneCountry country, String digits}) splitPhone(String? phone) {
  final p = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  if (p.startsWith('+')) {
    // Longest dial code first, so +880 isn't read as +88.
    final byLength = [...phoneCountries]..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    for (final c in byLength) {
      if (p.startsWith(c.dialCode)) return (country: c, digits: p.substring(c.dialCode.length));
    }
  }
  return (country: india, digits: p.replaceFirst('+', ''));
}
