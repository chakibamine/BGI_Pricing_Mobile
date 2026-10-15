import 'format.dart';

const monthShortLabels = [
  'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', //
  'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc',
];

const monthLabels = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', //
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];

const quinzaineStatusLabels = {
  'en_cours': 'En cours',
  'cloturee': 'Clôturée',
  'a_venir': 'À venir',
};

class QuinzaineInfo {
  const QuinzaineInfo({
    required this.key,
    required this.label,
    required this.start,
    required this.end,
  });

  final String key;
  final String label;
  final String start;
  final String end;

  String get windowLabel => '${formatDate(start)} → ${formatDate(end)}';
}

String _iso(int y, int m, int d) => isoDate(DateTime.utc(y, m, d));

/// Same windows as the server: Q1 of M = 13→27 of M-1, Q2 of M = 28 of M-1 → 12 of M.
QuinzaineInfo quinzaineOf(String dateIso) {
  final p = dateIso.substring(0, 10).split('-').map(int.parse).toList();
  var year = p[0];
  var month = p[1];
  final day = p[2];
  int period;
  if (day <= 12) {
    period = 2;
  } else {
    period = day <= 27 ? 1 : 2;
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  final prevYear = month == 1 ? year - 1 : year;
  final prevMonth = month == 1 ? 12 : month - 1;
  final start = period == 1
      ? _iso(prevYear, prevMonth, 13)
      : _iso(prevYear, prevMonth, 28);
  final end = period == 1 ? _iso(prevYear, prevMonth, 27) : _iso(year, month, 12);
  return QuinzaineInfo(
    key: '$year-${month.toString().padLeft(2, '0')}-Q$period',
    label: 'Q$period ${monthShortLabels[month - 1]} $year',
    start: start,
    end: end,
  );
}

sealed class GroupedRow<T> {
  const GroupedRow();
}

class GroupHeader<T> extends GroupedRow<T> {
  const GroupHeader(this.quinzaine);
  final QuinzaineInfo quinzaine;
}

class GroupItem<T> extends GroupedRow<T> {
  const GroupItem(this.row);
  final T row;
}

/// Insert a quinzaine header before each change of quinzaine (rows must be sorted by date).
List<GroupedRow<T>> withQuinzaineHeaders<T>(
  List<T> rows,
  String Function(T row) getDate,
) {
  final out = <GroupedRow<T>>[];
  var currentKey = '';
  for (final row in rows) {
    final q = quinzaineOf(getDate(row));
    if (q.key != currentKey) {
      out.add(GroupHeader<T>(q));
      currentKey = q.key;
    }
    out.add(GroupItem<T>(row));
  }
  return out;
}
