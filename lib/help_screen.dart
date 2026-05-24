// help_screen.dart
// Help and About screen for RestiView — uses AppFonts/AppColors and guards async UI updates.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';

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
      // ignore and leave _version empty
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

  Widget _buildGuideSection(String title, String body) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        title: Text(
          title,
          style: AppFonts.bold.copyWith(fontSize: 16, color: AppColors.darkGreen),
        ),
        iconColor: AppColors.darkGreen,
        collapsedIconColor: AppColors.darkGreen,
        children: [
          Text(body, style: AppFonts.standard.copyWith(fontSize: 15, height: 1.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(AppStr.help, style: AppFonts.bold.copyWith(color: AppColors.white)),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          children: [
            // About section
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStr.aboutTitle, style: AppFonts.bold.copyWith(fontSize: 24)),
                  const SizedBox(height: 16),
                  Text(AppStr.aboutDescription, style: AppFonts.standard.copyWith(fontSize: 16)),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Divider(),
            ),

            // User Guide heading
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                AppStr.userGuideTitle,
                style: AppFonts.bold.copyWith(fontSize: 20),
              ),
            ),

            // Accordion sections
            _buildGuideSection(AppStr.helpGettingStartedTitle, AppStr.helpGettingStartedBody),
            _buildGuideSection(AppStr.helpAddingReviewTitle, AppStr.helpAddingReviewBody),
            _buildGuideSection(AppStr.helpViewingReviewsTitle, AppStr.helpViewingReviewsBody),
            _buildGuideSection(AppStr.helpFriendsTitle, AppStr.helpFriendsBody),
            _buildGuideSection(AppStr.helpReviewRequestsTitle, AppStr.helpReviewRequestsBody),
            _buildGuideSection(AppStr.helpSettingsTitle, AppStr.helpSettingsBody),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Divider(),
            ),

            // Website link
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                AppStr.userGuideLinkPrompt,
                style: AppFonts.standard.copyWith(fontSize: 15),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: InkWell(
                onTap: _launchWebsite,
                child: Text(
                  AppStr.websiteUrl,
                  style: AppFonts.standard.copyWith(
                    fontSize: 15,
                    color: AppColors.darkGreen,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),

            // Version + Back button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  if (_version.isNotEmpty)
                    Text(
                      _version,
                      style: AppFonts.standard.copyWith(fontSize: 14, color: AppColors.mutedText),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (!mounted) return;
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ochre,
                        foregroundColor: AppColors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(AppStr.back, style: AppFonts.standard),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
