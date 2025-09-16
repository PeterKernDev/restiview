import 'package:flutter/material.dart';
import 'ratings_screen.dart';
import 'preview_screen.dart';
import 'sub_preview_screen/review_context.dart';

class GeneralScreen extends StatefulWidget {
  final ReviewContext context;

  const GeneralScreen({super.key, required this.context});

  @override
  State<GeneralScreen> createState() => _GeneralScreenState();
}

class _GeneralScreenState extends State<GeneralScreen> {
  late TextEditingController _restaurantController;
  late TextEditingController _cityController;
  late TextEditingController _dinersController;
  late TextEditingController _costController;

  String _selectedCountry = 'USA';
  String _selectedCuisine = 'Chinese';
  DateTime _selectedDate = DateTime.now();

  final List<String> _countries = ['USA', 'UK', 'France'];
  final List<String> _cuisines = ['Chinese', 'Italian', 'French'];

  @override
  void initState() {
    super.initState();

    final reviewMap = widget.context.reviewMap;

    _restaurantController = TextEditingController(text: reviewMap['restaurantName'] ?? '');
    _cityController = TextEditingController(text: reviewMap['city'] ?? '');
    _dinersController = TextEditingController(
      text: (reviewMap['numberOfDiners']?.toString() ?? '1'),
    );
    _costController = TextEditingController(
      text: reviewMap.containsKey('cost') ? (reviewMap['cost']?.toString() ?? '') : '',
    );

    _selectedCountry = reviewMap['country'] ?? 'USA';
    _selectedCuisine = reviewMap['cuisine'] ?? 'Chinese';

    if (reviewMap['dateOfReview'] != null) {
      _selectedDate = DateTime.tryParse(reviewMap['dateOfReview']) ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _cityController.dispose();
    _dinersController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _saveGeneralInfoToMap() {
    final reviewMap = widget.context.reviewMap;

    reviewMap['restaurantName'] = _restaurantController.text;
    reviewMap['country'] = _selectedCountry;
    reviewMap['city'] = _cityController.text;
    reviewMap['cuisine'] = _selectedCuisine;
    reviewMap['numberOfDiners'] = int.tryParse(_dinersController.text) ?? 1;
    reviewMap['cost'] = double.tryParse(_costController.text) ?? 0.0;
    reviewMap['currency'] = 'US\$';
    reviewMap['dateOfReview'] = _selectedDate.toIso8601String();
  }

  void _goToRatingsScreen() {
    _saveGeneralInfoToMap();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RatingsScreen(context: widget.context),
      ),
    );
  }

  void _goToPreviewScreen() {
    _saveGeneralInfoToMap();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(context: widget.context),
      ),
    );
  }

  void _goBackToTop() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralScreen(
          context: ReviewContext(reviewMap: {}, isEditing: false),
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.context.isEditing;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit General Info' : 'Add General Info'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _restaurantController,
              decoration: const InputDecoration(labelText: 'Restaurant'),
            ),
            DropdownButtonFormField<String>(
              value: _selectedCountry,
              items: _countries.map((country) {
                return DropdownMenuItem(value: country, child: Text(country));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCountry = value!;
                });
              },
              decoration: const InputDecoration(labelText: 'Country'),
            ),
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(labelText: 'City'),
            ),
            DropdownButtonFormField<String>(
              value: _selectedCuisine,
              items: _cuisines.map((cuisine) {
                return DropdownMenuItem(value: cuisine, child: Text(cuisine));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCuisine = value!;
                });
              },
              decoration: const InputDecoration(labelText: 'Cuisine'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Date: ${_selectedDate.toLocal().toString().split(' ')[0]}'),
                const Spacer(),
                ElevatedButton(
                  onPressed: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                      });
                    }
                  },
                  child: const Text('Pick Date'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dinersController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of Diners'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Cost:', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 12),
                const Text('US\$', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: null,
              child: const Text('ADD PHOTO'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _goBackToTop,
                  child: const Text('BACK'),
                ),
                ElevatedButton(
                  onPressed: _goToPreviewScreen,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('PREVIEW'),
                ),
                ElevatedButton(
                  onPressed: _goToRatingsScreen,
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