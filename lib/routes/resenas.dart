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

int _toInt(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  final p = int.tryParse('$v');
  return p ?? fallback;
}

/// GET /resenas/:idProducto
/// - Por defecto: ARRAY plano
/// - Compat: ?wrap=1 => { ok, count, data }
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
      'calificacion'   : _toInt(r['calificacion']),
      'comentario'     : _jsonSafe(r['comentario']),
      'fecha'          : _jsonSafe(r['fecha']),
    }).toList();

    final wrap = req.url.queryParameters['wrap'] == '1';
    final body = wrap
      ? jsonEncode({'ok': true, 'count': data.length, 'data': data})
      : jsonEncode(data);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /resenas/$idProducto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

/// POST /resenas/:idProducto
/// body: { id_usuario, calificacion(1..5), comentario }
/// - Devuelve el OBJETO creado (201). Compat: ?wrap=1 => { ok, data }
Future<Response> crearResenaHandler(Request req, String idProducto) async {
  try {
    final bodyStr = await req.readAsString();
    final body = (bodyStr.isEmpty ? {} : jsonDecode(bodyStr)) as Map<String, dynamic>;

    final idUsuario    = body['id_usuario']?.toString().trim();
    final calificacion = _toInt(body['calificacion']);
    final comentario   = (body['comentario'] ?? '').toString().trim();

    if (idUsuario == null || idUsuario.isEmpty || idProducto.isEmpty || comentario.isEmpty) {
      return Response(400,
        body: jsonEncode({'error': 'Faltan datos obligatorios (id_usuario, comentario)'}),
        headers: _jsonHeaders);
    }
    if (calificacion < 1 || calificacion > 5) {
      return Response(400,
        body: jsonEncode({'error': 'calificacion debe estar entre 1 y 5'}),
        headers: _jsonHeaders);
    }

    final ins = await dbQuery(
      '''INSERT INTO resenas (id_usuario, id_producto, calificacion, comentario, fecha)
         VALUES (?, ?, ?, ?, NOW())''',
      [idUsuario, idProducto, calificacion, comentario],
    );

    final newId = ins.insertId;

    // Traemos la reseña recién creada con JOIN para incluir nombre_usuario
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
      WHERE r.id = ?
      LIMIT 1
    ''', [newId]);

    final created = rs.isNotEmpty ? {
      'id'             : _jsonSafe(rs.first['id']),
      'id_usuario'     : _jsonSafe(rs.first['id_usuario']),
      'nombre_usuario' : _jsonSafe(rs.first['nombre_usuario']),
      'calificacion'   : _toInt(rs.first['calificacion']),
      'comentario'     : _jsonSafe(rs.first['comentario']),
      'fecha'          : _jsonSafe(rs.first['fecha']),
    } : {
      // Fallback si no se pudo leer (raro)
      'id'             : newId,
      'id_usuario'     : idUsuario,
      'nombre_usuario' : null,
      'calificacion'   : calificacion,
      'comentario'     : comentario,
      'fecha'          : DateTime.now().toIso8601String(),
    };

    final wrap = req.url.queryParameters['wrap'] == '1';
    final bodyOut = wrap
      ? jsonEncode({'ok': true, 'data': created})
      : jsonEncode(created);

    return Response(201, body: bodyOut, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /resenas/$idProducto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al crear reseña'}),
      headers: _jsonHeaders,
    );
  }
}

/// DELETE /resenas/:id
Future<Response> eliminarResenaHandler(Request req, String id) async {
  try {
    final r = await dbQuery('DELETE FROM resenas WHERE id = ?', [id]);
    final n = r.affectedRows ?? 0;

    if (n == 0) {
      return Response(404,
        body: jsonEncode({'error': 'Reseña no encontrada'}),
        headers: _jsonHeaders);
    }

    return Response.ok(jsonEncode({'ok': true, 'deleted': id}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /resenas/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al eliminar reseña'}),
      headers: _jsonHeaders,
    );
  }
}
