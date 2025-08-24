// lib/routes/productos.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;
import 'package:backend_dart/routes/shape.dart'
    show mapProductoFront, mapProductosFront;

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

/// ========== GET /productos ==========
/// Lista todos los productos.
/// - Por defecto: ARRAY en español.
/// - ?wrap=1 => { ok, count, data }
/// - ?shape=front => llaves en inglés (name, price, image, ...)
Future<Response> productosHandler(Request req) async {
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
        -- primera imagen
        (
          SELECT CAST(fp.url AS CHAR)
          FROM fotos_producto fp
          WHERE fp.id_producto = p.id_producto
          ORDER BY fp.id_foto ASC
          LIMIT 1
        ) AS imagen,
        -- datos de categoría (opcional para shape=front)
        CAST(c.slug AS CHAR)         AS cat_slug,
        c.nombre                     AS cat_nombre
      FROM productos p
      LEFT JOIN categorias c ON c.codigo_categoria = p.codigo_categoria
      ORDER BY p.id_producto DESC
    ''');

    final listEs = rs.map<Map<String, dynamic>>((r) {
      return {
        'id'              : _jsonSafe(r['id']),
        'id_vendedor'     : _jsonSafe(r['id_vendedor']),
        'nombre'          : _jsonSafe(r['nombre']),
        'descripcion'     : _jsonSafe(r['descripcion']),
        'precio'          : (r['precio'] as num?)?.toDouble() ?? 0.0,
        'estado'          : _jsonSafe(r['estado']),
        'envio_rapido'    : _toBool(r['envio_rapido']),
        'codigo_categoria': _jsonSafe(r['codigo_categoria']),
        'stock'           : (r['stock'] as num?)?.toInt() ?? 0,
        'imagen'          : _jsonSafe(r['imagen']),
        'categoria'       : {
          'slug' : _jsonSafe(r['cat_slug']),
          'nombre': _jsonSafe(r['cat_nombre']),
        },
      };
    }).toList();

    final bodyObj = shapeFront ? mapProductosFront(listEs) : listEs;

    final body = wrap
        ? jsonEncode({'ok': true, 'count': bodyObj.length, 'data': bodyObj})
        : jsonEncode(bodyObj);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /productos: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

/// ========== GET /productos/<slug> ==========
/// Lista productos por categoría. <slug> puede ser el slug o el código de categoría.
/// - Por defecto: ARRAY en español.
/// - ?wrap=1 => { ok, count, data }
/// - ?shape=front => llaves en inglés
Future<Response> productosPorCategoriaHandler(Request req, String slug) async {
  try {
    final qp = req.url.queryParameters;
    final wrap = qp['wrap'] == '1';
    final shapeFront = qp['shape'] == 'front';

    // 1) Resolver código de categoría a partir del slug (o aceptar directamente el código)
    String? codigoCat;
    final rsCat = await dbQuery(
      'SELECT codigo_categoria FROM categorias WHERE slug = ? OR codigo_categoria = ? LIMIT 1',
      [slug, slug],
    );
    if (rsCat.isNotEmpty) {
      codigoCat = rsCat.first['codigo_categoria']?.toString();
    }
    if (codigoCat == null || codigoCat.isEmpty) {
      // No existe la categoría
      final empty = wrap ? {'ok': true, 'count': 0, 'data': <dynamic>[]} : <dynamic>[];
      return Response.ok(jsonEncode(empty), headers: _jsonHeaders);
    }

    // 2) Traer productos de esa categoría
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
        ) AS imagen,
        CAST(c.slug AS CHAR)         AS cat_slug,
        c.nombre                     AS cat_nombre
      FROM productos p
      JOIN categorias c ON c.codigo_categoria = p.codigo_categoria
      WHERE p.codigo_categoria = ?
      ORDER BY p.id_producto DESC
    ''', [codigoCat]);

    final listEs = rs.map<Map<String, dynamic>>((r) {
      return {
        'id'              : _jsonSafe(r['id']),
        'id_vendedor'     : _jsonSafe(r['id_vendedor']),
        'nombre'          : _jsonSafe(r['nombre']),
        'descripcion'     : _jsonSafe(r['descripcion']),
        'precio'          : (r['precio'] as num?)?.toDouble() ?? 0.0,
        'estado'          : _jsonSafe(r['estado']),
        'envio_rapido'    : _toBool(r['envio_rapido']),
        'codigo_categoria': _jsonSafe(r['codigo_categoria']),
        'stock'           : (r['stock'] as num?)?.toInt() ?? 0,
        'imagen'          : _jsonSafe(r['imagen']),
        'categoria'       : {
          'slug' : _jsonSafe(r['cat_slug']),
          'nombre': _jsonSafe(r['cat_nombre']),
        },
      };
    }).toList();

    final bodyObj = shapeFront ? mapProductosFront(listEs) : listEs;

    final body = wrap
        ? jsonEncode({'ok': true, 'count': bodyObj.length, 'data': bodyObj})
        : jsonEncode(bodyObj);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /productos/<slug>: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders,
    );
  }
}

