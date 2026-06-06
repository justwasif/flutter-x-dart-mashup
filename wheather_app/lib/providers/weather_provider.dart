import 'package:flutter/material.dart';
import '../models/weather_model.dart';
import '../services/weather_service.dart';

class WeatherProvider extends ChangeNotifier {
  final WeatherService _service =
      WeatherService();

  WeatherModel? weather;

  bool isLoading = false;

  String error = "";

  Future<void> fetchWeather(
      String city) async {

    try {
      isLoading = true;
      error = "";

      notifyListeners();

      final data =
          await _service.getWeather(city);

      weather =
          WeatherModel.fromJson(data);

    } catch (e) {
      error = e.toString();
    }

    isLoading = false;

    notifyListeners();
  }
}