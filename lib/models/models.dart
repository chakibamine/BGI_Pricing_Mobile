import '../core/format.dart';

typedef Json = Map<String, dynamic>;

List<T> _list<T>(Object? raw, T Function(Json) parse) =>
    (raw as List? ?? const []).map((e) => parse(e as Json)).toList();

String _str(Object? v) => v?.toString() ?? '';

enum Product {
  gasoil('GASOIL', 'Gasoil'),
  ssp('SSP', 'SSP');

  const Product(this.code, this.label);
  final String code;
  final String label;

  static Product fromCode(String? code) =>
      Product.values.firstWhere((p) => p.code == code, orElse: () => gasoil);
}

class AuthUser {
  AuthUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.mustChangePassword,
  });

  factory AuthUser.fromJson(Json j) => AuthUser(
        id: j['id'] as int,
        username: _str(j['username']),
        email: _str(j['email']),
        role: _str(j['role']),
        mustChangePassword: j['mustChangePassword'] == true,
      );

  final int id;
  final String username;
  final String email;
  final String role;
  final bool mustChangePassword;

  bool get isAdmin => role == 'admin';

  AuthUser copyWith({bool? mustChangePassword}) => AuthUser(
        id: id,
        username: username,
        email: email,
        role: role,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      );
}

class QuinzaineRef {
  QuinzaineRef(this.label, this.year, this.month, this.period);

  static QuinzaineRef? fromJson(Object? raw) {
    if (raw is! Json) return null;
    return QuinzaineRef(
      _str(raw['label']),
      raw['year'] as int,
      raw['month'] as int,
      raw['period'] as int,
    );
  }

  final String label;
  final int year;
  final int month;
  final int period;
}

class LabelValue {
  LabelValue(this.label, this.value);
  final String label;
  final double? value;
}

class DatedValue {
  DatedValue(this.date, this.value);
  final String date;
  final double value;
}

class GridCell {
  GridCell({
    required this.year,
    required this.month,
    required this.period,
    required this.label,
    required this.status,
    required this.lastPriceTtc,
  });

  final int year;
  final int month;
  final int period;
  final String label;
  final String status;
  final double? lastPriceTtc;
}

class DashboardData {
  DashboardData({
    required this.activeQuinzaine,
    required this.displayQuinzaine,
    required this.usingFallback,
    required this.cifNweAverage,
    required this.cifQuotationsCount,
    required this.todayPriceTtc,
    required this.todayPriceDate,
    required this.windowStart,
    required this.windowEnd,
    required this.currentYear,
    required this.previousYear,
    required this.grid,
    required this.evolution,
    required this.rawQuotations,
  });

  factory DashboardData.fromJson(Json j) {
    final k = j['kpis'] as Json;
    final cif = k['cifNweAverage'] as Json?;
    final today = k['todayPriceTtc'] as Json?;
    final window = k['quotationWindow'] as Json?;
    final chart = j['yearComparisonChart'] as Json? ?? const {};
    LabelValue lv(Json e) => LabelValue(_str(e['label']), toDouble(e['value']));
    return DashboardData(
      activeQuinzaine: QuinzaineRef.fromJson(k['activeQuinzaine']),
      displayQuinzaine: QuinzaineRef.fromJson(k['displayQuinzaine']),
      usingFallback: k['usingFallback'] == true,
      cifNweAverage: toDouble(cif?['value']),
      cifQuotationsCount: (cif?['quotationsCount'] as int?) ?? 0,
      todayPriceTtc: toDouble(today?['value']),
      todayPriceDate: isoDay(today?['calculationDate']),
      windowStart: isoDay(window?['start']),
      windowEnd: isoDay(window?['end']),
      currentYear: _list(chart['currentYear'], lv),
      previousYear: _list(chart['previousYear'], lv),
      grid: _list(
        j['quinzaineGrid'],
        (e) => GridCell(
          year: e['year'] as int,
          month: e['month'] as int,
          period: e['period'] as int,
          label: _str(e['label']),
          status: _str(e['status']),
          lastPriceTtc: toDouble(e['lastPriceTtc']),
        ),
      ),
      evolution: _list(
        j['selectedQuinzaineEvolution'],
        (e) => DatedValue(isoDay(e['date'])!, toDoubleOr0(e['priceTtc'])),
      ),
      rawQuotations: _list(
        j['rawQuotations'],
        (e) => DatedValue(isoDay(e['date'])!, toDoubleOr0(e['value'])),
      ),
    );
  }

