# ========== Build ==========
FROM dart:stable AS build
WORKDIR /app

# Cache de dependencias
COPY pubspec.* ./
RUN dart pub get

# Código y build AOT
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/backend_dart.dart -o /app/bin/server

# ========== Runtime ==========
FROM dart:stable-runtime
WORKDIR /app
# runtime de Dart (necesario para binario AOT)
COPY --from=build /runtime/ /runtime/
COPY --from=build /app/bin/server /app/server

# Render asigna el puerto en $PORT
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
