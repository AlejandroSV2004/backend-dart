// Endpoints:
//   GET  /api/producto/<id>
//   PUT  /api/producto/<id>


import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:backend_dart/db.dart' show dbQuery;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

// ====== GET /api/producto/<id> ======
Future<Response> _getProductoPorId(Request req, String idStr) async {
  try {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Response(400,
          body: jsonEncode({'error': 'ID inválido'}),
          headers: _jsonHeaders);
    }

    final rs = await dbQuery(
      '''
      SELECT 
         p.id_producto AS id,
         p.nombre       AS name,
         p.descripcion  AS descripcion,
         p.precio       AS price,
         COALESCE(f.url_imagen, 'https://placehold.co/300x400') AS image,
         p.stock        AS stock,
         p.id_vendedor  AS sellerId,
         u.nombre_usuario AS sellerName,
         u.correo         AS sellerEmail
       FROM productos p
       JOIN usuarios u      ON p.id_vendedor = u.id_usuario
       LEFT JOIN fotos_producto f ON f.id_producto = p.id_producto
       WHERE p.id_producto = ?
       LIMIT 1
      ''',
      [id],
    );

    if (rs.isEmpty) {
      return Response(404,
          body: jsonEncode({'error': 'Producto no encontrado'}),
          headers: _jsonHeaders);
    }

    final row = rs.first;

    final out = {
      'id': row['id'],
      'name': row['name']?.toString(),
      'descripcion': row['descripcion']?.toString(),
      'price': '${row['price']}',
      'image': row['image']?.toString(),
      'stock': (row['stock'] is num) ? (row['stock'] as num).toInt() : row['stock'],
      'sellerId': row['sellerId']?.toString(),
      'sellerName': row['sellerName']?.toString(),
      'sellerEmail': row['sellerEmail']?.toString(),
    };

    return Response.ok(jsonEncode(out), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error al obtener producto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

// ====== PUT /api/producto/<id> ======
Future<Response> _putActualizarProducto(Request req, String idStr) async {
  try {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Response(400,
          body: jsonEncode({'error': 'ID inválido'}),
          headers: _jsonHeaders);
    }

    final body =
        (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final nombre      = body['nombre'];
    final descripcion = body['descripcion'];
    final stock       = body['stock'];

    // Existe?
    final existe = await dbQuery(
      'SELECT * FROM productos WHERE id_producto = ?',
      [id],
    );
    if (existe.isEmpty) {
      return Response(404,
          body: jsonEncode({'error': 'Producto no encontrado'}),
          headers: _jsonHeaders);
    }
    final cur = existe.first;

    final nuevoNombre = (nombre ?? cur['nombre'])?.toString();
    final nuevaDescripcion = (descripcion ?? cur['descripcion'])?.toString();
    final nuevoStock = (stock ?? cur['stock']);

    // Actualizar
    final upd = await dbQuery(
      '''
      UPDATE productos
      SET nombre = ?, descripcion = ?, stock = ?
      WHERE id_producto = ?
      ''',
      [nuevoNombre, nuevaDescripcion, nuevoStock, id],
    );

    final affected = upd.affectedRows ?? 0;
    if (affected == 0) {
      return Response(404,
          body: jsonEncode({'error': 'No se actualizó ningún producto'}),
          headers: _jsonHeaders);
    }

    // Devolver versión resumida
    final sel = await dbQuery(
      '''
      SELECT 
         id_producto AS id, 
         nombre      AS name, 
         descripcion, 
         precio      AS price, 
         stock
      FROM productos 
      WHERE id_producto = ?
      ''',
      [id],
    );

    final r = sel.first;
    final out = {
      'id': r['id'],
      'name': r['name']?.toString(),
      'descripcion': r['descripcion']?.toString(),
      'price': '${r['price']}',
      'stock': (r['stock'] is num) ? (r['stock'] as num).toInt() : r['stock'],
    };

    return Response.ok(jsonEncode(out), headers: _jsonHeaders);
  } catch (e, st) {
    print('❌ Error al actualizar producto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

Future<Response> _debugCatchAll(Request req, String _path) async {
  print('[DEBUG producto.dart] Método: ${req.method}, URL: ${req.requestedUri}');
  return Response.notFound(
    jsonEncode({'error': 'Ruta no encontrada dentro de producto.dart'}),
    headers: _jsonHeaders,
  );
}

// ====== Router exportado ======
final Router productoRouter = Router()
  ..get('/<id|[0-9]+>', (req, id) => _getProductoPorId(req, id))
  ..put('/<id|[0-9]+>', (req, id) => _putActualizarProducto(req, id))
  ..all('/<path|.*>', (req, path) => _debugCatchAll(req, path));
