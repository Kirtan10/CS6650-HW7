# Build stage. `go mod tidy` resolves the AWS SDK at build time, so no go.sum
# needs to be committed (run `go mod tidy` locally if you want to pin it).
FROM golang:1.25-alpine AS build
WORKDIR /app
COPY . .
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -o /receiver .

# Run stage: alpine (not scratch) so busybox wget exists for the ECS health check.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=build /receiver /receiver
EXPOSE 8080
ENTRYPOINT ["/receiver"]
