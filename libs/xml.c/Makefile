CC=gcc

all: libcxml.so

CFLAGS=-g -Werror -fPIC -I c

SRCS=xml.c xml.h

libcxml.so: ${SRCS} 
	$(CC) ${CFLAGS} -Werror $^ -fPIC -shared -o $@

clean:
	rm -f libbit64.so