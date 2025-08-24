
// Endpoints:
//   GET    /api/usuarios
//   POST   /api/usuarios/register        (multipart/form-data o JSON; campo archivo: "foto_perfil")
//   POST   /api/usuarios/login           (JSON {correo, contrasena})
//   GET    /api/usuarios/<id>            (alfa-num de 6 chars normalmente)
//   PUT    /api/usuarios/<id>            (JSON {nombre_usuario?, localidad?, descripcion?})

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:backend_dart/db.dart' show dbQuery;
import 'package:crypto/crypto.dart' show sha1;
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

const _json = {'Content-Type': 'application/json; charset=utf-8'};

// ------------------------- Utilidades -------------------------

final _rnd = Random.secure();

Future<String> _generarIDUnico() async {
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  while (true) {
    final id = List.generate(6, (_) => chars[_rnd.nextInt(chars.length)]).join();
    final rs =
        await dbQuery('SELECT id_usuario FROM usuarios WHERE id_usuario = ?', [id]);
    if (rs.isEmpty) return id;
  }
}

bool _toBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

String? _contentType(Request req) =>
    req.headers['content-type'] ?? req.headers['Content-Type'];

String _signParams(Map<String, String> params, String apiSecret) {
  final keys = params.keys.toList()..sort();
  final toSign = keys.map((k) => '$k=${params[k]}').join('&');
  return sha1.convert(utf8.encode('$toSign$apiSecret')).toString();
}

/// Sube bytes a Cloudinary
Future<String?> _uploadToCloudinary({
  required Uint8List bytes,
  required String filename,
  String? mimeType,
}) async {
  final env = DotEnv()..load();
  final cloud = env['CLOUD_NAME'] ?? env['CLOUDINARY_CLOUD_NAME'];
  final apiKey = env['CLOUD_API_KEY'] ?? env['CLOUDINARY_API_KEY'];
  final apiSecret = env['CLOUD_API_SECRET'] ?? env['CLOUDINARY_API_SECRET'];
  final uploadPreset = env['CLOUD_UPLOAD_PRESET'];

  if (cloud == null || apiKey == null || (uploadPreset == null && apiSecret == null)) {
    print('⚠️ Cloudinary vars faltantes (CLOUD_NAME/CLOUD_API_KEY/[CLOUD_UPLOAD_PRESET|CLOUD_API_SECRET])');
    return null;
  }

  final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloud/image/upload');
  final req = http.MultipartRequest('POST', uri);

  req.fields['folder'] = 'usuarios';
  req.fields['transformation'] = 'c_limit,w_500,h_500';

  if (uploadPreset != null && uploadPreset.isNotEmpty) {
    // Unsigned upload (más simple)
    req.fields['upload_preset'] = uploadPreset;
  } else {
    // Signed upload
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final paramsToSign = <String, String>{
      'folder': 'usuarios',
      'transformation': 'c_limit,w_500,h_500',
      'timestamp': timestamp,
    };
    final signature = _signParams(paramsToSign, apiSecret!);
    req.fields.addAll({
      'timestamp': timestamp,
      'api_key': apiKey,
      'signature': signature,
    });
  }

  req.files.add(http.MultipartFile.fromBytes(
    'file',
    bytes,
    filename: filename,
    contentType: mimeType != null ? MediaType.parse(mimeType) : null,
  ));

  final resp = await req.send();
  final body = await resp.stream.bytesToString();

  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['secure_url'] ?? data['url'])?.toString();
  } else {
    print('❌ Cloudinary ${resp.statusCode}: $body');
    return null;
  }
}


