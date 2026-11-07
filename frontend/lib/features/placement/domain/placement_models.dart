/// Placement Hub read models: companies, JDs, pre-placement talks, hiring statistics,
/// interview experiences and the imports. Company forums live in features/forums.
library;

int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
String? _str(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
List<Map<String, dynamic>> _list(dynamic v) => (v as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

class Company {
  final String id;
  final String name;
  final String? industry;
  final String? description;
  final String? website;
  final int roleCount;
  final int interviewCount;
  final DateTime? nextPptAt;

  /// The next date of any kind on its schedule (talk, online test, interviews).
  final DateTime? nextDateAt;
  final PptKind? nextDateKind;
  final int? latestYear;
  final int latestYearSelected;
  final int totalSelected;

  /// Full-time compensation in the latest season that has it: lowest and highest, rupees a year.
  final int? ctcYear;
  final int? ctcMin;
  final int? ctcMax;

  /// Only on the company page (GET /companies/{id}).
  final List<JobDescription> jobDescriptions;
  final List<Ppt> ppts;
  final bool viewerCanManage;

  const Company({
    required this.id,
    required this.name,
    this.industry,
    this.description,
    this.website,
    this.roleCount = 0,
    this.interviewCount = 0,
    this.nextPptAt,
    this.nextDateAt,
    this.nextDateKind,
    this.latestYear,
    this.latestYearSelected = 0,
    this.totalSelected = 0,
    this.ctcYear,
    this.ctcMin,
    this.ctcMax,
    this.jobDescriptions = const [],
    this.ppts = const [],
    this.viewerCanManage = false,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: '${json['id']}',
        name: json['name']?.toString() ?? '',
        industry: _str(json['industry']),
        description: _str(json['description']),
        website: _str(json['website']),
        roleCount: _int(json['role_count']),
        interviewCount: _int(json['interview_count']),
        nextPptAt: _date(json['next_ppt_at']),
        nextDateAt: _date(json['next_date_at']),
        nextDateKind: json['next_date_kind'] == null ? null : PptKind.parse(json['next_date_kind']),
        latestYear: _intOrNull(json['latest_year']),
        latestYearSelected: _int(json['latest_year_selected']),
        totalSelected: _int(json['total_selected']),
        ctcYear: _intOrNull(json['ctc_year']),
        ctcMin: _intOrNull(json['ctc_min']),
        ctcMax: _intOrNull(json['ctc_max']),
        jobDescriptions: _list(json['job_descriptions']).map(JobDescription.fromJson).toList(),
        ppts: _list(json['ppts']).map(Ppt.fromJson).toList(),
        viewerCanManage: json['viewer_can_manage'] == true,
      );

  /// Two-letter badge for the company logo placeholder.
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, words.first.length.clamp(1, 2)).toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}

class JobDescription {
  final String id;
  final String companyId;
  final String roleTitle;
  final String? description;
  /// As announced ("₹32 LPA", "Refer JD"); [ctcMin]/[ctcMax] are the amount read from it, rupees a year.
  final String? compensation;
  final int? ctcMin;
  final int? ctcMax;
  final String? base;
  final int? baseAnnual;

  /// The season the role was offered in, e.g. 2026 for 2025-26.
  final int? placementYear;

  /// full_time, internship, ppo or other.
  final String jobType;
  final String? skills;
  final String? fileS3Key;
  final String? fileUrl;

  const JobDescription({
    required this.id,
    required this.companyId,
    required this.roleTitle,
    this.description,
    this.compensation,
    this.ctcMin,
    this.ctcMax,
    this.base,
    this.baseAnnual,
    this.placementYear,
    this.jobType = 'full_time',
    this.skills,
    this.fileS3Key,
    this.fileUrl,
  });

  static const jobTypeLabels = {'full_time': 'Full time', 'internship': 'Internship', 'ppo': 'PPO', 'other': 'Other'};

  String get jobTypeLabel => jobTypeLabels[jobType] ?? jobType;

  factory JobDescription.fromJson(Map<String, dynamic> json) => JobDescription(
        id: '${json['id']}',
        companyId: '${json['company_id']}',
        roleTitle: json['role_title']?.toString() ?? '',
        description: _str(json['description']),
        compensation: _str(json['compensation']),
        ctcMin: _intOrNull(json['ctc_min']),
        ctcMax: _intOrNull(json['ctc_max']),
        base: _str(json['base']),
        baseAnnual: _intOrNull(json['base_annual']),
        placementYear: _intOrNull(json['placement_year']),
        jobType: json['job_type']?.toString() ?? 'full_time',
        skills: _str(json['skills']),
        fileS3Key: _str(json['file_s3_key']),
        fileUrl: _str(json['file_url']),
      );
}

enum PptWhen { upcoming, past, unscheduled }

/// What a date on the placement schedule is.
enum PptKind {
  ppt('Pre-placement talk', 'PPT'),
  oa('Online test', 'OA'),
  interview('Interviews', 'Interview'),
  other('Other', 'Date');

  final String label;
  final String short;

  const PptKind(this.label, this.short);

  static PptKind parse(dynamic v) => PptKind.values.firstWhere((k) => k.name == v, orElse: () => PptKind.ppt);
}

class Ppt {
  final String id;
  final String companyId;
  final String companyName;
  final PptKind kind;
  final String? details;
  final String? venue;
  final DateTime? scheduledAt;

  /// Only the day is known (imported without a time).
  final bool timeTbd;
  final PptWhen when;

  const Ppt({
    required this.id,
    required this.companyId,
    required this.companyName,
    this.kind = PptKind.ppt,
    this.details,
    this.venue,
    this.scheduledAt,
    this.timeTbd = false,
    this.when = PptWhen.unscheduled,
  });

  factory Ppt.fromJson(Map<String, dynamic> json) => Ppt(
        id: '${json['id']}',
        companyId: '${json['company_id']}',
        companyName: json['company_name']?.toString() ?? '',
        kind: PptKind.parse(json['kind']),
        details: _str(json['details']),
        venue: _str(json['venue']),
        scheduledAt: _date(json['scheduled_at']),
        timeTbd: json['time_tbd'] == true,
        when: PptWhen.values.firstWhere((w) => w.name == json['when'], orElse: () => PptWhen.unscheduled),
      );
}

class RoleCount {
  final String roleTitle;
  final int studentsSelected;

  const RoleCount(this.roleTitle, this.studentsSelected);

  factory RoleCount.fromJson(Map<String, dynamic> json) =>
      RoleCount(json['role_title']?.toString() ?? '', _int(json['students_selected']));
}

class YearStats {
  final int year;
  final int studentsSelected;
  final List<RoleCount> roles;

  const YearStats({required this.year, required this.studentsSelected, this.roles = const []});

  factory YearStats.fromJson(Map<String, dynamic> json) => YearStats(
        year: _int(json['year']),
        studentsSelected: _int(json['students_selected']),
        roles: _list(json['roles']).map(RoleCount.fromJson).toList(),
      );
}

class HiringStats {
  final String companyId;
  final int totalSelected;

  /// Newest year first; empty when no imported sheet mentions the company.
  final List<YearStats> years;

  const HiringStats({required this.companyId, this.totalSelected = 0, this.years = const []});

  factory HiringStats.fromJson(Map<String, dynamic> json) => HiringStats(
        companyId: '${json['company_id']}',
        totalSelected: _int(json['total_selected']),
        years: _list(json['years']).map(YearStats.fromJson).toList(),
      );
}

class SeasonStats {
  final int year;
  final int studentsSelected;
  final int companies;

  const SeasonStats({required this.year, required this.studentsSelected, required this.companies});

  factory SeasonStats.fromJson(Map<String, dynamic> json) => SeasonStats(
        year: _int(json['year']),
        studentsSelected: _int(json['students_selected']),
        companies: _int(json['companies']),
      );
}

class TopCompany {
  final String companyId;
  final String companyName;
  final int studentsSelected;
  final int? ctcMin;
  final int? ctcMax;

  const TopCompany(
      {required this.companyId, required this.companyName, required this.studentsSelected, this.ctcMin, this.ctcMax});

  factory TopCompany.fromJson(Map<String, dynamic> json) => TopCompany(
        companyId: '${json['company_id']}',
        companyName: json['company_name']?.toString() ?? '',
        studentsSelected: _int(json['students_selected']),
        ctcMin: _intOrNull(json['ctc_min']),
        ctcMax: _intOrNull(json['ctc_max']),
      );
}

/// A company's full-time compensation in a season (Statistics: highest packages).
class CompanyPay {
  final String companyId;
  final String companyName;
  final int ctcMin;
  final int ctcMax;
  final int roles;

  const CompanyPay(
      {required this.companyId, required this.companyName, required this.ctcMin, required this.ctcMax, this.roles = 1});

  factory CompanyPay.fromJson(Map<String, dynamic> json) => CompanyPay(
        companyId: '${json['company_id']}',
        companyName: json['company_name']?.toString() ?? '',
        ctcMin: _int(json['ctc_min']),
        ctcMax: _int(json['ctc_max']),
        roles: _int(json['roles']),
      );
}

/// "₹48 LPA", "₹12–15 LPA", "₹9.6 LPA" from rupees a year.
String formatCtc(int? min, int? max) {
  if (min == null && max == null) return '';
  String lpa(int v) {
    final l = v / 100000;
    if (l >= 100) return '${(l / 100).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')} Cr';
    // Up to two decimals, trailing zeros dropped: 48, 9.6, 15.05.
    return l.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }
  final lo = min ?? max!, hi = max ?? min!;
  String one(int v) => v >= 10000000 ? '₹${lpa(v)}' : '₹${lpa(v)} LPA';
  if (lo == hi) return one(lo);
  // Same unit on both ends shares it ("₹12–15 LPA"); a range across ₹1 Cr names both ("₹20 LPA–₹1 Cr").
  if (hi < 10000000) return '₹${lpa(lo)}–${lpa(hi)} LPA';
  if (lo >= 10000000) return '₹${lpa(lo)}–${lpa(hi)}';
  return '${one(lo)}–${one(hi)}';
}

