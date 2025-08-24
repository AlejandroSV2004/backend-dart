import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:dotenv/dotenv.dart';

import 'package:backend_dart/db.dart';

// Rutas
import 'package:backend_dart/routes/categorias.dart';
import 'package:backend_dart/routes/usuarios.dart';          // incluye loginUsuarioHandler
import 'package:backend_dart/routes/productos.dart';        // incluye productosPorCategoriaHandler
import 'package:backend_dart/routes/resenas.dart';
import 'package:backend_dart/routes/carrito.dart';
import 'package:backend_dart/routes/producto.dart';
import 'package:backend_dart/routes/productos_vendedor.dart';

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

Future<void> main() async {
  final env = DotEnv(includePlatformEnvironment: true)..load();

  await initDb(env: env);

  final router = Router()
    ..get('/', rootHandler)

    // ---------- Categorías ----------
    ..get('/categorias', categoriasHandler)

    // ---------- Productos (grupo) ----------
    // Canonicaliza /productos -> /productos/
    ..get('/productos', (req) => Response.found('/productos/'))
    ..mount(
      '/productos/',
      Router()
        // Lista completa
        ..get('/', productosHandler)
        // Crear
        ..post('/', crearProductoHandler)
        // Página admin (defínela ANTES que la dinámica)
        ..get('/admin', adminProductosPageHandler)
        // Productos por categoría (slug o código)
        ..get('/<slug>', productosPorCategoriaHandler)
        // Eliminar por id (DELETE)
        ..delete('/<id>', eliminarProductoHandler),
    )

    // ---------- Usuarios ----------
    // Login PRIMERO para evitar choques con patrones dinámicos
    ..post('/usuarios/login', loginUsuarioHandler)
    ..get('/usuarios', usuariosHandler)
    ..post('/usuarios', crearUsuarioHandler)
    ..delete('/usuarios/<id>', eliminarUsuarioHandler)
    ..get('/usuarios/admin', adminUsuariosPageHandler)

    // ---------- Producto (detalle + update) ----------
    ..mount(
      '/producto/',
      Router()
        ..get('/<id>', productoGetHandler)
        ..put('/<id>', productoUpdateHandler),
    )

    // ---------- Reseñas ----------
    ..mount(
      '/resenas/',
      Router()
        ..get('/<id_producto>', resenasPorProductoHandler)
        ..post('/<id_producto>', crearResenaHandler)
        ..delete('/<id>', eliminarResenaHandler),
    )

    // ---------- Carrito ----------
    ..mount(
      '/carrito/',
      Router()
        ..get('/<id_usuario>', carritoPorUsuarioHandler)
        ..post('/agregar', agregarAlCarritoHandler)
        ..post('/disminuir', disminuirDelCarritoHandler)
        ..delete('/eliminar', eliminarItemCarritoHandler)
        ..delete('/vaciar/<id_usuario>', vaciarCarritoHandler),
    )

    // ---------- Productos por vendedor ----------
    ..mount(
      '/productosVendedor/',
      Router()..get('/<vendedorId>', productosDeVendedorHandler),
    )

    // ---------- Preflight CORS ----------
    ..options('/<ignored|.*>', _optionsHandler);

  // Pipeline + CORS
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware)
      .addHandler(router);

  // Envolver para devolver 404 en JSON (evita "Route not found" texto plano)
  Future<Response> app(Request req) async {
    final res = await handler(req);
    if (res.statusCode == 404) {
      return Response.notFound(
        jsonEncode({'error': 'Route not found', 'path': '/${req.url}'}),
        headers: _jsonHeaders,
      );
    }
    return res;
  }

  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server = await io.serve(app, InternetAddress.anyIPv4, port);
  print('Backend escuchando en http://${server.address.host}:$port');

  // Apagado limpio (CTRL+C y SIGTERM)
  void _shutdown() async {
    print('\nApagando…');
    await closeDb();
    await server.close(force: true);
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => _shutdown());
  if (Platform.isLinux || Platform.isMacOS) {
    ProcessSignal.sigterm.watch().listen((_) => _shutdown());
  }
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
  return Response.ok(jsonEncode(body), headers: _jsonHeaders);
}
