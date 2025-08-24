# ========= Build =========
FROM dart:stable AS build
WORKDIR /app

# Cache deps
COPY pubspec.* ./
RUN dart pub get

# Código y build AOT
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/backend_dart.dart -o /app/server

# ========= Runtime (simple) =========
FROM dart:stable
WORKDIR /app
COPY --from=build /app/server /app/server

# Render te da $PORT, debes escucharlo en 0.0.0.0
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