class PlacementOverview {
  /// Newest first.
  final List<SeasonStats> seasons;

  /// The season [topCompanies] is for.
  final int? year;
  final List<TopCompany> topCompanies;

  /// The latest season with compensation data, and its best-paying companies (full-time roles).
  final int? payYear;
  final List<CompanyPay> topPaying;

  const PlacementOverview(
      {this.seasons = const [], this.year, this.topCompanies = const [], this.payYear, this.topPaying = const []});

  factory PlacementOverview.fromJson(Map<String, dynamic> json) => PlacementOverview(
        seasons: _list(json['seasons']).map(SeasonStats.fromJson).toList(),
        year: _intOrNull(json['year']),
        topCompanies: _list(json['top_companies']).map(TopCompany.fromJson).toList(),
        payYear: _intOrNull(json['pay_year']),
        topPaying: _list(json['top_paying']).map(CompanyPay.fromJson).toList(),
      );
}

class InterviewExperience {
  final String id;
  final String companyId;
  final String companyName;
  final String? roleTitle;
  final int? placementYear;
  final String content;
  final bool isAnonymous;
  final bool isMine;

  /// null for anonymous posts (except to their author) and for guests.
  final String? authorName;
  final DateTime createdAt;

  const InterviewExperience({
    required this.id,
    required this.companyId,
    required this.companyName,
    this.roleTitle,
    this.placementYear,
    required this.content,
    this.isAnonymous = false,
    this.isMine = false,
    this.authorName,
    required this.createdAt,
  });