  final QuinzaineRef? activeQuinzaine;
  final QuinzaineRef? displayQuinzaine;
  final bool usingFallback;
  final double? cifNweAverage;
  final int cifQuotationsCount;
  final double? todayPriceTtc;
  final String? todayPriceDate;
  final String? windowStart;
  final String? windowEnd;
  final List<LabelValue> currentYear;
  final List<LabelValue> previousYear;
  final List<GridCell> grid;
  final List<DatedValue> evolution;
  final List<DatedValue> rawQuotations;
}

class Calculation {
  Calculation(this._j);

  final Json _j;

  int get configId => _j['configId'] as int? ?? 0;
  String get configName => _str(_j['configName']);
  bool get isDefaultConfig => _j['isDefaultConfig'] == true;
  String get calculationDate => isoDay(_j['calculationDate']) ?? '';
  double get cifNweAverage => toDoubleOr0(_j['cifNweAverage']);
  int get quotationsCount => _j['quotationsCount'] as int? ?? 0;
  double get exchangeRate => toDoubleOr0(_j['exchangeRate']);
  double get premium => toDoubleOr0(_j['premium']);
  double get tic => toDoubleOr0(_j['tic']);
  double get densityFactor => toDoubleOr0(_j['densityFactor']);
  double get diversFrais => toDoubleOr0(_j['diversFrais']);
  double get prixRepriseHt => toDoubleOr0(_j['prixRepriseHt']);
  double get tva => toDoubleOr0(_j['tva']);
  double get creditDroit => toDoubleOr0(_j['creditDroit']);
  double get creditDroitRate => toDoubleOr0(_j['creditDroitRate']);
  double get purchasePriceTtc => toDoubleOr0(_j['purchasePriceTtc']);
}

class ConfigRef {
  ConfigRef(this.id, this.name, this.isDefault);
  final int id;
  final String name;
  final bool isDefault;
}

class QuinzaineDetail {
  QuinzaineDetail({
    required this.windowStart,
    required this.windowEnd,
    required this.status,
    required this.frozen,
    required this.configs,
    required this.calculations,
  });

  factory QuinzaineDetail.fromJson(Json j) {
    final w = j['window'] as Json;
    return QuinzaineDetail(
      windowStart: isoDay(w['start'])!,
      windowEnd: isoDay(w['end'])!,
      status: _str(j['status']),
      frozen: j['frozen'] == true,
      configs: _list(
        j['configs'],
        (e) => ConfigRef(e['id'] as int, _str(e['name']), e['isDefault'] == true),
      ),
      calculations: _list(j['calculations'], Calculation.new),
    );
  }

  final String windowStart;
  final String windowEnd;
  final String status;
  final bool frozen;
  final List<ConfigRef> configs;
  final List<Calculation> calculations;
}

class ProductConfig {
  ProductConfig({
    required this.id,
    required this.name,
    required this.product,
    required this.premium,
    required this.tic,
    required this.densityFactor,
    required this.diversFrais,
    required this.creditDroitRate,
    required this.isActive,
    required this.isDefault,
    this.validFrom,
    this.validUntil,
    this.note,
  });

  factory ProductConfig.fromJson(Json j) => ProductConfig(
        id: j['id'] as int,
        name: _str(j['name']),
        product: Product.fromCode(j['product'] as String?),
        premium: toDoubleOr0(j['premium']),
        tic: toDoubleOr0(j['tic']),
        densityFactor: toDoubleOr0(j['densityFactor']),
        diversFrais: toDoubleOr0(j['diversFrais']),
        creditDroitRate: toDoubleOr0(j['creditDroitRate']),
        isActive: j['isActive'] == true,
        isDefault: j['isDefault'] == true,
        validFrom: isoDay(j['validFrom']),
        validUntil: isoDay(j['validUntil']),
        note: j['note'] as String?,
      );

  final int id;
  final String name;
  final Product product;
  final double premium;
  final double tic;
  final double densityFactor;
  final double diversFrais;
  final double creditDroitRate;
  final bool isActive;
  final bool isDefault;
  final String? validFrom;
  final String? validUntil;
  final String? note;
}

