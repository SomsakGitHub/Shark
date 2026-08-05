FROM golang:1.25-alpine AS builder

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /shark-api .

FROM alpine:3.20

RUN adduser -D -H -u 10001 appuser
USER appuser

COPY --from=builder /shark-api /shark-api

EXPOSE 8080

CMD ["/shark-api"]
