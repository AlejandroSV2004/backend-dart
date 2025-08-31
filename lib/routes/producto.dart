import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:backend_dart/db.dart' show dbQuery, dbQueryMaps;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

Future<Response> _getProductoPorId(Request req, String idStr) async {
  try {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Response(400, body: jsonEncode({'error': 'ID inválido'}), headers: _jsonHeaders);
    }

    final rs = await dbQueryMaps(
      '''
      SELECT 
         p.id_producto AS id,
         p.nombre AS name,
         p.descripcion AS descripcion,
         p.precio AS price,
         COALESCE(f.url_imagen, 'https://placehold.co/300x400') AS image,
         p.stock AS stock,
         p.id_vendedor AS sellerId,
         u.nombre_usuario AS sellerName,
         u.correo AS sellerEmail
       FROM productos p
       JOIN usuarios u ON p.id_vendedor = u.id_usuario
       LEFT JOIN fotos_producto f ON f.id_producto = p.id_producto
       WHERE p.id_producto = ?
       LIMIT 1
      ''',
      [id],
    );

    if (rs.isEmpty) {
      return Response(404, body: jsonEncode({'error': 'Producto no encontrado'}), headers: _jsonHeaders);
    }

    final row = rs.first;
    final out = {
      'id': row['id'],
      'name': row['name']?.toString(),
      'descripcion': row['descripcion']?.toString(),
      'price': '${row['price']}',
      'image': row['image']?.toString(),
      'stock': row['stock'] is num ? (row['stock'] as num).toInt() : row['stock'],
      'sellerId': row['sellerId']?.toString(),
      'sellerName': row['sellerName']?.toString(),
      'sellerEmail': row['sellerEmail']?.toString(),
    };

    return Response.ok(jsonEncode(out), headers: _jsonHeaders);
  } catch (e) {
    return Response.internalServerError(body: jsonEncode({'error': 'Error interno del servidor'}), headers: _jsonHeaders);
  }
}

