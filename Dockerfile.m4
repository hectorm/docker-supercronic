m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

FROM docker.io/golang:1-bullseye AS build
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectorm/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

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
ARG SUPERCRONIC_TREEISH=v0.2.1
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

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:22.04]], [[FROM docker.io/ubuntu:22.04]]) AS main
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectorm/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		bzip2 \
		ca-certificates \
		curl \
		dnsutils \
		file \
		gawk \
		git \
		gnupg \
		grep \
		idn2 \
		iputils-ping \
		jq \
		lftp \
		locales \
		make \
		mime-support \
		netcat-openbsd \
		openssh-client \
		openssl \
		patch \
		publicsuffix \
		rsync \
		sed \
		tzdata \
		unzip \
		wget \
		xz-utils \
		zip \
	&& rm -rf /var/lib/apt/lists/*

# Create users and groups
ARG SUPERCRONIC_USER_UID=1000
ARG SUPERCRONIC_USER_GID=1000
RUN groupadd \
		--gid "${SUPERCRONIC_USER_GID:?}" \
		supercronic
RUN useradd \
		--uid "${SUPERCRONIC_USER_UID:?}" \
		--gid "${SUPERCRONIC_USER_GID:?}" \
		--shell "$(command -v bash)" \
		--home-dir /home/supercronic/ \
		--create-home \
		supercronic

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
USER supercronic:supercronic

ENTRYPOINT ["/usr/bin/supercronic"]
CMD ["/etc/crontab"]
