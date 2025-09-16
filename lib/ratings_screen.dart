import 'package:flutter/material.dart';
import 'general_screen.dart';
import 'goodfor_screen.dart';
import 'sub_preview_screen/review_context.dart';

class RatingsScreen extends StatefulWidget {
  final ReviewContext context;

  const RatingsScreen({super.key, required this.context});

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  late double foodRating;
  late double serviceRating;
  late double ambianceRating;
  late double drinksRating;
  late double vfmsRating;
  late double michelinStars;

  @override
  void initState() {
    super.initState();
    final reviewMap = widget.context.reviewMap;
    foodRating = reviewMap['foodRating'] ?? 0.0;
    serviceRating = reviewMap['serviceRating'] ?? 0.0;
    ambianceRating = reviewMap['ambianceRating'] ?? 0.0;
    drinksRating = reviewMap['drinksRating'] ?? 0.0;
    vfmsRating = reviewMap['vfmsRating'] ?? 0.0;
    michelinStars = reviewMap['michelinStars'] ?? 0.0;
  }

  void _updateRating(String category, double value) {
    setState(() {
      switch (category) {
        case 'Food':
          foodRating = value;
          break;
        case 'Service':
          serviceRating = value;
          break;
        case 'Ambiance':
          ambianceRating = value;
          break;
        case 'Drinks':
          drinksRating = value;
          break;
        case 'VFMS':
          vfmsRating = value;
          break;
      }
    });
  }

  Widget _buildRatingRow(String label, double currentValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 14))),
          Expanded(
            child: Slider(
              value: currentValue,
              min: 0,
              max: 10,
              divisions: 20,
              label: currentValue.toStringAsFixed(1),
              onChanged: (value) => _updateRating(label, value),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              currentValue.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMichelinSelector(double currentValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Michelin Stars', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(
          children: List.generate(4, (index) {
            return Row(
              children: [
                Radio<double>(
                  value: index.toDouble(),
                  groupValue: currentValue,
                  onChanged: (value) {
                    setState(() {
                      michelinStars = value!;
                    });
                  },
                ),
                Text('$index'),
              ],
            );
          }),
        ),
      ],
    );
  }

  void _goToNextScreen() {
    final reviewMap = widget.context.reviewMap;
    reviewMap['foodRating'] = foodRating;
    reviewMap['serviceRating'] = serviceRating;
    reviewMap['ambianceRating'] = ambianceRating;
    reviewMap['drinksRating'] = drinksRating;
    reviewMap['vfmsRating'] = vfmsRating;
    reviewMap['michelinStars'] = michelinStars;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoodForScreen(context: widget.context),
      ),
    );
  }

  void _goBack() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralScreen(context: widget.context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalRating = foodRating + serviceRating + ambianceRating + drinksRating + vfmsRating;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate the Restaurant'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildRatingRow('Food', foodRating),
            _buildRatingRow('Service', serviceRating),
            _buildRatingRow('Ambiance', ambianceRating),
            _buildRatingRow('Drinks', drinksRating),
            _buildRatingRow('VFMS', vfmsRating),
            const SizedBox(height: 8),
            _buildMichelinSelector(michelinStars),
            const SizedBox(height: 16),
            Text(
              'Restaurant Rating: ${totalRating.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: null,
                  child: const Text('CLEAR'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                ),
                ElevatedButton(
                  onPressed: _goBack,
                  child: const Text('BACK'),
                ),
                ElevatedButton(
                  onPressed: null,
                  child: const Text('PREVIEW'),
                ),
                ElevatedButton(
                  onPressed: _goToNextScreen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('NEXT'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}