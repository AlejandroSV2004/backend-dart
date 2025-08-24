// Endpoints:
//   POST /api/productos/<slugCategoria>
//   GET  /api/productos/<slugCategoria>

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:backend_dart/db.dart' show dbQuery;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

bool _toBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

// ========== POST /api/productos/<slugCategoria> ==========
Future<Response> _crearProductoPorCategoria(
  Request req,
  String slugCategoria,
) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>? ?? {};
    final idVendedor = (body['id_vendedor'] ?? '').toString().trim();
    final nombre     = (body['nombre'] ?? '').toString().trim();
    final descripcion= (body['descripcion'] ?? '').toString();
    final precio     = body['precio'];
    final stock      = body['stock'];
    final imagen     = (body['imagen'] ?? '').toString().trim();

    // Validaciones mínimas
    if (idVendedor.isEmpty || nombre.isEmpty || precio == null || stock == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'Faltan campos requeridos: id_vendedor, nombre, precio, stock'}),
        headers: _jsonHeaders,
      );
    }

    // Verificar que el usuario sea negocio
    final verif = await dbQuery(
      'SELECT es_negocio FROM usuarios WHERE id_usuario = ?',
      [idVendedor],
    );
    if (verif.isEmpty || !_toBool(verif.first['es_negocio'])) {
      return Response(
        403,
        body: jsonEncode({'error': 'No autorizado para crear productos'}),
        headers: _jsonHeaders,
      );
    }

    // Obtener código de categoría por slug
    final catRs = await dbQuery(
      'SELECT codigo_categoria FROM categorias WHERE slug = ?',
      [slugCategoria],
    );
    if (catRs.isEmpty) {
      return Response(
        400,
        body: jsonEncode({'error': 'Categoría inválida'}),
        headers: _jsonHeaders,
      );
    }
    final codigoCategoria = catRs.first['codigo_categoria'];

    // Insertar producto
    final insertRes = await dbQuery(
      '''
      INSERT INTO productos
        (id_vendedor, nombre, descripcion, precio, stock, codigo_categoria)
      VALUES (?,?,?,?,?,?)
      ''',
      [idVendedor, nombre, descripcion, precio, stock, codigoCategoria],
    );
    final newId = insertRes.insertId;

    // Si viene imagen, insertarla
    if (imagen.isNotEmpty) {
      await dbQuery(
        'INSERT INTO fotos_producto (id_producto, url_imagen) VALUES (?, ?)',
        [newId, imagen],
      );
    }

    return Response(201, body: jsonEncode({'success': true}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error al crear producto con categoría: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

// ========== GET /api/productos/<slugCategoria> ==========
Future<Response> _listarProductosPorCategoria(
  Request req,
  String slugCategoria,
) async {
  try {
    // Buscar categoría
    final catRs = await dbQuery(
      'SELECT codigo_categoria FROM categorias WHERE slug = ?',
      [slugCategoria],
    );
    if (catRs.isEmpty) {
      return Response(404, body: jsonEncode({'error': 'Categoría no encontrada'}), headers: _jsonHeaders);
    }
    final codigoCategoria = catRs.first['codigo_categoria'];

    // Traer productos de la categoría (con 1 imagen o placeholder)
    final rs = await dbQuery(
      '''
      SELECT
        p.id_producto AS id,
        p.nombre      AS name,
        p.precio      AS price,
        p.descripcion,
        COALESCE(f.url_imagen, 'https://placehold.co/300x400') AS image
      FROM productos p
      LEFT JOIN fotos_producto f ON f.id_producto = p.id_producto
      WHERE p.codigo_categoria = ?
      ''',
      [codigoCategoria],
    );

    // Mapear EXACTO como tu Node (price como string si viene decimal)
    final out = <Map<String, dynamic>>[];
    for (final row in rs) {
      out.add({
        'id'         : row['id'],
        'name'       : row['name'],
        'price'      : '${row['price']}',            // mantener string como en mysql2/Node
        'descripcion': row['descripcion']?.toString(),
        'image'      : row['image']?.toString(),
      });
    }

    return Response.ok(jsonEncode(out), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error al obtener productos: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

// ========== Router exportado ==========
final Router productosRouter = Router()
  ..post('/<slugCategoria>', (req, slug) => _crearProductoPorCategoria(req, slug))
  ..get ('/<slugCategoria>', (req, slug) => _listarProductosPorCategoria(req, slug));
