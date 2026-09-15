FROM eclipse-temurin:17-jdk AS build
WORKDIR /workspace/app

# Install minimal dependencies for uv
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv using unmanaged installation to /usr/local/uv
RUN mkdir -p /usr/local/uv && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/local/uv" sh && \
    ln -s /usr/local/uv/uv /usr/local/bin/uv

# Let uv install and manage Python 3.12.10
RUN uv python install 3.12.10

COPY gradlew .
COPY gradlew.bat .
COPY gradle gradle
COPY build.gradle .
COPY src src
COPY .env .env
COPY scripts scripts
COPY DSL DSL

RUN chmod 754 ./gradlew
RUN ./gradlew -Pprod clean bootJar
RUN mkdir -p build/libs && (cd build/libs; jar -xf *.jar)

FROM eclipse-temurin:17-jdk
VOLUME /build/tmp

# Install minimal dependencies for uv and jq
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    jq \
    nano \
    perl \
    && rm -rf /var/lib/apt/lists/*

# Install uv using unmanaged installation to /usr/local/uv
RUN mkdir -p /usr/local/uv && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/local/uv" sh && \
    ln -s /usr/local/uv/uv /usr/local/bin/uv

# Let uv install and manage Python 3.12.10
RUN uv python install 3.12.10

# Creating python virtual environment using uv with uv-managed Python
RUN uv venv /app/python_virtual_env --python 3.12.10

ARG DEPENDENCY=/workspace/app/build/libs
COPY --from=build ${DEPENDENCY}/BOOT-INF/lib /app/lib
COPY --from=build ${DEPENDENCY}/META-INF /app/META-INF
COPY --from=build ${DEPENDENCY}/BOOT-INF/classes /app
COPY DSL /DSL
COPY scripts /app/scripts/
COPY constants.ini /app/constants.ini
RUN chmod a+x /app/scripts/*

ENV application.config-path=/DSL

COPY .env /app/.env
RUN echo BUILDTIME=`date +%s` >> /app/.env

RUN useradd cronmanager
RUN chown -R cronmanager:cronmanager /app
RUN chown -R cronmanager:cronmanager /DSL
USER cronmanager

EXPOSE 9010

ENTRYPOINT ["java","-cp","app:app/lib/*","ee.buerokratt.cronmanager.CronManagerApplication"]
