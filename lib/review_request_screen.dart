// lib/review_request_screen.dart
// Screen for creating review requests with tree-view country/city selection.
// Reads provider's review_info from users_by_email to show available reviews.
// Stores filters array format: [{'country': 'USA', 'city': 'Denver'}, ...]

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'services/session_cache.dart';
import 'services/db_utils.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'friends_screen.dart';

class CountryNode {
  final String country;
  final int totalCount;
  final Map<String, int> cities;
  bool isExpanded;
  bool isCountrySelected;
  final Set<String> selectedCities;

  CountryNode({
    required this.country,
    required this.totalCount,
    required this.cities,
    this.isExpanded = false,
    this.isCountrySelected = false,
  }) : selectedCities = <String>{};

  bool get hasAnyCitySelected => selectedCities.isNotEmpty;
}

class ReviewRequestScreen extends StatefulWidget {
  const ReviewRequestScreen({super.key});

  @override
  State<ReviewRequestScreen> createState() => _ReviewRequestScreenState();
}

class _ReviewRequestScreenState extends State<ReviewRequestScreen> {
  bool _loading = true;
  bool _sending = false;
  final TextEditingController _commentCtl = TextEditingController();

  String? _reviewFriendUid;
  String? _providerEmail;
  String? _providerUsername;
  String? _checkedNormalized;

  final List<CountryNode> _countries = <CountryNode>[];
  int _totalSelectedReviews = 0;

