// lib/routes/resenas.dart
//
// Endpoints:
//   GET    /api/resenas/<id_producto>
//   POST   /api/resenas/<id_producto>     (body: { id_usuario, calificacion, comentario })
//   DELETE /api/resenas/<id>              (id = id de reseña)
//
// Respuestas exactamente como Node:
//   [{ id, id_usuario, nombre_usuario, calificacion, comentario, fecha }, ...]
//   fecha en ISO 8601 con 'Z' si se recibe DateTime.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:backend_dart/db.dart' show dbQuery;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

String? _isoOrString(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toUtc().toIso8601String();
  // Si viene como string, intenta parsear
  try {
    final dt = DateTime.parse(v.toString());
    return dt.toUtc().toIso8601String();
  } catch (_) {
    return v.toString();
  }
}

// ========== GET /api/resenas/<id_producto> ==========
Future<Response> _getResenas(Request req, String idProductoStr) async {
  try {
    final idProd = int.tryParse(idProductoStr);
    if (idProd == null) {
      return Response(400,
          body: jsonEncode({'error': 'id_producto inválido'}),
          headers: _jsonHeaders);
    }

    final rs = await dbQuery(
      '''
      SELECT 
        r.id,
        r.id_usuario,
        u.nombre_usuario,
        r.calificacion,
        r.comentario,
        r.fecha
      FROM resenas r
      JOIN usuarios u ON u.id_usuario = r.id_usuario
      WHERE r.id_producto = ?
      ORDER BY r.fecha DESC
      ''',
      [idProd],
    );

    final out = <Map<String, dynamic>>[];
    for (final row in rs) {
      out.add({
        'id': row['id'],
        'id_usuario': row['id_usuario']?.toString(),
        'nombre_usuario': row['nombre_usuario']?.toString(),
        'calificacion': row['calificacion'] is num
            ? (row['calificacion'] as num).toInt()
            : int.tryParse('${row['calificacion']}'),
        'comentario': row['comentario']?.toString(),
        'fecha': _isoOrString(row['fecha']),
      });
    }

    return Response.ok(jsonEncode(out), headers: _jsonHeaders);
  } catch (e, st) {
    print('❌ Error al obtener reseñas: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al obtener reseñas'}),
      headers: _jsonHeaders,
    );
  }
}

// ========== POST /api/resenas/<id_producto> ==========
Future<Response> _postResena(Request req, String idProductoStr) async {
  try {
    final idProd = int.tryParse(idProductoStr);
    if (idProd == null) {
      return Response(400,
          body: jsonEncode({'error': 'id_producto inválido'}),
          headers: _jsonHeaders);
    }

    final body =
        (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final idUsuario = (body['id_usuario'] ?? '').toString().trim();
    final calif = body['calificacion'];
    final comentario = (body['comentario'] ?? '').toString().trim();

    if (idUsuario.isEmpty || calif == null || comentario.isEmpty) {
      return Response(400,
          body: jsonEncode(
              {'error': 'Faltan datos obligatorios: id_usuario, calificacion, comentario'}),
          headers: _jsonHeaders);
    }

    await dbQuery(
      '''
      INSERT INTO resenas (id_usuario, id_producto, calificacion, comentario, fecha)
      VALUES (?, ?, ?, ?, NOW())
      ''',
      [idUsuario, idProd, calif, comentario],
    );

    // Devolver lista actualizada como en Node
    return _getResenas(req, idProductoStr);
  } catch (e, st) {
    print('❌ Error al insertar reseña: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al insertar reseña'}),
      headers: _jsonHeaders,
    );
  }
}

// ========== DELETE /api/resenas/<id> ==========
Future<Response> _deleteResena(Request req, String idStr) async {
  try {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Response(400,
          body: jsonEncode({'error': 'id inválido'}),
          headers: _jsonHeaders);
    }

    await dbQuery('DELETE FROM resenas WHERE id = ?', [id]);
    return Response.ok(jsonEncode({'success': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('❌ Error al eliminar reseña: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al eliminar reseña'}),
      headers: _jsonHeaders,
    );
  }
}

// ========== Router exportado ==========
final Router resenasRouter = Router()
  // GET reseñas por producto
  ..get('/<id_producto|[0-9]+>', (req, idProd) => _getResenas(req, idProd))
  // POST nueva reseña para producto (id en URL)
  ..post('/<id_producto|[0-9]+>', (req, idProd) => _postResena(req, idProd))
  // DELETE por id de reseña
  ..delete('/<id|[0-9]+>', (req, id) => _deleteResena(req, id));