/// ========== POST /productos  ó  POST /productos/ ==========
/// Crea producto. Soporta payload en español (nombre, descripcion, ...) y en inglés (name, description, ...).
/// Devuelve el objeto creado; ?shape=front para llaves en inglés.
Future<Response> crearProductoHandler(Request req) async {
  try {
    final qp = req.url.queryParameters;
    final shapeFront = qp['shape'] == 'front';

    final j = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};

    // admitir ambos nombres de campos (ES / EN)
    final idVendedor = (j['id_vendedor'] ?? j['sellerId'] ?? '').toString().trim();
    final nombre     = (j['nombre'] ?? j['name'] ?? '').toString().trim();
    final desc       = (j['descripcion'] ?? j['description'] ?? '').toString();
    final precio     = num.tryParse('${j['precio'] ?? j['price']}');
    final estado     = (j['estado'] ?? j['status'] ?? 'Disponible').toString().trim();
    final envioRap   = (j['envio_rapido'] == true || j['envio_rapido'] == 1 ||
                       '${j['envio_rapido']}'.toLowerCase()=='true') ? 1 : 0;
    final codCat     = (j['codigo_categoria'] ?? j['categoryId'] ?? '').toString().trim();
    final stock      = int.tryParse('${j['stock'] ?? j['quantity']}');

    const ESTADOS = {'Disponible','Agotado','En Oferta'};

    if (idVendedor.isEmpty || nombre.isEmpty || precio == null || !ESTADOS.contains(estado) || codCat.isEmpty || stock == null) {
      return Response(400,
        body: jsonEncode({'error':'Requeridos: id_vendedor, nombre, precio(num), estado(Disponible|Agotado|En Oferta), codigo_categoria, stock(int)'}),
        headers: _jsonHeaders);
    }

    final res = await dbQuery(
      '''
      INSERT INTO productos
        (id_vendedor, nombre, descripcion, precio, estado, envio_rapido, codigo_categoria, stock)
      VALUES (?,?,?,?,?,?,?,?)
      ''',
      [idVendedor, nombre, desc, precio, estado, envioRap, codCat, stock],
    );

    final newId = res.insertId;

    final createdEs = {
      'id'              : newId,
      'id_vendedor'     : idVendedor,
      'nombre'          : nombre,
      'descripcion'     : desc,
      'precio'          : precio.toDouble(),
      'estado'          : estado,
      'envio_rapido'    : envioRap == 1,
      'codigo_categoria': codCat,
      'stock'           : stock,
      'imagen'          : null,
    };

    final bodyObj = shapeFront ? mapProductoFront(createdEs) : createdEs;
    return Response(201, body: jsonEncode(bodyObj), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /productos: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/// ========== DELETE /productos/<id> ==========
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
    return Response.ok(jsonEncode({'ok': true, 'deleted': idNum}),
      headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /productos/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/// ========== Página demo admin (opcional) ==========
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
function toList(r){ return Array.isArray(r) ? r : (r?.data ?? []); }

async function cargar(){
  const r = await api('/productos?shape=front');
  const list = toList(r);
  const tb = document.querySelector('#tabla tbody'); tb.innerHTML='';
  list.forEach(p=>{
    const tr=document.createElement('tr');
    tr.innerHTML=`
      <td>${p.id}</td><td>${p.name||''}</td><td>${p.price}</td>
      <td>${p.status||''}</td><td>${p.stock ?? ''}</td>
      <td><button class="del" data-id="${p.id}">Eliminar</button></td>`;
    tb.appendChild(tr);
  });
}

document.querySelector('#refrescar').onclick=cargar;

document.querySelector('#crear').onclick=async()=>{
  const body={
    sellerId:document.querySelector('#id_vendedor').value,
    name:document.querySelector('#nombre').value,
    description:document.querySelector('#descripcion').value,
    price:document.querySelector('#precio').value,
    status:document.querySelector('#estado').value,
    envio_rapido:document.querySelector('#envio_rapido').checked,
    categoryId:document.querySelector('#codigo_categoria').value,
    quantity:document.querySelector('#stock').value,
  };
  const r=await fetch('/productos?shape=front',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
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
