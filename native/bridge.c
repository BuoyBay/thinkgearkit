/* ThinkGear byte transport. All library operations belong to one owner thread.
 * Byte-oriented ABI avoids UTF-8 conversion of binary ThinkGear packets.
 * No discovery, pairing, recording, or automatic radio access occurs here.
 */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#define API __declspec(dllexport)
#ifdef _MSC_VER
#define TLS __declspec(thread)
#else
#define TLS _Thread_local
#endif
typedef SOCKET tg_socket;
#define BAD_SOCKET INVALID_SOCKET
#define socket_close closesocket
#else
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netdb.h>
#include <poll.h>
#define API __attribute__((visibility("default")))
#define TLS _Thread_local
typedef int tg_socket;
#define BAD_SOCKET (-1)
#define socket_close close
#endif

typedef struct {
    int used, kind, state;
    int64_t token;
    tg_socket socket;
#ifdef _WIN32
    HANDLE serial;
#else
    int serial;
    struct termios previous;
    int restore;
#endif
    unsigned char buffer[4096];
    size_t cursor, count, sent;
} TGTransport;
static TGTransport slots[32];
static int64_t next_token = 1;
static TLS char last_error[512];
static const char handshake[] = "{\"enableRawOutput\":true,\"format\":\"Json\"}\n";
#ifdef __APPLE__
extern int64_t tg_macos_open_rfcomm(const char *name);
extern int64_t tg_macos_read_byte(int64_t handle);
extern int64_t tg_macos_status(int64_t handle);
extern void tg_macos_close(int64_t handle);
extern const char *tg_macos_error(void);
extern int64_t tg_ble_open(const char *name);
extern int64_t tg_ble_read_byte(int64_t handle);
extern int64_t tg_ble_status(int64_t handle);
extern void tg_ble_close(int64_t handle);
extern const char *tg_ble_error(void);
extern const char *tg_ble_drain_event(int64_t handle);
extern int64_t tg_ble_internal_events_dropped(int64_t handle);
extern double tg_ble_monotonic_seconds(void);
#endif
API const char *tg_error(void) { return last_error; }
static void error_text(const char *text) { snprintf(last_error,sizeof(last_error),"%s",text); }
static void native_error(const char *operation) {
#ifdef _WIN32
    snprintf(last_error,sizeof(last_error),"%s (native error %lu, socket error %d)", operation,(unsigned long)GetLastError(),WSAGetLastError());
#else
    snprintf(last_error,sizeof(last_error),"%s: %s",operation,strerror(errno));
#endif
}
static TGTransport *find_slot(int64_t token) {
    for (size_t i=0;i<32;i++) if(slots[i].used && slots[i].token==token) return &slots[i];
    error_text("Invalid or closed ThinkGear transport handle"); return NULL;
}
static TGTransport *new_slot(void) {
    for(size_t i=0;i<32;i++) if(!slots[i].used) {
        TGTransport *s=&slots[i]; memset(s,0,sizeof(*s)); s->used=1;
        s->token=next_token; next_token=next_token==INT64_MAX?1:next_token+1;
        s->socket=BAD_SOCKET;
#ifdef _WIN32
        s->serial=INVALID_HANDLE_VALUE;
#else
        s->serial=-1;
#endif
        return s;
    }
    error_text("ThinkGear transport capacity (32) reached"); return NULL;
}
static int would_block(void) {
#ifdef _WIN32
    int e=WSAGetLastError(); return e==WSAEWOULDBLOCK || e==WSAEINPROGRESS || e==WSAEALREADY;
#else
    return errno==EAGAIN || errno==EWOULDBLOCK || errno==EINPROGRESS || errno==EINTR;
#endif
}
API void tg_close(int64_t token) {
    TGTransport *s=find_slot(token); if(!s)return;
#ifdef __APPLE__
    if(s->kind==3)tg_macos_close((int64_t)s->sent);
    if(s->kind==4)tg_ble_close((int64_t)s->sent);
#endif
    if(s->socket!=BAD_SOCKET) socket_close(s->socket);
#ifdef _WIN32
    if(s->serial!=INVALID_HANDLE_VALUE)CloseHandle(s->serial);
#else
    if(s->serial>=0) { if(s->restore)tcsetattr(s->serial,TCSANOW,&s->previous); close(s->serial); }
#endif
    memset(s,0,sizeof(*s));
}
API int64_t tg_open_serial(const char *path) {
    last_error[0]=0;
    if(!path || !*path || strlen(path)>4096) {error_text("Serial path must contain 1..4096 UTF-8 bytes");return 0;}
    TGTransport *s=new_slot(); if(!s)return 0; s->kind=1;
#ifdef _WIN32
    char device[4120];
    if(strncmp(path,"\\\\.\\",4)==0)snprintf(device,sizeof(device),"%s",path);
    else snprintf(device,sizeof(device),"\\\\.\\%s",path);
    wchar_t wide[4120];
    if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,device,-1,wide,4120)) {native_error("Serial path UTF-8");goto fail;}
    s->serial=CreateFileW(wide,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,0,NULL);
    if(s->serial==INVALID_HANDLE_VALUE){native_error("Open serial port");goto fail;}
    DCB dcb={0};dcb.DCBlength=sizeof(dcb);
    if(!GetCommState(s->serial,&dcb)){native_error("Read serial state");goto fail;}
    dcb.BaudRate=CBR_57600;dcb.ByteSize=8;dcb.Parity=NOPARITY;dcb.StopBits=ONESTOPBIT;
    dcb.fBinary=TRUE;dcb.fParity=FALSE;dcb.fOutxCtsFlow=FALSE;dcb.fOutxDsrFlow=FALSE;
    dcb.fDtrControl=DTR_CONTROL_DISABLE;dcb.fRtsControl=RTS_CONTROL_DISABLE;
    dcb.fOutX=FALSE;dcb.fInX=FALSE;dcb.fDsrSensitivity=FALSE;
    COMMTIMEOUTS times={0};times.ReadIntervalTimeout=MAXDWORD;
    if(!SetCommState(s->serial,&dcb)||!SetCommTimeouts(s->serial,&times)){native_error("Configure serial port");goto fail;}
