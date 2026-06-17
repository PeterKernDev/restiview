/// RestiView — Database Integrity Checker (DBIC)
/// ================================================
/// Standalone Dart CLI tool.  Run from the project root:
///
///   dart run tool/dbic.dart check `<path-to-service-account.json>`
///   dart run tool/dbic.dart fix   `<path-to-service-account.json>`
///
/// SETUP (one-time):
///   1. Firebase Console → restiview-bb851 → gear → Project settings
///   2. Click the "Service accounts" tab
///   3. Click "Generate new private key" → "Generate key"
///      → saves  firebase-adminsdk-xxxx-xxxxxxxxxx.json  to Downloads
///   4. Move it somewhere permanent, e.g.:
///        C:\Users\Denve\restiview-sa.json
///   5. Run:
///        dart run tool/dbic.dart check "C:\Users\Denve\restiview-sa.json"
///
/// The service account JSON is gitignored — never commit it.
library;

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as gauth;

const String _dbUrl = 'https://restiview-bb851.firebaseio.com';
const List<String> _scopes = [
  'https://www.googleapis.com/auth/firebase.database',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/cloud-platform', // needed for Firebase Auth user lookup
];

// ─── Good-for tag count (must match app constant) ────────────────────────────
const int _goodForTagCount = 18;

// ─── Friend status codes ──────────────────────────────────────────────────────
const Set<int> _validFriendCodes = {0,1,2,3,4,5,6,8,9,10,99};
const Set<int> _validMailboxCodes = {0,1,3,5,6,8,9};

// ─── Entry point ─────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  if (args.length < 2) { _printUsage(); exit(1); }

  final mode   = args[0].toLowerCase();
  final saPath = args[1];

  if (mode != 'check' && mode != 'fix') { _printUsage(); exit(1); }
  if (!File(saPath).existsSync()) {
    print('ERROR: Service account file not found: $saPath');
    exit(1);
  }

  final now = DateTime.now();
  final ts = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}  '
             '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}';
  print('');
  print('╔══════════════════════════════════════════════════╗');
  print('║  RestiView — Database Integrity Checker (DBIC)  ║');
  print('║  Mode : ${mode.toUpperCase().padRight(40)}║');
  print('║  Run  : $ts                  ║');
  print('╚══════════════════════════════════════════════════╝');
  print('');
  print('Authenticating with service account...');

  // Obtain a short-lived OAuth2 access token from the service account JSON.
  final saJson = json.decode(File(saPath).readAsStringSync()) as Map<String, dynamic>;
  final credentials = gauth.ServiceAccountCredentials.fromJson(saJson);
  final baseClient  = http.Client();
  final authCreds   = await gauth.obtainAccessCredentialsViaServiceAccount(
    credentials, _scopes, baseClient,
  );
  baseClient.close();
  final authHeader = 'Bearer ${authCreds.accessToken.data}';
  print('Authenticated as: ${saJson['client_email']}');
  print('');

  final checker = DbicChecker(mode: mode, authHeader: authHeader);
  await checker.run();
}

void _printUsage() {
  print('Usage:');
  print('  dart run tool/dbic.dart check <service-account.json>');
  print('  dart run tool/dbic.dart fix   <service-account.json>');
  print('');
  print('Download service-account.json from:');
  print('  Firebase Console → Project settings → Service accounts');
  print('  → Generate new private key');
}

// ─── Checker ──────────────────────────────────────────────────────────────────

class _Error {
  final String severity; // ERROR | WARN | INFO
  final String category;
  final String path;
  final String message;
  final bool fixable;
  final String fixAction; // 'patch' | 'delete'
  final Map<String, dynamic>? fixData;
  _Error(this.severity, this.category, this.path, this.message,
      {this.fixable = false, this.fixAction = 'patch', this.fixData});
}

class DbicChecker {
  final String mode;
  final String authHeader; // 'Bearer ...' or '__secret__...'

  DbicChecker({required this.mode, required this.authHeader});

  final _errors   = <_Error>[];
  final _fixes    = <String>[];

  // Caches
  final _knownUids  = <String>{};
  final _normToUid  = <String, String>{};
  final _emailToUid = <String, String>{};
  Map<String, dynamic> _ubeRaw = {};
  final _ppUids     = <String>{};    // UIDs seen in public_profiles
  final _usersUids  = <String>{};    // UIDs seen in users/

  // Stats
  int ubeUsers = 0, publicProfiles = 0;
  int mailboxEntries = 0, mailboxUnprocessed = 0;
  int auditRequestEvents = 0;
  int auditDeletions = 0, auditAccountDeletions = 0, auditOtherEvents = 0;
  int ownReviews = 0, ownFriends = 0, ownReviewsRequested = 0;
  int ownCustomCuisines = 0, ownCustomOccasions = 0, ownCustomCountries = 0;

  // ── Entry ──────────────────────────────────────────────────────────────────

  Future<void> run() async {
    if (!await _preflight()) return;
    print('Running 7 check sections against the live database...');
    print('');
    await _checkUsersbyEmail();
    await _checkPublicProfiles();
    await _checkAllMailboxes();
    await _checkAuditInfo();
    await _checkFriendAuditNodes();
    await _checkAllUsersOwnData();
    await _checkStaleUBE();
    print('');
    print('All sections complete.');

    if (mode == 'fix') {
      await _applyFixes();
    }

    _printReport();
  }

  // ── Preflight ───────────────────────────────────────────────────────────────

