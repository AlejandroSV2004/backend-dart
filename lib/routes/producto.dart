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

Future<Map<String, dynamic>?> _fetchProducto(String id) async {
  final rs = await dbQuery('''
    SELECT 
      p.id_producto                 AS id,
      p.nombre                      AS nombre,
      CAST(p.descripcion AS CHAR)   AS descripcion,
      p.precio                      AS precio,
      p.estado                      AS estado,
      p.envio_rapido                AS envio_rapido,
      p.codigo_categoria            AS codigo_categoria,
      p.stock                       AS stock,
      u.id_usuario                  AS vendedor_id,
      u.nombre_usuario              AS vendedor_nombre
    FROM productos p
    LEFT JOIN usuarios u ON u.id_usuario = p.id_vendedor
    WHERE p.id_producto = ?
    LIMIT 1
  ''', [id]);

  if (rs.isEmpty) return null;

  final base = rs.first;

  final fotos = await dbQuery('''
    SELECT CAST(url AS CHAR) AS url
    FROM fotos_producto
    WHERE id_producto = ?
    ORDER BY id_foto ASC
  ''', [id]);

  final precio = (base['precio'] as num?)?.toDouble() ?? 0.0;
  final stock  = (base['stock']  as num?)?.toInt() ?? 0;
  final envioRapidoRaw = base['envio_rapido'];
  final envioRapido = (envioRapidoRaw is bool)
      ? envioRapidoRaw
      : ((envioRapidoRaw is num) ? envioRapidoRaw != 0 : false);

  return {
    'id'              : _jsonSafe(base['id']),
    'nombre'          : _jsonSafe(base['nombre']),
    'descripcion'     : _jsonSafe(base['descripcion']),
    'precio'          : precio,
    'estado'          : _jsonSafe(base['estado']),
    'envio_rapido'    : envioRapido,
    'codigo_categoria': _jsonSafe(base['codigo_categoria']),
    'stock'           : stock,
    'vendedor': {
      'id'    : _jsonSafe(base['vendedor_id']),
      'nombre': _jsonSafe(base['vendedor_nombre']),
    },
    'fotos': fotos.map((r) => _jsonSafe(r['url'])).toList(),
  };
}

/// GET /producto/:id
/// - Por defecto: OBJETO plano del producto
/// - Compat: agrega ?wrap=1 para { ok, data }
Future<Response> productoGetHandler(Request req, String id) async {
  try {
    final prod = await _fetchProducto(id);
    if (prod == null) {
      return Response(404,
        body: jsonEncode({'error': 'Producto no encontrado'}),
        headers: _jsonHeaders);
    }

    final wrap = req.url.queryParameters['wrap'] == '1';
    final body = wrap
        ? jsonEncode({'ok': true, 'data': prod})
        : jsonEncode(prod);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /producto/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

/// PUT /producto/:id
/// body: { nombre?, descripcion?, stock? }
/// - Devuelve el producto actualizado (mismo formato que GET)
Future<Response> productoUpdateHandler(Request req, String id) async {
  try {
    final bodyStr = await req.readAsString();
    final body = (bodyStr.isEmpty ? {} : jsonDecode(bodyStr)) as Map<String, dynamic>;

    final allowed = <String, dynamic>{};
    if (body.containsKey('nombre'))      allowed['nombre'] = body['nombre'];
    if (body.containsKey('descripcion')) allowed['descripcion'] = body['descripcion'];
    if (body.containsKey('stock'))       allowed['stock'] = body['stock'];

    if (allowed.isEmpty) {
      return Response(400,
        body: jsonEncode({'error': 'No hay campos válidos para actualizar (nombre, descripcion, stock)'}),
        headers: _jsonHeaders);
    }

    final sets = <String>[];
    final params = <dynamic>[];
    allowed.forEach((k, v) {
      sets.add('$k = ?');
      params.add(v);
    });
    params.add(id);

    await dbQuery('UPDATE productos SET ${sets.join(', ')} WHERE id_producto = ?', params);

    // Respuesta uniforme al GET
    final prod = await _fetchProducto(id);
    if (prod == null) {
      // improbable tras update, pero por si acaso
      return Response(404,
        body: jsonEncode({'error': 'Producto no encontrado tras actualizar'}),
        headers: _jsonHeaders);
    }

    final wrap = req.url.queryParameters['wrap'] == '1';
    final bodyOut = wrap
        ? jsonEncode({'ok': true, 'data': prod})
        : jsonEncode(prod);

    return Response.ok(bodyOut, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error PUT /producto/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}
