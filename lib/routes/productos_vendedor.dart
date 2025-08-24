// lib/routes/productos_vendedor.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;
import 'package:backend_dart/routes/shape.dart' show mapProductosFront;

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

bool _toBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
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

/// GET /productosVendedor/<vendedorId>
/// - Por defecto: ARRAY con llaves en español
/// - ?wrap=1 => { ok, count, data }
/// - ?shape=front => llaves en inglés (name, price, image, ...)
Future<Response> productosDeVendedorHandler(Request req, String vendedorId) async {
  if (vendedorId.isEmpty) {
    return Response(400,
        body: jsonEncode({'error': 'Falta el ID del vendedor'}),
        headers: _jsonHeaders);
  }

  try {
    final qp = req.url.queryParameters;
    final wrap = qp['wrap'] == '1';
    final shapeFront = qp['shape'] == 'front';

    final rs = await dbQuery('''
      SELECT
        p.id_producto                AS id,
        p.id_vendedor,
        p.nombre,
        CAST(p.descripcion AS CHAR)  AS descripcion,
        p.precio,
        p.estado,
        p.envio_rapido,
        p.codigo_categoria,
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

    final listEs = rs.map<Map<String, dynamic>>((r) {
      return {
        'id'              : _jsonSafe(r['id']),
        'id_vendedor'     : _jsonSafe(r['id_vendedor']),
        'nombre'          : _jsonSafe(r['nombre']),
        'descripcion'     : _jsonSafe(r['descripcion']),
        'precio'          : _toDouble(r['precio']),
        'estado'          : _jsonSafe(r['estado']),
        'envio_rapido'    : _toBool(r['envio_rapido']),
        'codigo_categoria': _jsonSafe(r['codigo_categoria']),
        'stock'           : _toInt(r['stock']),
        'imagen'          : _jsonSafe(r['imagen']),
      };
    }).toList();

    final bodyObj = shapeFront ? mapProductosFront(listEs) : listEs;

    final body = wrap
        ? jsonEncode({'ok': true, 'count': bodyObj.length, 'data': bodyObj})
        : jsonEncode(bodyObj);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /productosVendedor/$vendedorId: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}
