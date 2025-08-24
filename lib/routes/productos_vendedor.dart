// Endpoint:
//   GET /api/productosVendedor/<vendedorId>


import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:backend_dart/db.dart' show dbQuery;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

Future<Response> _getProductosDeVendedor(Request req, String vendedorId) async {
  try {
    if (vendedorId.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'Falta el ID del vendedor en la ruta'}),
        headers: _jsonHeaders,
      );
    }

    final rs = await dbQuery(
      '''
      SELECT 
        p.id_producto,
        p.nombre,
        p.precio,
        (
          SELECT url_imagen 
          FROM fotos_producto 
          WHERE id_producto = p.id_producto 
          LIMIT 1
        ) AS url_imagen
      FROM productos p
      WHERE p.id_vendedor = ?
      ORDER BY p.id_producto DESC
      ''',
      [vendedorId],
    );

    final out = <Map<String, dynamic>>[];
    for (final row in rs) {
      out.add({
        'id_producto': row['id_producto'],
        'nombre': row['nombre']?.toString(),
        'precio': '${row['precio']}',
        'url_imagen': row['url_imagen']?.toString(),
      });
    }

    return Response.ok(jsonEncode(out), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error al obtener productos del vendedor: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

// Router exportado
final Router productosVendedorRouter = Router()
  ..get('/<vendedorId|[A-Za-z0-9]+>',
      (req, vendedorId) => _getProductosDeVendedor(req, vendedorId));
