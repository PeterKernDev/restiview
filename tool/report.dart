/// RestiView — Activity Reporter
/// ==============================
/// Standalone Dart CLI tool.  Run from the project root:
///
///   dart run tool/report.dart full   `<path-to-service-account.json>`
///   dart run tool/report.dart weekly `<path-to-service-account.json>`
///
/// Or use the REPORT.bat wrapper (project root):
///   REPORT full
///   REPORT weekly
///
/// Modes:
///   full   — Every registered user: registration date, username, email,
///            own review count, received (friend) review count, last active.
///            Followed by a full DB integrity check.
///
///   weekly — New users registered in the last 7 days, plus any user whose
///            review activity or audit events fall within the last 7 days.
///            Followed by a full DB integrity check.
///
/// "Last Active" reflects the user's most recently created/updated review
/// or their most recent audit event (friend/review request action).
/// General logins are not tracked in the database.
///
/// SETUP: same service-account JSON as dbic.dart.
///   dart run tool/report.dart full `"C:\Users\Denve\restiview-sa.json"`
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
];

// ─── Entry point ─────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  if (args.length < 2) { _printUsage(); exit(1); }

  final mode   = args[0].toLowerCase();
  final saPath = args[1];

  if (mode != 'full' && mode != 'weekly') { _printUsage(); exit(1); }
  if (!File(saPath).existsSync()) {
    print('ERROR: Service account file not found: $saPath');
    exit(1);
  }

  final now = DateTime.now();

  // ── Set up timestamped report file ────────────────────────────────────────
  final reportsDir = Directory('${Directory.current.path}/Reports');
  if (!reportsDir.existsSync()) reportsDir.createSync(recursive: true);
  final stamp =
      '${now.year}${_pad(now.month)}${_pad(now.day)}'
      '_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
  final outFile  = File('${reportsDir.path}/report_${mode}_$stamp.txt');
  final fileSink = outFile.openWrite();

  await runZoned(
    () async {
      print('');
      print('Authenticating with service account...');

      final saJson      = json.decode(File(saPath).readAsStringSync()) as Map<String, dynamic>;
      final credentials = gauth.ServiceAccountCredentials.fromJson(saJson);
      final baseClient  = http.Client();
      final authCreds   = await gauth.obtainAccessCredentialsViaServiceAccount(
        credentials, _scopes, baseClient,
      );
      baseClient.close();
      final authHeader = 'Bearer ${authCreds.accessToken.data}';
      print('Authenticated as: ${saJson['client_email']}');
      print('');

      // Reporter prints the banner itself (after loading, so it knows user count).
      await ActivityReporter(mode: mode, authHeader: authHeader, now: now).run();

      // ── DB Integrity Check (always read-only) ───────────────────────────
      _printSectionHeader('DB INTEGRITY CHECK');
      print('Running dart run tool/dbic.dart check ...');
      print('');
      final dbicResult = await Process.run(
        'dart',
        ['run', 'tool/dbic.dart', 'check', saPath],
        workingDirectory: Directory.current.path,
        runInShell: true,
      );
      final dbicOut = dbicResult.stdout as String;
      stdout.write(dbicOut);
      fileSink.write(dbicOut);
      final errOut = dbicResult.stderr as String;
      if (errOut.isNotEmpty) stderr.write(errOut);
    },
    zoneSpecification: ZoneSpecification(
      print: (_, parent, zone, line) {
        stdout.writeln(line);
        fileSink.writeln(line);
      },
    ),
  );

  await fileSink.flush();
  await fileSink.close();
  stdout.writeln('');
  stdout.writeln('Report saved to: ${outFile.path}');
}

void _printUsage() {
  print('Usage:');
  print('  dart run tool/report.dart full   <service-account.json>');
  print('  dart run tool/report.dart weekly <service-account.json>');
  print('');
  print('Batch shortcut (REPORT.bat in project root):');
  print('  REPORT full');
  print('  REPORT weekly');
  print('');
  print('Download service-account.json from:');
  print('  Firebase Console → Project settings → Service accounts → Generate new private key');
}

// ─── Box / section helpers ────────────────────────────────────────────────────

const int _boxInner = 50; // content columns inside ║…║

