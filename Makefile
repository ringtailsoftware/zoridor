all:
	docker build -t zoridorwebsrv .
	docker run -p8000:8000 -v ${PWD}/zig-out:/data -w /data --rm zoridorwebsrv python3 -m http.server 8000