#else
    s->serial=open(path,O_RDWR|O_NOCTTY|O_NONBLOCK);
    if(s->serial<0){native_error("Open serial port");goto fail;}
    if(tcgetattr(s->serial,&s->previous)<0){native_error("Read serial state");goto fail;}
    s->restore=1;
    struct termios config=s->previous;
    config.c_iflag=0;config.c_oflag=0;config.c_lflag=0;
    config.c_cflag=CS8|CREAD|CLOCAL;
    config.c_cc[VMIN]=0;config.c_cc[VTIME]=0;
    if(cfsetispeed(&config,B57600)<0 || cfsetospeed(&config,B57600)<0 || tcsetattr(s->serial,TCSANOW,&config)<0){native_error("Configure serial port");goto fail;}
#endif
    s->state=2;return s->token;
fail:
    tg_close(s->token);return 0;
}
API int64_t tg_open_tcp(const char *host,int64_t port) {
    last_error[0]=0;
    if(!host || !*host || strlen(host)>1024 || port<1 || port>65535){error_text("Invalid TCP host or port");return 0;}
#ifdef _WIN32
    static int initialized; if(!initialized){WSADATA data;if(WSAStartup(MAKEWORD(2,2),&data)){error_text("Initialize Winsock");return 0;}initialized=1;}
#endif
    char service[8];snprintf(service,sizeof(service),"%u",(unsigned)port);
    struct addrinfo hints,*addresses=NULL;memset(&hints,0,sizeof(hints));hints.ai_socktype=SOCK_STREAM;hints.ai_family=AF_UNSPEC;
    int result=getaddrinfo(host,service,&hints,&addresses);
    if(result){snprintf(last_error,sizeof(last_error),"Resolve TCP host: %s",gai_strerror(result));return 0;}
    TGTransport *s=new_slot();if(!s){freeaddrinfo(addresses);return 0;}s->kind=2;
    for(struct addrinfo *a=addresses;a;a=a->ai_next){
        s->socket=socket(a->ai_family,a->ai_socktype,a->ai_protocol);if(s->socket==BAD_SOCKET)continue;
#ifdef SO_NOSIGPIPE
        int no_sigpipe=1;setsockopt(s->socket,SOL_SOCKET,SO_NOSIGPIPE,&no_sigpipe,sizeof(no_sigpipe));
#endif
#ifdef _WIN32
        u_long nonblocking=1;if(ioctlsocket(s->socket,FIONBIO,&nonblocking)){socket_close(s->socket);s->socket=BAD_SOCKET;continue;}
#else
        if(fcntl(s->socket,F_SETFL,O_NONBLOCK)<0){socket_close(s->socket);s->socket=BAD_SOCKET;continue;}
#endif
        if(connect(s->socket,a->ai_addr,(int)a->ai_addrlen)==0){s->state=2;break;}
        if(would_block()){s->state=1;break;}
        socket_close(s->socket);s->socket=BAD_SOCKET;
    }
    freeaddrinfo(addresses);
    if(s->socket==BAD_SOCKET){native_error("Connect TCP");tg_close(s->token);return 0;}
    return s->token;
}
API int64_t tg_status(int64_t token) {
    TGTransport *s=find_slot(token);if(!s)return 0;
#ifdef __APPLE__
    if(s->kind==3){s->state=(int)tg_macos_status((int64_t)s->sent);if(!s->state)error_text(tg_macos_error());return s->state;}
    if(s->kind==4){s->state=(int)tg_ble_status((int64_t)s->sent);if(!s->state)error_text(tg_ble_error());return s->state;}
#endif
    if(s->state==1){
#ifdef _WIN32
        fd_set writes,errors;FD_ZERO(&writes);FD_ZERO(&errors);FD_SET(s->socket,&writes);FD_SET(s->socket,&errors);
        struct timeval timeout={0,0};int ready=select((int)s->socket+1,NULL,&writes,&errors,&timeout);
#else
        struct pollfd connecting={s->socket,POLLOUT,0};
        int ready=poll(&connecting,1,0);
#endif
        if(ready<0){native_error("Poll TCP connection");s->state=0;return 0;}
        if(!ready)return 1;
        int error=0;
#ifdef _WIN32
        int length=sizeof(error);
#else
        socklen_t length=sizeof(error);
#endif
        if(getsockopt(s->socket,SOL_SOCKET,SO_ERROR,(void*)&error,&length)<0 || error){
            snprintf(last_error,sizeof(last_error),"TCP connection failed (socket error %d)",error);s->state=0;return 0;
        }
        s->state=2;
    }
    if(s->kind==2 && s->state==2 && s->sent<sizeof(handshake)-1){
        int flags=0;
#ifdef MSG_NOSIGNAL
        flags=MSG_NOSIGNAL;
#endif
        int n=(int)send(s->socket,handshake+s->sent,(int)(sizeof(handshake)-1-s->sent),flags);
        if(n>0)s->sent+=(size_t)n;
        else if(n<0&&!would_block()){native_error("Send ThinkGear configuration");s->state=0;}
    }
    return s->state;
}
API int64_t tg_read_byte(int64_t token) {
    TGTransport *s=find_slot(token);if(!s)return -2;
#ifdef __APPLE__
    if(s->kind==3){int64_t n=tg_macos_read_byte((int64_t)s->sent);if(n==-2)error_text(tg_macos_error());return n;}
    if(s->kind==4){int64_t n=tg_ble_read_byte((int64_t)s->sent);if(n==-2)error_text(tg_ble_error());return n;}
#endif
    int64_t state=tg_status(token);if(state==0)return -2;if(state==1)return -1;
    if(s->cursor<s->count)return s->buffer[s->cursor++];
    s->cursor=s->count=0;
    int count;
    if(s->kind==2){count=(int)recv(s->socket,(char*)s->buffer,sizeof(s->buffer),0);}
    else {
#ifdef _WIN32
        DWORD got=0;if(!ReadFile(s->serial,s->buffer,sizeof(s->buffer),&got,NULL)){native_error("Read serial");s->state=0;return -2;}count=(int)got;
#else
        struct pollfd watched={s->serial,POLLIN,0};
        if(poll(&watched,1,0)>0 && (watched.revents&(POLLHUP|POLLERR|POLLNVAL)) && !(watched.revents&POLLIN)) {
            error_text("ThinkGear serial port disconnected");s->state=0;return -2;
        }
        count=(int)read(s->serial,s->buffer,sizeof(s->buffer));
#endif
    }
    if(count>0){s->count=(size_t)count;s->cursor=1;return s->buffer[0];}
    if(count==0 && s->kind==1){
#ifndef _WIN32
        struct pollfd watched={s->serial,POLLIN,0};
        if(poll(&watched,1,0)>0 && (watched.revents&(POLLHUP|POLLERR|POLLNVAL))){
            error_text("ThinkGear serial port disconnected");s->state=0;return -2;
        }
#endif
        return -1;
    }
    if(count<0 && would_block())return -1;
    if(count==0)error_text("ThinkGear TCP connection closed");else native_error("Read ThinkGear transport");
    s->state=0;return -2;
}
#ifdef __APPLE__
API int64_t tg_open_rfcomm(const char *name) {
    TGTransport *s=new_slot();if(!s)return 0;
    int64_t native=tg_macos_open_rfcomm(name);
    if(!native){error_text(tg_macos_error());tg_close(s->token);return 0;}
    s->kind=3;s->sent=(size_t)native;return s->token;
}
API int64_t tg_open_ble(const char *name) {
    TGTransport *s=new_slot();if(!s)return 0;
    int64_t native=tg_ble_open(name);
    if(!native){error_text(tg_ble_error());tg_close(s->token);return 0;}
    s->kind=4;s->sent=(size_t)native;return s->token;
}
#else
API int64_t tg_open_rfcomm(const char *name) {(void)name;error_text("Direct RFCOMM requires macOS; use an OS-paired serial port on this platform");return 0;}
API int64_t tg_open_ble(const char *name) {(void)name;error_text("MindWave BLE transport requires macOS in this build");return 0;}
#endif

/* Drain before close, including after status/read failure. No run-loop pumping:
 * this preserves a finite queue boundary for each caller drain pass. */
API const char *tg_drain_ble_event(int64_t token) {
    TGTransport *s=find_slot(token);if(!s)return NULL;
#ifdef __APPLE__
    if(s->kind==4)return tg_ble_drain_event((int64_t)s->sent);
#endif
    return NULL;
}
API int64_t tg_ble_events_dropped(int64_t token) {
    TGTransport *s=find_slot(token);if(!s)return 0;
#ifdef __APPLE__
    if(s->kind==4)return tg_ble_internal_events_dropped((int64_t)s->sent);
#endif
    return 0;
}
API double tg_monotonic_seconds(void) {
#ifdef __APPLE__
    return tg_ble_monotonic_seconds();
#elif defined(_WIN32)
    LARGE_INTEGER counter,frequency;QueryPerformanceFrequency(&frequency);QueryPerformanceCounter(&counter);
    return (double)counter.QuadPart/(double)frequency.QuadPart;
#else
    struct timespec now;if(clock_gettime(CLOCK_MONOTONIC,&now))return 0;
    return (double)now.tv_sec+(double)now.tv_nsec/1e9;
#endif
}
