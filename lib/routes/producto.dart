// lib/routes/producto.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;
import 'package:backend_dart/routes/shape.dart' show mapProductoFront;

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

/// ---------- GET /producto/<id> ----------
/// - Por defecto devuelve llaves en español.
/// - ?shape=front => llaves en inglés (name, price, image, sellerId, sellerName, ...)
/// - ?wrap=1 => { ok, data }
Future<Response> productoGetHandler(Request req, String id) async {
  try {
    final qp = req.url.queryParameters;
    final shapeFront = qp['shape'] == 'front';
    final wrap = qp['wrap'] == '1';

    final rs = await dbQuery('''
      SELECT 
        p.id_producto                 AS id,
        p.nombre,
        CAST(p.descripcion AS CHAR)   AS descripcion,
        p.precio,
        p.estado,
        p.envio_rapido,
        p.codigo_categoria,
        p.stock,
        u.id_usuario                  AS vendedor_id,
        u.nombre_usuario              AS vendedor_nombre,
        u.correo                      AS vendedor_correo
      FROM productos p
      LEFT JOIN usuarios u ON u.id_usuario = p.id_vendedor
      WHERE p.id_producto = ?
      LIMIT 1
    ''', [id]);

    if (rs.isEmpty) {
      return Response(404,
          body: jsonEncode({'error': 'Producto no encontrado'}),
          headers: _jsonHeaders);
    }

    final base = rs.first;

    final fotos = await dbQuery('''
      SELECT CAST(url AS CHAR) AS url
      FROM fotos_producto
      WHERE id_producto = ?
      ORDER BY id_foto ASC
    ''', [id]);

    final dataEs = {
      'id'              : _jsonSafe(base['id']),
      'nombre'          : _jsonSafe(base['nombre']),
      'descripcion'     : _jsonSafe(base['descripcion']),
      'precio'          : (base['precio'] as num?)?.toDouble() ?? 0.0,
      'estado'          : _jsonSafe(base['estado']),
      'envio_rapido'    : _toBool(base['envio_rapido']),
      'codigo_categoria': _jsonSafe(base['codigo_categoria']),
      'stock'           : (base['stock'] as num?)?.toInt() ?? 0,
      'vendedor'        : {
        'id'    : _jsonSafe(base['vendedor_id']),
        'nombre': _jsonSafe(base['vendedor_nombre']),
        'correo': _jsonSafe(base['vendedor_correo']),
      },
      'fotos'           : fotos.map((r) => _jsonSafe(r['url'])).toList(),
    };

    final bodyObj = shapeFront ? mapProductoFront(dataEs) : dataEs;
    final body = wrap ? {'ok': true, 'data': bodyObj} : bodyObj;

    return Response.ok(jsonEncode(body), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /producto/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

/// ---------- PUT /producto/<id> ----------
/// Acepta campos en español o inglés:
///  - nombre|name, descripcion|description, stock|quantity,
///  - precio|price, estado|status, envio_rapido (bool|0/1|'true'/'false')
/// Devuelve el producto actualizado (respeta ?shape=front y ?wrap=1).
Future<Response> productoUpdateHandler(Request req, String id) async {
  try {
    final j = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};

    // normalización de nombres
    final nombre       = j.containsKey('nombre')       ? j['nombre']       : j['name'];
    final descripcion  = j.containsKey('descripcion')  ? j['descripcion']  : j['description'];
    final stock        = j.containsKey('stock')        ? j['stock']        : j['quantity'];
    final precio       = j.containsKey('precio')       ? j['precio']       : j['price'];
    final estado       = j.containsKey('estado')       ? j['estado']       : j['status'];
    final envioRap     = j['envio_rapido'];

    final sets = <String>[];
    final params = <dynamic>[];

    void add(String col, dynamic val) {
      sets.add('$col = ?');
      params.add(val);
    }

    if (nombre != null)      add('nombre', nombre);
    if (descripcion != null) add('descripcion', descripcion);
    if (stock != null)       add('stock', int.tryParse('$stock') ?? stock);
    if (precio != null)      add('precio', num.tryParse('$precio') ?? precio);
    if (estado != null)      add('estado', estado);
    if (envioRap != null) {
      final b = (envioRap == true || envioRap == 1 || '$envioRap'.toLowerCase() == 'true') ? 1 : 0;
      add('envio_rapido', b);
    }

    if (sets.isEmpty) {
      return Response(400,
          body: jsonEncode({
            'error':
                'No hay campos válidos para actualizar (nombre|name, descripcion|description, stock|quantity, precio|price, estado|status, envio_rapido)'
          }),
          headers: _jsonHeaders);
    }

    params.add(id);
    await dbQuery('UPDATE productos SET ${sets.join(', ')} WHERE id_producto = ?', params);

    // Reutilizamos el GET para devolver con el mismo shape/wrap que pidió el cliente
    return productoGetHandler(req, id);
  } catch (e, st) {
    print('Error PUT /producto/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}