Future<({
  Map<String, String> fields,
  Uint8List? fileBytes,
  String? fileName,
  String? fileMime
})> _parseRegisterBody(Request req) async {
  final ctype = _contentType(req) ?? '';
  if (!ctype.toLowerCase().startsWith('multipart/form-data')) {
    final Map<String, dynamic> j =
        (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    return (
      fields: j.map((k, v) => MapEntry(k, v?.toString() ?? '')),
      fileBytes: null,
      fileName: null,
      fileMime: null
    );
  }

  final match = RegExp(r'boundary=([^\s;]+)').firstMatch(ctype);
  if (match == null) {
    return (fields: <String, String>{}, fileBytes: null, fileName: null, fileMime: null);
  }
  final boundary = match.group(1)!;

  final transformer = MimeMultipartTransformer(boundary);
  final parts = await transformer.bind(req.read()).toList();

  final fields = <String, String>{};
  Uint8List? fileBytes;
  String? fileName;
  String? fileMime;

  for (final part in parts) {
    final disp = part.headers['content-disposition'] ?? '';
    final name = RegExp(r'name="([^"]+)"').firstMatch(disp)?.group(1);
    final filename = RegExp(r'filename="([^"]*)"').firstMatch(disp)?.group(1);
    final ct = part.headers['content-type'];

    final collected = await part.fold<List<int>>([], (p, e) => (p..addAll(e)));
    if (name == null) continue;

    if (filename != null && filename.isNotEmpty) {
      fileBytes = Uint8List.fromList(collected);
      fileName = filename;
      fileMime = ct ?? lookupMimeType(filename) ?? 'application/octet-stream';
    } else {
      fields[name] = utf8.decode(collected);
    }
  }

  return (fields: fields, fileBytes: fileBytes, fileName: fileName, fileMime: fileMime);
}

// ------------------------- Handlers -------------------------

// GET /api/usuarios
Future<Response> _listarUsuarios(Request req) async {
  try {
    final rs = await dbQuery('SELECT * FROM usuarios');

    final list = <Map<String, dynamic>>[];
    for (final row in rs) {
      list.add({
        'id_usuario': row['id_usuario']?.toString(),
        'correo': row['correo']?.toString(),
        'nombre_usuario': row['nombre_usuario']?.toString(),
        'foto_perfil': row['foto_perfil']?.toString(),
        'contrasena': row['contrasena']?.toString(),
        'es_negocio': row['es_negocio'],
      });
    }

    return Response.ok(jsonEncode(list), headers: _json);
  } catch (e, st) {
    print('❌ Error en /api/usuarios: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al obtener usuarios'}),
      headers: _json,
    );
  }
}

