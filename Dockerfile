FROM golang:1.23-alpine AS builder
WORKDIR /src/backend/go-gateway
COPY backend/go-gateway/go.mod backend/go-gateway/go.sum ./
RUN go mod download
COPY backend/go-gateway/ ./
RUN go test ./... && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/telefam-gateway ./cmd/gateway

FROM alpine:3.21
RUN apk add --no-cache ca-certificates ffmpeg && adduser -D -u 10001 app
COPY --from=builder /out/telefam-gateway /usr/local/bin/telefam-gateway
ENV PORT=8080
EXPOSE 8080
USER app
ENTRYPOINT ["/usr/local/bin/telefam-gateway"]
