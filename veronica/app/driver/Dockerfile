FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /driver ./cmd/driver

# distroless static carries the CA certificates the TLS connections to
# OpenAI need; scratch does not. Keeping the image tiny keeps the cold
# start inside the ring budget.
FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /driver /driver
ENTRYPOINT ["/driver"]
