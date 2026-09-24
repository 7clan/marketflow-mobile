/// A shipping address captured at checkout.
class Address {
  const Address({
    required this.fullName,
    required this.street,
    required this.city,
    required this.state,
    required this.zip,
    this.country = 'United States',
    required this.phone,
  });

  final String fullName;
  final String street;
  final String city;
  final String state;
  final String zip;
  final String country;
  final String phone;

  Address copyWith({
    String? fullName,
    String? street,
    String? city,
    String? state,
    String? zip,
    String? country,
    String? phone,
  }) {
    return Address(
      fullName: fullName ?? this.fullName,
      street: street ?? this.street,
      city: city ?? this.city,
      state: state ?? this.state,
      zip: zip ?? this.zip,
      country: country ?? this.country,
      phone: phone ?? this.phone,
    );
  }

  /// Single-line rendering, e.g. for order summaries.
  String get oneLine => '$street, $city, $state $zip, $country';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Address &&
        other.fullName == fullName &&
        other.street == street &&
        other.city == city &&
        other.state == state &&
        other.zip == zip &&
        other.country == country &&
        other.phone == phone;
  }

  @override
  int get hashCode =>
      Object.hash(fullName, street, city, state, zip, country, phone);

  @override
  String toString() => 'Address($oneLine)';
}
