FROM eclipse-temurin:17-jdk@sha256:5d6042fb8cdc14d614e4e421f52e3211fc5aeadddce44cbf9de8ed37c791f824 AS build
WORKDIR /workspace/app
COPY gradlew gradlew.bat build.gradle .env ./
COPY gradle gradle
COPY src src
RUN chmod 754 ./gradlew && ./gradlew -Pprod clean bootJar && mkdir -p build/libs && (cd build/libs; jar -xf *.jar)
FROM eclipse-temurin:17-jdk@sha256:5d6042fb8cdc14d614e4e421f52e3211fc5aeadddce44cbf9de8ed37c791f824 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates jq perl && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv@sha256:4a1f3666816dafadd20ceb71eac9a7d56d7ef30279f7d64048519ab901ada336 /uv /uvx /usr/local/bin/
ENV UV_PYTHON_INSTALL_DIR=/opt/cron-python UV_LINK_MODE=copy
RUN uv python install 3.12.10 && uv venv /app/python_virtual_env --python /opt/cron-python/cpython-3.12.10-linux-x86_64-gnu/bin/python3.12
COPY ci/central/requirements-vault.txt /tmp/requirements-vault.txt
RUN uv pip install --python /app/python_virtual_env/bin/python3 --no-deps --require-hashes -r /tmp/requirements-vault.txt
COPY --from=build /workspace/app/build/libs/BOOT-INF/lib /app/lib
COPY --from=build /workspace/app/build/libs/META-INF /app/META-INF
COPY --from=build /workspace/app/build/libs/BOOT-INF/classes /app
COPY DSL /DSL
COPY scripts /app/scripts/
COPY constants.ini .env /app/
COPY --from=llm DSL/CronManager/script/ /app/scripts/
COPY --from=llm src/utils/decrypt_vault_secrets.py /app/src/utils/decrypt_vault_secrets.py
COPY --from=llm src/loki_logger.py src/constants_loader.py /app/src/
RUN chmod a+rx /app/scripts/*.sh && chmod -R a+rX /opt/cron-python /app/src && chown -R 1000:1000 /app /DSL
ENV application.config-path=/DSL PYTHONPATH=/app VAULT_PYTHON_VENV=/app/python_virtual_env
USER 1000:1000
ENTRYPOINT ["java","-cp","app:app/lib/*","ee.buerokratt.cronmanager.CronManagerApplication"]
