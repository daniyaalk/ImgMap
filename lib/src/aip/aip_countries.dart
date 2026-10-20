import 'countries/india.dart';
import 'eaip_country.dart';

/// Every country the app can fetch AIP data for.
///
/// To add one with a Eurocontrol-style eAIP, write an [EaipCountry] in
/// `countries/` (its ICAO prefixes, where editions are announced, its page
/// naming and chart file conventions) and list it here.
final List<EaipCountry> aipCountries = [india];
