m4_changequote([[, ]])

m4_ifdef([[CROSS_QEMU]], [[
##################################################
## "qemu-user-static" stage
##################################################

FROM ubuntu:18.04 AS qemu-user-static
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends qemu-user-static
]])

##################################################
## "build-supercronic" stage
##################################################

FROM golang:1-stretch AS build-supercronic
m4_ifdef([[CROSS_QEMU]], [[COPY --from=qemu-user-static CROSS_QEMU CROSS_QEMU]])

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
	&& cd "${GOPATH}/src/github.com/golang/dep" \
	&& git checkout "$(git describe --abbrev=0 --tags)"
RUN cd "${GOPATH}/src/github.com/golang/dep" \
	&& go build -o ./cmd/dep/dep ./cmd/dep/ \
	&& mv ./cmd/dep/dep /usr/bin/dep

# Build Supercronic
ARG SUPERCRONIC_TREEISH=v0.1.8
RUN go get -v -d github.com/aptible/supercronic \
	&& cd "${GOPATH}/src/github.com/aptible/supercronic" \
	&& git checkout "${SUPERCRONIC_TREEISH}" \
	&& dep ensure
RUN cd "${GOPATH}/src/github.com/aptible/supercronic" \
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

m4_ifdef([[CROSS_ARCH]], [[FROM CROSS_ARCH/ubuntu:18.04]], [[FROM ubuntu:18.04]]) AS supercronic
m4_ifdef([[CROSS_QEMU]], [[COPY --from=qemu-user-static CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		tzdata \
	&& rm -rf /var/lib/apt/lists/*

# Create users and groups
ARG SUPERCRONIC_USER_UID=1000
ARG SUPERCRONIC_USER_GID=1000
RUN groupadd \
		--gid "${SUPERCRONIC_USER_GID}" \
		supercronic
RUN useradd \
		--uid "${SUPERCRONIC_USER_UID}" \
		--gid "${SUPERCRONIC_USER_GID}" \
		--shell "$(which bash)" \
		--home-dir /home/supercronic/ \
		--create-home \
		supercronic

# Copy Supercronic build
COPY --from=build-supercronic --chown=root:root /usr/bin/supercronic /usr/bin/supercronic

# Copy crontab
COPY --chown=root:root ./config/crontab /etc/crontab

# Drop root privileges
USER supercronic:supercronic

ENTRYPOINT ["/usr/bin/supercronic"]
CMD ["/etc/crontab"]
