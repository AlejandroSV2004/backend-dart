import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;

const _jsonHeaders = {'Content-Type': 'application/json; charset=utf-8'};

dynamic _jsonSafe(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toIso8601String();
  if (v is BigInt) return v.toString();
  if (v is Uint8List) return base64Encode(v);
  if (v is Blob) {
    final b = v.toBytes();
    try { return utf8.decode(b); } catch (_) { return base64Encode(b); }
  }
  return v;
}

bool _toBool(dynamic v) {
  if (v is bool) return v;
  if (v is num)  return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

/* =========================
 *   GET /productos  (lista)
 *   ARRAY plano por defecto. ?wrap=1 => { ok, count, data }
 * ========================= */
Future<Response> productosHandler(Request req) async {
  try {
    final rs = await dbQuery('''
      SELECT
        id_producto                AS id,
        id_vendedor,
        nombre,
        CAST(descripcion AS CHAR)  AS descripcion,
        precio,
        estado,
        envio_rapido,
        codigo_categoria,
        stock
      FROM productos
      ORDER BY id_producto DESC
    ''');

    final data = rs.map((r) {
      final precio = (r['precio'] as num?)?.toDouble() ?? 0.0;
      final stock  = (r['stock']  as num?)?.toInt() ?? 0;
      return {
        'id'              : _jsonSafe(r['id']),
        'id_vendedor'     : _jsonSafe(r['id_vendedor']),
        'nombre'          : _jsonSafe(r['nombre']),
        'descripcion'     : _jsonSafe(r['descripcion']),
        'precio'          : precio,
        'estado'          : _jsonSafe(r['estado']),
        'envio_rapido'    : _toBool(r['envio_rapido']),
        'codigo_categoria': _jsonSafe(r['codigo_categoria']),
        'stock'           : stock,
      };
    }).toList();

    final wrap = req.url.queryParameters['wrap'] == '1';
    final body = wrap
      ? jsonEncode({'ok': true, 'count': data.length, 'data': data})
      : jsonEncode(data);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /productos: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/* ===========================================
 *   GET /productos/<slug>
 *   Productos por categoría (por slug o código)
 *   ARRAY plano por defecto. ?wrap=1 => { ok, total, page, limit, data }
 *   Paginación: ?page=1&limit=24
 * =========================================== */
Future<Response> productosPorCategoriaHandler(Request req, String slugOrCodigo) async {
  try {
    final qp = req.url.queryParameters;
    final limit = (int.tryParse(qp['limit'] ?? '') ?? 24).clamp(1, 1000);
    final page  = (int.tryParse(qp['page']  ?? '') ?? 1).clamp(1, 100000);
    final offset = (page - 1) * limit;

    final cnt = await dbQuery('''
      SELECT COUNT(*) AS total
      FROM productos p
      JOIN categorias c ON c.codigo_categoria = p.codigo_categoria
      WHERE c.slug = ? OR p.codigo_categoria = ?
    ''', [slugOrCodigo, slugOrCodigo]);
    final total = (cnt.first['total'] as num?)?.toInt() ?? 0;

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
        c.slug                       AS categoria_slug,
        c.nombre                     AS categoria_nombre,
        p.stock,
        (
          SELECT CAST(fp.url AS CHAR)
          FROM fotos_producto fp
          WHERE fp.id_producto = p.id_producto
          ORDER BY fp.id_foto ASC
          LIMIT 1
        ) AS imagen
      FROM productos p
      JOIN categorias c ON c.codigo_categoria = p.codigo_categoria
      WHERE c.slug = ? OR p.codigo_categoria = ?
      ORDER BY p.id_producto DESC
      LIMIT ? OFFSET ?
    ''', [slugOrCodigo, slugOrCodigo, limit, offset]);

    final data = rs.map((r) {
      final precio = (r['precio'] as num?)?.toDouble() ?? 0.0;
      final stock  = (r['stock']  as num?)?.toInt() ?? 0;
      return {
        'id'              : _jsonSafe(r['id']),
        'id_vendedor'     : _jsonSafe(r['id_vendedor']),
        'nombre'          : _jsonSafe(r['nombre']),
        'descripcion'     : _jsonSafe(r['descripcion']),
        'precio'          : precio,
        'estado'          : _jsonSafe(r['estado']),
        'envio_rapido'    : _toBool(r['envio_rapido']),
        'codigo_categoria': _jsonSafe(r['codigo_categoria']),
        'categoria'       : {
          'slug'  : _jsonSafe(r['categoria_slug']),
          'nombre': _jsonSafe(r['categoria_nombre']),
        },
        'stock'           : stock,
        'imagen'          : _jsonSafe(r['imagen']),
      };
    }).toList();

    final wrap = req.url.queryParameters['wrap'] == '1';
    final body = wrap
      ? jsonEncode({'ok': true, 'total': total, 'page': page, 'limit': limit, 'data': data})
      : jsonEncode(data);

    return Response.ok(body, headers: {
      ..._jsonHeaders,
      'X-Total-Count': total.toString(),
    });
  } catch (e, st) {
    print('Error GET /productos/$slugOrCodigo: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

/* =========================
 *   POST /productos  (crear)
 *   Devuelve OBJETO creado. ?wrap=1 => { ok, data }
 * ========================= */
Future<Response> crearProductoHandler(Request req) async {
  try {
    final j = jsonDecode(await req.readAsString()) as Map<String, dynamic>;

    final idVendedor = (j['id_vendedor'] ?? '').toString().trim();
    final nombre     = (j['nombre'] ?? '').toString().trim();
    final desc       = (j['descripcion'] ?? '').toString();
    final precioNum  = num.tryParse('${j['precio']}');
    final estado     = (j['estado'] ?? '').toString().trim(); // 'Disponible' | 'Agotado' | 'En Oferta'
    final envioRap   = (j['envio_rapido'] == true || j['envio_rapido'] == 1 || '${j['envio_rapido']}'.toLowerCase()=='true') ? 1 : 0;
    final codCat     = (j['codigo_categoria'] ?? '').toString().trim();
    final stockInt   = int.tryParse('${j['stock']}');

    const ESTADOS = {'Disponible','Agotado','En Oferta'};

    if (idVendedor.isEmpty || nombre.isEmpty || precioNum == null || !ESTADOS.contains(estado) || codCat.isEmpty || stockInt == null) {
      return Response(400,
        body: jsonEncode({'error':'Requeridos: id_vendedor, nombre, precio(num), estado(Disponible|Agotado|En Oferta), codigo_categoria, stock(int)'}),
        headers: _jsonHeaders);
    }

    final ins = await dbQuery('''
      INSERT INTO productos
        (id_vendedor, nombre, descripcion, precio, estado, envio_rapido, codigo_categoria, stock)
      VALUES (?,?,?,?,?,?,?,?)
    ''', [idVendedor, nombre, desc, precioNum, estado, envioRap, codCat, stockInt]);

    final newId = ins.insertId;

    final created = {
      'id'              : newId,
      'id_vendedor'     : idVendedor,
      'nombre'          : nombre,
      'descripcion'     : desc,
      'precio'          : (precioNum as num).toDouble(),
      'estado'          : estado,
      'envio_rapido'    : envioRap == 1,
      'codigo_categoria': codCat,
      'stock'           : stockInt,
    };

    final wrap = req.url.queryParameters['wrap'] == '1';
    final body = wrap
      ? jsonEncode({'ok': true, 'data': created})
      : jsonEncode(created);

    return Response(201, body: body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /productos: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/* =========================
 *   DELETE /productos/<id>
 * ========================= */
Future<Response> eliminarProductoHandler(Request req, String id) async {
  try {
    final idNum = int.tryParse(id);
    if (idNum == null) {
      return Response(400,
        body: jsonEncode({'error':'id de producto inválido'}),
        headers: _jsonHeaders);
    }

    final r = await dbQuery('DELETE FROM productos WHERE id_producto = ?', [idNum]);
    final n = r.affectedRows ?? 0;
    if (n == 0) {
      return Response(404,
        body: jsonEncode({'error':'No existe el producto $idNum'}),
        headers: _jsonHeaders);
    }
    return Response.ok(jsonEncode({'ok': true, 'deleted': idNum}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /productos/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/* =====================================
 *   Página demo admin (mover a /admin/productos)
 *   (si la montas en /productos/admin, regístrala
 *   antes que la ruta dinámica <slug> para evitar choque)
 * ===================================== */
Future<Response> adminProductosPageHandler(Request req) async {
  const html = r'''
<!doctype html><html lang="es"><meta charset="utf-8">
<title>Admin Productos (demo)</title>
<style>
  body{font-family:system-ui,Arial;margin:24px;max-width:960px}
  input,select,button{padding:8px;margin:4px}
  table{border-collapse:collapse;margin-top:12px;width:100%}
  th,td{border:1px solid #ddd;padding:6px 10px} tr:nth-child(even){background:#f6f6f6}
  .row{display:flex;gap:8px;flex-wrap:wrap} .row>*{flex:1 1 180px}
</style>
<h1>Admin Productos (demo)</h1>
<div class="row">
  <input id="id_vendedor" placeholder="id_vendedor (char6)" maxlength="6" required>
  <input id="nombre" placeholder="nombre" required>
  <input id="descripcion" placeholder="descripcion">
  <input id="precio" type="number" step="0.01" placeholder="precio" required>
  <select id="estado">
    <option>Disponible</option><option>Agotado</option><option>En Oferta</option>
  </select>
  <label><input type="checkbox" id="envio_rapido"> envio_rapido</label>
  <input id="codigo_categoria" placeholder="codigo_categoria (char4)" maxlength="4" required>
  <input id="stock" type="number" step="1" placeholder="stock" required>
</div>
<button id="crear">Crear</button> <button id="refrescar">Refrescar</button>
<table id="tabla"><thead>
<tr><th>id</th><th>nombre</th><th>precio</th><th>estado</th><th>stock</th><th>acciones</th></tr>
</thead><tbody></tbody></table>
<script>
const api=(p,o={})=>fetch(p,o).then(r=>r.json());
const toList=r=>Array.isArray(r)?r:(r?.data??[]);

async function cargar(){
  const r = await api('/productos?wrap=1');
  const list = toList(r);
  const tb = document.querySelector('#tabla tbody'); tb.innerHTML='';
  list.forEach(p=>{
    const tr=document.createElement('tr');
    tr.innerHTML=`
      <td>${p.id}</td><td>${p.nombre||''}</td><td>${p.precio}</td>
      <td>${p.estado}</td><td>${p.stock}</td>
      <td><button class="del" data-id="${p.id}">Eliminar</button></td>`;
    tb.appendChild(tr);
  });
}
document.querySelector('#refrescar').onclick=cargar;
document.querySelector('#crear').onclick=async()=>{
  const body={
    id_vendedor:document.querySelector('#id_vendedor').value,
    nombre:document.querySelector('#nombre').value,
    descripcion:document.querySelector('#descripcion').value,
    precio:document.querySelector('#precio').value,
    estado:document.querySelector('#estado').value,
    envio_rapido:document.querySelector('#envio_rapido').checked,
    codigo_categoria:document.querySelector('#codigo_categoria').value,
    stock:document.querySelector('#stock').value,
  };
  const r=await fetch('/productos',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  if(r.ok){
    document.querySelectorAll('input').forEach(i=>{if(i.type!=='checkbox')i.value=''; else i.checked=false;});
    cargar();
  } else alert('Error al crear');
};
document.addEventListener('click',async e=>{
  const b=e.target.closest('.del'); if(!b) return;
  const id=b.getAttribute('data-id');
  const r=await fetch('/productos/'+encodeURIComponent(id),{method:'DELETE'});
  if(r.ok)cargar(); else alert('Error al borrar');
});
cargar();
</script></html>
''';
  return Response.ok(html, headers:{'Content-Type':'text/html; charset=utf-8'});
}
