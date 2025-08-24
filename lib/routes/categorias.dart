// lib/routes/categorias.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;
import 'package:backend_dart/routes/shape.dart' show mapCategoriasFront;

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

/// GET /categorias
/// - Por defecto: ARRAY plano con llaves en español.
/// - ?wrap=1 => { ok, count, data }
/// - ?shape=front => llaves en inglés (id,name,description,slug,icon,color,count)
Future<Response> categoriasHandler(Request request) async {
  try {
    final qp = request.url.queryParameters;
    final wrap = qp['wrap'] == '1';
    final shapeFront = qp['shape'] == 'front';

    // Traer categorías + conteo de productos por categoría (si existe la tabla productos)
    final results = await dbQuery('''
      SELECT
        c.codigo_categoria                         AS id,
        c.nombre                                   AS nombre,
        CAST(c.descripcion AS CHAR)                AS descripcion,
        CAST(c.slug        AS CHAR)                AS slug,
        COALESCE(pc.cnt, 0)                        AS cantidad_num
      FROM categorias c
      LEFT JOIN (
        SELECT codigo_categoria, COUNT(*) AS cnt
        FROM productos
        GROUP BY codigo_categoria
      ) pc ON pc.codigo_categoria = c.codigo_categoria
      ORDER BY c.nombre
    ''');

    // Iconos / colores por defecto (cíclicos)
    final icons  = ['Battery', 'Zap', 'Sun', 'Settings', 'Home', 'Grid3X3', 'Smartphone'];
    final colors = ['blue', 'yellow', 'green', 'red', 'purple', 'indigo', 'teal'];

    final rows = results.toList();
    final dataEs = <Map<String, dynamic>>[];

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final cnt = (r['cantidad_num'] as num?)?.toInt() ?? 0;

      dataEs.add({
        'id'         : _jsonSafe(r['id']),
        'nombre'     : _jsonSafe(r['nombre']),
        'descripcion': _jsonSafe(r['descripcion']),
        'slug'       : _jsonSafe(r['slug']),
        'icono'      : icons[i % icons.length],
        'color'      : colors[i % colors.length],
        'cantidad'   : '$cnt+ productos',
      });
    }

    // <-- aquí estaba el error: usar la función que mapea la LISTA completa
    final bodyObj = shapeFront ? mapCategoriasFront(dataEs) : dataEs;

    final body = wrap
        ? jsonEncode({'ok': true, 'count': bodyObj.length, 'data': bodyObj})
        : jsonEncode(bodyObj);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /categorias: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}
