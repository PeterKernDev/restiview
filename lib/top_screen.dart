// top_screen.dart
// Main dashboard screen after user login. Provides access to review creation, viewing, settings, help, sign-out, and friends access.
// Updated: friends button is disabled (greyed out) when the current user does not accept friend requests
// (determined by users/$uid/userSettings7 or default true).
//
// Change: removed accepted-friends counter entirely (no reads or display).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'general_screen.dart';
import 'settings_screen.dart';
import 'list_screen.dart';
import 'sub_preview_screen/review_context.dart';
import 'services/session_cache.dart';
import 'services/db_utils.dart';
import 'services/review_info_builder.dart';
import 'services/mailbox_helper.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/restiview_constants.dart';

class TopScreen extends StatefulWidget {
  const TopScreen({super.key});

  @override
  State<TopScreen> createState() => _TopScreenState();
}

class _TopScreenState extends State<TopScreen> {
  bool _isLoading = false;
  bool _acceptsFriends =
      true; // whether this user accepts friends (controls button enabled)
  bool _hasRequestedReviews = false; // whether user has any requested reviews
  bool _hasFriends = false; // whether user has any friends
  bool _hasPendingMailboxRequests =
      false; // whether user has pending friend/review requests
  Timer? _mailboxCheckTimer; // Periodic timer to check mailbox

  @override
  void initState() {
    super.initState();
    _loadAcceptsFriends();
    _checkRequestedReviews();
    _checkFriends();
    _checkMailbox(); // Check mailbox on screen open
    _startMailboxTimer(); // Start periodic mailbox checks
  }

  @override
  void dispose() {
    _mailboxCheckTimer?.cancel();
    super.dispose();
  }

