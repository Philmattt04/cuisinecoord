class DiningVisit {
  final String restaurantId;
  final String restaurantName;
  final DateTime visitedAt;
  final int? personalRating; // 1–5
  final String? note;

  const DiningVisit({
    required this.restaurantId,
    required this.restaurantName,
    required this.visitedAt,
    this.personalRating,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'visitedAt': visitedAt.toIso8601String(),
        'personalRating': personalRating,
        'note': note,
      };

  factory DiningVisit.fromJson(Map<String, dynamic> j) => DiningVisit(
        restaurantId: j['restaurantId'] as String,
        restaurantName: j['restaurantName'] as String,
        visitedAt: DateTime.parse(j['visitedAt'] as String),
        personalRating: j['personalRating'] as int?,
        note: j['note'] as String?,
      );
}

class RestaurantCollection {
  final String id;
  final String name;
  final List<String> restaurantIds;

  const RestaurantCollection({
    required this.id,
    required this.name,
    required this.restaurantIds,
  });

  bool contains(String restaurantId) => restaurantIds.contains(restaurantId);

  RestaurantCollection withRestaurant(String id) => RestaurantCollection(
        id: this.id,
        name: name,
        restaurantIds: [...restaurantIds, id],
      );

  RestaurantCollection withoutRestaurant(String id) => RestaurantCollection(
        id: this.id,
        name: name,
        restaurantIds: restaurantIds.where((r) => r != id).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'restaurantIds': restaurantIds,
      };

  factory RestaurantCollection.fromJson(Map<String, dynamic> j) =>
      RestaurantCollection(
        id: j['id'] as String,
        name: j['name'] as String,
        restaurantIds: (j['restaurantIds'] as List).cast<String>(),
      );
}