  bool _didInitArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitArgs) {
      return;
    }

    final Object? args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final String? friendEmail = args['friendEmail'] as String?;
      final String? friendUid = args['friendUid'] as String?;
      if (friendEmail != null && friendEmail.isNotEmpty) {
        _providerEmail = friendEmail;
        _checkedNormalized = normalizeEmailForPath(friendEmail.toLowerCase());
        _reviewFriendUid = (friendUid != null && friendUid.isNotEmpty)
            ? friendUid
            : null;
      }
    }

    if (_providerEmail == null || _providerEmail!.isEmpty) {
      final String pending = SessionCache.pendingFriendEmail.trim();
      if (pending.isNotEmpty) {
        _providerEmail = pending;
        _checkedNormalized = normalizeEmailForPath(pending.toLowerCase());
        _reviewFriendUid = SessionCache.pendingFriendUid;
      }
    }

    _didInitArgs = true;
    _loadReviewInfo();
  }

  @override
  void dispose() {
    _commentCtl.dispose();
    super.dispose();
  }

  Future<void> _loadReviewInfo() async {
    if (_providerEmail == null || _providerEmail!.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    final String normalized =
        _checkedNormalized ??
        normalizeEmailForPath(_providerEmail!.toLowerCase());

    try {
      final DataSnapshot snap = await FirebaseDatabase.instance
          .ref('users_by_email/$normalized/review_info')
          .get();

      if (!snap.exists || snap.value == null || snap.value is! Map) {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }

      final Map<dynamic, dynamic> reviewInfo = Map<dynamic, dynamic>.from(
        snap.value as Map,
      );

      final Map<dynamic, dynamic>? countriesData =
          (reviewInfo['countries'] is Map)
          ? Map<dynamic, dynamic>.from(reviewInfo['countries'] as Map)
          : null;

      if (countriesData == null || countriesData.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
        return;
      }

      final List<CountryNode> nodes = <CountryNode>[];

      for (final MapEntry<dynamic, dynamic> entry in countriesData.entries) {
        final String countryName = entry.key.toString();
        if (entry.value is! Map) {
          continue;
        }

        final Map<dynamic, dynamic> countryData = Map<dynamic, dynamic>.from(
          entry.value as Map,
        );
        final int total = (countryData['total'] is int)
            ? countryData['total'] as int
            : 0;

        final Map<String, int> cities = <String, int>{};
        if (countryData['cities'] is Map) {
          final Map<dynamic, dynamic> citiesData = Map<dynamic, dynamic>.from(
            countryData['cities'] as Map,
          );
          for (final MapEntry<dynamic, dynamic> cityEntry
              in citiesData.entries) {
            final String cityName = cityEntry.key.toString();
            final int count = (cityEntry.value is int)
                ? cityEntry.value as int
                : 0;
            if (count > 0) {
              cities[cityName] = count;
            }
          }
        }

        if (total > 0) {
          nodes.add(
            CountryNode(
              country: countryName,
              totalCount: total,
              cities: cities,
            ),
          );
        }
      }

      nodes.sort((a, b) => a.country.compareTo(b.country));

      if (!mounted) {
        return;
      }

      setState(() {
        _countries.clear();
        _countries.addAll(nodes);
        _loading = false;
      });

      await _loadProviderProfile();
    } catch (e) {
      debugPrint('[ReviewRequestScreen] Error loading review_info: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadProviderProfile() async {
    if (_reviewFriendUid == null || _reviewFriendUid!.isEmpty) {
      return;
    }

    try {
      final DataSnapshot pubSnap = await FirebaseDatabase.instance
          .ref('public_profiles/$_reviewFriendUid')
          .get();

      if (pubSnap.exists && pubSnap.value is Map) {
        final Map<dynamic, dynamic> profile = Map<dynamic, dynamic>.from(
          pubSnap.value as Map,
        );
        final String? displayName = (profile['displayName'] is String)
            ? profile['displayName'] as String
            : null;

        if (displayName != null && displayName.isNotEmpty && mounted) {
          setState(() {
            _providerUsername = displayName;
          });
        }
      }
    } catch (e) {
      // Error loading review_info
    }
  }

  void _toggleCountryExpansion(int index) {
    if (!mounted) {
      return;
    }
    setState(() {
      _countries[index].isExpanded = !_countries[index].isExpanded;
    });
  }

  void _selectCountry(int index) {
    if (!mounted) {
      return;
    }
    final CountryNode node = _countries[index];

    setState(() {
      if (node.isCountrySelected) {
        node.isCountrySelected = false;
      } else {
        node.isCountrySelected = true;
        node.selectedCities.clear();
      }
      _recalculateTotal();
    });
  }

  void _toggleCitySelection(int countryIndex, String cityName) {
    if (!mounted) {
      return;
    }
    final CountryNode node = _countries[countryIndex];

    if (node.isCountrySelected) {
      return;
    }

    setState(() {
      if (node.selectedCities.contains(cityName)) {
        node.selectedCities.remove(cityName);
      } else {
        node.selectedCities.add(cityName);
        
        // Check if all cities are now selected
        if (node.selectedCities.length == node.cities.length) {
          // Select the country instead and clear city selections
          node.isCountrySelected = true;
          node.selectedCities.clear();
          node.isExpanded = false;
        }
      }
      _recalculateTotal();
    });
  }

  void _recalculateTotal() {
    int total = 0;
    for (final CountryNode node in _countries) {
      if (node.isCountrySelected) {
        total += node.totalCount;
      } else {
        for (final String cityName in node.selectedCities) {
          total += node.cities[cityName] ?? 0;
        }
      }
    }
    _totalSelectedReviews = total;
  }

  List<Map<String, dynamic>> _buildFiltersArray() {
    final List<Map<String, dynamic>> filters = <Map<String, dynamic>>[];

    for (final CountryNode node in _countries) {
      if (node.isCountrySelected) {
        filters.add(<String, dynamic>{'country': node.country, 'city': null});
      } else {
        for (final String cityName in node.selectedCities) {
          filters.add(<String, dynamic>{
            'country': node.country,
            'city': cityName,
          });
        }
      }
    }

    return filters;
  }

  Future<void> _sendReviewRequest() async {
    final String senderUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (senderUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.signInRequired)));
      }
      return;
    }

    final String toEmail = _providerEmail ?? '';
    if (toEmail.isEmpty) {
      return;
    }

    final List<Map<String, dynamic>> filters = _buildFiltersArray();
    if (filters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStr.selectLocationRequired),
          ),
        );
      }
      return;
    }

    final String comment = _commentCtl.text.trim();
    final String normalized =
        _checkedNormalized ?? normalizeEmailForPath(toEmail.toLowerCase());
    String recipientUid = '';
    Map<dynamic, dynamic>? mapping;

    if (_reviewFriendUid != null && _reviewFriendUid!.isNotEmpty) {
      recipientUid = _reviewFriendUid!;
      try {
        final DataSnapshot pub = await FirebaseDatabase.instance
            .ref('public_profiles/$recipientUid')
            .get();
        if (pub.exists && pub.value != null && pub.value is Map) {
          mapping = Map<dynamic, dynamic>.from(pub.value as Map);
        }
      } catch (_) {}
    } else {
      DataSnapshot snap;
      try {
        snap = await FirebaseDatabase.instance
            .ref('users_by_email/$normalized')
            .get();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(AppStr.requestSendFailed)));
        }
        return;
      }

      if (!snap.exists || snap.value == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
        }
        return;
      }

      final Object? raw = snap.value;
      if (raw is Map) {
        mapping = Map<dynamic, dynamic>.from(raw);
        if (mapping['uid'] != null) {
          recipientUid = mapping['uid'].toString();
        }
      } else if (raw is String) {
        recipientUid = raw;
      }
    }

    if (recipientUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.userNotFound)));
      }
      return;
    }

    if (recipientUid == senderUid) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.cannotAddSelf)));
      }
      return;
    }

    try {
      if (mapping != null && mapping.containsKey('acceptsFriends')) {
        final dynamic af = mapping['acceptsFriends'];
        bool allows = true;
        if (af is bool) {
          allows = af;
        } else if (af is String) {
          allows = af.toLowerCase() == 'true';
        } else if (af is num) {
          allows = af != 0;
        }
        if (!allows) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppStr.friendRequestsDisabled)),
            );
          }
          return;
        }
      }
    } catch (_) {
      // ignore
    }

    String recipientEmail = toEmail;
    String recipientDisplayName = toEmail;
    try {
      final Map<String, String> resolved =
          await _resolveRecipientFromMappingOrPublic(recipientUid, mapping);
      recipientEmail = resolved['email']!;
      recipientDisplayName = resolved['username']!;
    } catch (_) {
      // ignore
    }

    final String clientRequestId = DateTime.now().millisecondsSinceEpoch
        .toString();
    final String fromEmail =
        (await SessionCache.getSavedEmail()) ??
        FirebaseAuth.instance.currentUser?.email ??
        '';
    final String fromDisplayName =
        (await SessionCache.getSavedDisplayName()) ??
        (FirebaseAuth.instance.currentUser?.displayName ?? fromEmail);

    final Map<String, dynamic> updates = <String, dynamic>{};
    final String mailboxPath =
        'users_by_email/$normalized/requests/$clientRequestId';

    updates[mailboxPath] = <String, dynamic>{
      'statusCode': 3,
      'type': 'review_request',
      'fromUid': senderUid,
      'fromEmail': fromEmail,
      'fromDisplayName': fromDisplayName,
      'comment': comment,
      'filters': filters,
      'createdAt': DateTime.now().toIso8601String(),
      'clientRequestId': clientRequestId,
    };

    updates['users/$senderUid/friends/$recipientUid'] = <String, dynamic>{
      'statusCode': statusRvAsked,
      'email': recipientEmail,
      'username': recipientDisplayName,
      'comment': comment,
      'clientRequestId': clientRequestId,
      'mailboxReqId': clientRequestId,
      'mailboxNormalized': normalized,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    if (!mounted) {
      return;
    }
    setState(() {
      _sending = true;
    });

    try {
      await _updateWithRetry(updates, maxAttempts: 3);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStr.requestSent)));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      return;
    } on FirebaseException catch (fe) {
      try {
        final DataSnapshot existing = await FirebaseDatabase.instance
            .ref(mailboxPath)
            .get();
        if (existing.exists &&
            existing.value != null &&
            existing.value is Map) {
          final Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(
            existing.value as Map,
          );
          if (m['clientRequestId'] != null &&
              m['clientRequestId'].toString() == clientRequestId) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(AppStr.requestSent)));
            if (!mounted) {
              return;
            }
            Navigator.of(context).pop(true);
            return;
          }
        }
      } catch (_) {
        // ignore
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppStr.requestSendFailed}: ${fe.message ?? fe.code}',
          ),
        ),
      );
      return;
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStr.requestSendFailed}: $e')),
      );
      return;
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<Map<String, String>> _resolveRecipientFromMappingOrPublic(
    String uid,
    Map<dynamic, dynamic>? mapping,
  ) async {
    String email = '';
    String username = '';

    if (mapping != null) {
      if (mapping['email'] is String &&
          (mapping['email'] as String).isNotEmpty) {
        email = mapping['email'] as String;
      }
      if (mapping['displayName'] is String &&
          (mapping['displayName'] as String).isNotEmpty) {
        username = mapping['displayName'] as String;
      } else if (mapping['userName'] is String &&
          (mapping['userName'] as String).isNotEmpty) {
        username = mapping['userName'] as String;
      }
    }

    if (username.isEmpty || email.isEmpty) {
      try {
        final DataSnapshot pub = await FirebaseDatabase.instance
            .ref('public_profiles/$uid')
            .get();
        if (pub.exists && pub.value != null && pub.value is Map) {
          final Map<dynamic, dynamic> pm = Map<dynamic, dynamic>.from(
            pub.value as Map,
          );
          if (pm['displayName'] is String &&
              (pm['displayName'] as String).isNotEmpty) {
            username = pm['displayName'] as String;
          }
          if (pm['email'] is String && (pm['email'] as String).isNotEmpty) {
            email = pm['email'] as String;
          }
        }
      } catch (_) {
        // ignore
      }
    }

    if (email.isEmpty) {
      email = uid;
    }
    if (username.isEmpty) {
      username = email;
    }
    return <String, String>{'email': email, 'username': username};
  }

  Future<void> _updateWithRetry(
    Map<String, dynamic> updates, {
    int maxAttempts = 3,
  }) async {
    int attempt = 0;
    while (true) {
      attempt += 1;
      try {
        await FirebaseDatabase.instance.ref().update(updates);
        return;
      } catch (e) {
        if (attempt >= maxAttempts) {
          rethrow;
        }
        final int backoffMs = 150 * (1 << (attempt - 1));
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sendEnabled =
        !_loading && !_sending && _totalSelectedReviews > 0;

    final String providerDisplay = _providerEmail ?? '';
    final String providerInfo =
        _providerUsername != null && _providerUsername!.isNotEmpty
        ? '$providerDisplay ($_providerUsername)'
        : providerDisplay;

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        backgroundColor: AppColors.darkGreen,
        title: Text(
          AppStr.requestReviewsTitle,
          style: AppFonts.bold.copyWith(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${AppStr.toLabel} $providerInfo',
                            style: AppFonts.bold.copyWith(fontSize: 16),
                          ),
                          const SizedBox(height: 16),

                          TextField(
                            controller: _commentCtl,
                            decoration: InputDecoration(
                              labelText: AppStr.requestCommentLabel,
                            ),
                            keyboardType: TextInputType.text,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 20),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.darkGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${AppStr.reviewsSelected} $_totalSelectedReviews',
                              style: AppFonts.bold.copyWith(
                                fontSize: 18,
                                color: AppColors.darkGreen,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (_countries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Center(
                                child: Text(
                                  AppStr.noReviewsAvailable,
                                  style: AppFonts.standard.copyWith(
                                    fontSize: 16,
                                    color: AppColors.grey,
                                  ),
                                ),
                              ),
                            )
                          else
                            ..._countries.asMap().entries.map((entry) {
                              final int index = entry.key;
                              final CountryNode node = entry.value;
                              return _buildCountryTile(index, node);
                            }),
                        ],
                      ),
                    ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.transparent,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: () {
                          if (!mounted) {
                            return;
                          }
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ochre,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(
                          AppStr.back,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                          style: AppFonts.bold,
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: sendEnabled
                            ? () async {
                                await _sendReviewRequest();
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: sendEnabled
                              ? AppColors.darkGreen
                              : AppColors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(0, 44),
                          textStyle: AppFonts.bold,
                        ),
                        child: Text(
                          'REQUEST',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                          style: AppFonts.bold.copyWith(color: Colors.white),
                        ),
                      ),
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

  Widget _buildCountryTile(int index, CountryNode node) {
    final bool isSelected = node.isCountrySelected;
    final bool hasCitySelections = node.hasAnyCitySelected;
    final Color countryBackgroundColor = isSelected
        ? AppColors.ochre.withValues(alpha: 0.6)
        : hasCitySelections
            ? AppColors.ochre.withValues(alpha: 0.3)
            : Colors.transparent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: countryBackgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: IconButton(
              icon: Icon(
                node.isExpanded ? Icons.expand_more : Icons.chevron_right,
              ),
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(),
              onPressed: () {
                _toggleCountryExpansion(index);
              },
            ),
            title: Row(
              children: <Widget>[
                Checkbox(
                  value: isSelected,
                  onChanged: (bool? value) {
                    _selectCountry(index);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${node.country} (${node.totalCount})',
                    style: AppFonts.bold.copyWith(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (node.isExpanded && !isSelected)
          ...node.cities.entries.map((cityEntry) {
            final String cityName = cityEntry.key;
            final int cityCount = cityEntry.value;
            final bool isCitySelected = node.selectedCities.contains(
              cityName,
            );
            final Color cityBgColor = isCitySelected
                ? AppColors.ochre.withValues(alpha: 0.3)
                : Colors.transparent;

            return Container(
              margin: const EdgeInsets.only(left: 40, top: 4),
              decoration: BoxDecoration(
                color: cityBgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListTile(
                leading: Checkbox(
                  value: isCitySelected,
                  onChanged: (bool? value) {
                    _toggleCitySelection(index, cityName);
                  },
                ),
                title: Text(
                  '$cityName ($cityCount)',
                  style: AppFonts.standard.copyWith(fontSize: 14),
                ),
                onTap: () {
                  _toggleCitySelection(index, cityName);
                },
              ),
            );
          }),
        const SizedBox(height: 8),
      ],
    );
  }
}
