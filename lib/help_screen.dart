// help_screen.dart
// Help and About screen for RestiView — shows app info, website link, and version.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = 'Version ${info.version}';
      });
    } catch (_) {
      // If retrieving version fails, silently ignore and leave _version empty.
    }
  }

  Future<void> _launchWebsite() async {
    final url = Uri.parse('https://www.restiview.com');
    try {
      final canLaunch = await canLaunchUrl(url);
      if (!canLaunch) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStr.invalidUrl)),
        );
        return;
      }

      final launched = await launchUrl(url);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStr.openUrlFailed)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStr.openUrlFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          AppStr.help,
          style: const TextStyle(
            fontFamily: 'Gelica',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStr.aboutTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Gelica',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStr.aboutDescription,
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Gelica',
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppStr.moreInfoPrompt,
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Gelica',
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _launchWebsite,
                child: Text(
                  AppStr.websiteUrl,
                  style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'Gelica',
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
              Center(
                child: Column(
                  children: [
                    Text(
                      _version,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Gelica',
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ochre,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: Text(
                        AppStr.back,
                        style: const TextStyle(fontFamily: 'Gelica'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
