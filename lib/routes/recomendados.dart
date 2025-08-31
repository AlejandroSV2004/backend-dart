import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db.dart';

Router recomendadosRouter() {
  final router = Router();

  router.get('/', (Request req) async {
    try {
      final rows = await dbQueryMaps('''
        SELECT 
          p.id_producto,
          p.nombre,
          p.precio,
          p.stock,
          (SELECT fp.url_imagen 
             FROM fotos_producto fp 
            WHERE fp.id_producto = p.id_producto 
            LIMIT 1) AS imagen
        FROM productos p
        ORDER BY RAND()
        LIMIT 3
      ''');
      return Response.ok(jsonEncode(rows), headers: {'content-type': 'application/json; charset=utf-8'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': 'No se pudieron obtener recomendados', 'detail': '$e'}), headers: {'content-type': 'application/json; charset=utf-8'});
    }
  });

  return router;
}
