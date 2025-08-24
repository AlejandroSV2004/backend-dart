
// GET /api/categorias/
// Lee: SELECT codigo_categoria AS id, nombre, descripcion, slug FROM categorias
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:mysql1/mysql1.dart' show Blob;
import 'package:backend_dart/db.dart' show dbQuery;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toUtc().toIso8601String();
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

final Router categoriasRouter = Router()
  ..get('/', (Request req) async {
    try {
      final rows = await dbQuery(
        'SELECT codigo_categoria AS id, nombre, descripcion, slug FROM categorias',
      );

      const icons = [
        'Battery', 'Zap', 'Sun', 'Settings', 'Home', 'Grid3X3', 'Smartphone'
      ];
      const colors = ['blue', 'yellow', 'green', 'red', 'purple', 'indigo', 'teal'];
      final rnd = Random();
      final enriched = <Map<String, dynamic>>[];
      var i = 0;
      for (final row in rows) {
        enriched.add({
          'id'         : _jsonSafe(row['id']),
          'nombre'     : _jsonSafe(row['nombre']),
          'descripcion': _jsonSafe(row['descripcion']),
          'slug'       : _jsonSafe(row['slug']),
          'icono'      : icons[i % icons.length],
          'color'      : colors[i % colors.length],
          'cantidad'   : '${rnd.nextInt(1000) + 100}+ productos',
        });
        i++;
      }

      return Response.ok(jsonEncode(enriched), headers: _jsonHeaders);
    } catch (e, st) {
      print('Error al obtener categorías: $e');
      print(st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Error interno del servidor'}),
        headers: _jsonHeaders,
      );
    }
  });
