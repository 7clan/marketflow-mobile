import '../../domain/entities/address.dart';
import 'json_reader.dart';

/// Wire representation of a shipping address.
class AddressModel {
  const AddressModel({
    required this.fullName,
    required this.street,
    required this.city,
    required this.state,
    required this.zip,
    required this.country,
    required this.phone,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      fullName: JsonReader.requireString(json, 'fullName'),
      street: JsonReader.requireString(json, 'street'),
      city: JsonReader.requireString(json, 'city'),
      state: JsonReader.requireString(json, 'state'),
      zip: JsonReader.requireString(json, 'zip'),
      country: JsonReader.optionalString(json, 'country') ?? 'United States',
      phone: JsonReader.requireString(json, 'phone'),
    );
  }

  final String fullName;
  final String street;
  final String city;
  final String state;
  final String zip;
  final String country;
  final String phone;

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'street': street,
    'city': city,
    'state': state,
    'zip': zip,
    'country': country,
    'phone': phone,
  };

  Address toDomain() => Address(
    fullName: fullName,
    street: street,
    city: city,
    state: state,
    zip: zip,
    country: country,
    phone: phone,
  );

  static AddressModel fromDomain(Address address) => AddressModel(
    fullName: address.fullName,
    street: address.street,
    city: address.city,
    state: address.state,
    zip: address.zip,
    country: address.country,
    phone: address.phone,
  );
}
