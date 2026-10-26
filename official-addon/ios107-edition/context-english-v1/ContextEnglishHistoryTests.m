#import "ContextEnglishHistory.h"
#include "english_progress.h"
#include <assert.h>
static NSDictionary *card(NSString *word){return @{@"english":word,@"quote":@"一起练习。",@"meaning":@"练习",@"example":@"Let's practice today.",@"kind":@"generated_expression"};}
static uint32_t word(NSString *s){NSData *d=[s.lowercaseString dataUsingEncoding:NSASCIIStringEncoding];uint32_t n=ce_crc32(d.bytes,d.length);return n?:1;}
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==2);NSURL *file=[NSURL fileURLWithPath:@(argv[1])];CEHistory *h=[[CEHistory alloc]initWithFile:file];assert([h clear:nil]);
    assert(([h remember:@[card(@"practice"),card(@"review")] peer:@"synthetic-peer" target:@"CET4" day:20001 error:nil]));
    assert(![h reviewsForPeer:@"synthetic-peer" target:@"CET4" day:20001 limit:5].count);
    CEProgress p={.day=20001,.used=2,.limit=5,.words={word(@"practice"),word(@"review")},.results={CE_REMEMBERED,CE_FORGOTTEN}};
    uint8_t raw[CE_PROGRESS_BYTES];assert(ce_progress_encode(&p,17,raw,sizeof raw)==sizeof raw);
    assert([h progress:[NSData dataWithBytes:raw length:sizeof raw] peer:@"synthetic-peer" error:nil]);
    NSArray *next=[h reviewsForPeer:@"synthetic-peer" target:@"CET4" day:20002 limit:5];assert(next.count==1&&[next[0][@"english"] isEqual:@"review"]);
    p.results[0]=p.results[1]=CE_SKIPPED;assert(ce_progress_encode(&p,17,raw,sizeof raw));
    assert([h progress:[NSData dataWithBytes:raw length:sizeof raw] peer:@"synthetic-peer" error:nil]);
    assert([h reviewsForPeer:@"synthetic-peer" target:@"CET4" day:20002 limit:5].count==1);
    h=[[CEHistory alloc]initWithFile:file];assert([h reviewsForPeer:@"synthetic-peer" target:@"CET4" day:20004 limit:5].count==2);
    assert(![h reviewsForPeer:@"other" target:@"CET4" day:20004 limit:5].count);
    assert(![h reviewsForPeer:@"synthetic-peer" target:@"IELTS" day:20004 limit:5].count);
    assert(![h reviewsForPeer:@"synthetic-peer" target:@"CET4" day:20004 limit:0].count);
    assert(![h reviewsForPeer:@"synthetic-peer" target:@"CET4" day:20033 limit:5].count);
    for(unsigned cut=0;cut<sizeof raw;cut++){CEProgress got;uint32_t tx;assert(!ce_progress_decode(raw,cut,&got,&tx));}
    for(unsigned i=0;i<sizeof raw;i++){raw[i]^=1;CEProgress got;uint32_t tx;assert(!ce_progress_decode(raw,sizeof raw,&got,&tx));raw[i]^=1;}
    p.words[1]=p.words[0];assert(!ce_progress_encode(&p,17,raw,sizeof raw));
    assert([h clear:nil]&&![h reviewsForPeer:@"synthetic-peer" target:@"CET4" day:20004 limit:5].count);
    puts("PASS: bounded private review history, peer/target isolation, restart, one/three-day due dates, stale reservation, 30-day expiry, corrupt/truncated progress; synthetic file only.");
}}
