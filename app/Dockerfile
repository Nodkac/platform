# Stage 1: build the binary. This stage has the whole Go toolchain (~800MB).
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app-bin .

# Stage 2: the image that actually ships. "distroless/static" has no shell,
# no package manager, no OS utilities — just your binary. Nothing to exploit.
FROM gcr.io/distroless/static-debian12
COPY --from=build /app-bin /app-bin
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app-bin"]



