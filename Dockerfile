# =============================================================================
#  Image de l'application Events (FST)
#  "Build once, deploy many" : le JAR est construit ET testé par Jenkins,
#  l'image ne fait que l'embarquer (pas de recompilation, pas de JDK en prod).
# =============================================================================
FROM eclipse-temurin:17-jre-alpine

LABEL org.opencontainers.image.title="events-app" \
      org.opencontainers.image.vendor="Faculté des Sciences de Tunis - IGL5 G2" \
      org.opencontainers.image.source="https://github.com/roudayn-kouka/IGL5-G2-EventsProjetcs"

# Utilisateur non-root (bonne pratique vérifiée par Trivy misconfig)
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /app

COPY --chown=10001:10001 target/*.jar app.jar

USER 10001:10001
EXPOSE 8089

# La JVM s'adapte aux limites mémoire du conteneur Kubernetes
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
