import 'inventory.dart';

/// The Food page's row composition, shared by the app and the agent CLI:
/// Inbox above Stock when not searching; search includes Deleted rows last.
class FoodRows {
  FoodRows({
    required this.state,
    required this.view,
    required this.query,
    Set<String> reasons = const {},
    Set<String> brands = const {},
    Set<String> locations = const {},
  }) : reasons = Set.unmodifiable(reasons),
       brands = Set.unmodifiable(brands),
       locations = Set.unmodifiable(locations) {
    final querying = query.trim().isNotEmpty;
    matches = List.unmodifiable(
      state.view(
        view == FoodView.inbox ? FoodView.inventory : view,
        search: query,
        reasons: reasons,
        brands: brands,
        locations: locations,
      ),
    );
    inbox = List.unmodifiable(
      (view == FoodView.inventory || view == FoodView.inbox) && !querying
          ? state.view(FoodView.inbox, brands: brands, locations: locations)
          : <FoodGroup>[],
    );
    groups = querying
        ? List.unmodifiable(matches.where((g) => !g.containers.first.deleted))
        : matches;
    deletedGroups = querying
        ? List.unmodifiable(matches.where((g) => g.containers.first.deleted))
        : const [];
    rows = List.unmodifiable([...inbox, ...groups, ...deletedGroups]);
  }

  final FoodState state;
  final FoodView view;
  final String query;
  final Set<String> reasons, brands, locations;
  late final List<FoodGroup> matches, inbox, groups, deletedGroups;

  /// Visible rows in display order, including Deleted rows.
  late final List<FoodGroup> rows;
}
