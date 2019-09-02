m4_changequote([[, ]])

##################################################
## "build-supercronic" stage
##################################################

FROM docker.io/golang:1-stretch AS build-supercronic
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Environment
ENV CGO_ENABLED=0

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		file \
		tzdata \
	&& rm -rf /var/lib/apt/lists/*

# Build Dep
RUN go get -v -d github.com/golang/dep \
	&& cd "${GOPATH:?}/src/github.com/golang/dep" \
	&& git checkout "$(git describe --abbrev=0 --tags)"
RUN cd "${GOPATH:?}/src/github.com/golang/dep" \
	&& go build -o ./cmd/dep/dep ./cmd/dep/ \
	&& mv ./cmd/dep/dep /usr/bin/dep

# Build Supercronic
ARG SUPERCRONIC_TREEISH=v0.1.9
RUN go get -v -d github.com/aptible/supercronic \
	&& cd "${GOPATH:?}/src/github.com/aptible/supercronic" \
	&& git checkout "${SUPERCRONIC_TREEISH:?}" \
	&& dep ensure
RUN cd "${GOPATH:?}/src/github.com/aptible/supercronic" \
	&& export GOOS=m4_ifdef([[CROSS_GOOS]], [[CROSS_GOOS]]) \
	&& export GOARCH=m4_ifdef([[CROSS_GOARCH]], [[CROSS_GOARCH]]) \
	&& export GOARM=m4_ifdef([[CROSS_GOARM]], [[CROSS_GOARM]]) \
	&& go build -o ./supercronic -ldflags '-s -w' ./main.go \
	&& mv ./supercronic /usr/bin/supercronic \
	&& file /usr/bin/supercronic \
	&& /usr/bin/supercronic -test ./integration/hello.crontab

##################################################
## "supercronic" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:18.04]], [[FROM docker.io/ubuntu:18.04]]) AS supercronic
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

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
RUN printf '%s\n' 'en_US.UTF-8 UTF-8' > /etc/locale.gen
RUN localedef -c -i en_US -f UTF-8 en_US.UTF-8 ||:
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Setup timezone
ENV TZ=UTC
RUN ln -snf "/usr/share/zoneinfo/${TZ:?}" /etc/localtime
RUN printf '%s\n' "${TZ:?}" > /etc/timezone

# Copy Supercronic build
COPY --from=build-supercronic --chown=root:root /usr/bin/supercronic /usr/bin/supercronic

# Copy crontab
COPY --chown=root:root ./config/crontab /etc/crontab

# Drop root privileges
USER supercronic:supercronic

ENTRYPOINT ["/usr/bin/supercronic"]
CMD ["/etc/crontab"]
