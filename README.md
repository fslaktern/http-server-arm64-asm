# HTTP server in ARM64 assembly

## Features

- CLI arguments to specify interface and port to listen on
- GET requests read files from current directory
- POST requests write to arbitrary files from current directory
- Path traversal protection by removing `.` from request path
- Can run on your phone

## Setup

Required binaries:

- qemu-aarch64 or an aarch64 CPU
- aarch64-linux-gnu-as
- aarch64-linux-gnu-ld

``` sh
sudo apt-get install -y binutils-aarch64-linux-gnu qemu-user
```

## Usage

``` sh
make build
make run
# HTTP server listening on 0.0.0.0:80
```

## Known bugs

- None

## TODOs

- Replace `add` and `sub` with signed equivalents and check for negative numbers
- Save LR in `_start`
- Make sure return code for all function calls are not error values
  - Return code is returned in x1, and value in x0
- Print error messages
- Implementations

### Tests

- IPv4 address with more than 3 digits per octet
- IPv4 address with no digits, only 3 dots
- Port larger than 65535

## Debugging workflow

### Terminal #1

``` sh
make build
qemu-aarch64 -g 1234 ./server 127.0.0.1 8000
```

### Terminal #2

``` sh
pwndbg server
# or
# gdb-multiarch server
```

``` text
pwndbg> target remote :1234
pwndbg> ni
```