class QuinzaineAttachment {
  QuinzaineAttachment(this.id, this.configId);

  factory QuinzaineAttachment.fromJson(Json j) =>
      QuinzaineAttachment(j['id'] as int, j['configId'] as int);

  final int id;
  final int configId;
}

class Quotation {
  Quotation({
    required this.id,
    required this.quotationDate,
    required this.product,
    required this.cifNweValue,
    required this.originalValue,
    required this.correctionReason,
    required this.source,
    required this.status,
  });

  factory Quotation.fromJson(Json j) => Quotation(
        id: j['id'] as int,
        quotationDate: isoDay(j['quotationDate'])!,
        product: _str(j['product']),
        cifNweValue: toDouble(j['cifNweValue']),
        originalValue: toDouble(j['originalValue']),
        correctionReason: j['correctionReason'] as String?,
        source: _str(j['source']),
        status: _str(j['status']),
      );

  final int id;
  final String quotationDate;
  final String product;
  final double? cifNweValue;
  final double? originalValue;
  final String? correctionReason;
  final String source;
  final String status;
}

class CalendarDay {
  CalendarDay(this.date, this.status, this.cifNweValue);

  factory CalendarDay.fromJson(Json j) => CalendarDay(
        isoDay(j['date'])!,
        _str(j['status']),
        toDouble(j['cifNweValue']),
      );

  final String date;
  final String status;
  final double? cifNweValue;
}

class ExchangeRate {
  ExchangeRate(this.id, this.rateDate, this.usdMadRate, this.source);

  factory ExchangeRate.fromJson(Json j) => ExchangeRate(
        j['id'] as int,
        isoDay(j['rateDate'])!,
        toDoubleOr0(j['usdMadRate']),
        _str(j['source']),
      );

  final int id;
  final String rateDate;
  final double usdMadRate;
  final String source;
}

class ImportReport {
  ImportReport(this.inserted, this.updated, this.skipped, this.errors);

  factory ImportReport.fromJson(Json j) => ImportReport(
        j['inserted'] as int? ?? 0,
        j['updated'] as int? ?? 0,
        j['skipped'] as int? ?? 0,
        _list(j['errors'], (e) => 'Ligne ${e['row']} : ${e['reason']}'),
      );

  final int inserted;
  final int updated;
  final int skipped;
  final List<String> errors;
}

class BkamPreviewRow {
  BkamPreviewRow(this.date, this.rate, this.status, this.message,
      this.existingRate);

  factory BkamPreviewRow.fromJson(Json j) => BkamPreviewRow(
        isoDay(j['date'])!,
        toDouble(j['rate']),
        _str(j['status']),
        j['message'] as String?,
        toDouble(j['existingRate']),
      );

  final String date;
  final double? rate;
  final String status;
  final String? message;
  final double? existingRate;

  bool get selectable => status == 'ok' && rate != null;

  /// new | changed | same | no_data | error
  String get kind {
    if (status == 'error') return 'error';
    if (status == 'no_data' || rate == null) return 'no_data';
    if (existingRate == null) return 'new';
    return (existingRate! - rate!).abs() < 1e-9 ? 'same' : 'changed';
  }
}

class AuditLog {
  AuditLog(this._j);

  final Json _j;

  String get id => _str(_j['id']);
  String get action => _str(_j['action']);
  String get tableName => _str(_j['tableName']);
  String? get recordId => _j['recordId']?.toString();
  /// JSON string or already-decoded value.
  Object? get dataBefore => _j['dataBefore'];
  Object? get dataAfter => _j['dataAfter'];
  String? get description => _j['description'] as String?;
  String get createdAt => _str(_j['createdAt']);
  String get username =>
      ((_j['user'] as Json?)?['username'] as String?) ?? 'Système';
}

class UserRow {
  UserRow(this._j);

  final Json _j;

  int get id => _j['id'] as int;
  String get username => _str(_j['username']);
  String get email => _str(_j['email']);
  String get role => _str(_j['role']);
  bool get isActive => _j['isActive'] == true;
  bool get receivesDailyEmail => _j['receivesDailyEmail'] == true;
  String? get lastLoginAt => _j['lastLoginAt'] as String?;
  String? get temporaryPassword => _j['temporaryPassword'] as String?;
}
