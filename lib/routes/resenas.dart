// lib/routes/resenas.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;
import 'package:backend_dart/routes/shape.dart' show mapResenasFront, mapResenaFront;

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

/// ---------- GET /resenas/<id_producto> ----------
/// - Por defecto: { ok, count, data } con llaves en español
/// - ?shape=front => array o {ok,data} con llaves en inglés
/// - ?wrap=0 => devuelve array plano en vez de {ok,count,data}
Future<Response> resenasPorProductoHandler(Request req, String idProducto) async {
  try {
    final qp = req.url.queryParameters;
    final shapeFront = qp['shape'] == 'front';
    final wrapParam = qp['wrap']; // '1' | '0' | null
    final wrap = wrapParam == null ? true : wrapParam == '1';

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

    final listEs = rs.map<Map<String, dynamic>>((r) => {
          'id'            : _jsonSafe(r['id']),
          'id_usuario'    : _jsonSafe(r['id_usuario']),
          'nombre_usuario': _jsonSafe(r['nombre_usuario']),
          'calificacion'  : _toInt(r['calificacion']),
          'comentario'    : _jsonSafe(r['comentario']),
          'fecha'         : _jsonSafe(r['fecha']),
        }).toList();

    final data = shapeFront ? mapResenasFront(listEs) : listEs;

    if (wrap) {
      return Response.ok(
        jsonEncode({'ok': true, 'count': data.length, 'data': data}),
        headers: _jsonHeaders,
      );
    } else {
      return Response.ok(jsonEncode(data), headers: _jsonHeaders);
    }
  } catch (e, st) {
    print('Error GET /resenas/$idProducto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

/// ---------- POST /resenas/<id_producto> ----------
/// body: { id_usuario, calificacion, comentario }
/// - Devuelve la lista actualizada igual que GET (respeta ?shape=front y ?wrap)
Future<Response> crearResenaHandler(Request req, String idProducto) async {
  try {
    final qp = req.url.queryParameters;
    final shapeFront = qp['shape'] == 'front';
    final wrapParam = qp['wrap'];
    final wrap = wrapParam == null ? true : wrapParam == '1';

    final body = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final idUsuario   = (body['id_usuario'] ?? body['userId'] ?? '').toString().trim();
    final calificacion= _toInt(body['calificacion'] ?? body['rating']);
    final comentario  = (body['comentario']  ?? body['comment'] ?? '').toString();

    if (idUsuario.isEmpty || idProducto.isEmpty || comentario.isEmpty || calificacion <= 0) {
      return Response(400,
        body: jsonEncode({'error':'Faltan datos: id_usuario, calificacion(1-5), comentario'}),
        headers: _jsonHeaders);
    }

    await dbQuery(
      '''INSERT INTO resenas (id_usuario, id_producto, calificacion, comentario, fecha)
         VALUES (?, ?, ?, ?, NOW())''',
      [idUsuario, idProducto, calificacion, comentario],
    );

    // devolver listado actualizado con el mismo shape/wrap
    final fakeReq = Request('GET', req.requestedUri.replace(queryParameters: {
      ...req.url.queryParameters,
      if (shapeFront) 'shape': 'front',
      if (wrapParam != null) 'wrap': wrapParam,
    }));
    return resenasPorProductoHandler(fakeReq, idProducto);
  } catch (e, st) {
    print('Error POST /resenas/$idProducto: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error al crear reseña'}),
      headers: _jsonHeaders);
  }
}

/// ---------- DELETE /resenas/<id> ----------
Future<Response> eliminarResenaHandler(Request req, String id) async {
  try {
    final r = await dbQuery('DELETE FROM resenas WHERE id = ?', [id]);
    final n = r.affectedRows ?? 0;
    if (n == 0) {
      return Response(404,
        body: jsonEncode({'error':'No existe la reseña $id'}),
        headers: _jsonHeaders);
    }
    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /resenas/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error al eliminar reseña'}),
      headers: _jsonHeaders);
  }
}
