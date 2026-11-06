import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/config/server_config.dart';
import '../../auth/providers/auth_providers.dart';

/// One thing I posted outside Buy & Sell and Lost & Found (GET /me/posts).
/// [route] is where tapping it goes: the course, company, event or mess page.
class MyPost {
  final String id;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String route;

  const MyPost({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.route,
  });
}

/// My course feedback and materials, and (moderators and admin) the companies, events and mess menus I added.
class MyPosts {
  final List<MyPost> feedback;
  final List<MyPost> materials;
  final List<MyPost> companies;

  /// Events and mess menus together, events first.
  final List<MyPost> events;

  const MyPosts({
    this.feedback = const [],
    this.materials = const [],
    this.companies = const [],
    this.events = const [],
  });

  static const empty = MyPosts();

  factory MyPosts.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String key) => (j[key] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    DateTime at(Map<String, dynamic> r, [String key = 'created_at']) =>
        DateTime.tryParse('${r[key]}')?.toLocal() ?? DateTime.now();
    String day(Map<String, dynamic> r, String key) => '${r[key]}'.split('T').first;

    return MyPosts(
      feedback: [
        for (final r in list('feedback'))
          MyPost(
            id: '${r['id']}',
            title: '${r['course_code']} · ${r['course_name']}',
            subtitle: '${r['is_anonymous'] == true ? 'Anonymous · ' : ''}${r['content']}',
            createdAt: at(r),
            route: '/courses/${r['course_id']}',
          ),
      ],
      materials: [
        for (final r in list('materials'))
          MyPost(
            id: '${r['id']}',
            title: '${r['title']}',
            subtitle:
                '${r['course_code']} · ${r['material_type']}${r['held'] == true ? ' · waiting for a moderator' : ''}',
            createdAt: at(r),
            route: '/courses/${r['course_id']}',
          ),
      ],
      companies: [
        for (final r in list('companies'))
          MyPost(
            id: '${r['id']}',
            title: '${r['name']}',
            subtitle: r['industry'] == null ? 'Company' : '${r['industry']}',
            createdAt: at(r),
            route: '/placements/${r['id']}',
          ),
      ],
      events: [
        for (final r in list('events'))
          MyPost(
            id: '${r['id']}',
            title: '${r['title']}',
            subtitle: 'Event · ${day(r, 'start_time')}${r['location'] == null ? '' : ' · ${r['location']}'}',
            createdAt: at(r),
            route: '/events/${r['id']}',
          ),
        for (final r in list('mess_menus'))
          MyPost(
            id: '${r['id']}',
            title: '${r['mess_name']} menu',
            subtitle: 'Mess menu · ${day(r, 'valid_from')} to ${day(r, 'valid_to')}',
            createdAt: at(r),
            route: '/mess?mess=${r['mess_id']}',
          ),
      ],
    );
  }
}

/// Auto-disposed, so it reloads each time the profile opens (posts may have been added or removed meanwhile).
final myPostsProvider = FutureProvider.autoDispose<MyPosts>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest || ref.watch(serverConfigProvider).useMockData) return MyPosts.empty;
  final response = await ref.watch(apiClientProvider).get(ApiEndpoints.myPosts);
  return MyPosts.fromJson(response.data as Map<String, dynamic>);
});
