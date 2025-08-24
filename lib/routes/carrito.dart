import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  return v;
}

/// GET /carrito/:idUsuario
/// - Formato por defecto: ARRAY plano de ítems
/// - Compat: agrega ?wrap=1 para { ok, count, data }
Future<Response> carritoPorUsuarioHandler(Request req, String idUsuario) async {
  try {
    final rs = await dbQuery('''
      SELECT 
        c.id_producto,
        c.cantidad,
        p.nombre,
        p.precio,
        (
          SELECT CAST(fp.url AS CHAR)
          FROM fotos_producto fp
          WHERE fp.id_producto = p.id_producto
          ORDER BY fp.id_foto ASC
          LIMIT 1
        ) AS imagen
      FROM carrito c
      JOIN productos p ON c.id_producto = p.id_producto
      WHERE c.id_usuario = ?
      ORDER BY p.nombre
    ''', [idUsuario]);

    final data = rs.map((r) {
      final cantidad = (r['cantidad'] as num?)?.toInt() ?? 0;
      final precio = (r['precio'] as num?)?.toDouble() ?? 0.0;
      return {
        'id_producto': _jsonSafe(r['id_producto']),
        'cantidad'   : cantidad,
        'nombre'     : _jsonSafe(r['nombre']),
        'precio'     : precio,
        'subtotal'   : double.parse((cantidad * precio).toStringAsFixed(2)),
        'imagen'     : _jsonSafe(r['imagen']),
      };
    }).toList();

    final wrap = req.url.queryParameters['wrap'] == '1';
    final body = wrap
        ? jsonEncode({'ok': true, 'count': data.length, 'data': data})
        : jsonEncode(data);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /carrito/$idUsuario: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'No se pudo obtener el carrito'}),
      headers: _jsonHeaders,
    );
  }
}

/// POST /carrito/agregar
/// body: { id_usuario, id_producto, cantidad? }
Future<Response> agregarAlCarritoHandler(Request req) async {
  try {
    final bodyStr = await req.readAsString();
    final body = (bodyStr.isEmpty ? {} : jsonDecode(bodyStr)) as Map<String, dynamic>;
    final idUsuario  = body['id_usuario'];
    final idProducto = body['id_producto'];
    final cantidad   = (body['cantidad'] ?? 1) as int;

    if (idUsuario == null || idProducto == null) {
      return Response(400,
        body: jsonEncode({'error': 'Faltan id_usuario o id_producto'}),
        headers: _jsonHeaders);
    }

    await dbQuery('''
      INSERT INTO carrito (id_usuario, id_producto, cantidad)
      VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE cantidad = cantidad + VALUES(cantidad)
    ''', [idUsuario, idProducto, cantidad]);

    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /carrito/agregar: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'No se pudo agregar al carrito'}),
      headers: _jsonHeaders,
    );
  }
}

/// POST /carrito/disminuir
/// body: { id_usuario, id_producto }
Future<Response> disminuirDelCarritoHandler(Request req) async {
  try {
    final bodyStr = await req.readAsString();
    final body = (bodyStr.isEmpty ? {} : jsonDecode(bodyStr)) as Map<String, dynamic>;
    final idUsuario  = body['id_usuario'];
    final idProducto = body['id_producto'];

    if (idUsuario == null || idProducto == null) {
      return Response(400,
        body: jsonEncode({'error': 'Faltan id_usuario o id_producto'}),
        headers: _jsonHeaders);
    }

    // Decrementa si >1, si queda <=1 lo elimina
    await dbQuery('''
      UPDATE carrito SET cantidad = cantidad - 1
      WHERE id_usuario = ? AND id_producto = ? AND cantidad > 1
    ''', [idUsuario, idProducto]);

    await dbQuery('''
      DELETE FROM carrito
      WHERE id_usuario = ? AND id_producto = ? AND cantidad <= 1
    ''', [idUsuario, idProducto]);

    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /carrito/disminuir: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'No se pudo disminuir'}),
      headers: _jsonHeaders,
    );
  }
}

/// DELETE /carrito/eliminar
/// body: { id_usuario, id_producto }
Future<Response> eliminarItemCarritoHandler(Request req) async {
  try {
    final bodyStr = await req.readAsString();
    final body = (bodyStr.isEmpty ? {} : jsonDecode(bodyStr)) as Map<String, dynamic>;
    final idUsuario  = body['id_usuario'];
    final idProducto = body['id_producto'];

    if (idUsuario == null || idProducto == null) {
      return Response(400,
        body: jsonEncode({'error': 'Faltan id_usuario o id_producto'}),
        headers: _jsonHeaders);
    }

    await dbQuery(
      'DELETE FROM carrito WHERE id_usuario = ? AND id_producto = ?',
      [idUsuario, idProducto],
    );

    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /carrito/eliminar: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'No se pudo eliminar el ítem'}),
      headers: _jsonHeaders,
    );
  }
}

/// DELETE /carrito/vaciar/:idUsuario
Future<Response> vaciarCarritoHandler(Request req, String idUsuario) async {
  try {
    await dbQuery('DELETE FROM carrito WHERE id_usuario = ?', [idUsuario]);
    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /carrito/vaciar/$idUsuario: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'No se pudo vaciar el carrito'}),
      headers: _jsonHeaders,
    );
  }
}
