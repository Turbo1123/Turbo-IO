#import "ExperimentalOTAFeed.h"
#include <assert.h>
#include <arpa/inet.h>
#include <errno.h>
#include <sys/socket.h>
#include <unistd.h>

static void QueryAndClose(uint16_t port) {
    int fd=socket(AF_INET,SOCK_STREAM,0);assert(fd>=0);
    struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(port);
    a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    struct timeval timeout={3,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    assert(connect(fd,(struct sockaddr *)&a,sizeof(a))==0);
    NSString *s=[NSString stringWithFormat:@"GET /g/xxxxxxxA78p2M?packageType=app HTTP/1.1\r\nHost: 127.0.0.1:%u\r\n\r\n",port];
    NSData *data=[s dataUsingEncoding:NSUTF8StringEncoding];
    assert(send(fd,data.bytes,data.length,0)==(ssize_t)data.length);
    char b[4096];ssize_t n;unsigned bytes=0;
    while((n=recv(fd,b,sizeof(b),0))>0)bytes+=(unsigned)n;
    assert(n==0&&bytes>0);close(fd);
}

int main(void){@autoreleasepool{
    TIOExperimentalOTAFeed *feed=[TIOExperimentalOTAFeed new];NSError *error=nil;
    assert([feed startOnPort:0 error:&error]);uint16_t port=feed.port;
    TIOExperimentalOTAFeed *duplicate=[TIOExperimentalOTAFeed new];
    assert(![duplicate startOnPort:port error:&error]); // Never share an active listener.
    assert([feed checkHealth]);assert([feed.status[@"queryCount"] unsignedIntegerValue]==0);
    QueryAndClose(port);[feed stop];assert(![feed checkHealth]);usleep(150000);
    assert([duplicate startOnPort:port error:&error]); // Failed bind is retryable.
    assert([duplicate checkHealth]&&![duplicate.status[@"armed"] boolValue]);
    [duplicate stop];usleep(150000);
    for(unsigned i=0;i<6;i++){
        TIOExperimentalOTAFeed *next=[TIOExperimentalOTAFeed new];
        if(![next startOnPort:port error:&error]){
            NSLog(@"FAIL: listener cannot rebind after a completed request (iteration %u)",i);return 1;
        }
        assert(![next.status[@"armed"] boolValue]); // Restart cannot authorize even a download.
        assert([next checkHealth]);QueryAndClose(port);[next stop];usleep(150000);
    }
    NSLog(@"PASS: six same-port restarts; active duplicate rejected; default disarmed; no glasses IO");
}return 0;}
