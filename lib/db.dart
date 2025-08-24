import 'dart:async';
import 'dart:io';
import 'package:mysql1/mysql1.dart';
import 'package:dotenv/dotenv.dart' show DotEnv;

DotEnv? _env;
late ConnectionSettings _settings;
MySqlConnection? _conn;
bool _initialized = false;

String _getVar(String key, {String def = ''}) {
  final v1 = _env?[key];
  if (v1 != null && v1.isNotEmpty) return v1;
  final v2 = Platform.environment[key];
  if (v2 != null && v2.isNotEmpty) return v2;
  return def;
}

int _getInt(String key, {required int def}) {
  final s = _getVar(key);
  final n = int.tryParse(s);
  return n ?? def;
}

Future<void> initDb({DotEnv? env}) async {
  try {
    if (env != null) {
      _env = env;
    } else {
      if (File('.env').existsSync()) {
        _env = DotEnv()..load();
      } else {
        _env = DotEnv();
      }
    }
  } catch (_) {
    _env = DotEnv();
  }

  final host = _getVar('DB_HOST', def: '127.0.0.1');
  final port = _getInt('DB_PORT', def: 3306);
  final user = _getVar('DB_USER', def: 'lumina_user');
  final pass = _getVar('DB_PASSWORD', def: _getVar('DB_PASS', def: ''));
  final db   = _getVar('DB_NAME', def: 'lumina_marketplace');

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
