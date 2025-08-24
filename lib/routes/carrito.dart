// lib/routes/carrito.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  if (v is Uint8List) return base64Encode(v);
  if (v is Blob) {
    final b = v.toBytes();
    try {
      return utf8.decode(b);
    } catch (_) {
      return base64Encode(b);
    }
  }
  return v;
}

int _toInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final p = int.tryParse('$v');
  return p ?? fallback;
}

double _toDouble(dynamic v, {double fallback = 0.0}) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  final p = double.tryParse('$v');
  return p ?? fallback;
}

/// ---------- GET /carrito/<id_usuario> ----------
/// Lista los ítems del carrito del usuario.
/// - Por defecto: { ok, count, data } con llaves en español.
/// - ?wrap=0 => devuelve array plano.
/// - ?shape=front => llaves en inglés: { productId, quantity, name, price, image }
Future<Response> carritoPorUsuarioHandler(Request req, String idUsuario) async {
  try {
    final qp = req.url.queryParameters;
    final wrapParam = qp['wrap']; // '1' | '0' | null
    final wrap = wrapParam == null ? true : wrapParam == '1';
    final shapeFront = qp['shape'] == 'front';

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
      ORDER BY c.id_producto DESC
    ''', [idUsuario]);

    final dataEs = rs.map<Map<String, dynamic>>((r) => {
          'id_producto': _toInt(r['id_producto']),
          'cantidad': _toInt(r['cantidad'], fallback: 1),
          'nombre': _jsonSafe(r['nombre']),
          'precio': _toDouble(r['precio']),
          'imagen': _jsonSafe(r['imagen']),
        }).toList();

    final data = shapeFront
        ? dataEs
            .map((e) => {
                  'productId': e['id_producto'],
                  'quantity': e['cantidad'],
                  'name': e['nombre'],
                  'price': e['precio'],
                  'image': e['imagen'],
                })
            .toList()
        : dataEs;

    if (wrap) {
      return Response.ok(jsonEncode({'ok': true, 'count': data.length, 'data': data}),
          headers: _jsonHeaders);
    } else {
      return Response.ok(jsonEncode(data), headers: _jsonHeaders);
    }
  } catch (e, st) {
    print('Error GET /carrito/$idUsuario: $e\n$st');
    return Response.internalServerError(
        body: jsonEncode({'error': 'No se pudo obtener el carrito'}),
        headers: _jsonHeaders);
  }
}

/// ---------- POST /carrito/agregar ----------
/// body: { id_usuario|userId, id_producto|productId, cantidad|quantity }
/// Devuelve { ok: true }
Future<Response> agregarAlCarritoHandler(Request req) async {
  try {
    final body = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final idUsuario = (body['id_usuario'] ?? body['userId'] ?? '').toString().trim();
    final idProducto = _toInt(body['id_producto'] ?? body['productId']);
    final cantidad = _toInt(body['cantidad'] ?? body['quantity'], fallback: 1);

    if (idUsuario.isEmpty || idProducto == 0) {
      return Response(400,
          body: jsonEncode({'error': 'Faltan id_usuario/userId o id_producto/productId'}),
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
        headers: _jsonHeaders);
  }
}

/// ---------- POST /carrito/disminuir ----------
/// body: { id_usuario|userId, id_producto|productId }
/// Reduce en 1 la cantidad; si queda <=1, elimina el item.
Future<Response> disminuirDelCarritoHandler(Request req) async {
  try {
    final body = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final idUsuario = (body['id_usuario'] ?? body['userId'] ?? '').toString().trim();
    final idProducto = _toInt(body['id_producto'] ?? body['productId']);

    if (idUsuario.isEmpty || idProducto == 0) {
      return Response(400,
          body: jsonEncode({'error': 'Faltan id_usuario/userId o id_producto/productId'}),
          headers: _jsonHeaders);
    }

    // Disminuir si hay más de 1
    await dbQuery('''
      UPDATE carrito SET cantidad = cantidad - 1
      WHERE id_usuario = ? AND id_producto = ? AND cantidad > 1
    ''', [idUsuario, idProducto]);

    // Eliminar si quedó 1 (o no cambió) -> borra
    await dbQuery('''
      DELETE FROM carrito
      WHERE id_usuario = ? AND id_producto = ? AND cantidad <= 1
    ''', [idUsuario, idProducto]);

    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /carrito/disminuir: $e\n$st');
    return Response.internalServerError(
        body: jsonEncode({'error': 'No se pudo disminuir'}), headers: _jsonHeaders);
  }
}

/// ---------- DELETE /carrito/eliminar ----------
/// body: { id_usuario|userId, id_producto|productId }
Future<Response> eliminarItemCarritoHandler(Request req) async {
  try {
    final body = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final idUsuario = (body['id_usuario'] ?? body['userId'] ?? '').toString().trim();
    final idProducto = _toInt(body['id_producto'] ?? body['productId']);

    if (idUsuario.isEmpty || idProducto == 0) {
      return Response(400,
          body: jsonEncode({'error': 'Faltan id_usuario/userId o id_producto/productId'}),
          headers: _jsonHeaders);
    }

    await dbQuery('DELETE FROM carrito WHERE id_usuario = ? AND id_producto = ?',
        [idUsuario, idProducto]);

    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /carrito/eliminar: $e\n$st');
    return Response.internalServerError(
        body: jsonEncode({'error': 'No se pudo eliminar el ítem'}), headers: _jsonHeaders);
  }
}

/// ---------- DELETE /carrito/vaciar/<id_usuario> ----------
Future<Response> vaciarCarritoHandler(Request req, String idUsuario) async {
  try {
    await dbQuery('DELETE FROM carrito WHERE id_usuario = ?', [idUsuario]);
    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /carrito/vaciar/$idUsuario: $e\n$st');
    return Response.internalServerError(
        body: jsonEncode({'error': 'No se pudo vaciar el carrito'}),
        headers: _jsonHeaders);
  }
}