  factory InterviewExperience.fromJson(Map<String, dynamic> json) => InterviewExperience(
        id: '${json['id']}',
        companyId: '${json['company_id']}',
        companyName: json['company_name']?.toString() ?? '',
        roleTitle: _str(json['role_title']),
        placementYear: _intOrNull(json['placement_year']),
        content: json['content']?.toString() ?? '',
        isAnonymous: json['is_anonymous'] == true,
        isMine: json['is_mine'] == true,
        authorName: (json['author'] as Map?)?['name']?.toString(),
        createdAt: _date(json['created_at']) ?? DateTime.now(),
      );

  String get displayAuthor => isAnonymous && !isMine ? 'Anonymous student' : (authorName ?? 'A student');
}

class RejectedSheetRow {
  final int line;
  final String reason;

  const RejectedSheetRow(this.line, this.reason);
}

class ImportResult {
  final int placementYear;
  final int rowsTotal;
  final int rowsCreated;
  final int rowsUpdated;
  final int rowsRejected;
  final List<String> companiesCreated;
  final List<RejectedSheetRow> rejectedRows;

  /// Companies in this sheet that are probably the same as another one, for the moderator to review.
  final List<SimilarCompanyGroup> similarCompanies;

  const ImportResult({
    required this.placementYear,
    required this.rowsTotal,
    required this.rowsCreated,
    required this.rowsUpdated,
    required this.rowsRejected,
    this.companiesCreated = const [],
    this.rejectedRows = const [],
    this.similarCompanies = const [],
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) => ImportResult(
        placementYear: _int(json['placement_year']),
        rowsTotal: _int(json['rows_total']),
        rowsCreated: _int(json['rows_created']),
        rowsUpdated: _int(json['rows_updated']),
        rowsRejected: _int(json['rows_rejected']),
        companiesCreated: (json['companies_created'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
        rejectedRows: _list(json['rejected_rows'])
            .map((r) => RejectedSheetRow(_int(r['line']), r['reason']?.toString() ?? ''))
            .toList(),
        similarCompanies: _list(json['similar_companies']).map(SimilarCompanyGroup.fromJson).toList(),
      );
}

/// One company in a [SimilarCompanyGroup], with how many placement records it has.
class SimilarCompany {
  final String id;
  final String name;
  final int records;

  const SimilarCompany({required this.id, required this.name, required this.records});

  factory SimilarCompany.fromJson(Map<String, dynamic> j) =>
      SimilarCompany(id: '${j['id']}', name: j['name']?.toString() ?? '', records: _int(j['records']));
}

/// Companies that are probably one company under different names ("Accenture", "Accenture [Mock
/// Assessment]"), with a clean name to merge them under.
class SimilarCompanyGroup {
  final String suggestedName;
  final List<SimilarCompany> companies;

  const SimilarCompanyGroup({required this.suggestedName, required this.companies});

  factory SimilarCompanyGroup.fromJson(Map<String, dynamic> j) => SimilarCompanyGroup(
        suggestedName: j['suggested_name']?.toString() ?? '',
        companies: _list(j['companies']).map(SimilarCompany.fromJson).toList(),
      );
}

// ---------------------------------------------------------------- CSV imports
/// Result of importing a company list or a placement schedule.
class CsvImportResult {
  final int rowsTotal;
  final int rowsCreated;
  final int rowsUpdated;
  final int rowsRejected;
  final List<String> companiesCreated;
  final List<RejectedSheetRow> rejectedRows;

  /// Schedule imports: rows saved per type ("interview": 7), and how many of the dates have passed.
  final Map<PptKind, int> kinds;
  final int pastRows;

  /// Companies in the file that are probably the same as another company, for review (like a sheet import).
  final List<SimilarCompanyGroup> similarCompanies;

  const CsvImportResult({
    this.kinds = const {},
    this.pastRows = 0,
    required this.rowsTotal,
    required this.rowsCreated,
    required this.rowsUpdated,
    required this.rowsRejected,
    this.companiesCreated = const [],
    this.rejectedRows = const [],
    this.similarCompanies = const [],
  });

  factory CsvImportResult.fromJson(Map<String, dynamic> json) => CsvImportResult(
        similarCompanies: _list(json['similar_companies']).map(SimilarCompanyGroup.fromJson).toList(),
        rowsTotal: _int(json['rows_total']),
        kinds: {
          for (final e in ((json['kinds'] as Map?) ?? const {}).entries) PptKind.parse(e.key): _int(e.value),
        },
        pastRows: _int(json['past_rows']),
        rowsCreated: _int(json['rows_created']),
        rowsUpdated: _int(json['rows_updated']),
        rowsRejected: _int(json['rows_rejected']),
        companiesCreated: (json['companies_created'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
        rejectedRows: _list(json['rejected_rows'])
            .map((r) => RejectedSheetRow(_int(r['line']), r['reason']?.toString() ?? ''))
            .toList(),
      );
}
