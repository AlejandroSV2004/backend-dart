// lib/db.dart
import 'package:mysql1/mysql1.dart';
import 'package:dotenv/dotenv.dart' show DotEnv;

late ConnectionSettings _settings;
MySqlConnection? _conn;
bool _initialized = false;

/// Carga solo lo del .env y deja la conexión lista.
Future<void> initDb({required DotEnv env}) async {
  final host = env['DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(env['DB_PORT'] ?? '') ?? 3306;
  final user = env['DB_USER'] ?? 'lumina_user';
  final pass = env['DB_PASSWORD'] ?? env['DB_PASS'] ?? '';
  final db   = env['DB_NAME'] ?? 'lumina_marketplace';

  _settings = ConnectionSettings(
    host: host,
    port: port,
    user: user,
    password: pass,
    db: db,
  );
  _initialized = true;

  // Log simple (sin password)
  // ignore: avoid_print
  print('DB => $user@$host:$port/$db');

  // Conectar una vez al inicio para fallar rápido si algo está mal.
  await _ensureConn();
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

/// Ejecuta una consulta usando una única conexión persistente.
Future<Results> dbQuery(String sql, [List<Object?> params = const []]) async {
  final conn = await _ensureConn();
  return conn.query(sql, params);
}

/// Verifica si la DB responde.
Future<bool> dbAlive() async {
  try {
    await dbQuery('SELECT 1');
    return true;
  } catch (_) {
    return false;
  }
}

/// Cierra la conexión al apagar el servidor.
Future<void> closeDb() async {
  try { await _conn?.close(); } catch (_) {}
  _conn = null;
}
