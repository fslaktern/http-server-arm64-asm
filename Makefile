build: server.S
	aarch64-linux-gnu-as server.S -o server.o
	aarch64-linux-gnu-ld server.o -o server

run: server
	qemu-aarch64 ./server 0.0.0.0 80

debug: server
	@echo "Connect to 127.0.0.1:1234 using your debugger"
	qemu-aarch64 -g 1234 ./server 127.0.0.1 8000

clean:
	rm -rf server server.o
