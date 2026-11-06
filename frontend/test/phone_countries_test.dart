import 'package:campus_hub/core/utils/phone_countries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('India is the default and needs a 10-digit mobile number', () {
    expect(phoneCountries.first, india);
    expect(india.check(''), isNull); // optional
    expect(india.check('9876543210'), isNull);
    expect(india.check('987654321'), contains('10 digits'));
    expect(india.check('5876543210'), contains('start with 6, 7, 8 or 9'));
    expect(india.flag, '🇮🇳');
  });

  test('saved numbers are split into country and digits', () {
    expect(splitPhone('+919876543210'), (country: india, digits: '9876543210'));
    final bd = splitPhone('+8801712345678'); // +880, not +88 or +8
    expect(bd.country.name, 'Bangladesh');
    expect(bd.digits, '1712345678');
    expect(splitPhone('9876543210').country, india); // old numbers without a code
    expect(splitPhone(null).digits, '');
  });
}
