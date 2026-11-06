import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/server_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/campus_services_repository.dart';
import '../domain/campus_service.dart';

final campusServicesRepositoryProvider = Provider<ICampusServicesRepository>((ref) {
  if (ref.watch(serverConfigProvider).useMockData) {
    return MockCampusServicesRepository();
  }
  return ApiCampusServicesRepository(ref.watch(apiClientProvider));
});

/// Active services shown to everyone.
final campusServicesProvider = FutureProvider<List<CampusService>>((ref) {
  return ref.watch(campusServicesRepositoryProvider).fetchServices();
});

/// Every service including hidden ones, for the admin's editor.
final allCampusServicesProvider = FutureProvider<List<CampusService>>((ref) {
  return ref.watch(campusServicesRepositoryProvider).fetchServices(includeInactive: true);
});
