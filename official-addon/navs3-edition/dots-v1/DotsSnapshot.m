#import "DotsSnapshot.h"
#import "DotsClient.h"
static BOOL putID(id text,char *output,size_t capacity){if(!TDIdentifier(text))return NO;NSData *d=[text dataUsingEncoding:NSUTF8StringEncoding];if(d.length>=capacity)return NO;memcpy(output,d.bytes,d.length);output[d.length]=0;return YES;}
BOOL TDMakeSnapshot(NSDictionary *recent,DotsSnapshot *output,NSError **error){
    NSDictionary *conversation=nil;NSArray *messages=nil,*states=nil;
    if(!output||![recent isKindOfClass:NSDictionary.class]||![recent[@"conversation"]isKindOfClass:NSDictionary.class])goto bad;
    conversation=recent[@"conversation"];messages=recent[@"messages"];
    if(![messages isKindOfClass:NSArray.class]||messages.count>DOTS_COUNT||![conversation[@"revision"]isKindOfClass:NSNumber.class]||[conversation[@"revision"]longLongValue]<=0)goto bad;
    DotsSnapshot snapshot={0};if(!putID(conversation[@"id"],snapshot.conversation,sizeof snapshot.conversation))goto bad;
    snapshot.revision=[conversation[@"revision"]unsignedLongLongValue];snapshot.count=(uint8_t)messages.count;
    states=@[@"sent",@"queued",@"waiting_agent",@"running",@"completed",@"failed",@"expired",@"cancelled"];
    for(NSUInteger i=0;i<messages.count;i++){
        NSDictionary *m=messages[i];if(![m isKindOfClass:NSDictionary.class]||![m[@"content"]isKindOfClass:NSString.class]||![@[@"user",@"assistant"]containsObject:m[@"role"]])goto bad;
        DotsMessage *out=&snapshot.messages[i];if(!putID(m[@"id"],out->id,sizeof out->id))goto bad;NSUInteger state=[states indexOfObject:m[@"state"]];if(state==NSNotFound)goto bad;
        out->role=[m[@"role"]isEqual:@"assistant"]?1:0;out->state=(uint8_t)state;
        NSString *content=m[@"content"];if([content lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>8192)goto bad;
        NSMutableData *bytes=[NSMutableData data];__block BOOL clipped=NO;
        [content enumerateSubstringsInRange:NSMakeRange(0,content.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *part,NSRange range,NSRange enclosing,BOOL *stop){(void)range;(void)enclosing;
            // Direction/control formatting is not trusted UI markup. Replace
            // unsupported controls rather than risk rearranging status text.
            BOOL unsafe=NO;for(NSUInteger n=0;n<part.length;n++){unichar ch=[part characterAtIndex:n];if((ch<32&&ch!='\n'&&ch!='\t')||(ch>=127&&ch<=159)||(ch>=0x202a&&ch<=0x202e)||(ch>=0x2066&&ch<=0x2069))unsafe=YES;}
            NSData *d=[(unsafe?@" ":part)dataUsingEncoding:NSUTF8StringEncoding];if(unsafe)clipped=YES;
            if(!d||bytes.length+d.length>=DOTS_BODY){clipped=YES;*stop=YES;return;}[bytes appendData:d];
        }];
        memcpy(out->body,bytes.bytes,bytes.length);out->truncated=clipped?1:0;
    }
    if(!dots_snapshot_valid(&snapshot))goto bad;*output=snapshot;return YES;
bad:
    if(error)*error=TDError(@"invalid_glasses_snapshot");return NO;
}