/// Prints the top-level report banner box.
void _printBox(List<String> lines) {
  print('╔${'═' * _boxInner}╗');
  for (final line in lines) {
    print('║  ${line.padRight(_boxInner - 2)}║');
  }
  print('╚${'═' * _boxInner}╝');
}

/// Prints a section divider used between major sections of the report.
void _printSectionHeader(String title) {
  print('┌${'─' * _boxInner}┐');
  print('│  ${title.padRight(_boxInner - 2)}│');
  print('└${'─' * _boxInner}┘');
  print('');
}

// ─── Formatting helpers ───────────────────────────────────────────────────────

String _pad(int n) => n.toString().padLeft(2, '0');

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '---';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  } catch (_) {
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
}

String _fmtDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '(none)';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  } catch (_) {
    return iso;
  }
}

DateTime? _parseIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try { return DateTime.parse(iso); } catch (_) { return null; }
}

/// Returns whichever of [a] or [b] represents the later point in time.
String? _maxIso(String? a, String? b) {
  final da = _parseIso(a);
  final db = _parseIso(b);
  if (da == null) return b;
  if (db == null) return a;
  return da.isAfter(db) ? a : b;
}

// ─── User record ─────────────────────────────────────────────────────────────

class _User {
  final String  uid;
  final String  email;
  final String  displayName;
  final String? registeredAt;   // updatedAt from users_by_email written at registration
  int     ownReviews        = 0;
  int     friendReviews     = 0;
  String? lastActivity;         // latest ISO timestamp across reviews + audit events
  String? homeCountry;          // baseCountry from users/$uid
  // Weekly-only extras
  int ownReviewsThisWeek  = 0;
  int auditEventsThisWeek = 0;

  _User({
    required this.uid,
    required this.email,
    required this.displayName,
    this.registeredAt,
  });
}

// ─── Reporter ─────────────────────────────────────────────────────────────────

class ActivityReporter {
  final String   mode;
  final String   authHeader;
  final DateTime now;
  late final DateTime _weekAgo;