Future<Response> _putActualizarProducto(Request req, String idStr) async {
  try {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Response(400, body: jsonEncode({'error': 'ID inválido'}), headers: _jsonHeaders);
    }

    final body = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final nombre = body['nombre'] ?? body['name'];
    final descripcion = body['descripcion'];
    final stock = body['stock'];

    final existe = await dbQueryMaps('SELECT * FROM productos WHERE id_producto = ?', [id]);
    if (existe.isEmpty) {
      return Response(404, body: jsonEncode({'error': 'Producto no encontrado'}), headers: _jsonHeaders);
    }
    final cur = existe.first;

    final nuevoNombre = (nombre ?? cur['nombre'])?.toString();
    final nuevaDescripcion = (descripcion ?? cur['descripcion'])?.toString();
    final nuevoStock = (stock ?? cur['stock']);

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
      return Response(404, body: jsonEncode({'error': 'No se actualizó ningún producto'}), headers: _jsonHeaders);
    }

    final sel = await dbQueryMaps(
      '''
      SELECT 
         id_producto AS id, 
         nombre AS name, 
         descripcion, 
         precio AS price, 
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
      'stock': r['stock'] is num ? (r['stock'] as num).toInt() : r['stock'],
    };

    return Response.ok(jsonEncode(out), headers: _jsonHeaders);
  } catch (e) {
    return Response.internalServerError(body: jsonEncode({'error': 'Error interno del servidor'}), headers: _jsonHeaders);
  }
}

Future<Response> _putActualizarImagen(Request req, String idStr) async {
  try {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Response(400, body: jsonEncode({'error': 'ID inválido'}), headers: _jsonHeaders);
    }

    final bodyRaw = await req.readAsString();
    final body = bodyRaw.isEmpty ? <String, dynamic>{} : (jsonDecode(bodyRaw) as Map<String, dynamic>);
    final idUsuario = body['id_usuario']?.toString();
    final image = body['image']?.toString();

    if (idUsuario == null || idUsuario.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'id_usuario requerido'}), headers: _jsonHeaders);
    }
    if (image == null || image.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'image requerido'}), headers: _jsonHeaders);
    }

    final prod = await dbQueryMaps('SELECT id_vendedor FROM productos WHERE id_producto = ?', [id]);
    if (prod.isEmpty) {
      return Response(404, body: jsonEncode({'error': 'Producto no encontrado'}), headers: _jsonHeaders);
    }
    final vendedor = prod.first['id_vendedor']?.toString();
    if (vendedor != idUsuario) {
      return Response(403, body: jsonEncode({'error': 'No autorizado'}), headers: _jsonHeaders);
    }

    final foto = await dbQueryMaps('SELECT id FROM fotos_producto WHERE id_producto = ? LIMIT 1', [id]);
    if (foto.isEmpty) {
      await dbQuery('INSERT INTO fotos_producto (id_producto, url_imagen) VALUES (?, ?)', [id, image]);
    } else {
      await dbQuery('UPDATE fotos_producto SET url_imagen = ? WHERE id_producto = ?', [image, id]);
    }

    return Response.ok(jsonEncode({'ok': true, 'image': image}), headers: _jsonHeaders);
  } catch (e) {
    return Response.internalServerError(body: jsonEncode({'error': 'Error interno del servidor'}), headers: _jsonHeaders);
  }
}

Future<Response> _deleteProducto(Request req, String idStr) async {
  try {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Response(400, body: jsonEncode({'error': 'ID inválido'}), headers: _jsonHeaders);
    }

    final bodyRaw = await req.readAsString();
    final body = bodyRaw.isEmpty ? <String, dynamic>{} : (jsonDecode(bodyRaw) as Map<String, dynamic>);
    final idUsuario = body['id_usuario']?.toString();

    if (idUsuario == null || idUsuario.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'id_usuario requerido'}), headers: _jsonHeaders);
    }

    final prod = await dbQueryMaps('SELECT id_vendedor FROM productos WHERE id_producto = ?', [id]);
    if (prod.isEmpty) {
      return Response(404, body: jsonEncode({'error': 'Producto no encontrado'}), headers: _jsonHeaders);
    }
    final vendedor = prod.first['id_vendedor']?.toString();
    if (vendedor != idUsuario) {
      return Response(403, body: jsonEncode({'error': 'No autorizado'}), headers: _jsonHeaders);
    }

    await dbQuery('DELETE FROM carrito WHERE id_producto = ?', [id]);
    await dbQuery('DELETE FROM resenas WHERE id_producto = ?', [id]);
    await dbQuery('DELETE FROM fotos_producto WHERE id_producto = ?', [id]);
    final del = await dbQuery('DELETE FROM productos WHERE id_producto = ? LIMIT 1', [id]);

    final ok = (del.affectedRows ?? 0) > 0;
    if (!ok) {
      return Response(500, body: jsonEncode({'error': 'No se pudo eliminar'}), headers: _jsonHeaders);
    }

    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e) {
    return Response.internalServerError(body: jsonEncode({'error': 'Error interno del servidor'}), headers: _jsonHeaders);
  }
}

Future<Response> _debugCatchAll(Request req, String _path) async {
  return Response.notFound(jsonEncode({'error': 'Ruta no encontrada dentro de producto.dart'}), headers: _jsonHeaders);
}

final Router productoRouter = Router()
  ..get('/<id|[0-9]+>', (req, id) => _getProductoPorId(req, id))
  ..put('/<id|[0-9]+>', (req, id) => _putActualizarProducto(req, id))
  ..put('/<id|[0-9]+>/imagen', (req, id) => _putActualizarImagen(req, id))
  ..delete('/<id|[0-9]+>', (req, id) => _deleteProducto(req, id))
  ..all('/<path|.*>', (req, path) => _debugCatchAll(req, path));
