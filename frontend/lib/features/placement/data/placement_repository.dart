import 'dart:convert';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/placement_models.dart';

/// Placement Hub: company pages, JDs, PPTs, hiring statistics, interview experiences, the company
/// forum, and (moderators) the placement sheet import.
abstract class IPlacementRepository {
  /// [sort] is `name`, `most_hired` or `upcoming_ppt`.
  Future<List<Company>> fetchCompanies({String? query, String sort = 'name', int limit = 50});

  Future<Company> getCompany(String companyId);

  Future<HiringStats> fetchHiringStats(String companyId);

  Future<PlacementOverview> fetchOverview();

  Future<List<Ppt>> fetchUpcomingPpts({int limit = 10});

  /// Newest first. [companyId] null = across all companies.
  Future<List<InterviewExperience>> fetchInterviews({String? companyId, String? query, int limit = 30});

  Future<InterviewExperience> postInterview(String companyId,
      {required String roleTitle, int? placementYear, required String content, bool anonymous = false});

  Future<InterviewExperience> updateInterview(String interviewId,
      {String? roleTitle, int? placementYear, String? content, bool? anonymous});

  Future<void> deleteInterview(String interviewId);

  // Moderators
  Future<Company> saveCompany({String? companyId, required String name, String? industry, String? website,
      String? description});

  Future<void> deleteCompany(String companyId);

  /// [removeFile] drops a JD file attached through the API (the app edits JDs as text).
  Future<void> saveJobDescription({String? jdId, required String companyId, required String roleTitle,
      String? description, String? compensation, bool removeFile = false});

  Future<void> deleteJobDescription(String jdId);

  Future<void> savePpt({String? pptId, required String companyId, String? details, String? venue, DateTime? scheduledAt});

  Future<void> deletePpt(String pptId);

  Future<ImportResult> importSheet(int placementYear, String sheet);

  // Company forum
  Future<String> companyForumId(String companyId);

  Future<List<ForumThread>> fetchThreads(String forumId);

  Future<ForumThread> getThread(String threadId);

  Future<ForumThread> createThread(String forumId, String title, String content);

  Future<void> reply(String threadId, String content);

  Future<void> deleteThread(String threadId);

  Future<void> deleteComment(String commentId);
}

