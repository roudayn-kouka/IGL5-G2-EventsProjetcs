# =============================================================================
#  Image unique Events (FST) : backend Spring Boot + frontend Angular
#  - Etape 1 : build du frontend Angular (Node, jetable)
#  - Etape 2 : JRE seul ; le JAR est construit ET teste par Jenkins ("build once")
#  Le frontend est servi par Spring Boot sous /events/ (meme origine que l'API).
# =============================================================================

# ---------- Etape 1 : build Angular ----------
FROM node:22-alpine AS front
WORKDIR /front
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
# base-href = context-path du backend (server.servlet.context-path=/events)
RUN npm run build -- --configuration production --base-href /events/

# ---------- Etape 2 : image finale ----------
FROM eclipse-temurin:17-jre-alpine

LABEL org.opencontainers.image.title="events-app" \
      org.opencontainers.image.vendor="Faculté des Sciences de Tunis - IGL5 G2" \
      org.opencontainers.image.source="https://github.com/roudayn-kouka/IGL5-G2-EventsProjetcs"

# Utilisateur non-root (UID numerique : requis par runAsNonRoot de Kubernetes)
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /app

COPY --chown=10001:10001 target/*.jar app.jar
# Sortie Angular (dist/<projet>/browser) -> dossier statique lu par Spring Boot
COPY --from=front --chown=10001:10001 /front/dist/*/browser/ /app/public/

USER 10001:10001
EXPOSE 9082

# /app/public passe en premier : son index.html Angular prime sur static/index.html du JAR
ENV SPRING_WEB_RESOURCES_STATIC_LOCATIONS="file:/app/public/,classpath:/static/,classpath:/public/,classpath:/resources/,classpath:/META-INF/resources/"
# La JVM s'adapte aux limites memoire du conteneur Kubernetes
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]