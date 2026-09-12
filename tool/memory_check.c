#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
extern int32_t slim_run(const uint8_t*,size_t,const uint8_t*,size_t,uint8_t**,size_t*);
extern void slim_free(uint8_t*,size_t);
static int calls=0;
static void check(const uint8_t *input,size_t size,const char *plan,int expected) {
    uint8_t *out=NULL;size_t len=0;
    int code=slim_run(input,size,(const uint8_t*)plan,strlen(plan),&out,&len);
    if(code!=expected){fprintf(stderr,"Unexpected status %d expected %d\n",code,expected);exit(2);}
    if(code==1 && (!out || !len)){fprintf(stderr,"Missing error text\n");exit(3);}
    slim_free(out,len);calls++;
}
int main(int argc,char **argv){
    if(argc!=2)return 1;
    FILE *f=fopen(argv[1],"rb");if(!f)return 1;
    fseek(f,0,SEEK_END);size_t size=(size_t)ftell(f);rewind(f);
    uint8_t *input=malloc(size);if(!input)return 1;
    if(fread(input,1,size,f)!=size)return 1;fclose(f);
    const char *jpeg="{\"operations\":[],\"format\":\"jpeg\",\"quality\":90}";
    for(int i=0;i<100;i++){
        check(input,size,jpeg,0);
        check(input,size,"{\"operations\":[],\"format\":\"jpeg\",\"quality\":95}",0);
        check(input,size,"{\"operations\":[],\"format\":\"png\",\"quality\":90}",0);
        check(input,size,"{\"operations\":[],\"format\":\"webp\",\"quality\":90}",0);
        check(input,size,"{\"operations\":[],\"format\":\"jpeg\",\"quality\":0}",1);
        check(input,size,"{\"operations\":[],\"format\":\"bad\",\"quality\":90}",1);
        check(input,size,"{\"operations\":[{\"crop\":{\"x\":999,\"y\":0,\"width\":1,\"height\":1}}],\"format\":\"png\",\"quality\":90}",1);
        check(input,16,jpeg,1);
        check(input,size,"{bad json",1);
        check(NULL,0,jpeg,2);
    }
    /* Within pipeline pixel limit, beyond TurboJPEG's dimension limit:
       exercise compressor failure after native initialization and resize. */
    for(int i=0;i<5;i++)check(input,size,"{\"operations\":[{\"resize\":{\"width\":65536,\"height\":1,\"filter\":\"triangle\"}}],\"format\":\"jpeg\",\"quality\":90}",1);
    check(input,size,jpeg,0);
    slim_free(NULL,0);free(input);
    printf("PASS: %d calls including codec failure and subsequent recovery\n",calls);
    return 0;
}
