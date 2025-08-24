import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  return v;
}

Future<Response> productosDeVendedorHandler(Request req, String vendedorId) async {
  if (vendedorId.isEmpty) {
    return Response(400, body: jsonEncode({'error':'Falta el ID del vendedor'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }

  try {
    final rs = await dbQuery('''
      SELECT
        p.id_producto AS id,
        p.nombre,
        p.precio,
        p.estado,
        p.stock,
        (
          SELECT CAST(fp.url AS CHAR) 
          FROM fotos_producto fp
          WHERE fp.id_producto = p.id_producto
          ORDER BY fp.id_foto ASC
          LIMIT 1
        ) AS imagen
      FROM productos p
      WHERE p.id_vendedor = ?
      ORDER BY p.id_producto DESC
    ''', [vendedorId]);

    final data = rs.map((r) => {
      'id'     : _jsonSafe(r['id']),
      'nombre' : _jsonSafe(r['nombre']),
      'precio' : r['precio'],
      'estado' : _jsonSafe(r['estado']),
      'stock'  : r['stock'],
      'imagen' : _jsonSafe(r['imagen']),
    }).toList();

    return Response.ok(jsonEncode({'ok': true, 'count': data.length, 'data': data}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error GET /productosVendedor/$vendedorId: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}
