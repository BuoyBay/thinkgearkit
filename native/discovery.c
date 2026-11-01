/* Read-only OS inventory: no scan, device open, pairing, or connection.
 * One owner thread. Returned JSON is borrowed until the next discovery call. */
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <devguid.h>
#define API __declspec(dllexport)
#else
#include <dirent.h>
#include <sys/stat.h>
#define API __attribute__((visibility("default")))
#endif
#define TG_DISCOVERY_LIMIT 64
#define TG_DISCOVERY_BUFFER 262144
#ifndef __APPLE__
static char tg_inventory[TG_DISCOVERY_BUFFER];
typedef struct {char id[4096],name[4096],endpoint[4096];} TGKnownDevice;
static TGKnownDevice tg_known[TG_DISCOVERY_LIMIT];
static size_t tg_count;
static int tg_complete;
static char tg_inventory_error[512];
static int tg_contains_mindwave(const char *s) {
    const char *needle="mindwave";
    for(;*s;s++) {size_t i=0;while(needle[i] && s[i] && tolower((unsigned char)s[i])==needle[i])i++;if(!needle[i])return 1;}
    return 0;
}
static void tg_incomplete(const char *message) {tg_complete=0;if(!*tg_inventory_error)snprintf(tg_inventory_error,sizeof(tg_inventory_error),"%s",message);}
static int tg_utf8(const unsigned char *s) {
    while(*s){unsigned c=*s++;if(c<128)continue;unsigned need,min;
        if(c>=0xc2&&c<=0xdf){need=1;min=0x80;c&=31;}
        else if(c>=0xe0&&c<=0xef){need=2;min=0x800;c&=15;}
        else if(c>=0xf0&&c<=0xf4){need=3;min=0x10000;c&=7;}else return 0;
        for(unsigned i=0;i<need;i++){if((*s&0xc0)!=0x80)return 0;c=(c<<6)|(*s++&63);}
        if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff))return 0;
    }return 1;
}
static void tg_add_known(const char *id,const char *name,const char *endpoint) {
    if(!tg_utf8((const unsigned char*)id)||!tg_utf8((const unsigned char*)name)||!tg_utf8((const unsigned char*)endpoint)){tg_incomplete("A candidate has invalid UTF-8 metadata");return;}
    if(strlen(id)>=4089||strlen(name)>=4096||strlen(endpoint)>=4089){tg_incomplete("Candidate metadata exceeds bounded field size");return;}
    for(size_t i=0;i<tg_count;i++)if(!strcmp(tg_known[i].id+7,id)){
        if(strcmp(endpoint,tg_known[i].endpoint+7)<0){
            snprintf(tg_known[i].name,sizeof(tg_known[i].name),"%s",name);
            snprintf(tg_known[i].endpoint,sizeof(tg_known[i].endpoint),"serial:%s",endpoint);
        }
        return;
    }
    if(tg_count>=TG_DISCOVERY_LIMIT){tg_incomplete("Inventory exceeds 64 headset candidates");return;}
    TGKnownDevice *d=&tg_known[tg_count++];
    snprintf(d->id,sizeof(d->id),"serial:%s",id);snprintf(d->name,sizeof(d->name),"%s",name);snprintf(d->endpoint,sizeof(d->endpoint),"serial:%s",endpoint);
}
static int tg_compare_known(const void *a,const void *b){return strcmp(((const TGKnownDevice*)a)->endpoint,((const TGKnownDevice*)b)->endpoint);}
static int tg_json_text(char *out,size_t cap,size_t *at,const char *s){
    if(*at+1>=cap)return 0;
    out[(*at)++]='"';
    for(const unsigned char *p=(const unsigned char*)s;*p;p++){
        if(*p=='"'||*p=='\\'){if(*at+2>=cap)return 0;out[(*at)++]='\\';out[(*at)++]=(char)*p;}
        else if(*p<32){if(*at+6>=cap)return 0;int n=snprintf(out+*at,cap-*at,"\\u%04x",*p);*at+=(size_t)n;}
        else {if(*at+1>=cap)return 0;out[(*at)++]=(char)*p;}
    }if(*at+1>=cap)return 0;out[(*at)++]='"';out[*at]=0;return 1;
}
static int tg_append(char *out,size_t cap,size_t *at,const char *s){size_t n=strlen(s);if(n>=cap-*at)return 0;memcpy(out+*at,s,n+1);*at+=n;return 1;}
static const char *tg_render_inventory(void){
    qsort(tg_known,tg_count,sizeof(*tg_known),tg_compare_known);
    char entries[250000];size_t at=0,emitted=0;entries[0]=0;
    for(size_t i=0;i<tg_count;i++){
        size_t saved=at;int ok=1;
#define ADD(s) (ok=ok&&tg_append(entries,sizeof(entries),&at,(s)))
#define TG_JSON_TEXT(s) (ok=ok&&tg_json_text(entries,sizeof(entries),&at,(s)))
        if(emitted){ADD(",");}
        ADD("{\"id\":");TG_JSON_TEXT(tg_known[i].id);ADD(",\"name\":");TG_JSON_TEXT(tg_known[i].name);ADD(",\"endpoint\":");TG_JSON_TEXT(tg_known[i].endpoint);ADD(",\"transport\":\"serial\",\"pairing_known\":false,\"paired\":false}");
#undef ADD
#undef TG_JSON_TEXT
        if(!ok){at=saved;entries[at]=0;tg_incomplete("Inventory JSON exceeds bounded output size");break;}emitted++;
    }
    size_t out=0;tg_inventory[0]=0;
    tg_append(tg_inventory,sizeof(tg_inventory),&out,tg_complete?"{\"supported\":true,\"complete\":true,\"devices\":[":"{\"supported\":true,\"complete\":false,\"devices\":[");
    tg_append(tg_inventory,sizeof(tg_inventory),&out,entries);tg_append(tg_inventory,sizeof(tg_inventory),&out,"],\"error\":");tg_json_text(tg_inventory,sizeof(tg_inventory),&out,tg_inventory_error);tg_append(tg_inventory,sizeof(tg_inventory),&out,"}");return tg_inventory;
}
#if defined(_WIN32)
static int tg_wide_utf8(const wchar_t *wide,char *text,size_t size){
    if(!WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,wide,-1,text,(int)size,NULL,NULL)){tg_incomplete("Windows port metadata cannot fit UTF-8 output");return 0;}return 1;
}
static void tg_windows_inventory(void){
    HDEVINFO inventory=SetupDiGetClassDevsW(&GUID_DEVCLASS_PORTS,NULL,NULL,DIGCF_PRESENT);
    if(inventory==INVALID_HANDLE_VALUE){tg_incomplete("SetupAPI cannot enumerate present COM ports");return;}
    for(DWORD i=0;i<16384;i++){
        SP_DEVINFO_DATA device={0};device.cbSize=sizeof(device);
        if(!SetupDiEnumDeviceInfo(inventory,i,&device)){
            if(GetLastError()!=ERROR_NO_MORE_ITEMS)tg_incomplete("SetupAPI port enumeration failed");
            break;
        }
        if(i==16383)tg_incomplete("OS port inventory reached 16384-entry inspection limit");
        wchar_t friendly[4096]={0};DWORD type=0,needed=0;
        if(!SetupDiGetDeviceRegistryPropertyW(inventory,&device,SPDRP_FRIENDLYNAME,&type,(BYTE*)friendly,sizeof(friendly),&needed)){
            DWORD code=GetLastError();if(code!=ERROR_INVALID_DATA&&code!=ERROR_NOT_FOUND)tg_incomplete("Cannot read a COM port friendly name");continue;
        }
        friendly[4095]=0;if(type!=REG_SZ){tg_incomplete("COM port friendly name has unexpected registry type");continue;}
        char name[4096];if(!tg_wide_utf8(friendly,name,sizeof(name))||!tg_contains_mindwave(name))continue;
        HKEY key=SetupDiOpenDevRegKey(inventory,&device,DICS_FLAG_GLOBAL,0,DIREG_DEV,KEY_QUERY_VALUE);
        if(key==INVALID_HANDLE_VALUE){tg_incomplete("Cannot read MindWave COM endpoint registry key");continue;}
        wchar_t port[128]={0};DWORD bytes=sizeof(port);type=0;
        LONG result=RegQueryValueExW(key,L"PortName",NULL,&type,(BYTE*)port,&bytes);RegCloseKey(key);port[127]=0;
        if(result!=ERROR_SUCCESS||type!=REG_SZ||bytes<sizeof(wchar_t)){tg_incomplete("Cannot resolve MindWave COM endpoint");continue;}
        if(wcsncmp(port,L"COM",3)||!port[3]){tg_incomplete("MindWave port has no COM endpoint");continue;}
        int valid=1;for(size_t n=3;port[n];n++)if(port[n]<L'0'||port[n]>L'9')valid=0;
        if(!valid){tg_incomplete("MindWave port has invalid COM endpoint");continue;}
        char endpoint[128];if(tg_wide_utf8(port,endpoint,sizeof(endpoint)))tg_add_known(endpoint,name,endpoint);
    }
    SetupDiDestroyDeviceInfoList(inventory);
}
#elif !defined(__APPLE__)
static void tg_linux_directory(const char *directory,int optional){
    DIR *dir=opendir(directory);
    if(!dir){if(!optional||errno!=ENOENT)tg_incomplete("Cannot read serial device inventory directory");return;}
    struct dirent *entry;size_t inspected=0;
    while(1){
        errno=0;entry=readdir(dir);
        if(!entry){if(errno)tg_incomplete("Serial inventory directory iteration failed");break;}
        if(++inspected>16384){tg_incomplete("Serial inventory exceeds 16384 directory entries");break;}
        if(entry->d_name[0]=='.')continue;
        char path[4096];int n=snprintf(path,sizeof(path),"%s/%s",directory,entry->d_name);
        if(n<0||(size_t)n>=sizeof(path)){tg_incomplete("Serial inventory pathname exceeds 4095 bytes");continue;}
        if(!tg_contains_mindwave(entry->d_name))continue;
        struct stat metadata;
        if(stat(path,&metadata)<0){tg_incomplete("Cannot inspect a named MindWave candidate");continue;}
        if(S_ISCHR(metadata.st_mode)){
            char resolved[4096];
            if(!realpath(path,resolved)){tg_incomplete("Cannot resolve a named MindWave serial endpoint");continue;}
            tg_add_known(resolved,entry->d_name,path);
        }
    }
    closedir(dir);
}
#endif
#endif /* non-Apple implementations */
#ifdef __APPLE__
extern const char *tg_macos_discover_headsets(void);
API const char *tg_discover_headsets(void){return tg_macos_discover_headsets();}
#else
API const char *tg_discover_headsets(void){
    tg_count=0;tg_complete=1;tg_inventory_error[0]=0;
#ifdef _WIN32
    tg_windows_inventory();
#else
    tg_linux_directory("/dev",0);tg_linux_directory("/dev/serial/by-id",1);
#endif
    return tg_render_inventory();
}
#endif
#ifdef TG_DISCOVERY_TEST
API const char *tg_discover_fixture(const char *directory){tg_count=0;tg_complete=1;tg_inventory_error[0]=0;tg_linux_directory(directory,0);return tg_render_inventory();}
#endif
