FROM alpine:edge as base

RUN apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    # Basic tools
    bash \
    ca-certificates \
    curl \
    git \
    gnupg \
    img \
    jq \
    unzip \
    rsync \
    # Python3
    python3 \
    py3-pip \
    py3-virtualenv \
    py3-wheel \
    # Infrastructure
    terraform \
    kubectl \
    helm \
    mono \
    # .NET Core dependencies
    krb5-libs \
    libgcc \
    libintl \
    libssl1.1 \
    libstdc++ \
    zlib && \
    # terragrunt binary
    curl -o terragrunt -Ls \
    "https://github.com/gruntwork-io/terragrunt/releases/download/v0.28.15/terragrunt_linux_amd64" && \
    install -o root -g root -m 0755 terragrunt /usr/local/bin/terragrunt && \
    rm -r terragrunt && \
    # Azure CLI
    apk add --virtual=build gcc libffi-dev musl-dev openssl-dev python3-dev make && \
    pip3 install --no-cache-dir azure-cli && \
    apk del --purge build
    
ENV \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    # Set the invariant mode since icu_libs isn't included (see https://github.com/dotnet/announcements/issues/20)
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true \
    HOME=/github/home \
    GITHUB_WORKSPACE=/github/workspace \
    USER=runner \
    # Set directory for runtime files
    XDG_RUNTIME_DIR=/run/user/1000 \
    PATH="/github/externals/node12/bin:/github/externals/bin:${PATH}"

RUN mkdir -p /github/home && \
    mkdir -p /github/workspace && \
    adduser \
    --disabled-password \
    --gecos "" \
    --home "${HOME}" \
    --uid "1000" \
    "$USER" && \
    chown -R $USER:$USER /github

# Patches required for img image building, please see https://github.com/genuinetools/img/blob/master/Dockerfile
RUN chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap && \
    mkdir -m 700 -p /run/user/1000 && \
    chown -R runner:runner /run/user/1000 && \
    echo runner:100000:65536 | tee /etc/subuid | tee /etc/subgid


FROM base as build
USER runner
WORKDIR /github/home
ENV PATH=/github/home/.dotnet:$PATH

# Install dotnet 3.1 SDK
RUN curl -s https://dotnet.microsoft.com/download/dotnet/scripts/v1/dotnet-install.sh --output dotnet-install.sh && \
    /bin/bash dotnet-install.sh

# Install node12 as external tools
RUN curl -s https://vstsagenttools.blob.core.windows.net/tools/nodejs/12.13.1/alpine/x64/node-12.13.1-alpine-x64.tar.gz -o node.tar.gz && \
    mkdir -p release/externals/node12 && \
    tar xzvf node.tar.gz -C release/externals/node12

# Clone GitHub Actions runner git repository
RUN git clone https://github.com/actions/runner.git runner

# Apply fixes for alpine release
COPY --chown=runner:runner fixes/Runner.Sdk/. runner/src/Runner.Sdk
COPY --chown=runner:runner fixes/layoutroot/. runner/src/Misc/layoutroot
COPY --chown=runner:runner fixes/version.json runner
RUN cp -R runner/src/Misc/layoutroot/. release && \
    cp -R runner/src/Misc/layoutbin/. release/bin

# Publish release for GitHub Actions runner
RUN dotnet sln runner/src/ActionsRunner.sln remove runner/src/Runner.Service/Windows/RunnerService.csproj runner/src/Test/Test.csproj && \
    dotnet publish runner/src/ActionsRunner.sln -c Release -o release/bin --self-contained true -p:PublishReadyToRun=false -r linux-musl-x64


FROM base as runner
USER runner
WORKDIR /github
COPY --chown=runner:runner --from=build /github/home/release/. /github
COPY --chown=runner:runner entrypoint.sh .

ENTRYPOINT ["./entrypoint.sh"]