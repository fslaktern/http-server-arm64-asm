build: server.S
	aarch64-linux-gnu-as server.S -o server.o
	aarch64-linux-gnu-ld server.o -o server

run: server
	qemu-aarch64 ./server 0.0.0.0 80

clean:
	rm -rf server server.o