List<Map<String, dynamic>> _items(dynamic data) =>
    ((data as Map<String, dynamic>)['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

class ApiPlacementRepository implements IPlacementRepository {
  final ApiClient apiClient;

  ApiPlacementRepository(this.apiClient);

  @override
  Future<List<Company>> fetchCompanies({String? query, String sort = 'name', int limit = 50}) async {
    final response = await apiClient.get(ApiEndpoints.companies, queryParameters: {
      if (_blankToNull(query) != null) 'q': query!.trim(),
      'sort': sort,
      'limit': limit,
    });
    return _items(response.data).map(Company.fromJson).toList();
  }

  @override
  Future<Company> getCompany(String companyId) async {
    final response = await apiClient.get(ApiEndpoints.company(companyId));
    return Company.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<HiringStats> fetchHiringStats(String companyId) async {
    final response = await apiClient.get(ApiEndpoints.companyHiringStats(companyId));
    return HiringStats.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<PlacementOverview> fetchOverview() async {
    final response = await apiClient.get(ApiEndpoints.placementStats);
    return PlacementOverview.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<Ppt>> fetchUpcomingPpts({int limit = 10}) async {
    final response = await apiClient.get(ApiEndpoints.placementPpts, queryParameters: {'when': 'upcoming', 'limit': limit});
    return _items(response.data).map(Ppt.fromJson).toList();
  }

  @override
  Future<List<InterviewExperience>> fetchInterviews({String? companyId, String? query, int limit = 30}) async {
    final response = await apiClient.get(ApiEndpoints.interviews, queryParameters: {
      if (companyId != null) 'company_id': companyId,
      if (_blankToNull(query) != null) 'q': query!.trim(),
      'limit': limit,
    });
    return _items(response.data).map(InterviewExperience.fromJson).toList();
  }

  @override
  Future<InterviewExperience> postInterview(String companyId,
      {required String roleTitle, int? placementYear, required String content, bool anonymous = false}) async {
    final response = await apiClient.post(ApiEndpoints.companyInterviews(companyId), data: {
      'role_title': roleTitle,
      'placement_year': placementYear,
      'content': content,
      'is_anonymous': anonymous,
    });
    return InterviewExperience.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<InterviewExperience> updateInterview(String interviewId,
      {String? roleTitle, int? placementYear, String? content, bool? anonymous}) async {
    final response = await apiClient.patch(ApiEndpoints.interview(interviewId), data: {
      if (roleTitle != null) 'role_title': roleTitle,
      'placement_year': placementYear,
      if (content != null) 'content': content,
      if (anonymous != null) 'is_anonymous': anonymous,
    });
    return InterviewExperience.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteInterview(String interviewId) async {
    await apiClient.delete(ApiEndpoints.interview(interviewId));
  }

  @override
  Future<Company> saveCompany({String? companyId, required String name, String? industry, String? website,
      String? description}) async {
    final body = {
      'name': name,
      'industry': _blankToNull(industry),
      'website': _blankToNull(website),
      'description': _blankToNull(description),
    };
    final response = companyId == null
        ? await apiClient.post(ApiEndpoints.companies, data: body)
        : await apiClient.patch(ApiEndpoints.company(companyId), data: body);
    return Company.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteCompany(String companyId) async {
    await apiClient.delete(ApiEndpoints.company(companyId));
  }

  @override
  Future<void> saveJobDescription({String? jdId, required String companyId, required String roleTitle,
      String? description, String? compensation, bool removeFile = false}) async {
    final body = {
      'role_title': roleTitle,
      'description': _blankToNull(description),
      'compensation': _blankToNull(compensation),
      if (removeFile) 'file_s3_key': null,
    };
    if (jdId == null) {
      await apiClient.post(ApiEndpoints.companyJds(companyId), data: body);
    } else {
      await apiClient.patch(ApiEndpoints.jd(jdId), data: body);
    }
  }

  @override
  Future<void> deleteJobDescription(String jdId) async {
    await apiClient.delete(ApiEndpoints.jd(jdId));
  }

  @override
  Future<void> savePpt({String? pptId, required String companyId, String? details, String? venue,
      DateTime? scheduledAt}) async {
    final body = {
      'details': _blankToNull(details),
      'venue': _blankToNull(venue),
      'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
    };
    if (pptId == null) {
      await apiClient.post(ApiEndpoints.companyPpts(companyId), data: body);
    } else {
      await apiClient.patch(ApiEndpoints.ppt(pptId), data: body);
    }
  }

  @override
  Future<void> deletePpt(String pptId) async {
    await apiClient.delete(ApiEndpoints.ppt(pptId));
  }

  @override
  Future<ImportResult> importSheet(int placementYear, String sheet) async {
    final response = await apiClient.post(ApiEndpoints.placementImports,
        data: {'placement_year': placementYear, 'sheet': sheet});
    return ImportResult.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<String> companyForumId(String companyId) async {
    final response = await apiClient.get(ApiEndpoints.companyForum(companyId));
    return '${(response.data as Map<String, dynamic>)['id']}';
  }

  @override
  Future<List<ForumThread>> fetchThreads(String forumId) async {
    final response = await apiClient.get(ApiEndpoints.forumThreads(forumId), queryParameters: {'limit': 50});
    return _items(response.data).map(ForumThread.fromJson).toList();
  }

  @override
  Future<ForumThread> getThread(String threadId) async {
    final response = await apiClient.get(ApiEndpoints.thread(threadId));
    return ForumThread.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<ForumThread> createThread(String forumId, String title, String content) async {
    final response =
        await apiClient.post(ApiEndpoints.forumThreads(forumId), data: {'title': title, 'content': content});
    return ForumThread.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> reply(String threadId, String content) async {
    await apiClient.post(ApiEndpoints.threadComments(threadId), data: {'content': content});
  }

  @override
  Future<void> deleteThread(String threadId) async {
    await apiClient.delete(ApiEndpoints.thread(threadId));
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await apiClient.delete(ApiEndpoints.comment(commentId));
  }
}

/// In-memory version for mock mode: a few companies with three seasons of statistics.
class MockPlacementRepository implements IPlacementRepository {
  static final _companies = <Company>[
    Company(id: 'co_google', name: 'Google', industry: 'Software', description: 'Search, cloud and AI products.',
        website: 'https://careers.google.com', roleCount: 1, interviewCount: 1,
        nextPptAt: DateTime.now().add(const Duration(days: 4)), latestYear: 2026, latestYearSelected: 6,
        totalSelected: 15),
    const Company(id: 'co_gs', name: 'Goldman Sachs', industry: 'Finance',
        description: 'Investment banking and securities.', latestYear: 2026, latestYearSelected: 4, totalSelected: 9),
    const Company(id: 'co_nvidia', name: 'NVIDIA', industry: 'Semiconductors',
        description: 'GPUs and accelerated computing.', latestYear: 2025, latestYearSelected: 3, totalSelected: 5),
  ];

  static final _jds = <JobDescription>[
    const JobDescription(id: 'jd_1', companyId: 'co_google', roleTitle: 'Software Engineer',
        description: 'Build large-scale backend systems.', compensation: '₹38 LPA'),
  ];

  static final _ppts = <Ppt>[
    Ppt(id: 'ppt_1', companyId: 'co_google', companyName: 'Google', details: 'Roles, process and Q&A.',
        venue: 'Faculty Hall', scheduledAt: DateTime.now().add(const Duration(days: 4)), when: PptWhen.upcoming),
  ];

  static final _interviews = <InterviewExperience>[
    InterviewExperience(id: 'iv_1', companyId: 'co_google', companyName: 'Google', roleTitle: 'Software Engineer',
        placementYear: 2025, authorName: 'Ananya Rao',
        content: 'Round 1: two DSA questions (LRU cache, merge intervals).\nRound 2: system design of a URL shortener.\n'
            'Tip: practise explaining trade-offs out loud.',
        createdAt: DateTime(2025, 12, 10)),
  ];

  static final _threads = <ForumThread>[];

  static const _stats = {
    'co_google': [
      YearStats(year: 2026, studentsSelected: 6, roles: [RoleCount('Software Engineer', 4), RoleCount('Research Engineer', 2)]),
      YearStats(year: 2025, studentsSelected: 5, roles: [RoleCount('Software Engineer', 5)]),
      YearStats(year: 2024, studentsSelected: 4, roles: [RoleCount('Software Engineer', 3), RoleCount('Research Engineer', 1)]),
    ],
    'co_gs': [
      YearStats(year: 2026, studentsSelected: 4, roles: [RoleCount('Quant Strategist', 4)]),
      YearStats(year: 2025, studentsSelected: 5, roles: [RoleCount('Analyst', 5)]),
    ],
    'co_nvidia': [
      YearStats(year: 2025, studentsSelected: 3, roles: [RoleCount('Deep Learning Engineer', 3)]),
      YearStats(year: 2024, studentsSelected: 2, roles: [RoleCount('GPU Architect', 2)]),
    ],
  };

  Company _withDetails(Company c) => Company(
        id: c.id,
        name: c.name,
        industry: c.industry,
        description: c.description,
        website: c.website,
        roleCount: _jds.where((j) => j.companyId == c.id).length,
        interviewCount: _interviews.where((i) => i.companyId == c.id).length,
        nextPptAt: c.nextPptAt,
        latestYear: c.latestYear,
        latestYearSelected: c.latestYearSelected,
        totalSelected: c.totalSelected,
        jobDescriptions: _jds.where((j) => j.companyId == c.id).toList(),
        ppts: _ppts.where((p) => p.companyId == c.id).toList(),
        viewerCanManage: true,
      );

  @override
  Future<List<Company>> fetchCompanies({String? query, String sort = 'name', int limit = 50}) async {
    final q = (query ?? '').trim().toLowerCase();
    final list = _companies
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || (c.industry ?? '').toLowerCase().contains(q))
        .map(_withDetails)
        .toList();
    if (sort == 'most_hired') {
      list.sort((a, b) => b.latestYearSelected.compareTo(a.latestYearSelected));
    } else {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  @override
  Future<Company> getCompany(String companyId) async {
    final match = _companies.where((c) => c.id == companyId);
    if (match.isEmpty) throw Exception('Company not found.');
    return _withDetails(match.first);
  }

  @override
  Future<HiringStats> fetchHiringStats(String companyId) async {
    final years = _stats[companyId] ?? const <YearStats>[];
    return HiringStats(
        companyId: companyId, years: years, totalSelected: years.fold(0, (sum, y) => sum + y.studentsSelected));
  }

  @override
  Future<PlacementOverview> fetchOverview() async => const PlacementOverview(
        seasons: [
          SeasonStats(year: 2026, studentsSelected: 10, companies: 2),
          SeasonStats(year: 2025, studentsSelected: 13, companies: 3),
          SeasonStats(year: 2024, studentsSelected: 6, companies: 2),
        ],
        year: 2026,
        topCompanies: [
          TopCompany(companyId: 'co_google', companyName: 'Google', studentsSelected: 6),
          TopCompany(companyId: 'co_gs', companyName: 'Goldman Sachs', studentsSelected: 4),
        ],
      );

  @override
  Future<List<Ppt>> fetchUpcomingPpts({int limit = 10}) async =>
      _ppts.where((p) => p.when == PptWhen.upcoming).take(limit).toList();

  @override
  Future<List<InterviewExperience>> fetchInterviews({String? companyId, String? query, int limit = 30}) async {
    final q = (query ?? '').trim().toLowerCase();
    return _interviews
        .where((i) => companyId == null || i.companyId == companyId)
        .where((i) => q.isEmpty || i.content.toLowerCase().contains(q) || (i.roleTitle ?? '').toLowerCase().contains(q))
        .take(limit)
        .toList();
  }

  @override
  Future<InterviewExperience> postInterview(String companyId,
      {required String roleTitle, int? placementYear, required String content, bool anonymous = false}) async {
    final company = await getCompany(companyId);
    final item = InterviewExperience(
        id: 'iv_${DateTime.now().microsecondsSinceEpoch}', companyId: companyId, companyName: company.name,
        roleTitle: roleTitle, placementYear: placementYear, content: content, isAnonymous: anonymous, isMine: true,
        authorName: 'You', createdAt: DateTime.now());
    _interviews.insert(0, item);
    return item;
  }

  @override
  Future<InterviewExperience> updateInterview(String interviewId,
      {String? roleTitle, int? placementYear, String? content, bool? anonymous}) async {
    final i = _interviews.indexWhere((x) => x.id == interviewId);
    if (i < 0) throw Exception('Interview experience not found.');
    final old = _interviews[i];
    _interviews[i] = InterviewExperience(
        id: old.id, companyId: old.companyId, companyName: old.companyName, roleTitle: roleTitle ?? old.roleTitle,
        placementYear: placementYear, content: content ?? old.content, isAnonymous: anonymous ?? old.isAnonymous,
        isMine: old.isMine, authorName: old.authorName, createdAt: old.createdAt);
    return _interviews[i];
  }

  @override
  Future<void> deleteInterview(String interviewId) async => _interviews.removeWhere((i) => i.id == interviewId);

  @override
  Future<Company> saveCompany({String? companyId, required String name, String? industry, String? website,
      String? description}) async {
    final company = Company(id: companyId ?? 'co_${DateTime.now().microsecondsSinceEpoch}', name: name,
        industry: _blankToNull(industry), website: _blankToNull(website), description: _blankToNull(description));
    final i = _companies.indexWhere((c) => c.id == company.id);
    if (i >= 0) {
      _companies[i] = company;
    } else {
      _companies.add(company);
    }
    return _withDetails(company);
  }

  @override
  Future<void> deleteCompany(String companyId) async => _companies.removeWhere((c) => c.id == companyId);

  @override
  Future<void> saveJobDescription({String? jdId, required String companyId, required String roleTitle,
      String? description, String? compensation, bool removeFile = false}) async {
    _jds.removeWhere((j) => j.id == jdId);
    _jds.add(JobDescription(id: jdId ?? 'jd_${DateTime.now().microsecondsSinceEpoch}', companyId: companyId,
        roleTitle: roleTitle, description: _blankToNull(description), compensation: _blankToNull(compensation)));
  }

  @override
  Future<void> deleteJobDescription(String jdId) async => _jds.removeWhere((j) => j.id == jdId);

  @override
  Future<void> savePpt({String? pptId, required String companyId, String? details, String? venue,
      DateTime? scheduledAt}) async {
    final company = await getCompany(companyId);
    _ppts.removeWhere((p) => p.id == pptId);
    _ppts.add(Ppt(
        id: pptId ?? 'ppt_${DateTime.now().microsecondsSinceEpoch}', companyId: companyId, companyName: company.name,
        details: _blankToNull(details), venue: _blankToNull(venue), scheduledAt: scheduledAt,
        when: scheduledAt == null
            ? PptWhen.unscheduled
            : (scheduledAt.isAfter(DateTime.now()) ? PptWhen.upcoming : PptWhen.past)));
  }

  @override
  Future<void> deletePpt(String pptId) async => _ppts.removeWhere((p) => p.id == pptId);

  @override
  Future<ImportResult> importSheet(int placementYear, String sheet) async {
    final lines = const LineSplitter().convert(sheet).where((l) => l.trim().isNotEmpty).toList();
    final rows = lines.length > 1 ? lines.length - 1 : 0;
    return ImportResult(
        placementYear: placementYear, rowsTotal: rows, rowsCreated: rows, rowsUpdated: 0, rowsRejected: 0);
  }

  @override
  Future<String> companyForumId(String companyId) async => 'forum_$companyId';

  @override
  Future<List<ForumThread>> fetchThreads(String forumId) async => _threads.where((t) => t.forumId == forumId).toList();

  @override
  Future<ForumThread> getThread(String threadId) async => _threads.firstWhere((t) => t.id == threadId);

  @override
  Future<ForumThread> createThread(String forumId, String title, String content) async {
    final now = DateTime.now();
    final thread = ForumThread(
        id: 'th_${now.microsecondsSinceEpoch}', forumId: forumId, title: title, authorId: 'me', authorName: 'You',
        commentCount: 1, lastCommentAt: now, createdAt: now, viewerCanModerate: true,
        comments: [ForumComment(id: 'cm_${now.microsecondsSinceEpoch}', authorId: 'me', authorName: 'You',
            content: content, createdAt: now)]);
    _threads.insert(0, thread);
    return thread;
  }

  @override
  Future<void> reply(String threadId, String content) async {
    final i = _threads.indexWhere((t) => t.id == threadId);
    if (i < 0) return;
    final t = _threads[i];
    final now = DateTime.now();
    _threads[i] = ForumThread(
        id: t.id, forumId: t.forumId, title: t.title, authorId: t.authorId, authorName: t.authorName,
        commentCount: t.commentCount + 1, lastCommentAt: now, createdAt: t.createdAt,
        viewerCanModerate: t.viewerCanModerate,
        comments: [...t.comments, ForumComment(id: 'cm_${now.microsecondsSinceEpoch}', authorId: 'me',
            authorName: 'You', content: content, createdAt: now)]);
  }

  @override
  Future<void> deleteThread(String threadId) async => _threads.removeWhere((t) => t.id == threadId);

  @override
  Future<void> deleteComment(String commentId) async {}
}
