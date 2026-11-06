import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../domain/campus_service.dart';

/// Campus services for the landing page (`/campus-services`). Anyone reads; only the admin edits.
abstract class ICampusServicesRepository {
  /// Grouped by category, then sort order. [includeInactive] only works for the admin.
  Future<List<CampusService>> fetchServices({bool includeInactive = false});

  Future<CampusService> createService(CampusService service);

  Future<CampusService> updateService(CampusService service);

  Future<void> deleteService(String id);
}

class ApiCampusServicesRepository implements ICampusServicesRepository {
  final ApiClient apiClient;

  ApiCampusServicesRepository(this.apiClient);

  @override
  Future<List<CampusService>> fetchServices({bool includeInactive = false}) async {
    final response = await apiClient.get(
      ApiEndpoints.campusServices,
      queryParameters: {if (includeInactive) 'include_inactive': true},
    );
    return (response.data as List<dynamic>)
        .map((j) => CampusService.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<CampusService> createService(CampusService service) async {
    final response = await apiClient.post(ApiEndpoints.campusServices, data: service.toJson());
    return CampusService.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<CampusService> updateService(CampusService service) async {
    final response = await apiClient.patch(ApiEndpoints.campusService(service.id), data: service.toJson());
    return CampusService.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> deleteService(String id) async {
    await apiClient.delete(ApiEndpoints.campusService(id));
  }
}

/// In-memory version for mock mode, with the same starting links as `db/reference-data.sql`.
class MockCampusServicesRepository implements ICampusServicesRepository {
  static final List<CampusService> _initial = [
    const CampusService(
      id: 'cs_1',
      name: 'Health Centre',
      description: 'Doctors, pharmacy, lab tests and specialist clinics on campus.',
      category: CampusServiceCategory.health,
      url: 'https://healthcentre.iisc.ac.in/',
      sortOrder: 10,
    ),
    const CampusService(
      id: 'cs_2',
      name: 'Emergency / Ambulance',
      description: 'Health Centre emergency line, any time.',
      category: CampusServiceCategory.health,
      phone: '080-2293-4444',
      sortOrder: 20,
    ),
    const CampusService(
      id: 'cs_3',
      name: 'Wellness Centre',
      description: 'Free, confidential counselling and wellbeing support for students.',
      category: CampusServiceCategory.wellbeing,
      url: 'https://wellness.iisc.ac.in/',
      sortOrder: 10,
    ),
    const CampusService(
      id: 'cs_4',
      name: 'Student grievance redressal',
      description: 'How to raise an academic or administrative grievance, and who handles it.',
      category: CampusServiceCategory.grievance,
      url: 'https://www.iisc.ac.in/wp-content/uploads/2025/01/Approval-Note_Students-Grievances-Guidelines.pdf',
      sortOrder: 10,
    ),
    const CampusService(
      id: 'cs_5',
      name: 'Internal Committee Against Sexual Harassment (ICASH)',
      description: 'Report sexual harassment, confidentially.',
      category: CampusServiceCategory.grievance,
      url: 'https://www.iisc.ac.in/icash/',
      sortOrder: 20,
    ),
  ];

  static final List<CampusService> _services = List.of(_initial);

  static void resetMockData() => _services
    ..clear()
    ..addAll(_initial);

  @override
  Future<List<CampusService>> fetchServices({bool includeInactive = false}) async {
    final list = _services.where((s) => includeInactive || s.isActive).toList()
      ..sort((a, b) {
        final byCategory = a.category.index.compareTo(b.category.index);
        return byCategory != 0 ? byCategory : a.sortOrder.compareTo(b.sortOrder);
      });
    return list;
  }

  @override
  Future<CampusService> createService(CampusService service) async {
    final created = service.copyWith(id: 'cs_${DateTime.now().microsecondsSinceEpoch}');
    _services.add(created);
    return created;
  }

  @override
  Future<CampusService> updateService(CampusService service) async {
    final i = _services.indexWhere((s) => s.id == service.id);
    if (i < 0) throw Exception('Campus service not found.');
    _services[i] = service;
    return service;
  }

  @override
  Future<void> deleteService(String id) async => _services.removeWhere((s) => s.id == id);
}
