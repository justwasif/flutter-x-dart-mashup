import 'package:flutter/material.dart';
import '../models/weather_model.dart';

class WeatherCard extends StatelessWidget {
  final WeatherModel weather;

  const WeatherCard({
    super.key,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [

            Text(
              weather.cityName,
              style: const TextStyle(
                fontSize: 30,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              "${weather.temperature}°C",
              style: const TextStyle(
                fontSize: 40,
              ),
            ),

            Text(weather.condition),

            const SizedBox(height: 10),

            Text(
                "Humidity: ${weather.humidity}%"),

            Text(
                "Wind: ${weather.windSpeed} m/s"),
          ],
        ),
      ),
    );
  }
}