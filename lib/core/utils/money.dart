/// Money is always an integer number of minor units (1 QAR = 100 dirhams),
/// never a double, so shares add up to the total exactly.
class Money {
  Money._();

  /// Supported currencies and the number of decimals of their minor unit.
  /// Must match CURRENCIES in functions/src/config.ts.
  static const Map<String, int> currencies = {
    'QAR': 2, 'AED': 2, 'SAR': 2, 'KWD': 3, 'BHD': 3, 'OMR': 3,
    'USD': 2, 'EUR': 2, 'GBP': 2, 'INR': 2, 'PKR': 2, 'BDT': 2,
    'LKR': 2, 'NPR': 2, 'PHP': 2, 'EGP': 2, 'JPY': 0,
  };

  /// 100,000,000.00 in a 2-decimal currency. Matches MAX_TOTAL_MINOR on the server.
  static const int maxTotalMinor = 10000000000;

  static int decimals(String currency) => currencies[currency] ?? 2;

  static int _scale(String currency) {
    var s = 1;
    for (var i = 0; i < decimals(currency); i++) {
      s *= 10;
    }
    return s;
  }

  /// 120000, QAR -> "1,200" ; 3334, QAR -> "33.34"
  static String number(int minor, String currency) {
    final d = decimals(currency);
    final scale = _scale(currency);
    final abs = minor.abs();
    final whole = (abs ~/ scale).toString();
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    final frac = abs % scale;
    final fracStr = (frac == 0 || d == 0) ? '' : '.${frac.toString().padLeft(d, '0')}';
    return '${minor < 0 ? '-' : ''}$grouped$fracStr';
  }

  /// 120000, QAR -> "1,200 QAR"
  static String format(int minor, String currency) => '${number(minor, currency)} $currency';

  /// What to put in a text field when editing: 3334 -> "33.34", 120000 -> "1200"
  static String editable(int minor, String currency) => number(minor, currency).replaceAll(',', '');

  /// Parses what a user typed ("1,200", "33.34") into minor units.
  /// Returns null if it is not a valid non-negative amount for the currency.
  static int? parse(String input, String currency) {
    final text = input.trim().replaceAll(',', '').replaceAll(' ', '');
    if (text.isEmpty) return null;
    final d = decimals(currency);
    final match = RegExp(r'^(\d{0,12})(?:\.(\d*))?$').firstMatch(text);
    if (match == null) return null;
    final whole = match.group(1) ?? '';
    final frac = match.group(2) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    if (frac.length > d) return null;
    final minor = int.parse(whole.isEmpty ? '0' : whole) * _scale(currency) +
        (frac.isEmpty ? 0 : int.parse(frac.padRight(d, '0')));
    if (minor > maxTotalMinor) return null;
    return minor;
  }
}
