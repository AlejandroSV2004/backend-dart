import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:dotenv/dotenv.dart';

import 'package:backend_dart/db.dart';

import 'package:backend_dart/routes/categorias.dart';
import 'package:backend_dart/routes/usuarios.dart';
import 'package:backend_dart/routes/productos.dart';

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load();

  await initDb(env: env);

  final router = Router()
    ..get('/', rootHandler)
    // Categorías
    ..get('/categorias', categoriasHandler)
    // Productos (grupo montado)
    ..get('/productos', (req) => Response.found('/productos/'))
    ..mount('/productos/', Router()
      ..get('/', productosHandler)
      ..post('/', crearProductoHandler)
      ..delete('/<id>', eliminarProductoHandler)
      ..get('/admin', adminProductosPageHandler)
    )
    // Usuarios
    ..get('/usuarios', usuariosHandler)
    ..post('/usuarios', crearUsuarioHandler)
    ..delete('/usuarios/<id>', eliminarUsuarioHandler)
    ..get('/usuarios/admin', adminUsuariosPageHandler)

    ..options('/<ignored|.*>', _optionsHandler);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware)
      .addHandler(router);

  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Backend escuchando en http://${server.address.host}:$port');

  ProcessSignal.sigint.watch().listen((_) async {
    print('\nApagando…');
    await closeDb();
    await server.close(force: true);
    exit(0);
  });
}


const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
};

Middleware get _corsMiddleware => (inner) => (request) async {
  if (request.method == 'OPTIONS') return Response.ok('', headers: _corsHeaders);
  final res = await inner(request);
  return res.change(headers: {...res.headers, ..._corsHeaders});
};

Future<Response> _optionsHandler(Request request) async =>
    Response.ok('', headers: _corsHeaders);


final _startedAt = DateTime.now();

Future<Response> rootHandler(Request req) async {
  final body = {
    'ok': true,
    'name': 'Backend Dart API',
    'uptime_s': DateTime.now().difference(_startedAt).inSeconds,
    'db': await dbAlive() ? 'up' : 'down',
  };
  return Response.ok(
    jsonEncode(body),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}
