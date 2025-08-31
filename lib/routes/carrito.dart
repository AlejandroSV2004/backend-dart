import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db.dart';

Router carritoRouter() {
  final router = Router();

  router.get('/<idUsuario>', (Request req, String idUsuario) async {
    try {
      final items = await dbQueryMaps('''
        SELECT 
          c.id_producto,
          p.nombre,
          p.precio,
          c.cantidad,
          (SELECT fp.url_imagen 
             FROM fotos_producto fp 
            WHERE fp.id_producto = p.id_producto 
            LIMIT 1) AS imagen
        FROM carrito c
        JOIN productos p ON p.id_producto = c.id_producto
       WHERE c.id_usuario = ?
      ''', [idUsuario]);
      return Response.ok(jsonEncode(items), headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': 'No se pudo obtener el carrito', 'detail': '$e'}), headers: {'content-type': 'application/json; charset=utf-8'});
    }
  });

  router.post('/agregar', (Request req) async {
    try {
      final data = jsonDecode(await req.readAsString());
      final String idUsuario = data['id_usuario'].toString();
      final int idProducto = int.parse(data['id_producto'].toString());
      final int cantidad = int.tryParse(data['cantidad']?.toString() ?? '1') ?? 1;

      final prod = await dbQueryMaps('SELECT id_producto, stock FROM productos WHERE id_producto = ? LIMIT 1', [idProducto]);
      if (prod.isEmpty) {
        return Response(404, body: jsonEncode({'error': 'Producto no encontrado'}), headers: {'content-type': 'application/json; charset=utf-8'});
      }

      final existente = await dbQueryMaps('SELECT cantidad FROM carrito WHERE id_usuario = ? AND id_producto = ?', [idUsuario, idProducto]);

      if (existente.isEmpty) {
        await dbQuery('INSERT INTO carrito (id_usuario, id_producto, cantidad) VALUES (?, ?, ?)', [idUsuario, idProducto, cantidad]);
      } else {
        await dbQuery('UPDATE carrito SET cantidad = cantidad + ? WHERE id_usuario = ? AND id_producto = ?', [cantidad, idUsuario, idProducto]);
      }

      return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': 'No se pudo agregar al carrito', 'detail': '$e'}), headers: {'content-type': 'application/json; charset=utf-8'});
    }
  });

  router.post('/disminuir', (Request req) async {
    try {
      final data = jsonDecode(await req.readAsString());
      final String idUsuario = data['id_usuario'].toString();
      final int idProducto = int.parse(data['id_producto'].toString());

      final fila = await dbQueryMaps('SELECT cantidad FROM carrito WHERE id_usuario = ? AND id_producto = ?', [idUsuario, idProducto]);
      if (fila.isEmpty) {
        return Response(404, body: jsonEncode({'error': 'El ítem no está en el carrito'}), headers: {'content-type': 'application/json; charset=utf-8'});
      }

      final int cant = int.parse(fila.first['cantidad'].toString());
      if (cant <= 1) {
        await dbQuery('DELETE FROM carrito WHERE id_usuario = ? AND id_producto = ?', [idUsuario, idProducto]);
      } else {
        await dbQuery('UPDATE carrito SET cantidad = cantidad - 1 WHERE id_usuario = ? AND id_producto = ?', [idUsuario, idProducto]);
      }

      return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': 'No se pudo disminuir el ítem', 'detail': '$e'}), headers: {'content-type': 'application/json; charset=utf-8'});
    }
  });

  router.delete('/vaciar/<idUsuario>', (Request req, String idUsuario) async {
    try {
      await dbQuery('DELETE FROM carrito WHERE id_usuario = ?', [idUsuario]);
      return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': 'No se pudo vaciar el carrito', 'detail': '$e'}), headers: {'content-type': 'application/json; charset=utf-8'});
    }
  });

  router.delete('/<idUsuario>/<idProducto>', (Request req, String idUsuario, String idProducto) async {
    try {
      await dbQuery('DELETE FROM carrito WHERE id_usuario = ? AND id_producto = ?', [idUsuario, int.parse(idProducto)]);
      return Response.ok(jsonEncode({'ok': true}), headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': 'No se pudo eliminar el ítem', 'detail': '$e'}), headers: {'content-type': 'application/json; charset=utf-8'});
    }
  });

  return router;
}

