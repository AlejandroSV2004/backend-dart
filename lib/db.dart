import 'package:dotenv/dotenv.dart';
import 'package:mysql1/mysql1.dart';

MySqlConnection? _conn;

Future<void> initDb({required DotEnv env}) async {
  final settings = ConnectionSettings(
    host: env['DB_HOST'] ?? '127.0.0.1',
    port: int.tryParse(env['DB_PORT'] ?? '') ?? 3306,
    user: env['DB_USER'] ?? 'root',
    password: env['DB_PASSWORD'] ?? '',
    db: env['DB_NAME'] ?? '',
  );
  _conn = await MySqlConnection.connect(settings);
}

Future<void> closeDb() async => _conn?.close();

Future<Results> dbQuery(String sql, [List<Object?>? params]) {
  final c = _conn;
  if (c == null) {
    throw StateError('DB no inicializada. Llama initDb() primero.');
  }
  return c.query(sql, params);
}

Future<bool> dbAlive() async {
  final c = _conn;
  if (c == null) return false;
  try {
    await c.query('SELECT 1');
    return true;
  } catch (_) {
    return false;
  }
}

