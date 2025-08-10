import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  if (v is Uint8List) return base64Encode(v);
  if (v is Blob) {
    final bytes = v.toBytes();
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return base64Encode(bytes);
    }
  }
  return v;
}

Future<Response> categoriasHandler(Request request) async {
  try {
    final results = await dbQuery('''
      SELECT 
        codigo_categoria AS id,
        nombre,
        CAST(descripcion AS CHAR) AS descripcion,
        CAST(slug AS CHAR) AS slug
      FROM categorias
      ORDER BY nombre
    ''');

    final icons  = ['Battery', 'Zap', 'Sun', 'Settings', 'Home', 'Grid3X3', 'Smartphone'];
    final colors = ['blue', 'yellow', 'green', 'red', 'purple', 'indigo', 'teal'];

    final rows = results.toList();
    final data = <Map<String, dynamic>>[];

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      data.add({
        'id'        : _jsonSafe(r['id']),
        'nombre'    : _jsonSafe(r['nombre']),
        'descripcion': _jsonSafe(r['descripcion']),
        'slug'      : _jsonSafe(r['slug']),
        'icono'     : icons[i % icons.length],
        'color'     : colors[i % colors.length],
        'cantidad'  : '${(100 + i * 37) % 1000}+ productos',
      });
    }

    return Response.ok(
      jsonEncode({'ok': true, 'data': data}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  } catch (e, st) {
    print('Error al obtener categorías: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}