// POST /api/usuarios/register
Future<Response> _registrarUsuario(Request req) async {
  try {
    final parsed = await _parseRegisterBody(req);
    final f = parsed.fields;

    final correo = (f['correo'] ?? '').trim();
    final nombreUsuario = (f['nombre_usuario'] ?? '').trim();
    final contrasena = (f['contrasena'] ?? '').trim();
    final esNegocioStr = (f['es_negocio'] ?? 'false').trim();
    final esNegocio = _toBool(esNegocioStr) ? 1 : 0;

    if (correo.isEmpty || nombreUsuario.isEmpty || contrasena.isEmpty) {
      return Response(400,
          body: jsonEncode({'error': 'Faltan campos requeridos'}),
          headers: _json);
    }

    // Correo único
    final existing =
        await dbQuery('SELECT 1 FROM usuarios WHERE correo = ?', [correo]);
    if (existing.isNotEmpty) {
      return Response(409,
          body: jsonEncode({'error': 'Correo ya registrado'}), headers: _json);
    }

    // Subir foto si vino archivo o aceptar URL directa en "foto_perfil"
    String? fotoUrl = (f['foto_perfil'] ?? '').trim().isEmpty ? null : f['foto_perfil']!.trim();
    if (parsed.fileBytes != null && parsed.fileBytes!.isNotEmpty) {
      final up = await _uploadToCloudinary(
        bytes: parsed.fileBytes!,
        filename: parsed.fileName ?? 'foto.jpg',
        mimeType: parsed.fileMime,
      );
      if (up != null) fotoUrl = up;
    }

    // Generar ID único
    final idUsuario = await _generarIDUnico();

    await dbQuery(
      '''
      INSERT INTO usuarios (id_usuario, correo, nombre_usuario, contrasena, es_negocio, foto_perfil)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [idUsuario, correo, nombreUsuario, contrasena, esNegocio, fotoUrl],
    );

    return Response.ok(jsonEncode({'success': true}), headers: _json);
  } catch (e, st) {
    print('Error al registrar usuario: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al registrar usuario'}),
      headers: _json,
    );
  }
}

// POST /api/usuarios/login
Future<Response> _login(Request req) async {
  try {
    final j = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final correo = (j['correo'] ?? '').toString();
    final contrasena = (j['contrasena'] ?? '').toString();

    final rs = await dbQuery(
      '''
      SELECT id_usuario, correo, nombre_usuario, foto_perfil, es_negocio
      FROM usuarios
      WHERE correo = ? AND contrasena = ?
      ''',
      [correo, contrasena],
    );

    if (rs.isEmpty) {
      return Response(401,
          body: jsonEncode({'error': 'Credenciales incorrectas'}),
          headers: _json);
    }

    final urow = rs.first;
    final u = {
      'id_usuario': urow['id_usuario']?.toString(),
      'correo': urow['correo']?.toString(),
      'nombre_usuario': urow['nombre_usuario']?.toString(),
      'foto_perfil': urow['foto_perfil']?.toString(),
      'es_negocio': urow['es_negocio'],
    };

    return Response.ok(jsonEncode({'success': true, 'usuario': u}), headers: _json);
  } catch (e, st) {
    print('❌ Error al iniciar sesión: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error al iniciar sesión'}),
      headers: _json,
    );
  }
}

// GET /api/usuarios/<id>
Future<Response> _getUsuarioPorId(Request req, String id) async {
  try {
    final rs = await dbQuery(
      '''
      SELECT u.id_usuario, u.nombre_usuario, u.correo, u.foto_perfil, u.es_negocio,
             v.descripcion, v.localidad
      FROM usuarios u
      LEFT JOIN vendedores v ON u.id_usuario = v.id_usuario
      WHERE u.id_usuario = ?
      ''',
      [id],
    );

    if (rs.isEmpty) {
      return Response(404,
          body: jsonEncode({'error': 'Usuario no encontrado'}),
          headers: _json);
    }

    final r = rs.first;
    final out = {
      'id_usuario': r['id_usuario']?.toString(),
      'nombre_usuario': r['nombre_usuario']?.toString(),
      'correo': r['correo']?.toString(),
      'foto_perfil': r['foto_perfil']?.toString(),
      'es_negocio': r['es_negocio'],
      'descripcion': r['descripcion']?.toString(),
      'localidad': r['localidad']?.toString(),
    };

    return Response.ok(jsonEncode(out), headers: _json);
  } catch (e, st) {
    print('❌ Error al obtener usuario: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _json,
    );
  }
}

// PUT /api/usuarios/<id>
Future<Response> _putUsuario(Request req, String id) async {
  try {
    final j = (jsonDecode(await req.readAsString()) as Map<String, dynamic>?) ?? {};
    final nombreUsuario =
        j.containsKey('nombre_usuario') ? j['nombre_usuario']?.toString() : null;
    final localidad = j.containsKey('localidad') ? j['localidad']?.toString() : null;
    final descripcion =
        j.containsKey('descripcion') ? j['descripcion']?.toString() : null;

    if (nombreUsuario != null) {
      await dbQuery(
          'UPDATE usuarios SET nombre_usuario = ? WHERE id_usuario = ?',
          [nombreUsuario, id]);
    }

    if (localidad != null || descripcion != null) {
      final ex = await dbQuery('SELECT * FROM vendedores WHERE id_usuario = ?', [id]);
      if (ex.isEmpty) {
        await dbQuery(
          'INSERT INTO vendedores (id_usuario, descripcion, localidad) VALUES (?, ?, ?)',
          [id, descripcion, localidad],
        );
      } else {
        await dbQuery(
          'UPDATE vendedores SET descripcion = ?, localidad = ? WHERE id_usuario = ?',
          [descripcion ?? ex.first['descripcion'], localidad ?? ex.first['localidad'], id],
        );
      }
    }

    return Response.ok(jsonEncode({'success': true}), headers: _json);
  } catch (e, st) {
    print('Error al actualizar usuario: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error interno del servidor'}),
      headers: _json,
    );
  }
}

// ------------------------- Router exportado -------------------------

final Router usuariosRouter = Router()
  ..get('/', _listarUsuarios)
  ..post('/register', _registrarUsuario)
  ..post('/login', _login)
  ..get('/<id|[A-Za-z0-9]+>', (req, id) => _getUsuarioPorId(req, id))
  ..put('/<id|[A-Za-z0-9]+>', (req, id) => _putUsuario(req, id));
