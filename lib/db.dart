// lib/db.dart
import 'dart:async';
import 'dart:io';
import 'package:mysql1/mysql1.dart';
import 'package:dotenv/dotenv.dart' show DotEnv;

DotEnv? _env;
late ConnectionSettings _settings;
MySqlConnection? _conn;
bool _initialized = false;

/// Inicializa la DB. Si no pasas `env`, carga .env automáticamente.
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

  // Log simple (sin password)
  // ignore: avoid_print
  print('DB => $user@$host:$port/$db');

  // Conectar una vez para fallar rápido si algo está mal.
  await _ensureConn();

  _setupSignalHandlers();
}

void _setupSignalHandlers() {
  // Cierre ordenado en Ctrl+C (SIGINT)
  ProcessSignal.sigint.watch().listen((_) async {
    await closeDb();
  });
  // SIGTERM no existe en Windows
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

/// Ejecuta una consulta y retorna `Results`.
Future<Results> dbQuery(String sql, [List<Object?> params = const []]) async {
  final conn = await _ensureConn();
  return conn.query(sql, params);
}

/// Ejecuta y devuelve una lista de Map<String,dynamic>.
Future<List<Map<String, dynamic>>> dbQueryMaps(
  String sql, [
  List<Object?> params = const [],
]) async {
  final rs = await dbQuery(sql, params);
  final out = <Map<String, dynamic>>[];

  // IMPORTANTE: Field.name es String?; usamos índice para leer valores,
  // y si el nombre es null, generamos uno de respaldo.
  final fields = rs.fields; // List<Field>
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

/// Igual que arriba pero devuelve solo la primera fila (o null).
Future<Map<String, dynamic>?> dbQueryOneMap(
  String sql, [
  List<Object?> params = const [],
]) async {
  final list = await dbQueryMaps(sql, params);
  return list.isEmpty ? null : list.first;
}

/// Verifica si la DB responde.
Future<bool> dbAlive() async {
  try {
    final r = await dbQuery('SELECT 1');
    return r.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Cierra la conexión al apagar el servidor.
Future<void> closeDb() async {
  try { await _conn?.close(); } catch (_) {}
  _conn = null;
}
  