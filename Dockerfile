# ============================================================
# Railway AMS — Multi-Stage Container Build (Jakarta EE 10 / Tomcat 10.1)
# ============================================================

# Stage 1: Build WAR with Maven
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build

COPY pom.xml .
COPY .mvn .mvn
COPY mvnw mvnw.cmd ./
RUN ./mvnw dependency:go-offline -B

COPY src ./src
RUN ./mvnw clean package -DskipTests

# Stage 2: Runtime Container
FROM tomcat:10.1-jdk17
LABEL maintainer="Subham Swastik Dhal <subhamsdhal@gmail.com>"
LABEL description="Railway Asset Management System (AMS) — Enterprise Edition"

# Remove default sample webapps for security hardening
RUN rm -rf /usr/local/tomcat/webapps/*

# Copy compiled WAR to Tomcat webapps as root application
COPY --from=builder /build/target/RailwayAMS.war /usr/local/tomcat/webapps/ROOT.war

# Cloud Run / Container standard HTTP port
EXPOSE 8080

CMD ["catalina.sh", "run"]
