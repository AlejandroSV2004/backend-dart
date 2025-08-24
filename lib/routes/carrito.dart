import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  return v;
}

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
    ''', [idUsuario]);

    final data = rs.map((r) => {
      'id_producto': _jsonSafe(r['id_producto']),
      'cantidad'   : r['cantidad'],
      'nombre'     : _jsonSafe(r['nombre']),
      'precio'     : r['precio'],
      'imagen'     : _jsonSafe(r['imagen']),
    }).toList();

    return Response.ok(jsonEncode({'ok': true, 'count': data.length, 'data': data}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error GET /carrito/$idUsuario: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'No se pudo obtener el carrito'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}

Future<Response> agregarAlCarritoHandler(Request req) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
    final idUsuario   = body['id_usuario'];
    final idProducto  = body['id_producto'];
    final cantidad    = (body['cantidad'] ?? 1) as int;

    if (idUsuario == null || idProducto == null) {
      return Response(400, body: jsonEncode({'error':'Faltan id_usuario o id_producto'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }

    await dbQuery('''
      INSERT INTO carrito (id_usuario, id_producto, cantidad)
      VALUES (?, ?, ?)
      ON DUPLICATE KEY UPDATE cantidad = cantidad + VALUES(cantidad)
    ''', [idUsuario, idProducto, cantidad]);

    return Response.ok(jsonEncode({'ok': true}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error POST /carrito/agregar: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'No se pudo agregar al carrito'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}

Future<Response> disminuirDelCarritoHandler(Request req) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
    final idUsuario   = body['id_usuario'];
    final idProducto  = body['id_producto'];

    if (idUsuario == null || idProducto == null) {
      return Response(400, body: jsonEncode({'error':'Faltan id_usuario o id_producto'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }

    await dbQuery('''
      UPDATE carrito SET cantidad = cantidad - 1
      WHERE id_usuario = ? AND id_producto = ? AND cantidad > 1
    ''', [idUsuario, idProducto]);

    await dbQuery('''
      DELETE FROM carrito
      WHERE id_usuario = ? AND id_producto = ? AND cantidad <= 1
    ''', [idUsuario, idProducto]);

    return Response.ok(jsonEncode({'ok': true}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error POST /carrito/disminuir: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'No se pudo disminuir'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}


Future<Response> eliminarItemCarritoHandler(Request req) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
    final idUsuario   = body['id_usuario'];
    final idProducto  = body['id_producto'];

    if (idUsuario == null || idProducto == null) {
      return Response(400, body: jsonEncode({'error':'Faltan id_usuario o id_producto'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }

    await dbQuery('DELETE FROM carrito WHERE id_usuario = ? AND id_producto = ?', [idUsuario, idProducto]);

    return Response.ok(jsonEncode({'ok': true}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error DELETE /carrito/eliminar: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'No se pudo eliminar el ítem'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}


Future<Response> vaciarCarritoHandler(Request req, String idUsuario) async {
  try {
    await dbQuery('DELETE FROM carrito WHERE id_usuario = ?', [idUsuario]);
    return Response.ok(jsonEncode({'ok': true}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error DELETE /carrito/vaciar/$idUsuario: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'No se pudo vaciar el carrito'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}
