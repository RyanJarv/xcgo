# This neilotoole/xcgo Dockerfile builds a maximalist Go/Golang CGo-enabled
# cross-compiling image It can build CGo apps on macOS, Linux, and Windows.
# It also contains supporting tools such as docker and snapcraft.
# See https://github.com/neilotoole/xcgo
ARG OSX_SDK="MacOSX11.3.sdk"
ARG OSX_CODENAME="big_sur"
ARG OSX_VERSION_MIN="10.10"
#ARG OSX_SDK_BASEURL="https://github.com/neilotoole/xcgo/releases/download/v0.1"
ARG OSX_SDK_BASEURL="https://github.com/phracker/MacOSX-SDKs/releases/download/11.3"
ARG OSX_SDK_SUM="cd4f08a75577145b8f05245a2975f7c81401d75e9535dcffbb879ee1deefcbf4"
ARG OSX_CROSS_COMMIT="be2b79f444aa0b43b8695a4fb7b920bf49ecc01c"
ARG LIBTOOL_VERSION="2.4.6_4"
ARG GOLANGCI_LINT_VERSION="1.43.0"
ARG GORELEASER_VERSION="1.3.1"
ARG GO_VERSION=""
ARG UBUNTU=20.04


####################  golangcore  ####################
FROM ubuntu:${UBUNTU} AS golangcore
ARG GO_VERSION
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl

ENV GOPATH="/go"
ENV PATH="/usr/local/go/bin:$PATH"
RUN mkdir -p "${GOPATH}/src"

RUN if test -z "${GO_VERSION}"; then GO_VERSION=$(curl 'https://go.dev/VERSION?m=text'); fi \
	&& curl -L -o go.tar.gz https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz \
	&& rm -rf /usr/local/go \
	&& tar -C /usr/local -xzf go.tar.gz

RUN go version


####################  devtools  ####################
FROM ubuntu:${UBUNTU} AS devtools
# Dependencies for https://github.com/tpoechtrager/osxcross and some
# other stuff.

COPY --from=golangcore /usr/local/go /usr/local/go

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    docker.io \
    snapcraft \
    build-essential \
    clang \
    cmake \
    file \
    gcc-mingw-w64 gcc-mingw-w64-i686 gcc-mingw-w64-x86-64 \
    less \
    libc6-dev \
    libc6-dev-i386 \
    libc++-dev  \
    libltdl-dev \
    libsqlite3-dev \
    libssl-dev \
    libxml2-dev \
    llvm \
    man \
    parallel \
    patch \
    sqlite3 \
    tree \
    vim \
    git \
    wget \
    xz-utils \
    zlib1g-dev  \
    zsh



####################  osx-cross  ####################
# See https://github.com/tpoechtrager/osxcross
FROM devtools AS osx-cross
ARG OSX_SDK
ARG OSX_CODENAME
ARG OSX_SDK_BASEURL
ARG OSX_SDK_SUM
ARG OSX_CROSS_COMMIT
ARG OSX_VERSION_MIN
ARG LIBTOOL_VERSION
ENV OSX_CROSS_PATH=/osxcross

WORKDIR "${OSX_CROSS_PATH}"
RUN git clone https://github.com/tpoechtrager/osxcross.git . \
 && git checkout -q "${OSX_CROSS_COMMIT}" \
 && rm -rf ./.git

RUN curl -fsSL "${OSX_SDK_BASEURL}/${OSX_SDK}.tar.xz" -o "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz"
RUN echo "${OSX_SDK_SUM}"  "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz" | sha256sum -c -

RUN UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN} ./build.sh

RUN mkdir -p "${OSX_CROSS_PATH}/target/SDK/${OSX_SDK}/usr/"

# Download libtool bottle from homebrew.
RUN NAME=libtool VERSION=${LIBTOOL_VERSION} && curl \
	-L -H 'Authorization: Bearer QQ==' \
	-XGET "https://ghcr.io/v2/homebrew/core/${NAME}/blobs/sha256:$( \
		curl \
			-H 'Accept: application/vnd.oci.image.index.v1+json' \
			-H 'Authorization: Bearer QQ==' -XGET https://ghcr.io/v2/homebrew/core/${NAME}/manifests/${VERSION} \
				| jq -r '.manifests'\
'					|.[]'\
'					| select(.annotations."org.opencontainers.image.ref.name" == "'"${VERSION}.${OSX_CODENAME}"'")'\
'					| .annotations."sh.brew.bottle.digest"' \
	)" | gzip -dc | tar xf - \
		-C "${OSX_CROSS_PATH}/target/SDK/${OSX_SDK}/usr/" \
		--strip-components=2 \
		"libtool/${LIBTOOL_VERSION}/include/" \
		"libtool/${LIBTOOL_VERSION}/lib/"

WORKDIR /root


####################  gotools  ####################
FROM osx-cross AS gotools
# This section descended from https://github.com/mailchain/goreleaser-xcgo
# Much gratitude to the mailchain team.
ARG GORELEASER_VERSION
ARG GORELEASER_DOWNLOAD_FILE="goreleaser_Linux_x86_64.tar.gz"
ARG GORELEASER_DOWNLOAD_URL="https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE}"
ARG GOLANGCI_LINT_VERSION

RUN wget "${GORELEASER_DOWNLOAD_URL}"; \
    tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser; \
    rm $GORELEASER_DOWNLOAD_FILE;

# Add mage - https://magefile.org
RUN cd /tmp && git clone https://github.com/magefile/mage.git && cd mage && go run bootstrap.go && rm -rf /tmp/mage

# https://github.com/golangci/golangci-lint
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin "v${GOLANGCI_LINT_VERSION}"



####################  xcgo-final  ####################
FROM gotools AS xcgo-final
LABEL maintainer="neilotoole@apache.org"
ENV PATH=${OSX_CROSS_PATH}/target/bin:/usr/local/go/bin:$PATH:${GOPATH}/bin
ENV CGO_ENABLED=1

WORKDIR /root
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
