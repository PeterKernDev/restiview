// lib/sub_request_screen/location_inputs.dart
// Presentational location inputs: country (required), cuisine (optional), city (optional).
// - Pure UI with callbacks for changes. Does not fetch lists; callers may pass lists if desired.

import 'package:flutter/material.dart';
import '../constants/strings.dart';

typedef LocationChanged = void Function({
  required String country,
  String? cuisine,
  String? city,
});

class LocationInputs extends StatefulWidget {
  final String? initialCountry;
  final String? initialCuisine;
  final String? initialCity;
  final List<String>? countryOptions;
  final List<String>? cuisineOptions;
  final LocationChanged onChanged;

  const LocationInputs({
    super.key,
    required this.onChanged,
    this.initialCountry,
    this.initialCuisine,
    this.initialCity,
    this.countryOptions,
    this.cuisineOptions,
  });

  @override
  State<LocationInputs> createState() => _LocationInputsState();
}

class _LocationInputsState extends State<LocationInputs> {
  String? _country;
  String? _cuisine;
  late TextEditingController _cityController;

  @override
  void initState() {
    super.initState();
    _country = widget.initialCountry;
    _cuisine = widget.initialCuisine;
    _cityController = TextEditingController(text: widget.initialCity ?? '');
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  void _emitChange() {
    widget.onChanged(
      country: _country ?? '',
      cuisine: _cuisine,
      city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final countries = widget.countryOptions ?? <String>['Brazil', 'USA', 'UK', 'Other'];
    final cuisines = widget.cuisineOptions ?? <String>['Any', 'Italian', 'Japanese', 'Mexican', 'Other'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(AppStr.countryLabel, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('countryDropdown'),
          initialValue: _country != null && _country!.isNotEmpty ? _country : null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: countries.map((c) {
            return DropdownMenuItem<String>(
              value: c,
              child: Text(c),
            );
          }).toList(),
          onChanged: (v) {
            setState(() {
              _country = v;
            });
            _emitChange();
          },
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return AppStr.countryRequired;
            } else {
              return null;
            }
          },
        ),
        const SizedBox(height: 12),

        Text(AppStr.cuisineLabel, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('cuisineDropdown'),
          initialValue: _cuisine != null && _cuisine!.isNotEmpty ? _cuisine : null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: cuisines.map((c) {
            return DropdownMenuItem<String>(
              value: c == 'Any' ? '' : c,
              child: Text(c),
            );
          }).toList(),
          onChanged: (v) {
            setState(() {
              if (v != null && v.isNotEmpty) {
                _cuisine = v;
              } else {
                _cuisine = null;
              }
            });
            _emitChange();
          },
        ),
        const SizedBox(height: 12),

        Text(AppStr.cityLabel, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('cityField'),
          controller: _cityController,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'e.g., São Paulo'),
          onChanged: (v) {
            _emitChange();
          },
        ),
      ],
    );
  }
}
