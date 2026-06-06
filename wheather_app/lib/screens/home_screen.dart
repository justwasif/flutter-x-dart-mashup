import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/weather_provider.dart';
import '../widgets/weather_card.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  final TextEditingController
      controller =
      TextEditingController();

  @override
  Widget build(BuildContext context) {

    final provider =
        Provider.of<WeatherProvider>(
            context);

    return Scaffold(
      appBar: AppBar(
        title:
            const Text("Weather App"),
      ),

      body: Padding(
        padding:
            const EdgeInsets.all(16),

        child: Column(
          children: [

            TextField(
              controller: controller,

              decoration:
                  InputDecoration(
                hintText:
                    "Enter city",
                suffixIcon: IconButton(
                  icon:
                      const Icon(Icons.search),

                  onPressed: () {

                    provider.fetchWeather(
                        controller.text);
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (provider.isLoading)
              const CircularProgressIndicator(),

            if (provider.error
                .isNotEmpty)
              Text(provider.error),

            if (provider.weather != null)
              WeatherCard(
                weather:
                    provider.weather!,
              ),
          ],
        ),
      ),
    );
  }
}