build:
	go build -o ./bin/Ohara

run: build
	./bin/Ohara

test:
	go test ./...