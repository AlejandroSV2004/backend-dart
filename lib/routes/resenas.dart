import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  return v;
}


Future<Response> resenasPorProductoHandler(Request req, String idProducto) async {
  try {
    final rs = await dbQuery('''
      SELECT 
        r.id,
        r.id_usuario,
        u.nombre_usuario,
        r.calificacion,
        CAST(r.comentario AS CHAR) AS comentario,
        r.fecha
      FROM resenas r
      JOIN usuarios u ON u.id_usuario = r.id_usuario
      WHERE r.id_producto = ?
      ORDER BY r.fecha DESC
    ''', [idProducto]);

    final data = rs.map((r) => {
      'id'             : _jsonSafe(r['id']),
      'id_usuario'     : _jsonSafe(r['id_usuario']),
      'nombre_usuario' : _jsonSafe(r['nombre_usuario']),
      'calificacion'   : _jsonSafe(r['calificacion']),
      'comentario'     : _jsonSafe(r['comentario']),
      'fecha'          : _jsonSafe(r['fecha']),
    }).toList();

    return Response.ok(jsonEncode({'ok': true, 'count': data.length, 'data': data}),
      headers: {'Content-Type': 'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error GET /resenas/$idProducto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: {'Content-Type': 'application/json; charset=utf-8'});
  }
}

Future<Response> crearResenaHandler(Request req, String idProducto) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
    final idUsuario   = body['id_usuario'];
    final calificacion= body['calificacion'];
    final comentario  = body['comentario'];

    if (idUsuario == null || idProducto.isEmpty || calificacion == null || comentario == null) {
      return Response(400, body: jsonEncode({'error':'Faltan datos obligatorios'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }

    await dbQuery(
      '''INSERT INTO resenas (id_usuario, id_producto, calificacion, comentario, fecha)
         VALUES (?, ?, ?, ?, NOW())''',
      [idUsuario, idProducto, calificacion, comentario],
    );

    
    return resenasPorProductoHandler(req, idProducto);
  } catch (e, st) {
    print('Error POST /resenas/$idProducto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error al crear reseña'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}

Future<Response> eliminarResenaHandler(Request req, String id) async {
  try {
    await dbQuery('DELETE FROM resenas WHERE id = ?', [id]);
    return Response.ok(jsonEncode({'ok': true}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error DELETE /resenas/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error al eliminar reseña'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}
