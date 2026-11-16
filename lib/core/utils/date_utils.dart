/// Due dates are plain calendar dates stored as "yyyy-MM-dd" strings, and
/// recurring periods are "yyyy-MM". Strings in these formats sort correctly.
class Dates {
  Dates._();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String today() => ymd(DateTime.now());

  static String period(DateTime d) => ymd(d).substring(0, 7);

  static DateTime parse(String ymd) {
    final p = ymd.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p.length > 2 ? p[2] : 1);
  }

  /// "2026-12-05" -> "5 Dec" (with the year when it is not this year)
  static String short(String ymd) {
    final d = parse(ymd);
    final base = '${d.day} ${_months[d.month - 1]}';
    return d.year == DateTime.now().year ? base : '$base ${d.year}';
  }

  /// "2026-12" -> "Dec 2026"
  static String periodLabel(String period) {
    final d = parse(period);
    return '${_months[d.month - 1]} ${d.year}';
  }

  /// "Rent" + "2026-12" -> "Rent · Dec 2026"
  static String splitLabel(String title, String? periodKey) =>
      periodKey == null ? title : '$title · ${periodLabel(periodKey)}';

  static bool isOverdue(String? dueDate) => dueDate != null && dueDate.compareTo(today()) < 0;

  static int lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// The date a monthly rule runs in [period]. dayOfMonth is 1–28, or -1 for the last day.
  static DateTime runDate(String period, int dayOfMonth) {
    final d = parse(period);
    return DateTime(d.year, d.month, dayOfMonth == -1 ? lastDayOfMonth(d.year, d.month) : dayOfMonth);
  }

  static String nextPeriod(String period) {
    final d = parse(period);
    return Dates.period(DateTime(d.year, d.month + 1, 1));
  }

  static String ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }

  /// "just now", "5 min ago", "3 h ago", "yesterday", "5 Dec"
  static String ago(DateTime? t) {
    if (t == null) return 'just now';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return short(ymd(t));
  }
}
