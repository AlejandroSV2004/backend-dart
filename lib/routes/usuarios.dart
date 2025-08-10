import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:backend_dart/db.dart';
import 'package:mysql1/mysql1.dart' show Blob;

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

// ---------- GET /usuarios ----------
Future<Response> usuariosHandler(Request request) async {
  try {
    final rs = await dbQuery('''
      SELECT
        id_usuario   AS id,
        correo,
        nombre_usuario,
        foto_perfil,
        es_negocio
      FROM usuarios
      ORDER BY nombre_usuario
    ''');

    final data = rs.map((r) => {
      'id'            : _jsonSafe(r['id']),
      'correo'        : _jsonSafe(r['correo']),
      'nombre_usuario': _jsonSafe(r['nombre_usuario']),
      'foto_perfil'   : _jsonSafe(r['foto_perfil']),
      'es_negocio'    : _toBool(r['es_negocio']),
    }).toList();

    return Response.ok(
      jsonEncode({'ok': true, 'count': data.length, 'data': data}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  } catch (e, st) {
    print('Error GET /usuarios: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}

// ---------- POST /usuarios ----------
Future<Response> crearUsuarioHandler(Request req) async {
  try {
    final body = await req.readAsString();
    final j = jsonDecode(body) as Map<String, dynamic>;

    final id     = (j['id'] ?? j['id_usuario'] ?? '').toString().trim();
    final correo = (j['correo'] ?? '').toString().trim();
    final nombre = (j['nombre_usuario'] ?? '').toString().trim();
    final foto   = (j['foto_perfil'] ?? '').toString().trim();
    final pass   = (j['contrasena'] ?? '').toString(); // DEMO: en real, hashear
    final esNeg  = (j['es_negocio'] == true || j['es_negocio'] == 1 || '${j['es_negocio']}'.toLowerCase()=='true') ? 1 : 0;

    if (id.isEmpty || correo.isEmpty || nombre.isEmpty) {
      return Response(400,
        body: jsonEncode({'error':'Campos requeridos: id, correo, nombre_usuario'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }

    await dbQuery(
      'INSERT INTO usuarios (id_usuario, correo, nombre_usuario, foto_perfil, contrasena, es_negocio) VALUES (?,?,?,?,?,?)',
      [id, correo, nombre, foto.isEmpty ? null : foto, pass, esNeg],
    );

    return Response(201,
      body: jsonEncode({'ok': true, 'data': {
        'id': id, 'correo': correo, 'nombre_usuario': nombre, 'foto_perfil': foto.isEmpty?null:foto, 'es_negocio': esNeg==1
      }}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error POST /usuarios: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}

// ---------- DELETE /usuarios/<id> ----------
Future<Response> eliminarUsuarioHandler(Request req, String id) async {
  try {
    final r = await dbQuery('DELETE FROM usuarios WHERE id_usuario = ?', [id]);
    final n = r.affectedRows ?? 0;
    if (n == 0) {
      return Response(404,
        body: jsonEncode({'error':'No existe el usuario $id'}),
        headers: {'Content-Type':'application/json; charset=utf-8'});
    }
    return Response.ok(jsonEncode({'ok': true, 'deleted': id}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  } catch (e, st) {
    print('Error DELETE /usuarios/$id: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error':'Error interno del servidor'}),
      headers: {'Content-Type':'application/json; charset=utf-8'});
  }
}

// ---------- GET /usuarios/admin  ----------
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
const api = (p,o={}) => fetch(p,o).then(r => r.json());

async function cargar(){
  const res = await api('/usuarios');
  const tbody = document.querySelector('#tabla tbody');
  tbody.innerHTML = '';
  (res.data || []).forEach(u => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${u.id}</td>
      <td>${u.correo||''}</td>
      <td>${u.nombre_usuario||''}</td>
      <td>${u.es_negocio? 'Sí':'No'}</td>
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
  return Response.ok(html, headers: {'Content-Type':'text/html; charset=utf-8'});
}
