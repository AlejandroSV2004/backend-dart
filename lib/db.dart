// lib/db.dart
import 'package:mysql1/mysql1.dart';
import 'package:dotenv/dotenv.dart' show DotEnv;

/// Configuración global (inmutable después de initDb)
late ConnectionSettings _settings;
bool _initialized = false;

/// Inicializa los parámetros de conexión usando variables de entorno.
/// Requiere (mínimo): DB_HOST, DB_PORT, DB_USER, DB_PASS, DB_NAME
///
/// Opcionales:
/// - DB_USE_SSL = "true" | "false"   (por defecto false)
/// - DB_TIMEOUT_SECONDS (timeout de conexión en segundos; opcional)
Future<void> initDb({required DotEnv env}) async {
  final host = env['DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(env['DB_PORT'] ?? '') ?? 3306;
  final user = env['DB_USER'] ?? 'root';
  final pass = env['DB_PASS'] ?? '';
  final db   = env['DB_NAME'] ?? '';
  final useSSL = (env['DB_USE_SSL'] ?? 'false').toLowerCase() == 'true';

  if (db.isEmpty) {
    throw StateError('DB_NAME no configurado');
  }

  // mysql1 no tiene timeout directo en ConnectionSettings; el handshake respeta
  // socket timeouts del sistema. Preferimos conexiones "por query" para
  // evitar sockets colgados/idle (p. ej. en Render).
  _settings = ConnectionSettings(
    host: host,
    port: port,
    user: user,
    password: pass,
    db: db,
    useCompression: true,
    useSSL: useSSL,
  );

  _initialized = true;
}

/// Ejecuta una consulta abriendo y cerrando la conexión por cada llamada.
/// Esto evita errores como:
///  - "Bad state: Cannot write to socket, it is closed"
///  - conexiones que Render cierra por inactividad.
///
/// Devuelve [Results] de mysql1 (con `insertId`, `affectedRows`, etc).
Future<Results> dbQuery(String sql, [List<Object?> params = const []]) async {
  if (!_initialized) {
    throw StateError('initDb() no fue llamado antes de dbQuery()');
  }

  MySqlConnection? conn;
  try {
    conn = await MySqlConnection.connect(_settings);
    final res = await conn.query(sql, params);
    return res;
  } on MySqlException {
    rethrow; // deja que el caller maneje códigos específicos si quiere
  } finally {
    try {
      await conn?.close();
    } catch (_) {
      // ignora errores al cerrar
    }
  }
}

/// Verifica si la DB responde a un SELECT 1.
Future<bool> dbAlive() async {
  if (!_initialized) return false;
  MySqlConnection? conn;
  try {
    conn = await MySqlConnection.connect(_settings);
    await conn.query('SELECT 1');
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      await conn?.close();
    } catch (_) {}
  }
}

/// Cierre global. En este enfoque no mantenemos conexiones vivas,
/// así que no hay nada que cerrar; se deja por compatibilidad.
Future<void> closeDb() async {
  // no-op
}
