
int _toInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final p = int.tryParse('$v');
  return p ?? fallback;
}

double _toDouble(dynamic v, {double fallback = 0.0}) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  final p = double.tryParse('$v');
  return p ?? fallback;
}

bool _toBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

// ---------- Productos ----------

Map<String, dynamic> mapProductoFront(Map p) {
  // soporta objetos base de /producto/:id (con 'fotos' o 'vendedor') y
  // objetos de listado /productos o /productos/:slug (con 'imagen' y 'categoria')
  final fotos = (p['fotos'] is List) ? (p['fotos'] as List) : const [];
  final vendedor = (p['vendedor'] is Map) ? (p['vendedor'] as Map) : const {};

  return {
    'id': _toInt(p['id']),
    'name': (p['nombre'] ?? '').toString(),
    'description': (p['descripcion'] ?? '').toString(),
    'price': _toDouble(p['precio']),
    'image': fotos.isNotEmpty
        ? fotos.first
        : (p['imagen'] ?? ''), // primer fallback para listados
    'sellerId': (vendedor['id'] ?? p['vendedor_id'] ?? '').toString(),
    'sellerName': (vendedor['nombre'] ?? p['vendedor_nombre'] ?? '').toString(),
    'stock': _toInt(p['stock']),
    // extra opcional de categoría si viene en el SELECT:
    'category': (p['categoria'] is Map)
        ? {
            'slug': (p['categoria']['slug'] ?? '').toString(),
            'name': (p['categoria']['nombre'] ?? '').toString(),
          }
        : null,
  };
}

List<Map<String, dynamic>> mapProductosFront(Iterable items) =>
    items.map((e) => mapProductoFront(Map<String, dynamic>.from(e as Map))).toList();

// ---------- Reseñas ----------

Map<String, dynamic> mapResenaFront(Map r) => {
      'id': _toInt(r['id']),
      'userId': (r['id_usuario'] ?? '').toString(),
      'userName': (r['nombre_usuario'] ?? '').toString(),
      'rating': _toInt(r['calificacion']),
      'comment': (r['comentario'] ?? '').toString(),
      'date': (r['fecha'] ?? '').toString(), // ya suele venir ISO-8601
    };

List<Map<String, dynamic>> mapResenasFront(Iterable items) =>
    items.map((e) => mapResenaFront(Map<String, dynamic>.from(e as Map))).toList();

// ---------- Usuarios ----------

Map<String, dynamic> mapUserFront(Map u) => {
      'id': (u['id'] ?? u['id_usuario'] ?? '').toString(),
      'email': (u['correo'] ?? '').toString(),
      'name': (u['nombre_usuario'] ?? '').toString(),
      'avatar': (u['foto_perfil'] ?? '').toString(),
      'isBusiness': _toBool(u['es_negocio']),
    };

List<Map<String, dynamic>> mapUsersFront(Iterable items) =>
    items.map((e) => mapUserFront(Map<String, dynamic>.from(e as Map))).toList();

// ---------- Categorías (opcional, por si tu front las espera en inglés) ----------

Map<String, dynamic> mapCategoriaFront(Map c) => {
      'id': (c['id'] ?? c['codigo_categoria'] ?? '').toString(),
      'name': (c['nombre'] ?? '').toString(),
      'description': (c['descripcion'] ?? '').toString(),
      'slug': (c['slug'] ?? '').toString(),
      'icon': (c['icono'] ?? '').toString(),
      'color': (c['color'] ?? '').toString(),
      'count': (c['cantidad'] ?? '').toString(),
    };

List<Map<String, dynamic>> mapCategoriasFront(Iterable items) =>
    items.map((e) => mapCategoriaFront(Map<String, dynamic>.from(e as Map))).toList();