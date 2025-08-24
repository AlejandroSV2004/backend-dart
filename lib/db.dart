import 'dart:async';
import 'dart:io';
import 'package:mysql1/mysql1.dart';
import 'package:dotenv/dotenv.dart' show DotEnv;

DotEnv? _env;
late ConnectionSettings _settings;
MySqlConnection? _conn;
bool _initialized = false;

Future<void> initDb({DotEnv? env}) async {
  _env = env ?? (DotEnv()..load());

  final host = _env!['DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(_env!['DB_PORT'] ?? '') ?? 3306;
  final user = _env!['DB_USER'] ?? 'lumina_user';
  final pass = _env!['DB_PASSWORD'] ?? _env!['DB_PASS'] ?? '';
  final db   = _env!['DB_NAME'] ?? 'lumina_marketplace';

  _settings = ConnectionSettings(
    host: host,
    port: port,
    user: user,
    password: pass,
    db: db,
  );
  _initialized = true;
  print('DB => $user@$host:$port/$db');

  await _ensureConn();

  _setupSignalHandlers();
}

void _setupSignalHandlers() {
  ProcessSignal.sigint.watch().listen((_) async {
    await closeDb();
  });
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) async {
      await closeDb();
    });
  }
}

Future<MySqlConnection> _ensureConn() async {
  if (!_initialized) {
    throw StateError('initDb() debe llamarse antes de usar la DB');
  }
  if (_conn != null) {
    try {
      await _conn!.query('/* ping */ SELECT 1');
      return _conn!;
    } catch (_) {
      try { await _conn!.close(); } catch (_) {}
      _conn = null;
    }
  }
  _conn = await MySqlConnection.connect(_settings);
  return _conn!;
}

Future<Results> dbQuery(String sql, [List<Object?> params = const []]) async {
  final conn = await _ensureConn();
  return conn.query(sql, params);
}

Future<List<Map<String, dynamic>>> dbQueryMaps(
  String sql, [
  List<Object?> params = const [],
]) async {
  final rs = await dbQuery(sql, params);
  final out = <Map<String, dynamic>>[];

  final fields = rs.fields;
  for (final row in rs) {
    final m = <String, dynamic>{};
    for (var i = 0; i < fields.length; i++) {
      final name = fields[i].name ?? 'col_$i';
      m[name] = row[i];
    }
    out.add(m);
  }
  return out;
}

Future<Map<String, dynamic>?> dbQueryOneMap(
  String sql, [
  List<Object?> params = const [],
]) async {
  final list = await dbQueryMaps(sql, params);
  return list.isEmpty ? null : list.first;
}

Future<bool> dbAlive() async {
  try {
    final r = await dbQuery('SELECT 1');
    return r.isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<void> closeDb() async {
  try { await _conn?.close(); } catch (_) {}
  _conn = null;
}
