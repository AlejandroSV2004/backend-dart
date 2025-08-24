import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  return v;
}

Future<Response> productoGetHandler(Request req, String id) async {
  try {
    final rs = await dbQuery('''
      SELECT 
        p.id_producto AS id,
        p.nombre,
        CAST(p.descripcion AS CHAR) AS descripcion,
        p.precio,
        p.estado,
        p.envio_rapido,
        p.codigo_categoria,
        p.stock,
        u.id_usuario AS vendedor_id,
        u.nombre_usuario AS vendedor_nombre
      FROM productos p
      LEFT JOIN usuarios u ON u.id_usuario = p.id_vendedor
      WHERE p.id_producto = ?
      LIMIT 1
    ''', [id]);

    if (rs.isEmpty) {
      return Response(404, body: jsonEncode({'error':'Producto no encontrado'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }

    final base = rs.first;
    final fotos = await dbQuery('''
      SELECT CAST(url AS CHAR) AS url
      FROM fotos_producto
      WHERE id_producto = ?
      ORDER BY id_foto ASC
    ''', [id]);

    final data = {
      'id'              : _jsonSafe(base['id']),
      'nombre'          : _jsonSafe(base['nombre']),
      'descripcion'     : _jsonSafe(base['descripcion']),
      'precio'          : base['precio'],
      'estado'          : _jsonSafe(base['estado']),
      'envio_rapido'    : _jsonSafe(base['envio_rapido']),
      'codigo_categoria': _jsonSafe(base['codigo_categoria']),
      'stock'           : base['stock'],
      'vendedor': {
        'id'    : _jsonSafe(base['vendedor_id']),
        'nombre': _jsonSafe(base['vendedor_nombre']),
      },
      'fotos': fotos.map((r) => _jsonSafe(r['url'])).toList(),
    };

    return Response.ok(jsonEncode({'ok': true, 'data': data}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error GET /producto/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}

Future<Response> productoUpdateHandler(Request req, String id) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
    final allowed = <String, dynamic>{};
    if (body.containsKey('nombre'))      allowed['nombre'] = body['nombre'];
    if (body.containsKey('descripcion')) allowed['descripcion'] = body['descripcion'];
    if (body.containsKey('stock'))       allowed['stock'] = body['stock'];

    if (allowed.isEmpty) {
      return Response(400, body: jsonEncode({'error':'No hay campos válidos para actualizar (nombre, descripcion, stock)'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }

    final sets = <String>[];
    final params = <dynamic>[];
    allowed.forEach((k, v) {
      sets.add('$k = ?');
      params.add(v);
    });
    params.add(id);

    await dbQuery('UPDATE productos SET ${sets.join(', ')} WHERE id_producto = ?', params);

    return productoGetHandler(req, id);
  } catch (e, st) {
    print('Error PUT /producto/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}
