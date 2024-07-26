m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

FROM --platform=${BUILDPLATFORM} docker.io/golang:1-bookworm AS build

# Environment
ENV GO111MODULE=on
ENV CGO_ENABLED=0
ENV GOOS=m4_ifdef([[CROSS_GOOS]], [[CROSS_GOOS]])
ENV GOARCH=m4_ifdef([[CROSS_GOARCH]], [[CROSS_GOARCH]])
ENV GOARM=m4_ifdef([[CROSS_GOARM]], [[CROSS_GOARM]])

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		file \
		tzdata \
	&& rm -rf /var/lib/apt/lists/*

# Build Supercronic
ARG SUPERCRONIC_TREEISH=v0.2.30
ARG SUPERCRONIC_REMOTE=https://github.com/aptible/supercronic.git
WORKDIR /go/src/supercronic/
RUN git clone "${SUPERCRONIC_REMOTE:?}" ./
RUN git checkout "${SUPERCRONIC_TREEISH:?}"
RUN git submodule update --init --recursive
RUN go build -o ./supercronic -ldflags '-s -w' ./main.go
RUN mv ./supercronic /usr/bin/supercronic
RUN file /usr/bin/supercronic
RUN /usr/bin/supercronic -test ./integration/hello.crontab

##################################################
## "main" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:24.04]], [[FROM docker.io/ubuntu:24.04]]) AS main

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		bzip2 \
		ca-certificates \
		curl \
		dnsutils \
		file \
		findutils \
		gawk \
		git \
		gnupg \
		gosu \
		grep \
		idn2 \
		iputils-ping \
		jq \
		lftp \
		libarchive-tools \
		locales \
		make \
		media-types \
		moreutils \
		msmtp \
		netcat-openbsd \
		openssh-client \
		openssl \
		patch \
		perl \
		publicsuffix \
		rsync \
		sed \
		tzdata \
		unzip \
		wget \
		xz-utils \
		zip \
		zstd \
	&& rm -rf /var/lib/apt/lists/*

# Create unprivileged user
RUN userdel -rf "$(id -nu 1000)" && useradd -u 1000 -g 0 -s "$(command -v bash)" -m supercronic

# Setup locale
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
RUN printf '%s\n' "${LANG:?} UTF-8" > /etc/locale.gen \
	&& localedef -c -i "${LANG%%.*}" -f UTF-8 "${LANG:?}" ||:

# Setup timezone
ENV TZ=UTC
RUN printf '%s\n' "${TZ:?}" > /etc/timezone \
	&& ln -snf "/usr/share/zoneinfo/${TZ:?}" /etc/localtime

# Copy Supercronic build
COPY --from=build --chown=root:root /usr/bin/supercronic /usr/bin/supercronic

# Copy crontab
COPY --chown=root:root ./config/crontab /etc/crontab
RUN find /etc/crontab -type f -not -perm 0644 -exec chmod 0644 '{}' ';'

# Drop root privileges
USER supercronic:root

ENTRYPOINT ["/usr/bin/supercronic"]
CMD ["/etc/crontab"]
