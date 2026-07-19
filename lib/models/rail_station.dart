/// A railway station (code + display name), loaded from the bundled dataset.
class RailStation {
  final String code;
  final String name;

  const RailStation({required this.code, required this.name});

  factory RailStation.fromJson(Map<String, dynamic> json) => RailStation(
        code: (json['code'] as String).trim(),
        name: (json['name'] as String).trim(),
      );

  @override
  bool operator ==(Object other) =>
      other is RailStation && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