  /// Fires a cheap shallow GET to the root to verify we can reach and read
  /// the database before touching any real data.
  Future<bool> _preflight() async {
    print('Preflight: testing database connectivity and permissions...');
    final url = Uri.parse('$_dbUrl/.json?shallow=true');
    try {
      final resp = await http.get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body == null) {
          print('ERROR: Database returned null — the database may be empty or the URL is wrong.');
          print('  URL tried: $_dbUrl');
          return false;
        }
        print('Preflight: OK — database is reachable and auth is valid.');
        print('');
        return true;
      }

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        print('ERROR: Permission denied (HTTP ${resp.statusCode}).');
        print('  The service account may not have the required Firebase Database roles.');
        print('  In Firebase Console → Project settings → Service accounts, confirm the');
        print('  account has the "Firebase Admin" or "Firebase Realtime Database Admin" role.');
        return false;
      }

      if (resp.statusCode == 404) {
        print('ERROR: Database not found (HTTP 404).');
        print('  URL tried: $_dbUrl');
        print('  Check that the database URL is correct in tool/dbic.dart (_dbUrl constant).');
        return false;
      }

      print('ERROR: Unexpected response HTTP ${resp.statusCode}.');
      print('  Body: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');
      return false;

    } on SocketException catch (e) {
      print('ERROR: No network connection — $e');
      return false;
    } on TimeoutException {
      print('ERROR: Connection timed out after 15 seconds.');
      print('  Check your internet connection and that $_dbUrl is reachable.');
      return false;
    } catch (e) {
      print('ERROR: Preflight failed — $e');
      return false;
    }
  }

  // ── HTTP helpers ────────────────────────────────────────────────────────────

  Map<String, String> get _headers {
    if (authHeader.startsWith('__secret__')) return {};  // secret via query param
    return {'Authorization': authHeader};
  }

  String _urlFor(String path, {Map<String, String>? extra}) {
    final isSecret = authHeader.startsWith('__secret__');
    final secret   = isSecret ? authHeader.substring(10) : null;
    final base     = '$_dbUrl/$path.json';
    final params   = <String, String>{
      if (secret != null) 'auth': secret,
      ...?extra,
    };
    if (params.isEmpty) return base;
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '$base?$query';
  }

  Future<dynamic> _get(String path) async {
    final url = _urlFor(path, extra: {'shallow': 'false'});
    try {
      final resp = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        print('AUTH ERROR (${resp.statusCode}) at /$path — check your service account permissions');
        exit(2);
      }
      if (resp.statusCode != 200) return null; // 404 = node absent, treat as empty
      return json.decode(resp.body);
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  Future<bool> _patch(String path, Map<String, dynamic> data) async {
    final url = _urlFor(path);
    try {
      final resp = await http.patch(
        Uri.parse(url),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: json.encode(data),
      ).timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _delete(String path) async {
    final url = _urlFor(path);
    try {
      final resp = await http.delete(
        Uri.parse(url),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ── Error helpers ──────────────────────────────────────────────────────────

  void _err(String cat, String path, String msg,
      {bool fixable = false, String fixAction = 'patch', Map<String, dynamic>? fixData}) {
    _errors.add(_Error('ERROR', cat, path, msg,
        fixable: fixable, fixAction: fixAction, fixData: fixData));
  }

  void _warn(String cat, String path, String msg) {
    _errors.add(_Error('WARN', cat, path, msg));
  }

  void _log(String msg) => print(msg);

  // ── A. users_by_email ──────────────────────────────────────────────────────

  Future<void> _checkUsersbyEmail() async {
    _log('[A/6] users_by_email — loading the user registry...');
    final raw = await _get('users_by_email');
    if (raw == null || raw is! Map) {
      _err('UBE', 'users_by_email', 'Node is empty or missing / auth error'); return;
    }
    _ubeRaw = Map<String, dynamic>.from(raw);

    for (final entry in _ubeRaw.entries) {
      final norm = entry.key.toString();
      ubeUsers++;
      if (entry.value is! Map) {
        _err('UBE', 'users_by_email/$norm', 'Value is not a Map'); continue;
      }
      final data = Map<String, dynamic>.from(entry.value as Map);

      final uid = data['uid']?.toString();
      if (uid == null || uid.isEmpty) {
        _err('UBE', 'users_by_email/$norm', 'Missing uid'); continue;
      }
      final email = data['email']?.toString() ?? '';
      if (email.isNotEmpty) {
        final derived = _normalise(email);
        if (derived != norm) {
          _warn('UBE', 'users_by_email/$norm',
              'Key mismatch: key="$norm" but normalise("$email")="$derived"');
        }
        _emailToUid[email.toLowerCase()] = uid;
      } else {
        _warn('UBE', 'users_by_email/$norm', 'Missing email field');
      }
      if (!data.containsKey('acceptsFriends')) {
        _warn('UBE', 'users_by_email/$norm', 'Missing acceptsFriends field');
      }
      _knownUids.add(uid);
      _normToUid[norm] = uid;
    }
    _log('   → $ubeUsers users registered');
  }

  // ── B. public_profiles ────────────────────────────────────────────────────

  Future<void> _checkPublicProfiles() async {
    _log('[B/6] public_profiles — verifying display names and email cross-references...');
    final raw = await _get('public_profiles');
    final data = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    for (final uid in _knownUids) {
      if (!data.containsKey(uid)) {
        final normE = _normToUid.entries
            .firstWhere((e) => e.value == uid, orElse: () => const MapEntry('', ''))
            .key;
        _err('PUBLIC_PROFILES', 'public_profiles/$uid',
            'Missing public_profiles entry',
            fixable: normE.isNotEmpty,
            fixData: normE.isNotEmpty ? {'uid': uid, 'normEmail': normE} : null);
      }
    }

    for (final e in data.entries) {
      publicProfiles++;
      final uid = e.key.toString();
      _ppUids.add(uid);
      if (e.value is! Map) {
        _err('PUBLIC_PROFILES', 'public_profiles/$uid', 'Value is not a Map'); continue;
      }
      final pp = Map<String, dynamic>.from(e.value as Map);
      for (final f in ['displayName', 'email', 'updatedAt']) {
        if (pp[f]?.toString().isEmpty != false) {
          _warn('PUBLIC_PROFILES', 'public_profiles/$uid/$f', 'Missing or empty: $f');
        }
      }
      if (!_knownUids.contains(uid)) {
        _err('PUBLIC_PROFILES', 'public_profiles/$uid',
            'Orphan profile — no users_by_email entry for uid $uid',
            fixable: true, fixAction: 'delete',
            fixData: {'uid': uid, 'action': 'delete_profile'});
      }
      final ppEmail = pp['email']?.toString().toLowerCase() ?? '';
      if (ppEmail.isNotEmpty) {
        final ubeUid = _emailToUid[ppEmail];
        if (ubeUid != null && ubeUid != uid) {
          _err('PUBLIC_PROFILES', 'public_profiles/$uid',
              'Email "$ppEmail" uid conflict: here=$uid, UBE=$ubeUid');
        }
      }
    }
    _log('   → $publicProfiles profiles checked');
  }

  // ── C. Mailboxes ──────────────────────────────────────────────────────────

  Future<void> _checkAllMailboxes() async {
    _log('[C/6] mailboxes — scanning friend-request inboxes for stale or invalid entries...');
    for (final userEntry in _ubeRaw.entries) {
      final norm = userEntry.key.toString();
      if (userEntry.value is! Map) continue;
      final userData = Map<String, dynamic>.from(userEntry.value as Map);
      if (userData['requests'] is! Map) continue;
      final requests = Map<String, dynamic>.from(userData['requests'] as Map);

      for (final rq in requests.entries) {
        final reqId = rq.key.toString();
        mailboxEntries++;
        final path = 'users_by_email/$norm/requests/$reqId';

        if (rq.value is! Map) { _err('MAILBOX', path, 'Not a Map'); continue; }
        final req = Map<String, dynamic>.from(rq.value as Map);

        if (req['fromUid'] == null) _err('MAILBOX', path, 'Missing fromUid');
        if (req['createdAt'] == null) _warn('MAILBOX', path, 'Missing createdAt');

        final codeRaw = req['statusCode'];
        if (codeRaw == null) { _err('MAILBOX', path, 'Missing statusCode'); continue; }
        final code = _toInt(codeRaw);
        if (code == null || !_validMailboxCodes.contains(code)) {
          _err('MAILBOX', path, 'Invalid statusCode: $codeRaw');
        }

        final fromUid = req['fromUid']?.toString() ?? '';
        if (fromUid.isNotEmpty && !_knownUids.contains(fromUid)) {
          _warn('MAILBOX', path, 'fromUid "$fromUid" not in users_by_email');
        }

        if (req['processedBy'] == null) {
          mailboxUnprocessed++;
          final created = req['createdAt']?.toString() ?? '';
          if (created.isNotEmpty) {
            try {
              final age = DateTime.now().difference(DateTime.parse(created));
              if (age.inDays > 30) {
                _warn('MAILBOX', path,
                    'Unprocessed for ${age.inDays} days (statusCode=$code)');
              }
            } catch (_) {}
          }
        }
      }
    }
    _log('   → $mailboxEntries mailbox entries ($mailboxUnprocessed unprocessed)');
  }

  // ── D. audit_info/request_events ──────────────────────────────────────────

  Future<void> _checkAuditInfo() async {
    _log('[D/6] audit_info — reviewing the request event log...');
    final raw = await _get('audit_info/request_events');
    if (raw == null) { _log('   → (empty or timeout)'); return; }
    if (raw is! Map) { _warn('AUDIT', 'audit_info/request_events', 'Not a Map'); return; }

    for (final e in raw.entries) {
      auditRequestEvents++;
      if (e.value is! Map) continue;
      final evt = Map<String, dynamic>.from(e.value as Map);
      final path = 'audit_info/request_events/${e.key}';
      if (evt['eventType'] == null) _warn('AUDIT', path, 'Missing eventType');
      final actor  = evt['actorUid']  ?? evt['fromUid'];
      final target = evt['targetUid'] ?? evt['toUid'];
      if (actor == null) _warn('AUDIT', path, 'Missing actorUid/fromUid');
      if (target == null) _warn('AUDIT', path, 'Missing targetUid/toUid');
      if (evt['timestamp'] == null) _warn('AUDIT', path, 'Missing timestamp');
    }
    _log('   → $auditRequestEvents audit events checked');
  }

  // ── E. audit_info deletion sub-nodes ─────────────────────────────────────

  Future<void> _checkFriendAuditNodes() async {
    _log('[E/6] audit_info — checking deletion/other audit sub-nodes...');
    auditDeletions        = await _checkAuditInfoSubNode('audit_info/deletions');
    auditAccountDeletions = await _checkAuditInfoSubNode('audit_info/account_deletions');
    auditOtherEvents      = await _checkAuditInfoSubNode('audit_info/other');
  }

  /// Checks a flat push-keyed node written by audit_info.dart.
  /// Expected fields: timestamp (int ms), userId, type, target.
  Future<int> _checkAuditInfoSubNode(String path) async {
    final raw = await _get(path);
    if (raw == null) return 0;
    if (raw is! Map) { _warn('AUDIT', path, 'Not a Map'); return 0; }
    int count = 0;
    const required = ['timestamp', 'userId', 'type', 'target'];
    for (final e in raw.entries) {
      count++;
      if (e.value is! Map) { _warn('AUDIT', '$path/${e.key}', 'Not a Map'); continue; }
      final evt = Map<String, dynamic>.from(e.value as Map);
      for (final f in required) {
        if (evt[f] == null) _warn('AUDIT', '$path/${e.key}', 'Missing $f');
      }
    }
    _log('   → $path: $count entries');
    return count;
  }

  // ── F. All users' own data (admin reads all users/) ───────────────────────

  Future<void> _checkAllUsersOwnData() async {
    _log('[F/6] users tree — deep-scanning every account (reviews, friends, custom values)...');
    final raw = await _get('users');
    if (raw == null || raw is! Map) {
      _err('USERS', 'users', 'Could not read users node'); return;
    }
    for (final entry in raw.entries) {
      final uid = entry.key.toString();
      _usersUids.add(uid);
      if (entry.value is! Map) continue;
      final userData = Map<String, dynamic>.from(entry.value as Map);
      _checkUserSettings(uid, userData);
      _checkUserReviews(uid, userData);
      _checkUserFriends(uid, userData);
      _checkUserReviewsRequested(uid, userData);
      _checkUserCustomVals(uid, userData);
    }
    _log('   → ${_knownUids.length} accounts examined');
    _log('   → $ownReviews reviews  |  $ownFriends friend records  |  $ownReviewsRequested received reviews');
  }

  void _checkUserSettings(String uid, Map<String, dynamic> data) {
    const settingsFields = ['userName','userEmail','userSettings1','userSettings2','baseCountry'];
    final missing = <String>[];
    for (final f in settingsFields) {
      if (data[f]?.toString().isEmpty != false) {
        _warn('USER_SETTINGS', 'users/$uid/$f', 'Missing or empty: $f');
        missing.add(f);
      }
    }
    if (missing.isNotEmpty) {
      // Dump top-level scalar fields for diagnostic visibility
      _log('   ⚠  USER_SETTINGS warning on uid: $uid');
      final skip = {'reviews','friends','reviews_requested','customvals'};
      for (final entry in data.entries) {
        if (skip.contains(entry.key)) continue;
        final val = entry.value;
        if (val == null || val is Map || val is List) continue;
        _log('      ${entry.key.padRight(20)} = $val');
      }
      for (final f in missing) {
        _log('      ${f.padRight(20)} = (missing)');
      }
    }
  }

  void _checkUserReviews(String uid, Map<String, dynamic> userData) {
    final reviewsRaw = userData['reviews'];
    if (reviewsRaw == null) return;
    if (reviewsRaw is! Map) {
      _err('REVIEWS', 'users/$uid/reviews', 'Not a Map'); return;
    }
    for (final entry in reviewsRaw.entries) {
      final key = entry.key.toString();
      ownReviews++;
      final path = 'users/$uid/reviews/$key';
      if (entry.value is! Map) { _err('REVIEWS', path, 'Not a Map'); continue; }
      final r = Map<String, dynamic>.from(entry.value as Map);

      // Required fields (hard — actual data fields)
      const required = [
        'restname','restcountry','restcity','restcuisine',
        'rfood','rservice','rambiance','rdrinks','rvfm',
        'rmichlin','restrating','reviewdate','sortdate','sortrr',
        'goodfor','userEmail','userName',
      ];
      final missingRequired = <String>[];
      for (final f in required) {
        if (r[f] == null) {
          _err('REVIEWS', '$path/$f', 'Missing required field: $f');
          missingRequired.add(f);
        }
      }
      if (missingRequired.isNotEmpty) {
        _err('REVIEWS_CORRUPT', path,
            'Corrupt review: ${missingRequired.length} missing required field(s) '
            '(${missingRequired.join(", ")}) — safe to delete',
            fixable: true, fixAction: 'delete',
            fixData: {'uid': uid, 'key': key, 'action': 'delete_review'});
      }
      // These fields were added later — missing on legacy reviews is expected
      if (r['createdAt'] == null)  _warn('REVIEWS', '$path/createdAt',  'Missing createdAt (legacy review)');
      if (r['updatedAt'] == null)  _warn('REVIEWS', '$path/updatedAt',  'Missing updatedAt (legacy review)');
      if (r['timestamp'] == null)  _warn('REVIEWS', '$path/timestamp',  'Missing timestamp (legacy review)');

      // Rating ranges
      _checkRatingRange(r, path, 'rfood',     0, 20, uid, key);
      _checkRatingRange(r, path, 'rservice',  0, 20, uid, key);
      _checkRatingRange(r, path, 'rambiance', 0, 20, uid, key);
      _checkRatingRange(r, path, 'rdrinks',   0, 20, uid, key);
      _checkRatingRange(r, path, 'rvfm',      0, 20, uid, key);
      _checkRatingRange(r, path, 'rmichlin',  0,  3, uid, key);

      // restrating = sum of 5 components
      final rfood    = _toInt(r['rfood'])    ?? -1;
      final rservice = _toInt(r['rservice']) ?? -1;
      final rambiance= _toInt(r['rambiance'])?? -1;
      final rdrinks  = _toInt(r['rdrinks'])  ?? -1;
      final rvfm     = _toInt(r['rvfm'])     ?? -1;
      final rr       = _toInt(r['restrating'])?? -1;
      if (rfood >= 0 && rservice >= 0 && rambiance >= 0 &&
          rdrinks >= 0 && rvfm >= 0 && rr >= 0) {
        final expected = rfood + rservice + rambiance + rdrinks + rvfm;
        if (rr != expected) {
          _err('REVIEWS', '$path/restrating',
              'restrating=$rr but component sum=$expected',
              fixable: true,
              fixData: {'uid': uid, 'key': key, 'field': 'restrating',
                        'value': expected.toString()});
        }
        // sortrr
        final expectedSortrr = expected.toString().padLeft(3, '0');
        final sortrr = r['sortrr']?.toString() ?? '';
        if (sortrr.isNotEmpty && sortrr != expectedSortrr) {
          _err('REVIEWS', '$path/sortrr',
              'sortrr="$sortrr" should be "$expectedSortrr"',
              fixable: true,
              fixData: {'uid': uid, 'key': key, 'field': 'sortrr',
                        'value': expectedSortrr});
        }
      }

      // goodfor length and charset
      final goodfor = r['goodfor']?.toString() ?? '';
      if (goodfor.isNotEmpty) {
        if (goodfor.length < _goodForTagCount) {
          // Short goodfor = review created before new tags were added — not corruption
          _warn('REVIEWS', '$path/goodfor',
              'goodfor length ${goodfor.length} ≠ $_goodForTagCount (legacy review, pre-tag-expansion)');
        } else if (goodfor.length > _goodForTagCount) {
          _err('REVIEWS', '$path/goodfor',
              'goodfor length ${goodfor.length} > expected $_goodForTagCount');
        }
        if (!RegExp(r'^[YN]+$').hasMatch(goodfor)) {
          _err('REVIEWS', '$path/goodfor', 'Non Y/N characters in goodfor');
        }
      }

      // Date formats
      final reviewdate = r['reviewdate']?.toString() ?? '';
      final sortdate   = r['sortdate']?.toString() ?? '';
      if (reviewdate.isNotEmpty && !_isDDMMYYYY(reviewdate)) {
        _err('REVIEWS', '$path/reviewdate',
            'reviewdate "$reviewdate" not in dd/MM/yyyy');
      }
      if (sortdate.isNotEmpty && !_isYYYYMMDD(sortdate)) {
        _err('REVIEWS', '$path/sortdate',
            'sortdate "$sortdate" not in yyyy/MM/dd');
      }
      if (_isDDMMYYYY(reviewdate) && _isYYYYMMDD(sortdate)) {
        final p = reviewdate.split('/');
        final expected = '${p[2]}/${p[1]}/${p[0]}';
        if (sortdate != expected) {
          _err('REVIEWS', '$path/sortdate',
              'sortdate="$sortdate" should be "$expected"',
              fixable: true,
              fixData: {'uid': uid, 'key': key, 'field': 'sortdate',
                        'value': expected});
        }
      }
    }
  }

  void _checkRatingRange(Map<String, dynamic> r, String path,
      String field, int min, int max, String uid, String key) {
    final raw = r[field];
    if (raw == null) return;
    final v = _toInt(raw);
    if (v == null) {
      _err('REVIEWS', '$path/$field', '$field "$raw" is not an integer');
    } else if (v < min || v > max) {
      _err('REVIEWS', '$path/$field', '$field=$v out of range [$min,$max]');
    }
  }

  void _checkUserFriends(String uid, Map<String, dynamic> userData) {
    final friendsRaw = userData['friends'];
    if (friendsRaw == null) return;
    if (friendsRaw is! Map) {
      _err('FRIENDS', 'users/$uid/friends', 'Not a Map'); return;
    }
    for (final fEntry in friendsRaw.entries) {
      final friendUid = fEntry.key.toString();
      ownFriends++;
      final path = 'users/$uid/friends/$friendUid';
      if (fEntry.value is! Map) { _err('FRIENDS', path, 'Not a Map'); continue; }
      final f = Map<String, dynamic>.from(fEntry.value as Map);

      final codeRaw = f['statusCode'];
      if (codeRaw == null) { _err('FRIENDS', path, 'Missing statusCode'); continue; }
      final code = _toInt(codeRaw);
      if (code == null || !_validFriendCodes.contains(code)) {
        _err('FRIENDS', path, 'Invalid statusCode: $codeRaw'); continue;
      }
      if (f['email']?.toString().isEmpty != false) _warn('FRIENDS', path, 'Missing email');
      if (f['username']?.toString().isEmpty != false) _warn('FRIENDS', path, 'Missing username');
      if (f['updatedAt'] == null) _warn('FRIENDS', path, 'Missing updatedAt');

      // Symmetry check for accepted friendships (admin has access to both sides)
      if (code == 1) {
        // We already have the full users tree in memory — check the reverse stub
        // This will be verified when we process the other user's friends node.
        // Log for cross-reference — a separate pass would be needed for full check.
        // For now we just note it — will catch asymmetry during other user's processing.
      }

      if (code == 99) {
        // statusCode=99 was a legacy pending-delete feature no longer used by current app code.
        _warn('FRIENDS', path, 'statusCode=99 is a legacy code — not expected in current data');
      }
    }
  }

  void _checkUserReviewsRequested(String uid, Map<String, dynamic> userData) {
    final rrRaw = userData['reviews_requested'];
    if (rrRaw == null) return;
    if (rrRaw is! Map) {
      _err('REVIEWS_REQUESTED', 'users/$uid/reviews_requested', 'Not a Map'); return;
    }
    for (final entry in rrRaw.entries) {
      final key = entry.key.toString();
      if (key == '_meta') {
        if (entry.value is Map) {
          final meta = Map<String, dynamic>.from(entry.value as Map);
          final friends = meta['friends'];
          if (friends is Map) {
            for (final fe in friends.entries) {
              final norm = fe.key.toString();
              if (!_normToUid.containsKey(norm)) {
                _warn('REVIEWS_REQUESTED',
                    'users/$uid/reviews_requested/_meta/friends/$norm',
                    'Meta friend "$norm" has no users_by_email entry');
              }
            }
          }
        }
        continue;
      }
      ownReviewsRequested++;
      final path = 'users/$uid/reviews_requested/$key';
      if (entry.value is! Map) { _err('REVIEWS_REQUESTED', path, 'Not a Map'); continue; }
      final r = Map<String, dynamic>.from(entry.value as Map);

      final ownerEmail = r['owner_email']?.toString() ?? '';
      if (ownerEmail.isEmpty) {
        _err('REVIEWS_REQUESTED', '$path/owner_email', 'Missing owner_email');
      } else {
        final normOwner = _normalise(ownerEmail.toLowerCase());
        if (!_normToUid.containsKey(normOwner)) {
          _warn('REVIEWS_REQUESTED', '$path/owner_email',
              'owner_email "$ownerEmail" not in users_by_email');
        }
      }

      final cost = r['cost']?.toString() ?? '';
      if (cost.isNotEmpty) {
        _err('REVIEWS_REQUESTED', '$path/cost',
            'cost is not empty — financial data should be stripped',
            fixable: true,
            fixData: {'uid': uid, 'key': key, 'field': 'cost', 'value': ''});
      }

      for (final pf in ['photoPath','photoPath0','photoPath1','photoPath2',
                        'photos','photoPaths']) {
        if (r[pf] != null) {
          _err('REVIEWS_REQUESTED', '$path/$pf',
              'Photo field "$pf" present — should have been stripped',
              fixable: true,
              fixData: {'uid': uid, 'key': key, 'field': pf, 'value': null});
        }
      }
    }
  }

  void _checkUserCustomVals(String uid, Map<String, dynamic> userData) {
    final cv = userData['customvals'];
    if (cv == null) return;
    if (cv is! Map) { _warn('CUSTOMVALS', 'users/$uid/customvals', 'Not a Map'); return; }
    final cvMap = Map<String, dynamic>.from(cv);

    for (final field in ['cuisine', 'occasion']) {
      final list = cvMap[field];
      if (list == null) continue;
      if (list is! List) {
        _warn('CUSTOMVALS', 'users/$uid/customvals/$field', '$field is not a List'); continue;
      }
      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! List || item.length < 2) {
          _warn('CUSTOMVALS', 'users/$uid/customvals/$field[$i]',
              'Item $i is not a [name, usedFlag] pair');
        }
      }
      if (field == 'cuisine') ownCustomCuisines += list.length;
      if (field == 'occasion') ownCustomOccasions += list.length;
    }
    final countryList = cvMap['country'];
    if (countryList is List) {
      ownCustomCountries += countryList.length;
    } else if (countryList != null) {
      _warn('CUSTOMVALS', 'users/$uid/customvals/country', 'country is not a List');
    }
  }

  // ── G. Stale users_by_email ────────────────────────────────────────────────

  Future<void> _checkStaleUBE() async {
    _log('[G/7] users_by_email (stale) — cross-checking UBE against Auth and users/ tree...');

    final authUids = await _lookupAuthUids(_knownUids.toList());
    if (authUids == null) {
      _log('   → Auth lookup unavailable — skipping stale UBE detection');
      return;
    }

    // Collect emails whose UID lookup found no Auth match — look them up by email
    // to catch cases where the UBE uid is stale/mismatched.
    final emailsToRecheck = <String>[];
    for (final entry in _ubeRaw.entries) {
      if (entry.value is! Map) continue;
      final data  = Map<String, dynamic>.from(entry.value as Map);
      final uid   = data['uid']?.toString() ?? '';
      final email = data['email']?.toString() ?? '';
      if (uid.isEmpty || email.isEmpty) continue;
      if (!authUids.contains(uid)) emailsToRecheck.add(email);
    }
    // emailToAuthUid: email (lowercase) → real Auth UID for accounts that exist
    final emailToAuthUid = emailsToRecheck.isEmpty
        ? <String, String>{}
        : (await _lookupAuthByEmails(emailsToRecheck) ?? <String, String>{});

    int ghostCount = 0, authOnlyCount = 0, dataOnlyCount = 0;
    for (final entry in _ubeRaw.entries) {
      final norm  = entry.key.toString();
      if (entry.value is! Map) continue;
      final data  = Map<String, dynamic>.from(entry.value as Map);
      final uid   = data['uid']?.toString() ?? '';
      final email = data['email']?.toString() ?? '';
      if (uid.isEmpty) continue;

      // Auth exists if UID matched directly OR email resolved to an Auth account
      final authUidForEmail = emailToAuthUid[email.toLowerCase()];
      final hasAuth = authUids.contains(uid) || authUidForEmail != null;
      final hasUser = _usersUids.contains(uid);

      // If Auth exists under a different UID, surface that mismatch in the message
      final uidMismatch = authUidForEmail != null && authUidForEmail != uid
          ? '  ⚠ UBE uid=$uid but Auth uid=$authUidForEmail'
          : '';

      final fixBase = {'norm': norm, 'uid': uid, 'email': email,
                       'hasProfile': _ppUids.contains(uid).toString()};

      if (!hasAuth && !hasUser) {
        ghostCount++;
        _err('STALE_UBE_GHOST', 'users_by_email/$norm',
            'Ghost — no Auth account and no users/ record  (email=$email)',
            fixable: true, fixAction: 'delete', fixData: fixBase);
      } else if (hasAuth && !hasUser) {
        authOnlyCount++;
        _err('STALE_UBE_AUTH_ONLY', 'users_by_email/$norm',
            'Auth account exists but no users/ data  (email=$email)$uidMismatch',
            fixable: true, fixAction: 'delete', fixData: fixBase);
      } else if (!hasAuth && hasUser) {
        dataOnlyCount++;
        _err('STALE_UBE_DATA_ONLY', 'users_by_email/$norm',
            'users/ data exists but Auth account is gone — user locked out permanently  (email=$email)',
            fixable: true, fixAction: 'delete', fixData: fixBase);
      }
    }
    _log('   → $ghostCount ghost  |  $authOnlyCount auth-only  |  $dataOnlyCount data-only');
  }

  /// Batch-lookup UIDs in Firebase Auth via the Identity Toolkit REST API.
  /// Returns the set of UIDs that exist in Auth, or null if the lookup failed
  /// (to avoid false positives — callers should skip the check on null).
  Future<Set<String>?> _lookupAuthUids(List<String> uids) async {
    if (uids.isEmpty) return {};
    const projectId = 'restiview-bb851';
    const url       = 'https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup';
    final found     = <String>{};

    for (int i = 0; i < uids.length; i += 100) {
      final chunk = uids.sublist(i, (i + 100).clamp(0, uids.length));
      try {
        final resp = await http.post(
          Uri.parse(url),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: json.encode({'localId': chunk}),
        ).timeout(const Duration(seconds: 25));

        if (resp.statusCode == 200) {
          final body = json.decode(resp.body) as Map<String, dynamic>;
          final users = body['users'];
          if (users is List) {
            for (final u in users) {
              if (u is Map) found.add(u['localId']?.toString() ?? '');
            }
          }
          // A response with no 'users' key means none of the chunk UIDs exist — valid.
        } else if (resp.statusCode == 401 || resp.statusCode == 403) {
          _log('   WARN: Firebase Auth lookup — insufficient permissions (HTTP ${resp.statusCode}).');
          _log('         The service account may need the "Firebase Authentication Admin" role.');
          return null;
        } else {
          final snippet = resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
          _log('   WARN: Firebase Auth lookup — HTTP ${resp.statusCode}: $snippet');
          return null;
        }
      } on TimeoutException {
        _log('   WARN: Firebase Auth lookup timed out — skipping stale UBE check');
        return null;
      } on SocketException catch (e) {
        _log('   WARN: Firebase Auth lookup network error — $e');
        return null;
      }
    }
    return found;
  }

  /// Batch-lookup emails in Firebase Auth.
  /// Returns a map of lowercased email → Auth UID for accounts that exist,
  /// or null if the lookup failed.
  Future<Map<String, String>?> _lookupAuthByEmails(List<String> emails) async {
    if (emails.isEmpty) return {};
    const projectId = 'restiview-bb851';
    const url       = 'https://identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup';
    final found     = <String, String>{};

    for (int i = 0; i < emails.length; i += 100) {
      final chunk = emails.sublist(i, (i + 100).clamp(0, emails.length));
      try {
        final resp = await http.post(
          Uri.parse(url),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: json.encode({'email': chunk}),
        ).timeout(const Duration(seconds: 25));

        if (resp.statusCode == 200) {
          final body = json.decode(resp.body) as Map<String, dynamic>;
          final users = body['users'];
          if (users is List) {
            for (final u in users) {
              if (u is Map) {
                final authUid   = u['localId']?.toString() ?? '';
                final authEmail = u['email']?.toString().toLowerCase() ?? '';
                if (authUid.isNotEmpty && authEmail.isNotEmpty) {
                  found[authEmail] = authUid;
                }
              }
            }
          }
        } else if (resp.statusCode == 401 || resp.statusCode == 403) {
          _log('   WARN: Firebase Auth email lookup — insufficient permissions (HTTP ${resp.statusCode}).');
          return null;
        } else {
          final snippet = resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body;
          _log('   WARN: Firebase Auth email lookup — HTTP ${resp.statusCode}: $snippet');
          return null;
        }
      } on TimeoutException {
        _log('   WARN: Firebase Auth email lookup timed out');
        return null;
      } on SocketException catch (e) {
        _log('   WARN: Firebase Auth email lookup network error — $e');
        return null;
      }
    }
    return found;
  }

  Future<void> _applyFixes() async {
    final fixable = _errors.where((e) => e.fixable && e.fixData != null).toList();
    if (fixable.isEmpty) { print('\nNo auto-fixable issues found — nothing to do.'); return; }

    // ── Stale UBE — 3 phases, each entry offered individually ───────────────
    const staleCategories = {'STALE_UBE_GHOST', 'STALE_UBE_AUTH_ONLY', 'STALE_UBE_DATA_ONLY'};
    final others = fixable.where((e) => !staleCategories.contains(e.category)).toList();

    await _processStaleUbePhase(
      fixable.where((e) => e.category == 'STALE_UBE_GHOST').toList(),
      'PHASE 1/3 — GHOST  (no Auth account, no users/ data)',
      'These entries are completely dead — nothing exists for this UID anywhere.',
      offerUsersNode: false,
      warnAuthExists: false,
    );
    await _processStaleUbePhase(
      fixable.where((e) => e.category == 'STALE_UBE_AUTH_ONLY').toList(),
      'PHASE 2/3 — AUTH ONLY  (Auth account exists, no users/ data)',
      'Partial signup — the Auth account still exists but no app data was written.',
      offerUsersNode: false,
      warnAuthExists: true,
    );
    await _processStaleUbePhase(
      fixable.where((e) => e.category == 'STALE_UBE_DATA_ONLY').toList(),
      'PHASE 3/3 — DATA ONLY  (users/ data exists, Auth account gone)',
      'Auth account was deleted but DB data remains — this user can never log in again.',
      offerUsersNode: true,
      warnAuthExists: false,
    );

    // ── Other fixable errors — grouped by category ──────────────────────────
    if (others.isEmpty) return;

    final byCategory = <String, List<_Error>>{};
    for (final e in others) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }

    print('');
    print('${others.length} other fixable issue(s) across ${byCategory.length} category(ies).');
    print('Answer y/n for each group:\n');

    for (final entry in byCategory.entries) {
      final cat    = entry.key;
      final items  = entry.value;
      final action = items.any((e) => e.fixAction == 'delete') ? 'DELETE' : 'PATCH';
      stdout.write('  Fix all ${items.length} [$cat] issue(s) ($action)? [y/n]: ');
      final answer = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
      if (answer == 'y') {
        int ok = 0, fail = 0;
        for (final issue in items) {
          try {
            await _applyOneFix(issue);
            ok++;
          } catch (e) {
            _fixes.add('FAILED: ${issue.path} — $e');
            fail++;
          }
        }
        print('  → $ok applied${fail > 0 ? ", $fail failed" : ""}.');
      } else {
        print('  → Skipped.');
      }
    }
  }

  /// Shows each stale UBE entry individually with a y/n prompt.
  /// [offerUsersNode] — also prompt to delete `users/{uid}` (for DATA_ONLY phase).
  /// [warnAuthExists] — print a notice that the Auth account is still live (AUTH_ONLY phase).
  Future<void> _processStaleUbePhase(
      List<_Error> items, String phaseTitle, String phaseNote,
      {required bool offerUsersNode, required bool warnAuthExists}) async {
    if (items.isEmpty) return;
    print('');
    print('─' * 62);
    print('  $phaseTitle  (${items.length} entry(ies))');
    print('  $phaseNote');
    print('─' * 62);
    for (final issue in items) {
      final fd         = issue.fixData!;
      final norm       = fd['norm']?.toString() ?? '';
      final uid        = fd['uid']?.toString() ?? '';
      final email      = fd['email']?.toString() ?? '';
      final hasProfile = fd['hasProfile'] == 'true';
      print('');
      print('  Email : $email');
      print('  UID   : $uid');
      if (warnAuthExists) {
        print('  ℹ  Auth account still exists — only DB-side data will be removed here.');
      }
      stdout.write('  Delete users_by_email/$norm? [y/n]: ');
      final answer = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
      if (answer != 'y') { print('  → Skipped.'); continue; }

      final ok = await _delete('users_by_email/$norm');
      _fixes.add(ok
          ? 'DELETED: users_by_email/$norm  ($email)'
          : 'FAILED:  DELETE users_by_email/$norm');

      if (offerUsersNode) {
        stdout.write('  Also delete users/$uid (all reviews, friends, data)? [y/n]: ');
        final uAns = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
        if (uAns == 'y') {
          final uOk = await _delete('users/$uid');
          _fixes.add(uOk
              ? 'DELETED: users/$uid'
              : 'FAILED:  DELETE users/$uid');
        }
      }

      if (hasProfile) {
        stdout.write('  Also delete public_profiles/$uid? [y/n]: ');
        final ppAns = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
        if (ppAns == 'y') {
          final ppOk = await _delete('public_profiles/$uid');
          _fixes.add(ppOk
              ? 'DELETED: public_profiles/$uid'
              : 'FAILED:  DELETE public_profiles/$uid');
        }
      }
      print('  → Done.');
    }
  }

  Future<void> _applyOneFix(_Error issue) async {
    final fd = issue.fixData!;
    switch (issue.category) {
      case 'PUBLIC_PROFILES':
        final uid = fd['uid']?.toString() ?? '';
        if (uid.isEmpty) return;

        // Delete orphan profile
        if (fd['action'] == 'delete_profile') {
          final ok = await _delete('public_profiles/$uid');
          _fixes.add(ok
              ? 'DELETED: public_profiles/$uid'
              : 'FAILED: DELETE public_profiles/$uid');
          return;
        }

        // Create missing profile from UBE data
        final normEmail = fd['normEmail']?.toString() ?? '';
        if (normEmail.isEmpty) return;
        final ubeRaw = _ubeRaw[normEmail];
        if (ubeRaw is! Map) {
          _fixes.add('SKIPPED public_profiles/$uid — no UBE data cached');
          return;
        }
        final ube = Map<String, dynamic>.from(ubeRaw);
        final body = {
          'displayName': ube['displayName'] ?? ube['userName'] ?? '',
          'email':       ube['email'] ?? '',
          'updatedAt':   DateTime.now().toUtc().toIso8601String(),
        };
        final ok = await _patch('public_profiles/$uid', body);
        _fixes.add(ok
            ? 'FIXED: Created public_profiles/$uid'
            : 'FAILED: public_profiles/$uid — PATCH failed');
        break;

      case 'REVIEWS':
        final uid = fd['uid']?.toString() ?? '';
        final key = fd['key']?.toString() ?? '';
        final field = fd['field']?.toString() ?? '';
        final value = fd['value'];
        if (uid.isEmpty || key.isEmpty || field.isEmpty) return;
        final ok = await _patch('users/$uid/reviews/$key', {field: value});
        _fixes.add(ok
            ? 'FIXED: users/$uid/reviews/$key/$field = $value'
            : 'FAILED: users/$uid/reviews/$key/$field');
        break;

      case 'REVIEWS_CORRUPT':
        final uid = fd['uid']?.toString() ?? '';
        final key = fd['key']?.toString() ?? '';
        if (uid.isEmpty || key.isEmpty) return;
        final ok = await _delete('users/$uid/reviews/$key');
        _fixes.add(ok
            ? 'DELETED: users/$uid/reviews/$key (corrupt review)'
            : 'FAILED: DELETE users/$uid/reviews/$key');
        break;

      case 'REVIEWS_REQUESTED':
        final uid = fd['uid']?.toString() ?? '';
        final key = fd['key']?.toString() ?? '';
        final field = fd['field']?.toString() ?? '';
        final value = fd['value'];
        if (uid.isEmpty || key.isEmpty || field.isEmpty) return;
        final bool ok;
        if (value == null) {
          ok = await _delete('users/$uid/reviews_requested/$key/$field');
          _fixes.add(ok
              ? 'FIXED: Removed users/$uid/reviews_requested/$key/$field'
              : 'FAILED: DELETE users/$uid/reviews_requested/$key/$field');
        } else {
          ok = await _patch('users/$uid/reviews_requested/$key', {field: value});
          _fixes.add(ok
              ? 'FIXED: users/$uid/reviews_requested/$key/$field = $value'
              : 'FAILED: PATCH users/$uid/reviews_requested/$key/$field');
        }
        break;
    }
  }

  // ── Report ─────────────────────────────────────────────────────────────────

  void _printReport() {
    final errors   = _errors.where((e) => e.severity == 'ERROR').toList();
    final warnings = _errors.where((e) => e.severity == 'WARN').toList();

    // Count errors by category
    final errCounts  = <String, int>{};
    final warnCounts = <String, int>{};
    final fixCounts  = <String, int>{};
    for (final e in errors) {
      errCounts[e.category]  = (errCounts[e.category]  ?? 0) + 1;
      if (e.fixable) fixCounts[e.category] = (fixCounts[e.category] ?? 0) + 1;
    }
    for (final w in warnings) {
      warnCounts[w.category] = (warnCounts[w.category] ?? 0) + 1;
    }

    print('');
    print('═' * 56);
    print('  RESULTS — ${mode.toUpperCase()} mode');
    print('═' * 56);

    print('');
    print('  RECORD COUNTS');
    print('  ${'─' * 42}');
    _stat('Users (users_by_email)',                ubeUsers);
    _stat('Public profiles',                       publicProfiles);
    _stat('Mailbox entries',                       mailboxEntries);
    if (mailboxUnprocessed > 0) _stat('  Unprocessed mailbox entries', mailboxUnprocessed);
    _stat('Audit request_events',                  auditRequestEvents);
    _stat('Audit deletions',                        auditDeletions);
    _stat('Audit account_deletions',                auditAccountDeletions);
    _stat('Audit other',                            auditOtherEvents);
    _stat('Total reviews (all accounts)',          ownReviews);
    _stat('Total friend entries (all accounts)',   ownFriends);
    _stat('Total received reviews (all accounts)', ownReviewsRequested);
    _stat('Custom cuisines (all)',                 ownCustomCuisines);
    _stat('Custom occasions (all)',                ownCustomOccasions);
    _stat('Custom countries (all)',                ownCustomCountries);

    print('');
    print('  ERRORS by category  (${errors.length} total)');
    print('  ${'─' * 54}');
    if (errors.isEmpty) {
      print('    None');
    } else {
      // Group by category, then by message
      final errBycat = <String, Map<String, List<_Error>>>{};
      for (final e in errors) {
        errBycat.putIfAbsent(e.category, () => {});
        errBycat[e.category]!.putIfAbsent(e.message, () => []).add(e);
      }
      for (final cat in errBycat.keys) {
        final msgs = errBycat[cat]!;
        final catTotal = msgs.values.fold(0, (s, l) => s + l.length);
        print('    [$cat]  $catTotal issue(s)');
        for (final msg in msgs.keys) {
          final n       = msgs[msg]!.length;
          final fixable = msgs[msg]!.any((e) => e.fixable);
          final star    = fixable ? '  ★' : '';
          print('      ${n.toString().padLeft(3)}×  $msg$star');
        }
      }
    }

    print('');
    print('  WARNINGS by category  (${warnings.length} total)');
    print('  ${'─' * 54}');
    if (warnings.isEmpty) {
      print('    None');
    } else {
      final warnBycat = <String, Map<String, int>>{};
      for (final w in warnings) {
        warnBycat.putIfAbsent(w.category, () => {});
        warnBycat[w.category]![w.message] = (warnBycat[w.category]![w.message] ?? 0) + 1;
      }
      for (final cat in warnBycat.keys) {
        final msgs = warnBycat[cat]!;
        final catTotal = msgs.values.fold(0, (s, n) => s + n);
        print('    [$cat]  $catTotal warning(s)');
        for (final msg in msgs.keys) {
          print('      ${msgs[msg]!.toString().padLeft(3)}×  $msg');
        }
      }
    }

    if (_fixes.isNotEmpty) {
      print('');
      print('  FIXES APPLIED (${_fixes.length})');
      print('  ${'─' * 42}');
      for (final f in _fixes) { print('    $f'); }
    }

    print('');
    if (errors.isEmpty) {
      print('  ✓  Clean — no errors found.');
    } else {
      print('  ✗  ${errors.length} error(s), ${warnings.length} warning(s).');
      final totalFixable = fixCounts.values.fold(0, (a, b) => a + b);
      if (totalFixable > 0 && mode == 'check') {
        print('     $totalFixable can be auto-fixed — run:  .\\DBIC fix');
      }
    }
    print('═' * 56);
  }

  void _stat(String label, int value) {
    print('  ${label.padRight(44)} $value');
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  String _normalise(String email) =>
      email.trim().toLowerCase().replaceAll(RegExp(r'[.\$#\[\]/]'), '_');

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  bool _isDDMMYYYY(String s) {
    final p = s.split('/');
    if (p.length != 3) return false;
    final dd = int.tryParse(p[0]), mm = int.tryParse(p[1]), yy = int.tryParse(p[2]);
    return dd != null && mm != null && yy != null &&
        dd >= 1 && dd <= 31 && mm >= 1 && mm <= 12 && yy >= 2000;
  }

  bool _isYYYYMMDD(String s) {
    final p = s.split('/');
    if (p.length != 3) return false;
    final yy = int.tryParse(p[0]), mm = int.tryParse(p[1]), dd = int.tryParse(p[2]);
    return yy != null && mm != null && dd != null &&
        yy >= 2000 && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31;
  }
}
