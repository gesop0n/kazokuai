# バックエンドを Cloud Run のサービス kazokuai として動かすイメージ。
# リポジトリの直下から、cgo なしで ./backend を作る。
#	docker build -t kazokuai .
FROM golang:1.27.3 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /out/backend ./backend

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/backend /backend
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/backend"]
