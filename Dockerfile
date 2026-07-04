FROM node:24-bookworm-slim AS frontend

WORKDIR /workspace/frontend

COPY frontend/package.json frontend/pnpm-lock.yaml frontend/pnpm-workspace.yaml frontend/tsconfig.base.json ./
COPY frontend/apps ./apps
COPY frontend/packages ./packages
COPY frontend/scripts ./scripts

RUN corepack enable \
    && pnpm install --frozen-lockfile \
    && pnpm --filter @xzs/admin build \
    && pnpm --filter @xzs/student build

FROM maven:3.8.8-eclipse-temurin-8 AS backend

WORKDIR /workspace/source/xzs

COPY source/xzs ./
COPY --from=frontend /workspace/frontend/apps/admin/admin ./src/main/resources/static/admin
COPY --from=frontend /workspace/frontend/apps/student/student ./src/main/resources/static/student

RUN mvn -DskipTests package

FROM eclipse-temurin:8-jre

WORKDIR /app

ENV SPRING_PROFILES_ACTIVE=prod
ENV SERVER_PORT=8000
ENV XZS_LOG_PATH=/tmp/xzs/logs

COPY --from=backend /workspace/source/xzs/target/xzs-3.9.0.jar /app/xzs.jar

EXPOSE 8000

CMD ["java", "-Duser.timezone=Asia/Shanghai", "-jar", "/app/xzs.jar"]
