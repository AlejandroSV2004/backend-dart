import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'package:backend_dart/db.dart' show initDb;

import 'package:backend_dart/routes/categorias.dart' show categoriasRouter;
import 'package:backend_dart/routes/productos.dart' show productosRouter;
import 'package:backend_dart/routes/producto.dart' show productoRouter;
import 'package:backend_dart/routes/resenas.dart' show resenasRouter;
import 'package:backend_dart/routes/usuarios.dart' show usuariosRouter;
import 'package:backend_dart/routes/productos_vendedor.dart' show productosVendedorRouter;
import 'package:backend_dart/routes/carrito.dart' show carritoRouter;
import 'package:backend_dart/routes/recomendados.dart' show recomendadosRouter;

const _corsHeaders = <String, String>{
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers':
      'Origin, Content-Type, Accept, Authorization, X-Requested-With',
  'Access-Control-Expose-Headers': 'Content-Length, Content-Type',
  'Access-Control-Allow-Credentials': 'true',
};

Middleware _cors() {
  return (Handler inner) {
    return (Request req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final res = await inner(req);
      return res.change(headers: _corsHeaders);
    };
  };
}

Response _redir308(String to) => Response(308, headers: {'Location': to});

void main(List<String> args) async {
  final env = DotEnv()..load();
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ??
      int.tryParse((DotEnv()..load())['PORT'] ?? '') ??
      3001;

  await initDb();
  print('DB inicializada');

  final router = Router();

  router.get('/', (Request req) {
    return Response.ok('API Lumina funcionando',
        headers: {'Content-Type': 'text/plain; charset=utf-8'});
  });

  final uploadsDir = env['UPLOADS_DIR'] ?? 'uploads';
  final dir = Directory(uploadsDir);
  if (dir.existsSync()) {
    final uploadsHandler =
        createStaticHandler(uploadsDir, listDirectories: false);
    router.mount('/uploads/', uploadsHandler);
    print('/uploads servido desde "$uploadsDir"');
  } else {
    print('Carpeta "$uploadsDir" no encontrada; /uploads deshabilitado');
  }

  router.get('/api/categorias', (req) => _redir308('/api/categorias/'));
  router.get('/api/productos', (req) => _redir308('/api/productos/'));
  router.get('/api/producto', (req) => _redir308('/api/producto/'));
  router.get('/api/resenas', (req) => _redir308('/api/resenas/'));
  router.get('/api/usuarios', (req) => _redir308('/api/usuarios/'));
  router.get('/api/productosVendedor', (req) => _redir308('/api/productosVendedor/'));
  router.get('/api/carrito', (req) => _redir308('/api/carrito/'));
  router.get('/api/productos/recomendados', (req) => _redir308('/api/productos/recomendados/'));

  router.mount('/api/categorias/', categoriasRouter);
  router.mount('/api/productos/', productosRouter);
  router.mount('/api/producto/', productoRouter);
  router.mount('/api/resenas/', resenasRouter);
  router.mount('/api/usuarios/', usuariosRouter);
  router.mount('/api/productosVendedor/', productosVendedorRouter);
  router.mount('/api/carrito/', carritoRouter());
  router.mount('/api/productos/recomendados/', recomendadosRouter());

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(router);

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Backend escuchando en http://${server.address.address}:${server.port}');
}