  void _checkFriends() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final friendsRef = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('friends');
    final snapshot = await friendsRef.get();
    if (mounted) {
      setState(() {
        _hasFriends = snapshot.exists && (snapshot.value != null);
      });
    }
  }

  void _startMailboxTimer() {
    // Start periodic timer to check mailbox every N seconds
    // mailboxCheckIntervalSeconds is 30 for testing, 600 for production
    _mailboxCheckTimer = Timer.periodic(
      Duration(seconds: mailboxCheckIntervalSeconds),
      (Timer timer) {
        _checkMailbox();
      },
    );
  }

  Future<void> _checkMailbox() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      return;
    }

    final String normalizedEmail = normalizeEmailForPath(
      user.email!.toLowerCase(),
    );

    try {
      // Process any pending mailbox requests
      bool hasPending = await hasMailboxRequests(normalizedEmail);
      if (hasPending) {
        await processUserMailbox(user.uid, normalizedEmail);
      }

      // After processing mailbox, check if there are any pending friend actions
      // (unaccepted friend requests or review requests)
      bool hasPendingActions = await _hasPendingFriendActions(user.uid);

      if (mounted) {
        setState(() {
          _hasPendingMailboxRequests = hasPendingActions;
        });
      }
    } catch (e) {
      // Silent failure with logging
      debugPrint('Error checking mailbox: $e');
    }
  }

  /// Check if user has any pending friend actions requiring attention
  /// Returns true if there are friend requests (statusCode=2) or review requests (statusCode=3)
  Future<bool> _hasPendingFriendActions(String uid) async {
    try {
      final DatabaseReference friendsRef = FirebaseDatabase.instance.ref(
        'users/$uid/friends',
      );
      final DataSnapshot snapshot = await friendsRef.get();

      if (!snapshot.exists || snapshot.value == null) {
        return false;
      }

      if (snapshot.value is! Map) {
        return false;
      }

      final Map<dynamic, dynamic> friends = snapshot.value as Map;

      // Check if any friend has statusCode 2 (FR-WANTED) or 3 (RV-WANTED)
      for (final entry in friends.values) {
        if (entry is Map) {
          final statusCode = entry['statusCode'];
          if (statusCode == 2 || statusCode == 3) {
            return true; // Found a pending action
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error checking pending friend actions: $e');
      return false;
    }
  }

  Future<void> _checkRequestedReviews() async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return;
    }

    try {
      final DatabaseReference requestedRef = FirebaseDatabase.instance.ref(
        'users/$userId/reviews_requested',
      );
      final DataSnapshot snapshot = await requestedRef.get();

      if (mounted) {
        setState(() {
          _hasRequestedReviews =
              snapshot.exists &&
              snapshot.value is Map &&
              (snapshot.value as Map).isNotEmpty;
        });
      }
    } catch (e) {
      // Silently handle error - button just won't show
    }
  }

  Future<void> _loadAcceptsFriends() async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _acceptsFriends = true;
        });
      }
      return;
    }

    try {
      bool accepts = true;
      try {
        final DataSnapshot s7 = await FirebaseDatabase.instance
            .ref('users/$userId/userSettings7')
            .get();
        if (s7.exists && s7.value != null) {
          final Object? v = s7.value;
          if (v is bool) {
            accepts = v;
          } else if (v is String) {
            accepts = v.toLowerCase() == 'true';
          } else if (v is num) {
            accepts = v != 0;
          }
        }
      } catch (e) {
        // keep default true
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _acceptsFriends = accepts;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${AppStr.loadFriendsError}: $e')));
    }
  }

  Future<void> _signOut() async {
    // Update review_info before signing out (regardless of daily limit)
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final userEmail = SessionCache.userEmail;
    if (userId != null && userEmail.isNotEmpty) {
      try {
        final normalizedEmail = normalizeEmailForPath(userEmail);
        await updateReviewInfo(userId, normalizedEmail);
        final today = DateTime.now().toIso8601String().substring(0, 10);
        await SessionCache.setReviewInfoLastUpdate(today);
        await SessionCache.setReviewsAdded(false);
      } catch (e) {
        debugPrint('Error updating review_info on sign out: \$e');
      }
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${AppStr.signOutFailed}: $e')));
      return;
    }

    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, '/');
  }

  void _handleViewRequestedReviews() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ReviewListScreen(mode: 'requested'),
      ),
    );
  }

  Future<void> _handleViewReviews() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
    });

    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.userNotAuthenticated)));
      }
      return;
    }

    final DatabaseReference reviewsRef = FirebaseDatabase.instance.ref(
      'users/$userId/reviews',
    );

    try {
      final DataSnapshot snapshot = await reviewsRef.get();

      if (mounted) {
        if (snapshot.exists && snapshot.value is Map) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ReviewListScreen(mode: 'list'),
            ),
          );
        } else {
          showDialog(
            context: context,
            builder: (_) {
              return AlertDialog(
                title: Text(AppStr.noReviewsTitle, style: AppFonts.bold),
                content: Text(
                  AppStr.noReviewsMessage,
                  style: AppFonts.standard,
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(AppStr.ok, style: AppFonts.standard),
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStr.loadReviewsError}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startNewReview() {
    final ReviewContext newContext = ReviewContext(
      reviewMap: <String, dynamic>{},
      isEditing: false,
      reviewKey: null,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GeneralScreen(context: newContext)),
    );
  }

  void _openFriends() {
    if (!_acceptsFriends) {
      return;
    }
    Navigator.pushNamed(context, '/friends').then((_) async {
      await _loadAcceptsFriends();
    });
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = SessionCache.userName.isNotEmpty
        ? SessionCache.userName
        : AppStr.anonUser;

    // Add (!) to friends label if there are pending mailbox requests
    String friendsLabel = AppStr.friendsUpper;
    if (_hasPendingMailboxRequests) {
      friendsLabel = '$friendsLabel (!)';
    }

    final Color friendsBg = _acceptsFriends
        ? AppColors.ochre
        : AppColors.greyShade400;
    final Color friendsFg = _acceptsFriends ? Colors.black87 : Colors.black38;

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        title: Text(
          '${AppStr.appTitle} : $displayName',
          style: AppFonts.bold.copyWith(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 48),
                  Text(
                    AppStr.restaurantReviews,
                    style: AppFonts.bold.copyWith(
                      fontSize: 24,
                      color: AppColors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ochre,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _startNewReview,
                    child: Text(AppStr.addReview, style: AppFonts.standard),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ochre,
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleViewReviews,
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(AppStr.viewReviews, style: AppFonts.standard),
                  ),
                  if (_hasFriends) ...<Widget>[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasRequestedReviews
                            ? AppColors.ochre
                            : AppColors.greyShade400,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _hasRequestedReviews
                          ? _handleViewRequestedReviews
                          : null,
                      child: Text(
                        AppStr.friendReviewsButton,
                        style: AppFonts.standard,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: friendsBg,
                      foregroundColor: friendsFg,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _acceptsFriends ? _openFriends : null,
                    child: Text(
                      friendsLabel,
                      style: AppFonts.standard.copyWith(color: friendsFg),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 36),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings, color: Colors.white),
                    label: Text(
                      AppStr.settings,
                      style: AppFonts.standard.copyWith(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.grey,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlueAccent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, '/help');
                    },
                    child: Text(
                      AppStr.help,
                      style: AppFonts.standard.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _signOut,
                    child: Text(
                      AppStr.signOut,
                      style: AppFonts.standard.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
