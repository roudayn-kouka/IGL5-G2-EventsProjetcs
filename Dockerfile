FROM eclipse-temurin:17-jdk-alpine
EXPOSE 8080
COPY target/eventsProject-1.0.0-SNAPSHOT.jar app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
