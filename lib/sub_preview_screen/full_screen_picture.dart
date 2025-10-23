import 'dart:io';
import 'package:flutter/material.dart';
import '/constants/strings.dart'; // ✅ Centralized strings

class FullScreenImage extends StatelessWidget {
  final String path;

  const FullScreenImage({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text( AppStr.photoError,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}