  ActivityReporter({
    required this.mode,
    required this.authHeader,
    required this.now,
  }) {
    _weekAgo = now.subtract(const Duration(days: 7));
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  Map<String, String> get _headers => {'Authorization': authHeader};

  String _urlFor(String path, {bool shallow = false}) {
    final base = '$_dbUrl/$path.json';
    return shallow ? '$base?shallow=true' : base;
  }

  Future<dynamic> _get(String path, {bool shallow = false}) async {
    final url = Uri.parse(_urlFor(path, shallow: shallow));
    try {
      final resp = await http.get(url, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        print('AUTH ERROR (${resp.statusCode}) at /$path — check service account permissions');
        exit(2);
      }
      if (resp.statusCode != 200) return null;
      return json.decode(resp.body);
    } on SocketException catch (e) {
      print('NETWORK ERROR at /$path — $e');
      return null;
    } on TimeoutException {
      print('TIMEOUT at /$path');
      return null;
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<List<_User>> _loadUsers() async {
    print('Loading users from users_by_email...');
    final raw = await _get('users_by_email');
    if (raw == null) {
      print('ERROR: Could not read users_by_email. Aborting.');
      exit(1);
    }
    if (raw is! Map) return [];

    final users   = <_User>[];
    final uidSeen = <String>{};

    for (final entry in raw.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      final m = Map<String, dynamic>.from(v);

      final uid = (m['uid'] as String?) ?? '';
      if (uid.isEmpty || uidSeen.contains(uid)) continue;
      uidSeen.add(uid);

      final email       = (m['email']       as String?) ?? entry.key.toString();
      final displayName = (m['displayName'] as String?) ??
                          (m['userName']    as String?) ?? email;
      final regAt       = m['updatedAt'] as String?;

      users.add(_User(uid: uid, email: email, displayName: displayName, registeredAt: regAt));
    }

    print('  ${users.length} users found.');
    return users;
  }

  Future<void> _loadReviews(List<_User> users) async {
    print('Loading own reviews...');
    int total = 0;
    for (final user in users) {
      final raw = await _get('users/${user.uid}/reviews');
      if (raw is! Map) continue;
      final reviews = Map<String, dynamic>.from(raw);
      user.ownReviews = reviews.length;
      total += reviews.length;
      for (final rv in reviews.values) {
        if (rv is! Map) continue;
        final m    = Map<String, dynamic>.from(rv);
        final crAt = m['createdAt'] as String?;
        final upAt = m['updatedAt'] as String?;
        user.lastActivity = _maxIso(user.lastActivity, _maxIso(crAt, upAt));
        final crDt = _parseIso(crAt);
        if (crDt != null && crDt.isAfter(_weekAgo)) user.ownReviewsThisWeek++;
      }
    }
    print('  $total own reviews loaded.');
  }

  Future<void> _loadFriendReviews(List<_User> users) async {
    print('Loading friend reviews (reviews_requested)...');
    int total = 0;
    for (final user in users) {
      // Shallow fetch — we only need the key count, not review payloads.
      final raw = await _get('users/${user.uid}/reviews_requested', shallow: true);
      if (raw is! Map) continue;
      final count = raw.keys.where((k) => k.toString() != '_meta').length;
      user.friendReviews = count;
      total += count;
    }
    print('  $total friend reviews loaded.');
  }

  Future<void> _loadHomeCountries(List<_User> users) async {
    print('Loading home countries...');
    int found = 0;
    for (final user in users) {
      final raw = await _get('users/${user.uid}/baseCountry');
      if (raw is String && raw.isNotEmpty) {
        user.homeCountry = raw;
        found++;
      }
    }
    print('  $found home countries loaded.');
  }

  Future<void> _loadAuditEvents(List<_User> users) async {
    print('Loading audit events...');
    final uidIndex = {for (final u in users) u.uid: u};
    final raw = await _get('audit_info/request_events');
    if (raw is! Map) { print('  (none found)'); return; }
    final auditMap = Map<String, dynamic>.from(raw);
    int weekCount = 0;
    for (final ev in auditMap.values) {
      if (ev is! Map) continue;
      final m     = Map<String, dynamic>.from(ev);
      final actor = (m['actorUid'] as String?) ?? '';
      final ts    = m['timestamp'] as String?;
      if (actor.isEmpty || ts == null) continue;
      final user = uidIndex[actor];
      if (user == null) continue;
      user.lastActivity = _maxIso(user.lastActivity, ts);
      final tsDt = _parseIso(ts);
      if (tsDt != null && tsDt.isAfter(_weekAgo)) {
        user.auditEventsThisWeek++;
        weekCount++;
      }
    }
    print('  ${auditMap.length} audit events scanned ($weekCount in the last 7 days).');
  }

  // ── Main ──────────────────────────────────────────────────────────────────

  Future<void> run() async {
    final users = await _loadUsers();
    await _loadReviews(users);
    await _loadFriendReviews(users);
    await _loadAuditEvents(users);
    await _loadHomeCountries(users);
    print('');

    // ── Report banner (printed here so user count is known) ─────────────────
    final modeLabel = mode == 'full' ? 'Full' : 'Weekly';
    final dateStr   = _fmtDate(now.toIso8601String());
    final timeStr   = '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';
    _printBox([
      'RestiView Activity Report — $modeLabel',
      'Date  : $dateStr   Time : $timeStr',
      'Users : ${users.length}',
    ]);
    print('');

    if (mode == 'full') {
      _printFullReport(users);
    } else {
      _printWeeklyReport(users);
    }
  }

  // ── Full report ──────────────────────────────────────────────────────────

  void _printFullReport(List<_User> users) {
    // Sort oldest registration first; unknown dates go to the bottom.
    users.sort((a, b) {
      final da = _parseIso(a.registeredAt);
      final db = _parseIso(b.registeredAt);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    _printSectionHeader('ALL USERS  (${users.length})');

    const nameW   = 22;
    const emailW  = 28;
    const regW    = 12;
    const cntryW  = 16;
    const revW    = 9;
    const frW     = 11;

    final header =
        ' #  '
        '${'Display Name'.padRight(nameW)}'
        '${'Email'.padRight(emailW)}'
        '${'Registered'.padRight(regW)}'
        '${'Country'.padRight(cntryW)}'
        '${'Reviews'.padRight(revW)}'
        '${'Frnd Revs'.padRight(frW)}'
        'Last Activity';
    final sep = '─' * header.length;

    print(sep);
    print(header);
    print(sep);

    for (int i = 0; i < users.length; i++) {
      final u = users[i];
      print(
        '${(i + 1).toString().padLeft(3)} '
        '${_trunc(u.displayName, nameW - 1).padRight(nameW)}'
        '${_trunc(u.email, emailW - 1).padRight(emailW)}'
        '${_fmtDate(u.registeredAt).padRight(regW)}'
        '${_trunc(u.homeCountry ?? '---', cntryW - 1).padRight(cntryW)}'
        '${u.ownReviews.toString().padRight(revW)}'
        '${u.friendReviews.toString().padRight(frW)}'
        '${_fmtDateTime(u.lastActivity)}',
      );
    }

    print(sep);
    print('Total: ${users.length} users');
    print('');
  }

  // ── Weekly report ─────────────────────────────────────────────────────────

  void _printWeeklyReport(List<_User> users) {
    // ── New users this week ───────────────────────────────────────────────
    final newUsers = users
        .where((u) {
          final dt = _parseIso(u.registeredAt);
          return dt != null && dt.isAfter(_weekAgo);
        })
        .toList()
      ..sort((a, b) => (a.registeredAt ?? '').compareTo(b.registeredAt ?? ''));

    _printSectionHeader('NEW USERS THIS WEEK  (${newUsers.length})');

    if (newUsers.isEmpty) {
      print('   (none)');
    } else {
      const nameW  = 22;
      const emailW = 28;
      const regW   = 12;
      const cntryW = 16;
      const revW   = 9;

      final hdr =
          ' #  '
          '${'Display Name'.padRight(nameW)}'
          '${'Email'.padRight(emailW)}'
          '${'Registered'.padRight(regW)}'
          '${'Country'.padRight(cntryW)}'
          '${'Reviews'.padRight(revW)}'
          'Frnd Revs';
      print(hdr);
      print('─' * hdr.length);
      for (int i = 0; i < newUsers.length; i++) {
        final u = newUsers[i];
        print(
          '${(i + 1).toString().padLeft(3)} '
          '${_trunc(u.displayName, nameW - 1).padRight(nameW)}'
          '${_trunc(u.email, emailW - 1).padRight(emailW)}'
          '${_fmtDate(u.registeredAt).padRight(regW)}'
          '${_trunc(u.homeCountry ?? '---', cntryW - 1).padRight(cntryW)}'
          '${u.ownReviews.toString().padRight(revW)}'
          '${u.friendReviews}',
        );
      }
    }
    print('');

    // ── Active existing users this week ───────────────────────────────────
    final newUidSet   = newUsers.map((u) => u.uid).toSet();
    final activeUsers = users
        .where((u) {
          if (newUidSet.contains(u.uid)) return false;
          final actDt = _parseIso(u.lastActivity);
          return actDt != null && actDt.isAfter(_weekAgo);
        })
        .toList()
      ..sort((a, b) => (b.lastActivity ?? '').compareTo(a.lastActivity ?? ''));

    _printSectionHeader('EXISTING USER ACTIVITY THIS WEEK  (${activeUsers.length})');
    print('  Reviews (wk) = own reviews created this week');
    print('  Events  (wk) = friend/review request audit events this week');
    print('');

    if (activeUsers.isEmpty) {
      print('   (none)');
    } else {
      const nameW  = 22;
      const emailW = 28;
      const cntryW = 16;
      const revWkW = 14;
      const evWkW  = 13;

      final hdr =
          ' #  '
          '${'Display Name'.padRight(nameW)}'
          '${'Email'.padRight(emailW)}'
          '${'Country'.padRight(cntryW)}'
          '${'Reviews (wk)'.padRight(revWkW)}'
          '${'Events (wk)'.padRight(evWkW)}'
          'Last Activity';
      print(hdr);
      print('─' * hdr.length);
      for (int i = 0; i < activeUsers.length; i++) {
        final u = activeUsers[i];
        print(
          '${(i + 1).toString().padLeft(3)} '
          '${_trunc(u.displayName, nameW - 1).padRight(nameW)}'
          '${_trunc(u.email, emailW - 1).padRight(emailW)}'
          '${_trunc(u.homeCountry ?? '---', cntryW - 1).padRight(cntryW)}'
          '${u.ownReviewsThisWeek.toString().padRight(revWkW)}'
          '${u.auditEventsThisWeek.toString().padRight(evWkW)}'
          '${_fmtDateTime(u.lastActivity)}',
        );
      }
    }
    print('');
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Truncate [s] to [max] chars, appending '…' if truncated.
  static String _trunc(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }
}
