// ef51d67efa885cf346f5f9e8a82f9b66
import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const String apiKey =
      "ef51d67efa885cf346f5f9e8a82f9b66";

  Future<Map<String, dynamic>> getWeather(
      String city) async {

    final url =
        "https://api.openweathermap.org/data/2.5/weather?q=$city&appid=$apiKey&units=metric";

    final response =
        await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load weather");
    }
  }
}