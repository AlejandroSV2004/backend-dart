// lib/routes/usuarios.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob, MySqlException;
// mapUserFront ya no es necesario para login con shape Node, pero lo dejamos por compat (p.ej. GET /usuarios?shape=front)
import 'package:backend_dart/routes/shape.dart' show mapUserFront;

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
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

/// ---------- POST /usuarios/login ----------
/// body: { correo, contrasena }
/// RESPUESTA: { success: true, usuario: {...} }   (igual que Node)
Future<Response> loginUsuarioHandler(Request req) async {
  try {
    final bodyStr = await req.readAsString();
    final j = (bodyStr.isEmpty ? {} : jsonDecode(bodyStr)) as Map<String, dynamic>;

    final correo = (j['correo'] ?? '').toString().trim();
    final pass   = (j['contrasena'] ?? '').toString();

    if (correo.isEmpty || pass.isEmpty) {
      return Response(400,
        body: jsonEncode({'error': 'Faltan correo y/o contrasena'}),
        headers: _jsonHeaders);
    }

    // En producción: hashear y comparar de forma segura.
    final rs = await dbQuery('''
      SELECT
        id_usuario      AS id_usuario,
        correo,
        nombre_usuario,
        foto_perfil,
        es_negocio
      FROM usuarios
      WHERE correo = ? AND contrasena = ?
      LIMIT 1
    ''', [correo, pass]);

    if (rs.isEmpty) {
      return Response(401,
        body: jsonEncode({'error': 'Credenciales incorrectas'}),
        headers: _jsonHeaders);
    }

    final row = rs.first;
    final usuario = {
      'id_usuario'    : _jsonSafe(row['id_usuario']),
      'correo'        : _jsonSafe(row['correo']),
      'nombre_usuario': _jsonSafe(row['nombre_usuario']),
      'foto_perfil'   : _jsonSafe(row['foto_perfil']),
      'es_negocio'    : _toBool(row['es_negocio']) ? 1 : 0, // Node devolvía 0/1
    };

    // === Shape final igual a Express: { success: true, usuario: {...} } ===
    return Response.ok(jsonEncode({'success': true, 'usuario': usuario}),
      headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /usuarios/login: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/// ---------- GET /usuarios ----------
/// Por defecto: ARRAY plano. ?wrap=1 => { ok, count, data }
/// ?shape=front => llaves en inglés (id,email,name,avatar,isBusiness)
Future<Response> usuariosHandler(Request req) async {
  try {
    final qp = req.url.queryParameters;
    final wrap = qp['wrap'] == '1';
    final shapeFront = qp['shape'] == 'front';

    final rs = await dbQuery('''
      SELECT
        id_usuario      AS id,
        correo,
        nombre_usuario,
        foto_perfil,
        es_negocio
      FROM usuarios
      ORDER BY nombre_usuario
    ''');

    final list = rs.map<Map<String, dynamic>>((r) {
      final base = {
        'id'            : _jsonSafe(r['id']),
        'correo'        : _jsonSafe(r['correo']),
        'nombre_usuario': _jsonSafe(r['nombre_usuario']),
        'foto_perfil'   : _jsonSafe(r['foto_perfil']),
        'es_negocio'    : _toBool(r['es_negocio']),
      };
      return shapeFront ? mapUserFront(base) : base;
    }).toList();

    final body = wrap
      ? jsonEncode({'ok': true, 'count': list.length, 'data': list})
      : jsonEncode(list);

    return Response.ok(body, headers: _jsonHeaders);
  } catch (e, st) {
    print('Error GET /usuarios: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/// ---------- POST /usuarios ----------
/// body: { id, correo, nombre_usuario, foto_perfil?, contrasena?, es_negocio? }
/// Devuelve OBJETO creado. ?shape=front => llaves en inglés
Future<Response> crearUsuarioHandler(Request req) async {
  try {
    final qp = req.url.queryParameters;
    final shapeFront = qp['shape'] == 'front';

    final bodyStr = await req.readAsString();
    final j = (bodyStr.isEmpty ? {} : jsonDecode(bodyStr)) as Map<String, dynamic>;

    final id     = (j['id'] ?? j['id_usuario'] ?? '').toString().trim();
    final correo = (j['correo'] ?? '').toString().trim();
    final nombre = (j['nombre_usuario'] ?? '').toString().trim();
    final foto   = (j['foto_perfil'] ?? '').toString().trim();
    final pass   = (j['contrasena'] ?? '').toString(); // DEMO
    final esNeg  = (j['es_negocio'] == true || j['es_negocio'] == 1 || '${j['es_negocio']}'.toLowerCase()=='true') ? 1 : 0;

    if (id.isEmpty || correo.isEmpty || nombre.isEmpty) {
      return Response(400,
        body: jsonEncode({'error':'Campos requeridos: id, correo, nombre_usuario'}),
        headers: _jsonHeaders);
    }

    try {
      await dbQuery(
        'INSERT INTO usuarios (id_usuario, correo, nombre_usuario, foto_perfil, contrasena, es_negocio) VALUES (?,?,?,?,?,?)',
        [id, correo, nombre, foto.isEmpty ? null : foto, pass, esNeg],
      );
    } on MySqlException catch (e) {
      if (e.errorNumber == 1062) {
        return Response(409,
          body: jsonEncode({'error':'Usuario ya existe (id o correo duplicado)'}),
          headers: _jsonHeaders);
      }
      rethrow;
    }

    final createdBase = {
      'id'            : id,
      'correo'        : correo,
      'nombre_usuario': nombre,
      'foto_perfil'   : foto.isEmpty ? null : foto,
      'es_negocio'    : esNeg == 1,
    };
    final created = shapeFront ? mapUserFront(createdBase) : createdBase;

    return Response(201, body: jsonEncode(created), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error POST /usuarios: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/// ---------- DELETE /usuarios/<id> ----------
Future<Response> eliminarUsuarioHandler(Request req, String id) async {
  try {
    final r = await dbQuery('DELETE FROM usuarios WHERE id_usuario = ?', [id]);
    final n = r.affectedRows ?? 0;
    if (n == 0) {
      return Response(404,
        body: jsonEncode({'error':'No existe el usuario $id'}),
        headers: _jsonHeaders);
    }
    return Response.ok(jsonEncode({'ok': true, 'deleted': id}), headers: _jsonHeaders);
  } catch (e, st) {
    print('Error DELETE /usuarios/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: _jsonHeaders);
  }
}

/// ---------- GET /usuarios/admin (demo HTML) ----------
Future<Response> adminUsuariosPageHandler(Request req) async {
  const html = r'''
<!doctype html>
<html lang="es">
<meta charset="utf-8">
<title>Admin Usuarios (demo)</title>
<style>
  body{font-family:system-ui,Arial;margin:24px;max-width:920px}
  input,button{padding:8px;margin:4px}
  table{border-collapse:collapse;margin-top:12px;width:100%}
  th,td{border:1px solid #ddd;padding:6px 10px}
  tr:nth-child(even){background:#f6f6f6}
  .row{display:flex;gap:8px;flex-wrap:wrap}
  .row > *{flex:1 1 180px}
</style>
<h1>Admin Usuarios (demo)</h1>

<div class="row">
  <input id="id" placeholder="id_usuario (char(6))" maxlength="6" required>
  <input id="correo" placeholder="correo" required>
  <input id="nombre" placeholder="nombre_usuario" required>
  <input id="foto" placeholder="foto_perfil (URL)">
  <input id="pass" placeholder="contrasena (demo)" type="password">
  <label><input type="checkbox" id="neg"> es_negocio</label>
</div>
<button id="crear">Crear usuario</button>
<button id="refrescar">Refrescar</button>

<table id="tabla">
  <thead><tr><th>id</th><th>correo</th><th>nombre</th><th>negocio</th><th>acciones</th></tr></thead>
  <tbody></tbody>
</table>

<script>
const api=(p,o={})=>fetch(p,o).then(r=>r.json());
const toList = (r) => Array.isArray(r) ? r : (r?.data ?? []);

async function cargar(){
  const res = await api('/usuarios');
  const list = toList(res);
  const tbody = document.querySelector('#tabla tbody');
  tbody.innerHTML = '';
  list.forEach(u => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${u.id}</td>
      <td>${u.correo||u.email||''}</td>
      <td>${u.nombre_usuario||u.name||''}</td>
      <td>${(u.es_negocio ?? u.isBusiness) ? 'Sí':'No'}</td>
      <td><button data-id="${u.id}" class="del">Eliminar</button></td>`;
    tbody.appendChild(tr);
  });
}

document.querySelector('#refrescar').onclick = cargar;

document.querySelector('#crear').onclick = async () => {
  const body = {
    id: document.querySelector('#id').value,
    correo: document.querySelector('#correo').value,
    nombre_usuario: document.querySelector('#nombre').value,
    foto_perfil: document.querySelector('#foto').value,
    contrasena: document.querySelector('#pass').value,
    es_negocio: document.querySelector('#neg').checked,
  };
  const r = await fetch('/usuarios', {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body: JSON.stringify(body)
  });
  if (r.ok) { 
    document.querySelectorAll('input').forEach(i=>{ if(i.type!=='checkbox') i.value=''; else i.checked=false; });
    cargar(); 
  } else {
    const t = await r.text();
    alert('Error al crear: ' + t);
  }
};

document.addEventListener('click', async (e) => {
  const btn = e.target.closest('.del');
  if (!btn) return;
  const id = btn.getAttribute('data-id');
  const r = await fetch('/usuarios/'+encodeURIComponent(id), {method:'DELETE'});
  if (r.ok) cargar(); else alert('Error al borrar');
});

cargar();
</script>
</html>
''';
  return Response.ok(html, headers: {'Content-Type': 'text/html; charset=utf-8'});
}
